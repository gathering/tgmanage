/*
 * Map handlers/updaters for NMS.
 *
 * These are functions used to determine how the map should look in NMS.
 * They represent vastly different information, but in a uniform way. I
 * suppose this is the c++-type of object orientation...
 *
 * The idea is that these updaters only parse information that's fetched by
 * NMS - they do not request additional information. E.g., ping data is
 * always present, but until the ping-handler is active, it isn't
 * displayed. This might seem redundant, but it means any handler can
 * utilize information from any aspect of NMS, and thus opens NMS up to the
 * world of intelligent maps base don multiple data sources.
 */

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

var handler_comment = {
	updater:commentUpdater,
	init:commentInit,
	name:"Fresh comment spotter"
};
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
	setLegend(1,"blue","0 (N/A)");	
	setLegend(5,"red", "1000Mb/s or more");	
	setLegend(4,"yellow","100Mb/s to 800Mb/s");	
	setLegend(3,"green", "5Mb/s to 100Mb/s");	
	setLegend(2,"white","0 to 5Mb/s");	
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

function commentUpdater()
{
	var realnow = Date.now();
	if (nms.now) {
		realnow = Date.parse(nms.now);
	}
	var now = Math.floor(realnow / 1000);
	for (var sw in nms.switches_now["switches"]) {
		var c = "green";
		var s = nms.switches_now["switches"][sw];
		if (s["comments"] && s["comments"].length > 0) {
			var then = 0;
			c = "yellow";
			for (var v in s["comments"]) {
				var then_test = parseInt(s["comments"][v]["time"]);
				if (then_test > then && then_test <= now)
					then = then_test;
			}
			if (then > (now - (60*15))) {
				c = "red";
			} else if (then > (now - (120*60))) {
				c = "orange";
			} else if (then < (now - (60*60*24))) {
				c = "white";
			}
			/*
			 * Special case during time travel: We have
			 * comments, but are not showing them yet.
			 */
			if (then == 0)
				c = "green";
		}
		setSwitchColor(sw, c);
	}
}

function commentInit()
{
	setLegend(1,"green","0 comments");
	setLegend(2,"white","1d+ old");
	setLegend(3,"red", "0 - 15m old");
	setLegend(4,"orange","15m - 120m old");	
	setLegend(5,"yellow" ,"2h - 24h old");	
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
	setLegend(1,"blue","Y");	
	setLegend(2,"red", "M");
	setLegend(3,"yellow","C");
	setLegend(4,"green", "A");
	setLegend(5,"white","!");
}

