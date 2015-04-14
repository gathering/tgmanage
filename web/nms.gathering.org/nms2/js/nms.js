var nms = {
	updater:undefined, // Active updater
	switches_now:undefined, // Most recent data
	switches_then:undefined, // 2 minutes old
	speed:0, // Current aggregated speed
	full_speed:false, // Set to 'true' to include ALL interfaces
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
	fontSize:14, // This is scaled too, but 14 seems to make sense.
	fontFace:"Arial Black",
	outstandingAjaxRequests:0,
	ajaxOverflow:0,
	/*
	 * Set to 'true' after we've done some basic updating. Used to
	 * bootstrap the map quickly as soon as we have enough data, then
	 * ignored.
	 */
	did_update:false,
	/*
	 * Various setInterval() handlers.
	 */
	handlers: {
		replay:false,
		ports:false,
		info:false,
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

var tgStart = stringToEpoch('2015-04-01T09:00:00');
var tgEnd = stringToEpoch('2015-04-05T12:00:00');
var replayTime = 0;
var replayIncrement = 30 * 60;

/*
 * Handlers. "updater" is run periodically when the handler is active, and
 * "init" is run once when it's activated.
 */

var handler_uplinks = {
	updater:uplinkUpdater,
	init:uplinkInit,
	name:"Uplink map"
};

var handler_temp = {
	updater:tempUpdater,
	init:tempInit,
	name:"Temperature map"
};

var handler_ping = {
	updater:pingUpdater,
	init:pingInit,
	name:"IPv4 Ping map"
};

var handler_traffic = {
	updater:trafficUpdater,
	init:trafficInit,
	name:"Uplink traffic map"
};

var handler_disco = {
	updater:randomizeColors,
	init:discoInit,
	name:"Disco fever"
};

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

function byteCount(bytes) {
	var units = ['', 'K', 'M', 'G', 'T', 'P'];
	i = 0;
	while (bytes > 1024) {
		bytes = bytes / 1024;
		i++;
	}
	return bytes.toFixed(1) + units[i];
}

function toggleNightMode()
{
	setNightMode(!nms.nightMode);
}

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


function stringToEpoch(t)
{
	var ret = new Date(Date.parse(t));
	return parseInt(parseInt(ret.valueOf()) / 1000);
}

function epochToString(t)
{
	var d = new Date(parseInt(t) * parseInt(1000));
	var str = d.getFullYear() + "-" + (parseInt(d.getMonth())+1) + "-" + d.getDate() + "T";
	str += d.getHours() + ":" + d.getMinutes() + ":" + d.getSeconds();
	return str;
}
	

function timeReplay()
{
	if (replayTime >= tgEnd) {
		nms.handlers.replay.stop();
		return;
	}
	replayTime = parseInt(replayTime) + parseInt(replayIncrement);
	nms.now = epochToString(replayTime);
	drawNow();
}

function startReplay() {
	nms.handlers.replay.stop();
	resetColors();
	replayTime = tgStart;
	timeReplay();
	nms.handlers.replay.start();;
}

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
		var swpanel = document.getElementById("info-switch-panel-body");
		var switchele = document.getElementById("info-switch-table");
		if (switchele != undefined)
			swpanel.removeChild(switchele);
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
		td1.innerHTML = "Uplink speed (out , port 44,45,46,47)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1['data-toggle'] = "popover";
		td1.title = "Port 44, 45, 46 and 47 are used as uplinks.";
		td1.innerHTML = "Uplink speed (in , port 44,45,46,47)";
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


		swpanel.appendChild(switchele);
		swtop.style.display = 'block';
}

/*
 * Update various info elements periodically.
 */
function updateInfo()
{
	if (!nms.drawn && nms.switches_now != undefined) {
		drawSwitches();
		nms.drawn = true;
	}
	var speedele = document.getElementById("speed");
	speedele.innerHTML = (8 * parseInt(nms.speed) / 1024 / 1024 / 1024 ).toPrecision(5) + " Gbit/s";
}

/*
 * Update function for uplink map
 * Run periodically when uplink map is active.
 */
function uplinkUpdater()
{
	if (!nms.switches_now["switches"])
		return;
	for (sw in nms.switches_now["switches"]) {
		var uplinks=0;
		for (port in nms.switches_now["switches"][sw]["ports"]) {
			if (!nms.switches_then["switches"][sw]["ports"] || 
			    !nms.switches_now["switches"][sw]["ports"])
				continue;
			if (/ge-0\/0\/44$/.exec(port) ||
			    /ge-0\/0\/45$/.exec(port) ||
			    /ge-0\/0\/46$/.exec(port) ||
			    /ge-0\/0\/47$/.exec(port))
			 {
				 if (parseInt(nms.switches_then["switches"][sw]["ports"][port]["ifhcoutoctets"]) != parseInt(nms.switches_now["switches"][sw]["ports"][port]["ifhcoutoctets"])) {
					 uplinks += 1;
				 }
			 }
		}
		if (uplinks == 0) {
			setSwitchColor(sw,"blue");
		} else if (uplinks == 1) {
			setSwitchColor(sw,"red");
		} else if (uplinks == 2) {
			setSwitchColor(sw, "yellow");
		} else if (uplinks == 3) { 
			setSwitchColor(sw, "green");
		} else if (uplinks > 3) {
			setSwitchColor(sw, "white");
		}
	}
}

/*
 * Init-function for uplink map
 */
function trafficInit()
{
	setLegend(1,"blue","0 uplink utilization");	
	setLegend(5,"red", "1000Mb/s or more uplink utilization");	
	setLegend(4,"yellow","100Mb/s to 800Mb/s uplink utilization");	
	setLegend(3,"green", "5Mb/s to 100Mb/s uplink utilization");	
	setLegend(2,"white","0 to 5Mb/s uplink utilization");	
}

function trafficUpdater()
{
	if (!nms.switches_now["switches"])
		return;
	for (sw in nms.switches_now["switches"]) {
		var speed = 0;
		for (port in nms.switches_now["switches"][sw]["ports"]) {
			if (/ge-0\/0\/44$/.exec(port) ||
			    /ge-0\/0\/45$/.exec(port) ||
			    /ge-0\/0\/46$/.exec(port) ||
			    /ge-0\/0\/47$/.exec(port))
			 {
				 var t = nms.switches_then["switches"][sw]["ports"][port];
				 var n = nms.switches_now["switches"][sw]["ports"][port];
				 speed += (parseInt(t["ifhcoutoctets"]) -parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
				 speed += (parseInt(t["ifhcinoctets"]) -parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
			 }
		}
		var m = 1024 * 1024 / 8;
		if (speed == 0) {
			setSwitchColor(sw,"blue");
		} else if (speed > (1000 * m)) {
			setSwitchColor(sw,"red");
		} else if (speed > (800 * m)) {
			setSwitchColor(sw, "yellow");
		} else if (speed > (5 * m)) { 
			setSwitchColor(sw, "green");
		} else {
			setSwitchColor(sw, "white");
		}
	}
}

/*
 * Init-function for uplink map
 */
function uplinkInit()
{
	setLegend(1,"blue","0 uplinks");	
	setLegend(2,"red","1 uplink");	
	setLegend(3,"yellow","2 uplinks");	
	setLegend(4,"green","3 uplinks");	
	setLegend(5,"white","4 uplinks");	
}

/*
 * Give us a color from blue (0) to red (100).
 */
function rgb_from_max(x)
{
	x = x/100;
	var colorred = 255 * x;
	var colorblue = 255 - colorred;

	return 'rgb(' + Math.floor(colorred) + ", 0, " + Math.floor(colorblue) + ')';
}

/*
 * Tweaked this to scale from roughly 20C to 35C. Hence the -20  and /15
 * thing (e.g., "0" is 20 and "15" is 35 by the time we pass it to
 * rgb_from_max());
 */
function temp_color(t)
{
	if (t == undefined) {
		console.log("Temp_color, but temp is undefined");
		return "blue";
	}
	t = parseInt(t) - 20;
	t = Math.floor((t / 15) * 100);
	return rgb_from_max(t);
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

function tempUpdater()
{
	for (sw in nms.switches_now["switches"]) {
		var t = "white";
		if (nms.switches_now["switches"][sw]["temp"]) {
			t = temp_color(nms.switches_now["switches"][sw]["temp"]);
		}
		
		setSwitchColor(sw, t);
	}
}

function tempInit()
{
	setLegend(1,temp_color(20),"20 °C");	
	setLegend(2,temp_color(22),"22 °C");	
	setLegend(3,temp_color(27),"27 °C");	
	setLegend(4,temp_color(31),"31 °C");	
	setLegend(5,temp_color(35),"35 °C");	
}

function gradient_from_latency(latency_ms, latency_secondary_ms)
{
	if (latency_secondary_ms === undefined) {
		return rgb_from_latency(latency_ms);
	}
	return 'linear-gradient(' +
		rgb_from_latency(latency_ms) + ', ' +
		rgb_from_latency(latency_secondary_ms) + ')';
}

function rgb_from_latency(latency_ms)
{
	if (latency_ms === null || latency_ms === undefined) {
		return '#0000ff';
	}

	var l = latency_ms / 40.0;
	if (l >= 2.0) {
		return 'rgb(255, 0, 0)';
	} else if (l >= 1.0) {
		l = 2.0 - l;
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 255.0);
		return 'rgb(255, ' + l + ', 0)';
	} else {
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 255.0);
		return 'rgb(' + l + ', 255, 0)';
	}
}

function pingUpdater()
{
	for (var sw in nms.switches_now["switches"]) {
		var c = "blue";
		if (nms.ping_data['switches'] && nms.ping_data['switches'][sw])
			c = gradient_from_latency(nms.ping_data["switches"][sw]["latency"]);
		setSwitchColor(sw, c);
	}
	for (var ln in nms.switches_now["linknets"]) {
		var c1 = "blue";
		var c2 = c1;
		if (nms.ping_data['linknets'] && nms.ping_data['linknets'][ln]) {
			c1 = gradient_from_latency(nms.ping_data["linknets"][ln][0]);
			c2 = gradient_from_latency(nms.ping_data["linknets"][ln][1]);
		}
		setLinknetColors(ln, c1, c2);
	}
}

function pingInit()
{
	setLegend(1,gradient_from_latency(1),"1ms");	
	setLegend(2,gradient_from_latency(30),"30ms");	
	setLegend(3,gradient_from_latency(60),"60ms");	
	setLegend(4,gradient_from_latency(80),"80ms");	
	setLegend(5,"#0000ff" ,"No response");	
}

/*
 * Run periodically to trigger map updates when a handler is active
 */
function updateMap()
{
	if (nms.updater != undefined && nms.switches_now && nms.switches_then) {
		nms.updater();
	}
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
 * nms.speed is a total of ifHCInOctets across all interfaces.
 *
 * if nms.full_speed is true: Include ALL interfaces
 * if nms.full_speed is false: Include only e* switches and exclude
 * uplinks.
 */
function updateSpeed()
{
	var speed_in = parseInt(0);
	var speed_kant = parseInt(0);
	var counter=0;
	var sw;
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
			if (nms.full_speed || (( /e\d-\d/.exec(sw) || /e\d\d-\d/.exec(sw)) &&  ( /ge-\d\/\d\/\d$/.exec(port) || /ge-\d\/\d\/\d\d$/.exec(port)))) {
				if (nms.full_speed || !(
					/ge-0\/0\/44$/.exec(port) ||
					/ge-0\/0\/45$/.exec(port) ||
					/ge-0\/0\/46$/.exec(port) ||
					/ge-0\/0\/47$/.exec(port))) {
					speed_in += parseInt(diffval/diff) ;
					counter++;
				}
			}
			//speed_in += parseInt(diffval/diff) / 1024 ;
		}
	}
	nms.speed = speed_in;
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
 */
function drawNow()
{
	if (nms.now != false) {
		dr.top.ctx.font = Math.round(2 * nms.fontSize * canvas.scale) + "px " + nms.fontFace;
		dr.top.ctx.clearRect(0,0,Math.floor(400 * canvas.scale),Math.floor(60 * canvas.scale));
		dr.top.ctx.fillStyle = "white";
		dr.top.ctx.strokeStyle = "black";
		dr.top.ctx.lineWidth = Math.round(2 * canvas.scale);
		if (canvas.scale < 0.7) {
			dr.top.ctx.lineWidth = 2;
		}
		dr.top.ctx.strokeText("Now: " + nms.now, 0 + margin.text, 30 * canvas.scale);
		dr.top.ctx.fillText("Now: " + nms.now, 0 + margin.text, 30 * canvas.scale);
	}
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
 * Return a random-ish color (for testing)
 */
function getRandomColor()
{
	var i = Math.round(Math.random() * 5);
	var colors = [ "white", "red", "pink", "yellow", "orange", "green" ];
	return colors[i];	
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
 * Testing-function to randomize colors of linknets and switches
 */
function randomizeColors()
{
	for (var i in nms.switches_now.linknets) {
		setLinknetColors(i, getRandomColor(), getRandomColor());
	}
	for (var sw in nms.switches_now.switches) {
		setSwitchColor(sw, getRandomColor());
	}
}

function discoInit()
{
	setNightMode(true);
	setLegend(1,"blue","0");	
	setLegend(5,"red", "1");
	setLegend(4,"yellow","2");
	setLegend(3,"green", "3");
	setLegend(2,"white","4");
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
	dr.text.ctx.lineWidth = Math.floor(1 * canvas.scale);
	if (canvas.scale < 0.7) {
		dr.text.ctx.lineWidth = 0.5;
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
	dr.text.ctx.lineWidth = Math.floor(1 * canvas.scale);
	if (canvas.scale < 0.7) {
		dr.text.ctx.lineWidth = 0.5;
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


function initNMS() {
	var url;
	initDrawing();
	updatePorts();
	updatePing();
	window.addEventListener('resize',resizeEvent,true);
	document.addEventListener('load',resizeEvent,true);
	
	nms.handlers.ports = new nmsTimer(updatePorts, 1000, "Port updater", "AJAX request to update port data (traffic, etc)");
	nms.handlers.ports.start();

	nms.handlers.info = new nmsTimer(updateInfo, 5000, "Info updater", "Updates info-box about client speed (fast - no backend requests)");
	nms.handlers.info.start();

	nms.handlers.ping = new nmsTimer(updatePing, 1000, "Ping updater", "AJAX request to update ping data");
	nms.handlers.ping.start();
	
	nms.handlers.map = new nmsTimer(updateMap, 1000, "Map handler", "Updates the map using the chosen map handler (ping, uplink, traffic, etc)");
	nms.handlers.map.start();
	
	nms.handlers.speed = new nmsTimer(updateSpeed, 3000, "Speed updater", "Recompute total speed (no backend requests)");
	nms.handlers.speed.start();
	
	nms.handlers.replay = new nmsTimer(timeReplay, 1000, "Time machine", "Handler used to change time");

	url = document.URL;
	if (/#ping/.exec(url)) {
		setUpdater(handler_ping);
	}else if (/#uplink/.exec(url)) {
		setUpdater(handler_uplinks);
	} else if (/#temp/.exec(url)) {
		setUpdater(handler_temp);
	} else if (/#traffic/.exec(url)) {
		setUpdater(handler_traffic);
	} else if (/#disco/.exec(url)) {
		setUpdater(handler_disco);
	} else {
		setUpdater(handler_ping);
	}
	if (/nightMode/.exec(url)) {
		toggleNightMode();
	}
}

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
	for (var v in nms.handlers) {
		tr = document.createElement("tr");
		td = document.createElement("td");
		td.innerHTML = nms.handlers[v].handle;
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = "<input type=\"text\" id='handlerValue" + v + "' value='" + nms.handlers[v].interval + "'>";
		td.innerHTML += "<button type=\"button\" class=\"btn btn-default\" onclick=\"nms.handlers['" + v + "'].setInterval(document.getElementById('handlerValue" + v + "').value);\">Apply</button>";
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = nms.handlers[v].name;
		tr.appendChild(td);
		td = document.createElement("td");
		td.innerHTML = nms.handlers[v].description;
		tr.appendChild(td);
		table.appendChild(tr);
	}
	tableTop.appendChild(table);
	document.getElementById('debugTimers').style.display = 'block'; 
}

function debugHandlers() {
	for (var v in nms.handlers) {
		console.log(nms.handlers[v]);
	}
}
