var nms = {
	updater:undefined, // Active updater
	switches_now:undefined, // Most recent data
	switches_then:undefined, // 2 minutes old
	speed:0, // Current aggregated speed
	full_speed:false, // Set to 'true' to include ALL interfaces
	ping_data:undefined,
	globalmap:[], // DOM objects for switches
	drawn:false, // Set to 'true' when switches are drawn
	did_update:false // Set to 'true' after we've done some basic updating
};

/*
 * Handlers. "updater" is run periodically when the handler is active, and
 * "init" is run once when it's activated.
 */

var handler_uplinks = {
	updater:uplinkUpdater,
	init:uplinkInit
};

var handler_temp = {
	updater:tempUpdater,
	init:tempInit
};

var handler_ping = {
	updater:pingUpdater,
	init:pingInit
};

/*
 * Display info on switch "x" in the info-box
 */
function switchInfo(x)
{
		var switchele = document.getElementById("info-switch-table");
		var sw = nms.switches_now["switches"][x];
		var swtop = document.getElementById("info-switch-parent");
		var tr;
		var td1;
		var td2;
		
		swtop.removeChild(switchele);

		switchele = document.createElement("table");
		switchele.id = "info-switch-table";
		switchele.style.zIndex =  100;
		switchele.className = "table table-bordered";
			
		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Sysname";
		td2.innerHTML = x;
		tr.appendChild(td1); tr.appendChild(td2); switchele.appendChild(tr);

		tr = document.createElement("tr"); td1 = document.createElement("td"); td2 = document.createElement("td");
		td1.innerHTML = "Management IP";
		td2.innerHTML = sw["management"]["ip"];
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

		swtop.appendChild(switchele);
}

/*
 * Draw/create a specific switch
 */
function createSwitch(sysname, x, y, zorder, width, height)
{
	var s = document.createElement("div");
	var map = document.getElementById('map');
	var top_offset = map.getBoundingClientRect().top;
	var left_offset = map.getBoundingClientRect().left;

	var onclick = "console.log(\"foo\");";
	s.style.position = 'absolute';
	s.style.left = (left_offset + x) + 'px';
	s.style.top = (top_offset + y) + 'px';
	s.style.width = width + 'px';
	s.style.height = height + 'px';
	s.style.backgroundColor = '#0000ff';
	s.style.border = '1px solid black';
	s.style.padding = "0";
	s.style.zIndex = zorder + 100;
	s.addEventListener("click", function(){ switchInfo(sysname); });
	s.title = sysname + " - " + nms.switches_now["switches"][sysname]["management"]["ip"];
	nms.globalmap[sysname] = s;

	var span = document.createElement("div");
	span.className = "switchname";
	if (width < 1.5 * height) {
		span.className = "switchname rot";
	}
	span.style.border = "0";
	span.style.padding = "0";
	s.appendChild(span);

	var text = document.createTextNode(sysname);
	span.appendChild(text);

	s.setAttribute("data-sysname", sysname);

	document.body.appendChild(s);
}

/*
 * Draw/add switches.
 */
function drawSwitches()
{
	for (var sysname in nms.switches_now["switches"]) {
		var s = nms.switches_now['switches'][sysname]["placement"];
		createSwitch(sysname,
		              parseInt(s['x']),
			      parseInt(s['y']),
			      parseInt(s['zorder']),
		              parseInt(s['width']),
		              parseInt(s['height']));
	}
	nms.drawn = true;
}

/*
 * Update various info elements periodically.
 */
function updateInfo()
{
	if (!nms.drawn && nms.switches_now != undefined) {
		drawSwitches();
	}
	var speedele = document.getElementById("speed");
	speedele.innerHTML = (8 * parseInt(nms.speed) / 1024 / 1024 / 1024 ).toPrecision(5) + " Gbit/s";
}

/*
 * Short hand for setting color on a switch in the map
 */
function colorSwitch(sysname, color)
{
	nms.globalmap[sysname].style.background = color;
}

/*
 * Update function for uplink map
 * Run periodically when uplink map is active.
 */
function uplinkUpdater()
{
	for (sw in nms.switches_now["switches"]) {
		var uplinks=0;
		for (port in nms.switches_now["switches"][sw]["ports"]) {
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
			colorSwitch(sw,"blue");
		} else if (uplinks == 1) {
			colorSwitch(sw,"red");
		} else if (uplinks == 2) {
			colorSwitch(sw, "yellow");
		} else if (uplinks == 3) { 
			colorSwitch(sw, "green");
		} else if (uplinks > 3) {
			colorSwitch(sw, "white");
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

function rgb_from_max(x)
{
	x = x/100;
	var colorred = 255 * x;
	var colorblue = 255 - colorred;

	return 'rgb(' + Math.round(colorred) + ", 0, " + Math.round(colorblue) + ')';
}

function temp_color(t)
{
	t = Math.round((t / 60) * 100);
	return rgb_from_max(t);
}

/*
 * There are 4 legend-bars. This is a helper-function to set the color and
 * description/name for each one. Used from handler init-functions.
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
		var t = nms.switches_now["switches"][sw]["temp"];
		
		colorSwitch(sw, temp_color(t));
	}
}

function tempInit()
{
	setLegend(1,temp_color(10),"10 °C");	
	setLegend(2,temp_color(20),"20 °C");	
	setLegend(3,temp_color(30),"30 °C");	
	setLegend(4,temp_color(40),"40 °C");	
	setLegend(5,temp_color(50),"50 °C");	
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
		l = Math.round(l * 255.0);
		return 'rgb(255, ' + l + ', 0)';
	} else {
		l = Math.pow(l, 1.0/2.2);
		l = Math.round(l * 255.0);
		return 'rgb(' + l + ', 255, 0)';
	}
}

function pingUpdater()
{
	for (var sw in nms.ping_data["switches"]) {
		colorSwitch(sw, gradient_from_latency(nms.ping_data["switches"][sw]["latency"]));
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
	if (nms.updater != undefined) {
		nms.updater();
	}
}

/*
 * Change map handler (e.g., change from uplink map to ping map)
 */
function setUpdater(fo)
{
	nms.updater = undefined;
	fo.init();
	nms.updater = fo.updater;
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
		if (!nms.drawn) {
			drawSwitches();
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
	$.ajax({
		type: "GET",
		url: "/ping-json2.pl",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			nms.ping_data = JSON.parse(data);
			initialUpdate();
		}
	});
}

/*
 * Update nms.switches_now and nms.switches_then
 */
function updatePorts()
{
	$.ajax({
		type: "GET",
		url: "/port-state.pl",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			nms.switches_now = switchdata;
			initialUpdate();
		}
	});
	$.ajax({
		type: "GET",
		url: "/port-state.pl?time=5m",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			nms.switches_then = switchdata;
			initialUpdate();
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
