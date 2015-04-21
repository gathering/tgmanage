var nms = {
	updater:undefined, // Active updater
	switches_now:undefined, // Most recent data
	switches_then:undefined, // 2 minutes old
	speed:0, // Current aggregated speed
	ping_data:undefined, // JSON data for ping history.
	drawn:false, // Set to 'true' when switches are drawn
	switch_showing:"", // Which switch we are displaying (if any).
	nightMode:false, 
	/*
	 * Switch-specific variables. These are currently separate from
	 * "switches_now" because switches_now is reset every time we get
	 * new data.
	 */
	nightBlur:{}, // Have we blurred this switch or not?
	switch_color:{},  // Color for switch
	linknet_color:{}, // color for linknet
	textDrawn:{}, // Have we drawn text for this switch?
	now:false, // Date we are looking at (false for current date).
	fontSize:16, // This is scaled too, but 16 seems to make sense.
	fontFace:"Arial Black",
	/*
	 * This is used to track outbound AJAX requests and skip updates if
	 * we have too many outstanding requests. The ajaxOverflow is a
	 * counter that tracks how many times this has happened.
	 *
	 * It's a cheap way to be nice to the server.
	 */
	outstandingAjaxRequests:0,
	ajaxOverflow:0,
	/*
	 * Set to 'true' after we've done some basic updating. Used to
	 * bootstrap the map quickly as soon as we have enough data, then
	 * ignored.
	 */
	did_update:false,
	/*
	 * Various setInterval() handlers. See nmsTimer() for how they are
	 * used.
	 *
	 * Cool fact: Adding one here adds it to the 'debug timers'
	 * drop-down.
	 */
	timers: {
		replay:false,
		ports:false,
		ping:false,
		map:false,
		speed:false
	}
};


/*
 * Returns a handler object.
 *
 * This might seem a bit much for 'setInterval()' etc, but it's really more
 * about self-documentation and predictable ways of configuring timers.
 */
function nmsTimer(handler, interval, name, description) {
	this.handler = handler;
	this.handle = false;
	this.interval = parseInt(interval);
	this.name = name;
	this.description = description;
	this.start = function() { 
		if (this.handle) {
			this.stop();
		}
		this.handle = setInterval(this.handler,this.interval);
		};
	this.stop = function() { 
		if (this.handle)
			clearInterval(this.handle);
			this.handle = false;
		};

	this.setInterval = function(interval) {
		var started = this.handle == false ? false : true;
		this.stop();
		this.interval = parseInt(interval);
		if (started)
			this.start();
	};
}

/*
 * Drawing primitives.
 *
 * This contains both canvas and context for drawing layers. It's on a
 * top-level namespace to reduce SLIGHTLY the ridiculously long names
 * (e.g.: dr.bg.ctx.drawImage() is long enough....).
 *
 * Only initialized once (for now).
 */
var dr = {};

/*
 * Original scale. This is just used to define the coordinate system.
 * 1920x1032 was chosen for tg15 by coincidence: We scaled the underlying
 * map down to "full hd" and these are the bounds we got. There's no
 * particular reason this couldn't change, except it means re-aligning all
 * switches.
 */
var orig = {
	width:1920,
	height:1032
	};

/*
 * Canvas dimensions, and scale factor.
 *
 * We could derive scale factor from canvas.width / orig.width, but it's
 * used so frequently that this makes much more sense.
 *
 * Width and height are rarely used.
 */
var canvas = { 
	width:0,
	height:0,
	scale:1
};

/*
 * Various margins at the sides.
 *
 * Not really used much, except for "text", which is really more of a
 * padding than margin...
 */
var margin = {
	x:10,
	y:20,
	text:3
};

/*
 * All of these should be moved into nms.*
 *
 * tgStart/tgEnd are "constants".
 * replayTime is the current time as far as the replay-function is. This
 * should be merged with nms.now.
 *
 * replayIncrement is how many seconds to add for each replay timer tick
 * (e.g.: 30 minutes added for every 1 second display-time).
 */
var tgStart = stringToEpoch('2015-04-01T09:00:00');
var tgEnd = stringToEpoch('2015-04-05T12:00:00');
var replayTime = 0;
var replayIncrement = 30 * 60;

/*
 * Convenience-function to populate the 'dr' structure.
 *
 * Only run once.
 */
