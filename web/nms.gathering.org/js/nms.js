"use strict";
var nms = {
	stats:{}, // Various internal stats
	updater:undefined, // Active updater
	speed:0, // Current aggregated speed
	switch_showing:"", // Which switch we are displaying (if any).
	switchInfo:{},
	repop_switch:false, // True if we need to repopulate the switch info when port state updates (e.g.: added comments);
	repop_time:false, // Timestamp in case we get a cached result
	nightMode:false, 
	_now: false,
	get now() { return this._now },
	set now(v) { this._now = n; nmsData.now = n; },
	/*
	 * Various setInterval() handlers. See nmsTimer() for how they are
	 * used.
	 *
	 * Cool fact: Adding one here adds it to the 'debug timers'
	 * drop-down.
	 */
	timers: {
		playback:false,
	},
	menuShowing:true,
	/*
	 * This is a list of nms[x] variables that we store in our
	 * settings-cookie when altered and restore on load.
	 */
	settingsList:[
		'shadowBlur',
		'shadowColor',
		'nightMode',
		'menuShowing',
		'layerVisibility'
	],
	layerVisibility:{},
	keyBindings:{
		'?':toggleMenu,
		'n':toggleNightMode,
		'1':setMapModeFromN,
		'2':setMapModeFromN,
		'3':setMapModeFromN,
		'4':setMapModeFromN,
		'5':setMapModeFromN,
		'6':setMapModeFromN,
		'7':setMapModeFromN,
		'h':moveTimeFromKey,
		'j':moveTimeFromKey,
		'k':moveTimeFromKey,
		'l':moveTimeFromKey,
		'p':moveTimeFromKey,
		'r':moveTimeFromKey
	},
  /*
   * Playback controllers and variables
   */
  playback:{
    startTime: false,
    stopTime: false,
    playing: false,
    replayTime: 0,
    replayIncrement: 60 * 60
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
 * Convenience function that doesn't support huge numbers, and it's easier
 * to comment than to fix. But not really, but I'm not fixing it anyway.
 */
function byteCount(bytes) {
	var units = ['', 'K', 'M', 'G', 'T', 'P'];
	var i = 0;
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
	saveSettings();
}

/*
 * Parse 'now' from user-input.
 *
 * Should probably just use stringToEpoch() instead, but alas, not yet.
 */
function parseNow(now)
{
	if (Date.parse(now)) {
		// Adjust for timezone when converting from epoch (UTC) to string (local)
		var d = new Date(now);
		var timezoneOffset = d.getTimezoneOffset() * -60000;
		var d = new Date(Date.parse(now) - timezoneOffset);
		var str = d.getFullYear() + "-" + ("00" + (parseInt(d.getMonth())+1)).slice(-2) + "-" + ("00" + d.getDate()).slice(-2) + "T";
		str += ("00" + d.getHours()).slice(-2) + ":" + ("00" + d.getMinutes()).slice(-2) + ":" + ("00" + d.getSeconds()).slice(-2);
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
	var foo = t.toString();
//	foo = foo.replace('T',' ');
	var ret = new Date(Date.parse(foo));
	return parseInt(parseInt(ret.valueOf()) / 1000);
}

/*
 * Have to pad with zeroes to avoid "17:5:0" instead of the conventional
 * and more readable "17:05:00". I'm sure there's a better way, but this
 * works just fine.
 */
function epochToString(t)
{
	// Adjust for timezone when converting from epoch (UTC) to string (local)
	var d = new Date(parseInt(t) * parseInt(1000));
	var timezoneOffset = d.getTimezoneOffset() * -60;
	t = t - timezoneOffset;

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
function localEpochToString(t) {
  var d = new Date(parseInt(t) * parseInt(1000));
  var timezoneOffset = d.getTimezoneOffset() * -60;
  t = t + timezoneOffset;

  return epochToString(t);
}

/*
 * Start replaying historical data.
 */
nms.playback.startReplay = function(startTime,stopTime) {
  if(!startTime || !stopTime)
    return false;

  nms.playback.pause();
  nms.playback.startTime = stringToEpoch(startTime);
  nms.playback.stopTime = stringToEpoch(stopTime);
  nms.now = epochToString(nms.playback.startTime);
  nms.playback.play();
}
/*
 * Pause playback
 */
nms.playback.pause = function() {
  nms.timers.playback.stop();
  nms.playback.playing = false;
}
/*
 * Start playback
 */
nms.playback.play = function() {
  nms.playback.tick();
  nms.timers.playback.start();
  nms.playback.playing = true;
}
/*
 * Toggle playback
 */
nms.playback.toggle = function() {
  if(nms.playback.playing) {
    nms.playback.pause();
  } else {
    nms.playback.play();
  }
}
/*
 * Jump to place in time
 */
nms.playback.setNow = function(now) {
  resetSwitchStates();
  now = parseNow(now);
  nms.now = now;

  nms.playback.stopTime = false;
  nms.playback.startTime = false;
  nms.playback.tick();
}
/*
 * Step forwards or backwards in timer
 */
nms.playback.stepTime = function(n)
{
  now = getNowEpoch();
  newtime = parseInt(now) + parseInt(n);
  nms.now = epochToString(parseInt(newtime));

  if(!nms.playback.playing)
    nms.playback.tick();
}
/*
 * Ticker to trigger updates, and advance time if replaying
 *
 * This is run on a timer (nms.timers.tick) every second while unpaused
 */
nms.playback.tick = function()
{
  nms.playback.replayTime = getNowEpoch();

  // If outside start-/stopTime, remove limits and pause playback
  if (nms.playback.stopTime && (nms.playback.replayTime >= nms.playback.stopTime || nms.playback.replayTime < nms.playback.startTime)) {
    nms.playback.stopTime = false;
    nms.playback.startTime = false;
    nms.playback.pause();
    return;
  }

  // If past actual datetime, go live
  if (nms.playback.replayTime > parseInt(Date.now() / 1000)) {
    nms.now = false;
  }

  // If we are still replaying, advance time
  if(nms.now !== false && nms.playback.playing) {
    nms.playback.stepTime(nms.playback.replayIncrement);
  }

  // Update data and force redraw
  // FIXME: nmsData merge
  // nms.updater.updater();
  // FIXME: 2: This should not be necsarry. The updaters should be
  // data-driven, not time-driven. E.g.: If nmsData upates, the handlers
  // should run.
}
/*
 * Helper function for safely getting a valid now-epoch
 */
function getNowEpoch() {
  if (nms.now && nms.now != 0)
    return stringToEpoch(nms.now);
  else
    return parseInt(Date.now() / 1000);
}


/*
 * Hide switch info-box
 */
function hideSwitch()
{
		var swtop = document.getElementById("info-switch-parent");
		var switchele = document.getElementById("info-switch-table");
		var comments = document.getElementById("info-switch-comments-table");
		var commentbox;
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
 *
 * FIXME: THIS IS A MONSTROSITY.
 */
function showSwitch(x)
{
		var sw = nmsData.switches["switches"][x];
		var swm = nmsData.smanagement.switches[x];
		var swtop = document.getElementById("info-switch-parent");
		var swpanel = document.getElementById("info-switch-panel-body");
		var swtitle = document.getElementById("info-switch-title");
		var tr;
		var td1;
		var td2;
	
		hideSwitch();	
		nms.switch_showing = x;
		document.getElementById("aboutBox").style.display = "none";
		var switchele = document.createElement("table");
		switchele.id = "info-switch-table";
		switchele.className = "table";
		switchele.classList.add("table");
		switchele.classList.add("table-condensed");
		
		swtitle.innerHTML = x + '<button type="button" class="close" aria-labe="Close" onclick="hideSwitch();" style="float: right;"><span aria-hidden="true">&times;</span></button>';
		var speed = 0;
		var speed2 = 0;
		for (port in nmsData.switches["switches"][x]["ports"]) {
			if (nmsData.switches["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			if (/ge-0\/0\/44$/.exec(port) ||
			    /ge-0\/0\/45$/.exec(port) ||
			    /ge-0\/0\/46$/.exec(port) ||
			    /ge-0\/0\/47$/.exec(port))
			 {
				 var t = nms.switches_then["switches"][x]["ports"][port];
				 var n = nmsData.switches["switches"][x]["ports"][port];
				 speed += (parseInt(t["ifhcoutoctets"]) - parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
				 speed2 += (parseInt(t["ifhcinoctets"]) - parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
			 }
		}

		tr = switchele.insertRow(-1);
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = "Uplink speed (out , port 44-47)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";

		tr = switchele.insertRow(-1);
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.title = "Port 44, 45, 46 and 47 are used as uplinks.";
		td1.innerHTML = "Uplink speed (in , port 44-47)";
		td2.innerHTML = byteCount(8 * speed2) + "b/s";

		speed = 0;
		for (port in nmsData.switches["switches"][x]["ports"]) {
			if (nmsData.switches["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			 var t = nms.switches_then["switches"][x]["ports"][port];
			 var n = nmsData.switches["switches"][x]["ports"][port];
			 speed += (parseInt(t["ifhcinoctets"]) -parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
		}

		tr = switchele.insertRow(-1);
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = "Total speed (in)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";

		speed = 0;
		for (port in nmsData.switches["switches"][x]["ports"]) {
			if (nmsData.switches["switches"][x]["ports"] == undefined ||
			    nms.switches_then["switches"][x]["ports"] == undefined) {
				continue;
			}
			 var t = nms.switches_then["switches"][x]["ports"][port];
			 var n = nmsData.switches["switches"][x]["ports"][port];
			 speed += (parseInt(t["ifhcoutoctets"]) -parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
		}

		tr = switchele.insertRow(-1);
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = "Total speed (out)";
		td2.innerHTML = byteCount(8 * speed) + "b/s";

		for (var v in sw) { 
			tr = switchele.insertRow(-1);
			td1 = tr.insertCell(0);
			td2 = tr.insertCell(1);
			td1.innerHTML = v;
			td2.innerHTML = sw[v];
		}
		for (var v in swm) { 
			tr = switchele.insertRow(-1);
			td1 = tr.insertCell(0);
			td2 = tr.insertCell(1);
			td1.innerHTML = v;
			td2.innerHTML = swm[v];
		}

		var comments = document.createElement("table");
		comments.id = "info-switch-comments-table";
		comments.className = "table table-condensed";
		var cap = document.createElement("caption");
		cap.textContent = "Comments";
		comments.appendChild(cap);
	
		var has_comment = false;
		if (nmsData.comments.comments == undefined || nmsData.comments.comments[x] == undefined) {
			console.log("blank");
		} else {
			for (var c in nmsData.comments.comments[x]["comments"]) {
				var comment = nmsData.comments.comments[x]["comments"][c];
				has_comment = true;
				if (comment["state"] == "active" || comment["state"] == "persist" || comment["state"] == "inactive") {
					tr = comments.insertRow(-1);
					var col;
					if (comment["state"] == "active")
						col = "danger";
					else if (comment["state"] == "inactive")
						col = false;
					else
						col = "info";
					tr.className = col;
					tr.id = "commentRow" + comment["id"];
					td1 = tr.insertCell(0);
					td2 = tr.insertCell(1);
					td1.style.whiteSpace = "nowrap";
					td1.style.width = "8em";
					var txt =  '<div class="btn-group" role="group" aria-label="..."><button type="button" class="btn btn-xs btn-default" data-trigger="focus" data-toggle="popover" title="Info" data-content="Comment added ' + epochToString(comment["time"]) + " by user " + comment["username"] + ' and listed as ' + comment["state"] + '"><span class="glyphicon glyphicon-info-sign" aria-hidden="true"></span></button>';
					txt += '<button type="button" class="btn btn-xs btn-danger" data-trigger="focus" data-toggle="tooltip" title="Mark as deleted" onclick="commentDelete(' + comment["id"] + ');"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></button>';
					txt += '<button type="button" class="btn btn-xs btn-success" data-trigger="focus" data-toggle="tooltip" title="Mark as inactive/fixed" onclick="commentInactive(' + comment["id"] + ');"><span class="glyphicon glyphicon-ok" aria-hidden="true"></span></button>';
					txt += '<button type="button" class="btn btn-xs btn-info" data-trigger="focus" data-toggle="tooltip" title="Mark as persistent" onclick="commentPersist(' + comment["id"] + ');"><span class="glyphicon glyphicon-star" aria-hidden="true"></span></button></div>';
					td1.innerHTML = txt;
					td2.textContent = comment['comment'];
				}
			}
		}
		
		swtop.appendChild(switchele);
		if (has_comment) {
			swtop.appendChild(comments);
			$(function () { $('[data-toggle="popover"]').popover({placement:"top",continer:'body'}) })
		}
		var commentbox = document.createElement("div");
		commentbox.id = "commentbox";
		commentbox.className = "panel-body";
		commentbox.style.width = "100%";
		commentbox.innerHTML = '<div class="input-group"><input type="text" class="form-control" placeholder="Comment" id="' + x + '-comment"><span class=\"input-group-btn\"><button class="btn btn-default" onclick="addComment(\'' + x + '\',document.getElementById(\'' + x + '-comment\').value); document.getElementById(\'' + x + '-comment\').value = \'\'; document.getElementById(\'' + x + '-comment\').placeholder = \'Comment added. Wait for next refresh.\';">Add comment</button></span></div>';
		swtop.appendChild(commentbox);
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
	el.title = name;
	el.textContent = name;
}

/*
 * Run periodically to trigger map updates when a handler is active
 */
function updateMap()
{
	/*
	 * XXX: This a bit hacky: There are a bunch of links that use
	 * href="#foo" but probably shouldn't. This breaks refresh since we
	 * base this on the location hash. To circumvent that issue
	 * somewhat, we just update the location hash if it's not
	 * "correct".
	 */
	if (nms.updater) {
		if (document.location.hash != ('#' + nms.updater.tag)) {
			document.location.hash = nms.updater.tag;
		}
	}
	if (!newerSwitches())
		return;
	
	if (nms.updater != undefined && nmsData.switches && nms.switches_then) {
		nms.updater.updater();
	}
	drawNow();
}

/*
 * Change map handler (e.g., change from uplink map to ping map)
 */
function setUpdater(fo)
{
	nms.updater = undefined;
	nmsMap.reset();
	nmsData.unregisterHandlerWildcard("mapHandler");
	fo.init();
	nms.updater = fo;
	var foo = document.getElementById("updater_name");
	foo.innerHTML = fo.name + "   ";
	document.location.hash = fo.tag;
}

/*
 * Helper function for updating switch-data without overwriting existing
 * data with non-existent data
 */
function updateSwitches(switchdata,target) {
	target['time'] = switchdata['time'] //Assume we always get time

	if(switchdata.switches != undefined) {
		for(var sw in switchdata.switches) {
			if(switchdata.switches[sw]['management'] != undefined)
				updateSwitchProperty(sw,'management',switchdata.switches[sw]['management'],target);
			if(switchdata.switches[sw]['ports'] != undefined)
				updateSwitchProperty(sw,'ports',switchdata.switches[sw]['ports'],target);
			if(switchdata.switches[sw]['temp'] != undefined)
				updateSwitchProperty(sw,'temp',switchdata.switches[sw]['temp'],target);
			if(switchdata.switches[sw]['temp_time'] != undefined)
				updateSwitchProperty(sw,'temp_time',switchdata.switches[sw]['temp_time'],target);
			if(switchdata.switches[sw]['placement'] != undefined)
				updateSwitchProperty(sw,'placement',switchdata.switches[sw]['placement'],target);
		}
	}
}
/*
 * Helper function for updating a limited subset of switch properties,
 * while the current state of the switch data is unknown.
 */
function updateSwitchProperty(sw,property,data,target) {
  if(target.switches[sw] == undefined)
    target.switches[sw] = {};

  target.switches[sw][property] = data;
}

/*
 * Helper function for reseting switch state data (and keeping more permanent data)
 */
function resetSwitchStates() {
  for (var sw in nmsData.switches.switches) {
    for (var property in nmsData.switches.switches[sw]) {
      if (['ports','temp','temp_time'].indexOf(property) > -1) {
        nmsData.switches.switches[sw][property] = undefined;
      }
    }
  }
}

function applyBlur()
{
	var blur = document.getElementById("shadowBlur");
	var col = document.getElementById("shadowColor");
	nms.shadowBlur = blur.value;
	nms.shadowColor = col.value;
	resetBlur();
	saveSettings();
}

function toggleLayer(layer) {
       var l = document.getElementById(layer);
       if (l.style.display == 'none')
               l.style.display = '';
       else
               l.style.display = 'none';
}

function showBlurBox()
{
	var blur = document.getElementById("shadowBlur");
	var col = document.getElementById("shadowColor");
	blur.value = nms.shadowBlur;
	col.value = nms.shadowColor;
	document.getElementById("blurManic").style.display = '';
}


function commentInactive(id)
{
	commentChange(id,"inactive");
}

function commentPersist(id)
{
	commentChange(id,"persist");
}

function commentDelete(id)
{
	var r = confirm("Really delete comment? (Delted comments are still stored in the database, but never displayed)");
	if (r == true) {
		commentChange(id,"delete");
	}
}

/*
 * FIXME: Neither of these two handle failures in any way, shape or form.
 * Nor do they really give user-feedback. They work, but only by magic.
 */
function commentChange(id,state)
{
	var myData = {
		comment:id,
		state:state
	};
	var foo = document.getElementById("commentRow" + id);
	if (foo) {
		foo.className = '';
		foo.style.backgroundColor = "silver";
	}
	$.ajax({
		type: "POST",
		url: "/api/private/comment-change",
		dataType: "text",
		data:myData,
		success: function (data, textStatus, jqXHR) {
			nms.repop_switch = true;
		}
	});
}

function addComment(sw,comment)
{
	var myData = {
		switch:sw,
		comment:comment
	};
	myData = JSON.stringify(myData);
	$.ajax({
		type: "POST",
		url: "/api/private/comment-add",
		dataType: "text",
		data:myData,
		success: function (data, textStatus, jqXHR) {
			nms.repop_switch = true;
		}
	});
}

/*
 * Returns true if we have now and then-data for switches and that the
 * "now" is actually newer. Useful for basic sanity and avoiding negative
 * values when rewinding time.
 */
function newerSwitches()
{
	if (nmsData.switches.time == undefined || nms.switches_then.time == undefined)
		return false;
	var now_timestamp = stringToEpoch(nmsData.switches.time);
	var then_timestamp = stringToEpoch(nms.switches_then.time);
	if (now_timestamp == 0 || then_timestamp == 0 || then_timestamp >= now_timestamp)
		return false;
	return true;
}

/*
 * Draw a linknet with index i.
 *
 * XXX: Might have to change the index here to match backend
 */
function drawLinknet(i)
{
	var c1 = nms.linknet_color[i] && nms.linknet_color[i].c1 ? nms.linknet_color[i].c1 : blue;
	var c2 = nms.linknet_color[i] && nms.linknet_color[i].c2 ? nms.linknet_color[i].c2 : blue;
	if (nmsData.switches.switches[nmsData.switches.linknets[i].sysname1] && nmsData.switches.switches[nmsData.switches.linknets[i].sysname2]) {
		connectSwitches(nmsData.switches.linknets[i].sysname1,nmsData.switches.linknets[i].sysname2, c1, c2);
	}
}

/*
 * Draw all linknets
 */
function drawLinknets()
{
	if (nmsData.switches && nmsData.switches.linknets) {
		for (var i in nmsData.switches.linknets) {
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

function drawSwitchInfo()
{
	if (!nmsData.switches || !nmsData.switches.switches)
		return;
	for (var sw in nms.switchInfo) {
		switchInfoText(sw, nms.switchInfo[sw]);
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
	if (!nmsData.switches)
		return;
	// XXX: Get rid of microseconds that we get from the backend.
	var now = /^[^.]*/.exec(nmsData.switches.time);
	dr.top.ctx.font = Math.round(2 * nms.fontSize * canvas.scale) + "px " + nms.fontFace;
	dr.top.ctx.clearRect(0,0,Math.floor(800 * canvas.scale),Math.floor(100 * canvas.scale));
	dr.top.ctx.fillStyle = "white";
	dr.top.ctx.strokeStyle = "black";
	dr.top.ctx.lineWidth = Math.floor(nms.fontLineFactor * canvas.scale);
	if (dr.top.ctx.lineWidth == 0) {
		dr.top.ctx.lineWidth = Math.round(nms.fontLineFactor * canvas.scale);
	}
	dr.top.ctx.strokeText(now, 0 + margin.text, 25 * canvas.scale);
	dr.top.ctx.fillText(now, 0 + margin.text, 25 * canvas.scale);
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
	//dr.text.ctx.font = Math.floor(nms.fontSize * canvas.scale) + "px " + nms.fontFace;
	dr.textInfo.ctx.font = Math.floor(nms.fontSize * canvas.scale) + "px " + nms.fontFace;
	drawLinknets();
	drawSwitchInfo();
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
	x = parseInt(parseInt(x) / nmsMap.scale);
	y = parseInt(parseInt(y) / nmsMap.scale);

	for (var v in nmsData.switches.switches) {
		if(isIn(nmsData.switches.switches[v]['placement'],x,y)) {
			return v;
		}
	}
	return undefined;
}

/*
 * Called when a switch is clicked
 */
function switchClick(sw)
{
	if (nms.switch_showing == sw)
		hideSwitch();
	else
		showSwitch(sw);
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
 * Set night mode to whatever 'toggle' is.
 * 
 * XXX: setScale() is a bit of a hack, but it really is the same stuff we
 * need to do: Redraw "everything" (not really).
 */
function setNightMode(toggle) {
	nms.nightMode = toggle;
	var body = document.getElementById("body");
	body.style.background = toggle ? "black" : "white";
	var nav = document.getElementsByTagName("nav")[0];
	if (toggle) {
		nav.classList.add('navbar-inverse');
	} else {
		nav.classList.remove('navbar-inverse');
	}
	nmsMap.setNightMode(toggle);
}

/*
 * Draw the blur for a box.
 */
function drawBoxBlur(x,y,boxw,boxh)
{
	var myX = Math.floor(x * canvas.scale);
	var myY = Math.floor(y * canvas.scale);
	var myX2 = Math.floor((boxw) * canvas.scale);
	var myY2 = Math.floor((boxh) * canvas.scale);
	dr.blur.ctx.fillRect(myX,myY, myX2, myY2);
}

/*
 * Boot up "fully fledged" NMS.
 *
 * If you only want parts of the functionality, then re-implement this
 * (e.g., just add and start the handlers you want, don't worry about
 * drawing, etc).
 */
function initNMS() {
	
	nms.timers.playback = new nmsTimer(nms.playback.tick, 1000, "Playback ticker", "Handler used to advance time");
	
	// Public
	
	nmsData.registerSource("ping", "/api/public/ping");
	nmsData.registerSource("switches","/api/public/switches");
	nmsData.registerSource("switchstate","/api/public/switch-state");

	// Private	
	nmsData.registerSource("portstate","/api/private/port-state");
	nmsData.registerSource("comments", "/api/private/comments");
	nmsData.registerSource("smanagement","/api/private/switches-management");

	nmsMap.init();
	detectHandler();
	nms.playback.play();
	setupKeyhandler();
	restoreSettings();
}

function detectHandler() {
	var url = document.URL;
	for (var i in handlers) {
		if (('#' + handlers[i].tag) == document.location.hash) {
			setUpdater(handlers[i]);
			return;
		}
	}
	setUpdater(handler_ping);
}

function setMenu()
{
	var nav = document.getElementsByTagName("nav")[0];
	nav.style.display = nms.menuShowing ? '' : 'none';
}

function toggleMenu()
{
	nms.menuShowing = ! nms.menuShowing;
	setMenu();
	saveSettings();
}

function setMapModeFromN(e,key)
{
	switch(key) {
		case '1':
			setUpdater(handler_ping);
			break;
		case '2':
			setUpdater(handler_uplinks);
			break;
		case '3':
			setUpdater(handler_temp);
			break;
		case '4':
			setUpdater(handler_traffic);
			break;
		case '5':
			setUpdater(handler_comment);
			break;
		case '6':
			setUpdater(handler_traffic_tot);
			break;
		case '7':
			setUpdater(handler_disco);
			break;
	}
	return true;
}

function moveTimeFromKey(e,key)
{
	switch(key) {
		case 'h':
			nms.playback.stepTime(-3600);
			break;
		case 'j':
			nms.playback.stepTime(-300);
			break;
		case 'k':
			nms.playback.stepTime(300);
			break;
		case 'l':
			nms.playback.stepTime(3600);
			break;
		case 'p':
			nms.playback.toggle();
			break;
		case 'r':
			nms.playback.setNow();
			nms.playback.play();
			break;
	}
	return true;
}

function keyPressed(e)
{
	if (e.target.nodeName == "INPUT") {
		return false;
	}
	var key = String.fromCharCode(e.keyCode);
	if (nms.keyBindings[key])
		return nms.keyBindings[key](e,key);
	if (nms.keyBindings['default'])
		return nms.keyBindings['default'](e,key);
	return false;
}

function setupKeyhandler()
{
	var b = document.getElementsByTagName("body")[0];
	b.onkeypress = function(e){keyPressed(e);};
}


function getCookie(cname) {
	var name = cname + "=";
	var ca = document.cookie.split(';');
	for(var i=0; i<ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ')
			c = c.substring(1);
		if (c.indexOf(name) == 0)
			return c.substring(name.length,c.length);
	}
	return "";
}

function saveSettings()
{
	var foo={};
	for (var v in nms.settingsList) {
		foo[nms.settingsList[v]] = nms[nms.settingsList[v]];
	}
	document.cookie = 'nms='+btoa(JSON.stringify(foo));
}

function restoreSettings()
{
	try {
		var retrieve = JSON.parse(atob(getCookie("nms")));
	} catch(e) { 
		console.log("nothing saved");
	}

	for (var v in retrieve) {
		nms[v] = retrieve[v];
	}
	setMenu();
	setNightMode(nms.nightMode);
}

function forgetSettings()
{
	document.cookie = 'nms=' + btoa('{}');
}

/*
 * Time travel gui
 */
var datepicker;
function startNowPicker(now) {
  $.datetimepicker.setLocale('no');
  $('#nowPicker').datetimepicker('destroy');
  if(!now && nms.now)
    now = nms.now;
  datepicker = $('#nowPicker').datetimepicker({
    value: now,
    mask:false,
    inline:true,
    todayButton: false,
    validateOnBlur:false,
    dayOfWeekStart:1,
    maxDate:'+1970/01/01',
    onSelectDate: function(ct,$i){
      document.getElementById('nowPicker').dataset.iso = localEpochToString(ct.valueOf()/1000);
    },
    onSelectTime: function(ct,$i){
      document.getElementById('nowPicker').dataset.iso = localEpochToString(ct.valueOf()/1000);
    },
    onGenerate: function(ct,$i){
      document.getElementById('nowPicker').dataset.iso = localEpochToString(ct.valueOf()/1000);
    }
  });
}