function initDrawing() {
	dr['bg'] = {};
	dr['bg']['c'] = document.getElementById("bgCanvas");
	dr['bg']['ctx'] = dr['bg']['c'].getContext('2d');
	dr['link'] = {};
	dr['link']['c'] = document.getElementById("linkCanvas");
	dr['link']['ctx'] = dr['link']['c'].getContext('2d');
	dr['blur'] = {};
	dr['blur']['c'] = document.getElementById("blurCanvas");
	dr['blur']['ctx'] = dr['blur']['c'].getContext('2d');
	dr['switch'] = {};
	dr['switch']['c'] = document.getElementById("switchCanvas");
	dr['switch']['ctx'] = dr['switch']['c'].getContext('2d');
	dr['text'] = {};
	dr['text']['c'] = document.getElementById("textCanvas");
	dr['text']['ctx'] = dr['text']['c'].getContext('2d');
	dr['top'] = {};
	dr['top']['c'] = document.getElementById("topCanvas");
	dr['top']['ctx'] = dr['top']['c'].getContext('2d');
}

/*
 * Convenience function that doesn't support huge numbers, and it's easier
 * to comment than to fix. But not really, but I'm not fixing it anyway.
 */
function byteCount(bytes) {
	var units = ['', 'K', 'M', 'G', 'T', 'P'];
	i = 0;
	while (bytes > 1024) {
		bytes = bytes / 1024;
		i++;
	}
	return bytes.toFixed(1) + units[i];
}

/*
 * Definitely not a way to toggle night mode. Does something COMPLETELY
 * DIFFERENT.
 */
function toggleNightMode()
{
	setNightMode(!nms.nightMode);
}

/*
 * Parse 'now' from user-input.
 *
 * Should probably just use stringToEpoch() instead, but alas, not yet.
 */
function checkNow(now)
{
	if (Date.parse(now)) {
		var d = new Date(Date.parse(now));
		var str = d.getFullYear() + "-" + (parseInt(d.getMonth())+1) + "-" + d.getDate() + " ";
		str += d.getHours() + ":" + d.getMinutes() + ":" + d.getSeconds();
		return str;

	}
	if (now == "")
		return "";
	return false;
}

/*
 * Convert back and forth between epoch.
 *
 * There's no particular reason why I use seconds instead of javascript
 * microseconds, except to leave the mark of a C coder on this javascript
 * project.
 */
function stringToEpoch(t)
{
	var ret = new Date(Date.parse(t));
	return parseInt(parseInt(ret.valueOf()) / 1000);
}

/*
 * Have to pad with zeroes to avoid "17:5:0" instead of the conventional
 * and more readable "17:05:00". I'm sure there's a better way, but this
 * works just fine.
 */
function epochToString(t)
{
	var d = new Date(parseInt(t) * parseInt(1000));
	var str = d.getFullYear() + "-";
	if (parseInt(d.getMonth()) < 9)
		str += "0";
	str += (parseInt(d.getMonth())+1) + "-";
	if (d.getDate() < 10)
		str += "0";
	str += d.getDate() + "T";
	if (d.getHours() < 10)
		str += "0";
	str += d.getHours() + ":";
	if (d.getMinutes() < 10)
		str += "0";
	str += d.getMinutes() + ":";
	if (d.getSeconds() < 10)
		str += "0";
	str += d.getSeconds();

	return str;
}
	
/*
 * Move 'nms.now' forward in time, unless we're at the end of the event.
 *
 * This is run on a timer (nms.timers.replay) every second when we are
 * replaying.
 */
function timeReplay()
{
	if (replayTime >= tgEnd) {
		nms.timers.replay.stop();
		return;
	}
	replayTime = parseInt(replayTime) + parseInt(replayIncrement);
	nms.now = epochToString(replayTime);
}

/*
 * Start replaying the event.
 *
 * I want this to be more generic:
 *  - Set time
 *  - Set end-time
 *  - Start/stop/pause
 *  - Set speed increment
 *
 * Once the lib supports this, I can move 'tgStart' and 'tgEnd' to the GUI
 * and just provide them as default values or templates.
 */
function startReplay() {
	nms.timers.replay.stop();
	resetColors();
	replayTime = tgStart;
	timeReplay();
	nms.timers.replay.start();;
}

/*
 * Used to move to a specific time, but not replay.
 */
function changeNow() {
	 var newnow = checkNow(document.getElementById("nowPicker").value);
	if (!newnow) {
		alert('Bad date-field in time travel field');
		return;
	}
	if (newnow == "")
		newnow = false;
	
	nms.now = newnow;
	updatePorts();
	var boxHide = document.getElementById("nowPickerBox");
	if (boxHide) {
		boxHide.style.display = "none";
	}
}

/*
 * Hide switch info-box
 */
function hideSwitch()
{
		var swtop = document.getElementById("info-switch-parent");
		var switchele = document.getElementById("info-switch-table");
		var comments = document.getElementById("info-switch-comments-table");
		if (switchele != undefined)
			switchele.parentNode.removeChild(switchele);
		if (comments != undefined)
			comments.parentNode.removeChild(comments);
		commentbox = document.getElementById("commentbox");
		if (commentbox != undefined)
			commentbox.parentNode.removeChild(commentbox);
		swtop.style.display = 'none';
		nms.switch_showing = "";
}
/*
 * Display info on switch "x" in the info-box
 */
function switchInfo(x)
{
		var switchele = document.getElementById("info-switch-table");
		var sw = nms.switches_now["switches"][x];
		var swtop = document.getElementById("info-switch-parent");
		var swpanel = document.getElementById("info-switch-panel-body");
		var swtitle = document.getElementById("info-switch-title");
		var tr;
		var td1;
		var td2;
	
		if (nms.switch_showing == x) {
			hideSwitch();	
			return;
		} else {
			hideSwitch();	
			nms.switch_showing = x;
		}
		document.getElementById("aboutBox").style.display = "none";
		switchele = document.createElement("table");
		switchele.id = "info-switch-table";
		switchele.style.zIndex =  100;
		switchele.className = "table";
		
		swtitle.innerHTML = x + '<button type="button" class="close" aria-labe="Close" onclick="hideSwitch();" style="float: right;"><span aria-hidden="true">&times;</span></button>';
		var speed = 0;
		var speed2 = 0;
		for (port in nms.switches_now["switches"][x]["ports"]) {
			if (nms.switches_now["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			if (/ge-0\/0\/44$/.exec(port) ||
			    /ge-0\/0\/45$/.exec(port) ||
			    /ge-0\/0\/46$/.exec(port) ||
			    /ge-0\/0\/47$/.exec(port))
			 {
				 var t = nms.switches_then["switches"][x]["ports"][port];
				 var n = nms.switches_now["switches"][x]["ports"][port];
				 speed += (parseInt(t["ifhcoutoctets"]) - parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
				 speed2 += (parseInt(t["ifhcinoctets"]) - parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
			 }
		}

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Uplink speed (out , port 44-47)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1['data-toggle'] = "popover";
		td1.title = "Port 44, 45, 46 and 47 are used as uplinks.";
		td1.innerHTML = "Uplink speed (in , port 44-47)";
		td2.innerHTML = byteCount(8 * speed2) + "b/s";
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		speed = 0;
		for (port in nms.switches_now["switches"][x]["ports"]) {
			if (nms.switches_now["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			 var t = nms.switches_then["switches"][x]["ports"][port];
			 var n = nms.switches_now["switches"][x]["ports"][port];
			 speed += (parseInt(t["ifhcinoctets"]) -parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
		}

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Total speed (in)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		speed = 0;
		for (port in nms.switches_now["switches"][x]["ports"]) {
			if (nms.switches_now["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			 var t = nms.switches_then["switches"][x]["ports"][port];
			 var n = nms.switches_now["switches"][x]["ports"][port];
			 speed += (parseInt(t["ifhcoutoctets"]) -parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
		}

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Total speed (out)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Management IP";
		td2.innerHTML = sw["management"]["ip"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Latency";
		if (nms.ping_data && nms.ping_data["switches"] && nms.ping_data["switches"][x]) {
			td2.innerHTML = nms.ping_data["switches"][x]["latency"];
		} else {
			td2.innerHTML = "N/A";
		}
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Temperature";
		td2.innerHTML = sw["temp"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Temperature age";
		td2.innerHTML = sw["temp_time"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Type";
		td2.innerHTML = sw["switchtype"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Last Updated";
		td2.innerHTML = sw["management"]["last_updated"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Poll frequency";
		td2.innerHTML = sw["management"]["poll_frequency"];
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		
		comments = document.createElement("table");
		comments.id = "info-switch-comments-table";
		comments.border = "1";
		comments.className = "table col-md-6";
		var cap = document.createElement("caption");
		cap.innerText = "Comments";
		comments.appendChild(cap);
		
		tr = document.createElement("tr"); td1 = document.createElement("th"); td2 = document.createElement("th");
		td3 = document.createElement("th");
		td1.innerText = "Time";
		td2.innerText = "User";
		td3.innerText = "Comment";
		tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3); comments.appendChild(tr);
		var has_comment = false;
		for (var c in sw["comments"]) {
			var comment = sw["comments"][c];
			has_comment = true;
			if (comment["state"] == "active" || comment["state"] == "persist") {
				tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
				td3 = document.createElement("td");
				td1.innerText = epochToString(comment["time"]) + " ";
				td2.innerText = comment["username"] + " ";
				td3.innerText = comment['comment'];
				tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3); comments.appendChild(tr);
			}
		}
		
		swpanel.appendChild(switchele);
		if (has_comment) {
			swpanel.appendChild(comments);
		}
		var commentbox = document.createElement("div");
		commentbox.id = "commentbox";
		commentbox.innerHTML = '<input type="text" placeholder="Comment" id="' + x + '-comment"><button onclick="addComment(\'' + x + '\',document.getElementById(\'' + x + '-comment\').value); document.getElementById(\'' + x + '-comment\').value = \'added. Wait for it....\';">Add comment</button>';
		swpanel.appendChild(commentbox);
		swtop.style.display = 'block';
}

/*
 * There are 4 legend-bars. This is a helper-function to set the color and
 * description/name for each one. Used from handler init-functions.
 *
 * FIXME: Should be smarter, possibly use a canvas-writer so we can get
 * proper text (e.g.: not black text on dark blue). 
 */
function setLegend(x,color,name)
{
	var el = document.getElementById("legend-" + x);
	el.style.background = color;
	el.innerHTML = name;
}

/*
 * Run periodically to trigger map updates when a handler is active
 */
function updateMap()
{
	if (nms.updater != undefined && nms.switches_now && nms.switches_then) {
		nms.updater();
	}
	drawNow();
}

/*
 * Change map handler (e.g., change from uplink map to ping map)
 */
function setUpdater(fo)
{
	nms.updater = undefined;
	resetColors();
	fo.init();
	nms.updater = fo.updater;
	var foo = document.getElementById("updater_name");
	foo.innerHTML = fo.name + "   ";
	initialUpdate();
	if (nms.ping_data && nms.switches_then && nms.switches_now) {
		nms.updater();
	}
}


/*
 * Convenience function to avoid waiting for pollers when data is available
 * for the first time.
 */
function initialUpdate()
{
	if (nms.ping_data && nms.switches_then && nms.switches_now && nms.updater != undefined && nms.did_update == false ) {
		resizeEvent();
		if (!nms.drawn) {
			drawSwitches();
			drawLinknets();
		}
		nms.updater();
		nms.did_update = true;
	}
}

/*
 * Update nms.ping_data 
 */
function updatePing()
{
	var now = nms.now ? ("?now=" + nms.now) : "";
	if (nms.outstandingAjaxRequests > 5) {
		nms.ajaxOverflow++;
		return;
	}
	nms.outstandingAjaxRequests++;
	$.ajax({
		type: "GET",
		url: "/ping-json2.pl" + now,
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			nms.ping_data = JSON.parse(data);
			initialUpdate();
		},
		complete: function(jqXHR, textStatus) {
			nms.outstandingAjaxRequests--;
		}
	});
}

function addComment(sw,comment) {
	var myData = {
		switch:sw,
		comment:comment};
	console.log(myData);
	$.ajax({
		type: "POST",
		url: "/switch-comment.pl",
		dataType: "text",
		data:myData
	});
}
/*
 * Update nms.switches_now and nms.switches_then
 */
function updatePorts()
{
	var now = "";
	if (nms.outstandingAjaxRequests > 5) {
		nms.ajaxOverflow++;
		return;
	}
	nms.outstandingAjaxRequests++;
	if (nms.now != false)
		now = "?now=" + nms.now;
	$.ajax({
		type: "GET",
		url: "/port-state.pl"+ now ,
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			nms.switches_now = switchdata;
			parseIntPlacements();
			initialUpdate();
		},
		complete: function(jqXHR, textStatus) {
			nms.outstandingAjaxRequests--;
		}
	});
	now="";
	if (nms.now != false)
		now = "&now=" + nms.now;
	nms.outstandingAjaxRequests++;
	$.ajax({
		type: "GET",
		url: "/port-state.pl?time=5m" + now,
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			nms.switches_then = switchdata;
			initialUpdate();
		},
		complete: function(jqXHR, textStatus) {
			nms.outstandingAjaxRequests--;
		}
	})
}

/*
 * Use nms.switches_now and nms.switches_then to update 'nms.speed'.
 *
 * nms.speed is a total of ifHCInOctets across all client-interfaces
 * nms.speed_full is a total of for /all/ interfaces.
 *
 * This is run separate of updatePorts mainly for historic reasons, but
 * if it was added to the tail end of updatePorts, there'd have to be some
 * logic to ensure it was run after both requests. Right now, it's just
 * equally wrong for both scenarios, not consistently wrong (or something).
 *
 * FIXME: Err, yeah, add this to the tail-end of updatePorts instead :D
 *
 */
function updateSpeed()
{
	var speed_in = parseInt(0);
	var speed_full = parseInt(0);
	var counter=0;
	var sw;
	var speedele = document.getElementById("speed");
	for (sw in nms.switches_now["switches"]) {
		for (port in nms.switches_now["switches"][sw]["ports"]) {
			if (!nms.switches_now["switches"][sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			if (!nms.switches_then || !nms.switches_then["switches"] || !nms.switches_then["switches"][sw] || !nms.switches_then["switches"][sw]["ports"]) {
				continue;
			}
			if (!nms.switches_now || !nms.switches_now["switches"] || !nms.switches_now["switches"][sw] || !nms.switches_now["switches"][sw]["ports"]) {
				continue;
			}

			if (!nms.switches_then["switches"][sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			var diff = parseInt(parseInt(nms.switches_now["switches"][sw]["ports"][port]["time"]) - parseInt(nms.switches_then["switches"][sw]["ports"][port]["time"]));
			var then = parseInt(nms.switches_then["switches"][sw]["ports"][port]["ifhcinoctets"])  ;
			var now =  parseInt(nms.switches_now["switches"][sw]["ports"][port]["ifhcinoctets"]) ;
			var diffval = (now - then);
			if (then == 0 || now == 0 || diffval == 0 || diffval == NaN) {
				continue;
			}
			speed_full += parseInt(diffval/diff);
			if (( /e\d-\d/.exec(sw) || /e\d\d-\d/.exec(sw)) &&  ( /ge-\d\/\d\/\d$/.exec(port) || /ge-\d\/\d\/\d\d$/.exec(port))) {
				if (!(
					/ge-0\/0\/44$/.exec(port) ||
					/ge-0\/0\/45$/.exec(port) ||
					/ge-0\/0\/46$/.exec(port) ||
					/ge-0\/0\/47$/.exec(port))) {
					speed_in += parseInt(diffval/diff) ;
					counter++;
				}
			}
		}
	}
	nms.speed = speed_in;
	nms.speed_full = speed_full;
	if (speedele) {
		speedele.innerHTML = byteCount(8 * parseInt(nms.speed)) + "bit/s";
		speedele.innerHTML += " / " + byteCount(8 * parseInt(nms.speed_full)) + "bit/s";

	}
}

/*
 * Draw a linknet with index i.
 *
 * XXX: Might have to change the index here to match backend
 */
function drawLinknet(i)
{
	var c1 = nms.linknet_color[i] && nms.linknet_color[i].c1 ? nms.linknet_color[i].c1 : "blue";
	var c2 = nms.linknet_color[i] && nms.linknet_color[i].c2 ? nms.linknet_color[i].c2 : "blue";
	if (nms.switches_now.switches[nms.switches_now.linknets[i].sysname1] && nms.switches_now.switches[nms.switches_now.linknets[i].sysname2]) {
		connectSwitches(nms.switches_now.linknets[i].sysname1,nms.switches_now.linknets[i].sysname2, c1, c2);
	}
}

/*
 * Draw all linknets
 */
function drawLinknets()
{
	if (nms.switches_now && nms.switches_now.linknets) {
		for (var i in nms.switches_now.linknets) {
			drawLinknet(i);
		}
	}
}

/*
 * Change both colors of a linknet.
 *
 * XXX: Probably have to change this to better match the backend data
 */
function setLinknetColors(i,c1,c2)
{
	if (!nms.linknet_color[i] || 
 	     nms.linknet_color[i].c1 != c1 ||
	     nms.linknet_color[i].c2 != c2) {
		if (!nms.linknet_color[i])
			nms.linknet_color[i] = {};
		nms.linknet_color[i]['c1'] = c1;
		nms.linknet_color[i]['c2'] = c2;
		drawLinknet(i);
	}
}

/*
 * (Re)draw a switch 'sw'.
 *
 * Color defaults to 'blue' if it's not set in the data structure.
 */
function drawSwitch(sw)
{
		var box = nms.switches_now['switches'][sw]['placement'];
		var color = nms.switch_color[sw];
		if (color == undefined) {
			color = "blue";
		}
		dr.switch.ctx.fillStyle = color;
		if (nms.nightMode && nms.nightBlur[sw] != true) {
			dr.switch.ctx.shadowBlur = 10;
			dr.switch.ctx.shadowColor = "#00EE00";
			nms.nightBlur[sw] = true;
		} else {
			dr.switch.ctx.shadowBlur = 0;
			dr.switch.ctx.shadowColor = "#000000";
		}
		drawBox(box['x'],box['y'],box['width'],box['height']);
		dr.switch.ctx.shadowBlur = 0;
		if (!nms.textDrawn[sw]) {
			if ((box['width'] + 10 )< box['height'])
				drawSideways(sw,box['x'],box['y'],box['width'],box['height']);
			else
				drawRegular(sw,box['x'],box['y'],box['width'],box['height']);
			
			nms.textDrawn[sw] = true;
		}
}

/*
 * Make sure all placements of switches are parsed as integers so we don't
 * have to pollute the code with pasreInt() every time we use it.
 */
function parseIntPlacements() {
	for (var sw in nms.switches_now.switches) {
		nms.switches_now.switches[sw]['placement']['x'] =
			parseInt(nms.switches_now.switches[sw]['placement']['x']);
		nms.switches_now.switches[sw]['placement']['y'] =
			parseInt(nms.switches_now.switches[sw]['placement']['y']);
		nms.switches_now.switches[sw]['placement']['width'] =
			parseInt(nms.switches_now.switches[sw]['placement']['width']);
		nms.switches_now.switches[sw]['placement']['height'] =
			parseInt(nms.switches_now.switches[sw]['placement']['height']);
	}
}

/*
 * Draw all switches
 */
function drawSwitches()
{
	if (!nms.switches_now || !nms.switches_now.switches)
		return;
	for (var sw in nms.switches_now.switches) {
		drawSwitch(sw);
	}
	nms.drawn = true;
}

/*
 * Draw current time-window
 *
 * FIXME: The math here is just wild approximation and guesswork because
 * I'm lazy.
 */
function drawNow()
{
	// XXX: Get rid of microseconds that we get from the backend.
	var now = /^[^.]*/.exec(nms.switches_now.time);
	dr.top.ctx.font = Math.round(2 * nms.fontSize * canvas.scale) + "px " + nms.fontFace;
	dr.top.ctx.clearRect(0,0,Math.floor(800 * canvas.scale),Math.floor(100 * canvas.scale));
	dr.top.ctx.fillStyle = "white";
	dr.top.ctx.strokeStyle = "black";
	dr.top.ctx.lineWidth = Math.floor(4 * canvas.scale);
	if (dr.top.ctx.lineWidth == 0) {
		dr.top.ctx.lineWidth = Math.round(4 * canvas.scale);
	}
	dr.top.ctx.strokeText(now, 0 + margin.text, 30 * canvas.scale);
	dr.top.ctx.fillText(now, 0 + margin.text, 30 * canvas.scale);
}
/*
 * Draw foreground/scene.
 *
 * FIXME: Review this! This was made before linknets and switches were
 * split apart.
 *
 * This is used so linknets are drawn before switches. If a switch is all
 * that has changed, we just need to re-draw that, but linknets require
 * scene-redrawing.
 */
function drawScene()
{
	dr.text.ctx.font = Math.floor(nms.fontSize * canvas.scale) + "px " + nms.fontFace;
	drawLinknets();
	drawSwitches();
}

/*
 * Set the scale factor and (re)draw the scene and background.
 * Uses canvas.scale and updates canvas.height and canvas.width.
 */
function setScale()
{

	canvas.height =  orig.height * canvas.scale ;
	canvas.width = orig.width * canvas.scale ;
	for (var a in dr) {
		dr[a].c.height = canvas.height;
		dr[a].c.width = canvas.width;
	}
	nms.nightBlur = {};
	nms.textDrawn = {};
	drawBG();
	drawScene();
	
	document.getElementById("scaler").value = canvas.scale;
	document.getElementById("scaler-text").innerHTML = (parseFloat(canvas.scale)).toPrecision(3);
}

/*
 * Returns true if the coordinates (x,y) is inside the box defined by
 * box.{x,y,w.h} (e.g.: placement of a switch).
 */
function isIn(box, x, y)
{
	if ((x >= box.x) && (x <= (box.x + box.width)) && (y >= box.y) && (y <= (box.y + box.height))) {
		return true;
	}
	return false;

}

/*
 * Return the name of the switch found at coordinates (x,y), or 'undefined'
 * if none is found.
 */
function findSwitch(x,y) {
	x = parseInt(parseInt(x) / canvas.scale);
	y = parseInt(parseInt(y) / canvas.scale);

	for (var v in nms.switches_now.switches) {
		if(isIn(nms.switches_now.switches[v]['placement'],x,y)) {
			return v;
		}
	}
	return undefined;
}

/*
 * Set switch color of 'sw' to 'c', then re-draw the switch.
 */
function setSwitchColor(sw, c)
{
	if(!nms.switch_color || !nms.switch_color[sw] || nms.switch_color[sw] != c) {
		nms.switch_color[sw] = c;
		drawSwitch(sw);
	}
}

/*
 * Event handler for the front-end drag bar to change scale
 */
function scaleChange()
{
	var scaler = document.getElementById("scaler").value;
	canvas.scale = scaler;
	setScale();
}

/*
 * Called when a switch is clicked
 */
function switchClick(sw)
{
	switchInfo(sw);
}

/*
 * Resets the colors of linknets and switches.
 *
 * Useful when mode changes so we don't re-use colors from previous modes
 * due to lack of data or bugs.
 */
function resetColors()
{
	if (!nms.switches_now)
		return;
	if (nms.switches_now.linknets) {
		for (var i in nms.switches_now.linknets) {
			setLinknetColors(i, "blue","blue");
		}
	}
	for (var sw in nms.switches_now.switches) {
		setSwitchColor(sw, "blue");
	}
}

/*
 * onclick handler for the canvas.
 *
 * Currently just shows info for a switch.
 */
function canvasClick(e)
{
	var sw = findSwitch(e.pageX - e.target.offsetLeft, e.pageY - e.target.offsetTop);
	if (sw != undefined) {
		switchClick(sw);
	}
}

/*
 * Resize event-handler.
 *
 * Recomputes the scale and applies it.
 *
 * Has to use c.offset* since we are just scaling the canvas, not
 * everything else.
 *
 */
function resizeEvent()
{
	var width = window.innerWidth - dr.bg.c.offsetLeft;
	var height = window.innerHeight - dr.bg.c.offsetTop;
	if (width / (orig.width + margin.x) > height  /  (orig.height + margin.y)) {
		canvas.scale = height / (orig.height + margin.y);
	} else {
		canvas.scale = width / (orig.width + margin.x);
	}
	setScale();
}

/*
 * Draws the background image (scaled).
 */
function drawBG()
{
	if (nms.nightMode) {
		invertCanvas();
	} else {
		var image = document.getElementById('source');
		dr.bg.ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
	}
}

/*
 * Set night mode to whatever 'toggle' is.
 * 
 * XXX: setScale() is a bit of a hack, but it really is the same stuff we
 * need to do: Redraw "everything" (not really).
 */
function setNightMode(toggle) {
	nms.nightMode = toggle;
	var body = document.getElementById("body");
	body.style.background = toggle ? "black" : "white";
	setScale();
}
/*
 * Draw a box (e.g.: switch).
 */
function drawBox(x,y,boxw,boxh)
{
	var myX = Math.floor(x * canvas.scale);
	var myY = Math.floor(y * canvas.scale);
	var myX2 = Math.floor((boxw) * canvas.scale);
	var myY2 = Math.floor((boxh) * canvas.scale);
	dr.switch.ctx.fillRect(myX,myY, myX2, myY2);
	dr.switch.ctx.lineWidth = Math.floor(0.5 * canvas.scale);
	if (canvas.scale < 1.0) {
		dr.switch.ctx.lineWidth = 0.5;
	}
	dr.switch.ctx.strokeStyle = "#000000";
	dr.switch.ctx.strokeRect(myX,myY, myX2, myY2);
}

/*
 * Draw text on a box - sideways!
 *
 * XXX: This is pretty nasty and should also probably take a box as input.
 */
function drawSideways(text,x,y,w,h)
{
	dr.text.ctx.rotate(Math.PI * 3 / 2);
	dr.text.ctx.fillStyle = "white";
	dr.text.ctx.strokeStyle = "black";
	dr.text.ctx.lineWidth = Math.floor(3 * canvas.scale);
	if (dr.text.ctx.lineWidth == 0) {
		dr.text.ctx.lineWidth = Math.round(3 * canvas.scale);
	}
	dr.text.ctx.strokeText(text, - canvas.scale * (y + h - margin.text),canvas.scale * (x + w - margin.text) );
	dr.text.ctx.fillText(text, - canvas.scale * (y + h - margin.text),canvas.scale * (x + w - margin.text) );

	dr.text.ctx.rotate(Math.PI / 2);
}

/*
 * Draw background inverted (wooo)
 *
 * XXX: This is broken for chromium on local file system (e.g.: file:///)
 * Seems like a chromium bug?
 */
function invertCanvas() {
	var imageObj = document.getElementById('source');
	dr.bg.ctx.drawImage(imageObj, 0, 0, canvas.width, canvas.height);

	var imageData = dr.bg.ctx.getImageData(0, 0, canvas.width, canvas.height);
	var data = imageData.data;

	for(var i = 0; i < data.length; i += 4) {
		data[i] = 255 - data[i];
		data[i + 1] = 255 - data[i + 1];
		data[i + 2] = 255 - data[i + 2];
	}
	dr.bg.ctx.putImageData(imageData, 0, 0);
}

/*
 * Draw regular text on a box.
 *
 * Should take the same format as drawSideways()
 *
 * XXX: Both should be renamed to have 'text' or something in them
 */
function drawRegular(text,x,y,w,h) {

	dr.text.ctx.fillStyle = "white";
	dr.text.ctx.strokeStyle = "black";
	dr.text.ctx.lineWidth = Math.floor(3 * canvas.scale);
	if (dr.text.ctx.lineWidth == 0) {
		dr.text.ctx.lineWidth = Math.round(3 * canvas.scale);
	}
	dr.text.ctx.strokeText(text, (x + margin.text) * canvas.scale, (y + h - margin.text) * canvas.scale);
	dr.text.ctx.fillText(text, (x + margin.text) * canvas.scale, (y + h - margin.text) * canvas.scale);
}

/*
 * Draw a line between switch "insw1" and "insw2", using a gradiant going
 * from color1 to color2.
 *
 * XXX: beginPath() and closePath() is needed to avoid re-using the
 * gradient/color 
 */
function connectSwitches(insw1, insw2,color1, color2) {
	var sw1 = nms.switches_now.switches[insw1].placement;
	var sw2 = nms.switches_now.switches[insw2].placement;
	if (color1 == undefined)
		color1 = "blue";
	if (color2 == undefined)
		color2 = "blue";
	var x0 = Math.floor((sw1.x + sw1.width/2) * canvas.scale);
	var y0 = Math.floor((sw1.y + sw1.height/2) * canvas.scale);
	var x1 = Math.floor((sw2.x + sw2.width/2) * canvas.scale);
	var y1 = Math.floor((sw2.y + sw2.height/2) * canvas.scale);
	var gradient = dr.link.ctx.createLinearGradient(x1,y1,x0,y0);
	gradient.addColorStop(0, color1);
	gradient.addColorStop(1, color2);
	dr.link.ctx.beginPath();
	dr.link.ctx.strokeStyle = gradient;
	dr.link.ctx.moveTo(x0,y0);
	dr.link.ctx.lineTo(x1,y1); 
	dr.link.ctx.lineWidth = Math.floor(5 * canvas.scale);
	dr.link.ctx.closePath();
	dr.link.ctx.stroke();
	dr.link.ctx.moveTo(0,0);
}

/*
 * Boot up "fully fledged" NMS.
 *
 * If you only want parts of the functionality, then re-implement this
 * (e.g., just add and start the handlers you want, don't worry about
 * drawing, etc).
 */
function initNMS() {
	initDrawing();
	updatePorts();
	updatePing();
	window.addEventListener('resize',resizeEvent,true);
	document.addEventListener('load',resizeEvent,true);
	
	nms.timers.ports = new nmsTimer(updatePorts, 1000, "Port updater", "AJAX request to update port data (traffic, etc)");
	nms.timers.ports.start();

	nms.timers.ping = new nmsTimer(updatePing, 1000, "Ping updater", "AJAX request to update ping data");
	nms.timers.ping.start();
	
	nms.timers.map = new nmsTimer(updateMap, 1000, "Map handler", "Updates the map using the chosen map handler (ping, uplink, traffic, etc)");
	nms.timers.map.start();
	
	nms.timers.speed = new nmsTimer(updateSpeed, 1000, "Speed updater", "Recompute total speed (no backend requests)");
	nms.timers.speed.start();
	
	nms.timers.replay = new nmsTimer(timeReplay, 1000, "Time machine", "Handler used to change time");
	detectHandler();
}

function detectHandler() {
	var url = document.URL;
	if (/#ping/.exec(url)) {
		setUpdater(handler_ping);
	}else if (/#uplink/.exec(url)) {
		setUpdater(handler_uplinks);
	} else if (/#temp/.exec(url)) {
		setUpdater(handler_temp);
	} else if (/#traffic/.exec(url)) {
		setUpdater(handler_traffic);
	} else if (/#comment/.exec(url)) {
		setUpdater(handler_comment);
	} else if (/#disco/.exec(url)) {
		setUpdater(handler_disco);
	} else {
		setUpdater(handler_ping);
	}
	if (/nightMode/.exec(url)) {
		toggleNightMode();
	}
}

/*
 * Display and populate the dialog box for debugging timers.
 *
 * Could probably be cleaned up.
 */
function showTimerDebug() {
	var tableTop = document.getElementById('timerTableTop');
	var table = document.getElementById('timerTable');
	var tr, td1, td2;
	if (table)
		tableTop.removeChild(table);
	table = document.createElement("table");
	table.id = "timerTable";
	table.style.zIndex = 100;
	table.className = "table";
	table.classList.add("table");
	table.classList.add("table-default");
	table.border = "1";
	tr = document.createElement("tr");
	td = document.createElement("th");
	td.innerHTML = "Handler";
	tr.appendChild(td);
	td = document.createElement("th");
	td.innerHTML = "Interval (ms)";
	tr.appendChild(td);
	td = document.createElement("th");
	td.innerHTML = "Name";
	tr.appendChild(td);
	td = document.createElement("th");
	td.innerHTML = "Description";
	tr.appendChild(td);
	table.appendChild(tr);
	for (var v in nms.timers) {
		console.log(v);
		tr = document.createElement("tr");
		td = document.createElement("td");
		td.innerHTML = nms.timers[v].handle;
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = "<input type=\"text\" id='handlerValue" + v + "' value='" + nms.timers[v].interval + "'>";
		td.innerHTML += "<button type=\"button\" class=\"btn btn-default\" onclick=\"nms.timers['" + v + "'].setInterval(document.getElementById('handlerValue" + v + "').value);\">Apply</button>";
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = nms.timers[v].name;
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = nms.timers[v].description;
		tr.appendChild(td);
		table.appendChild(tr);
	}
	tableTop.appendChild(table);
	document.getElementById('debugTimers').style.display = 'block'; 
}

function hideLayer(layer) {
	var l = document.getElementById(layer);
	l.style.display = "none";
}

function showLayer(layer) {
	var l = document.getElementById(layer);
	l.style.display = "";
}
