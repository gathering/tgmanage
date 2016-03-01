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
	tag:"uplink",
	name:"Uplink map"
};

var handler_temp = {
	updater:tempUpdater,
	init:tempInit,
	tag:"temp",
	name:"Temperature map"
};

var handler_ping = {
	updater:pingUpdater,
	init:pingInit,
	tag:"ping",
	name:"IPv4 Ping map"
};

var handler_traffic = {
	updater:trafficUpdater,
	init:trafficInit,
	tag:"traffic",
	name:"Uplink traffic map"
};

var handler_traffic_tot = {
	updater:trafficTotUpdater,
	init:trafficTotInit,
	tag:"traffictot",
	name:"Switch traffic map"
};

var handler_disco = {
	updater:randomizeColors,
	init:discoInit,
	tag:"disco",
	name:"Disco fever"
};

var handler_comment = {
	updater:commentUpdater,
	init:commentInit,
	tag:"comment",
	name:"Fresh comment spotter"
};

var handlers = [
	handler_uplinks,
	handler_temp,
	handler_ping,
	handler_traffic,
	handler_disco,
	handler_comment,
	handler_traffic_tot
	];

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
			setSwitchColor(sw,"white");
		} else if (uplinks == 1) {
			setSwitchColor(sw,red);
		} else if (uplinks == 2) {
			setSwitchColor(sw, orange);
		} else if (uplinks == 3) { 
			setSwitchColor(sw, green);
		} else if (uplinks > 3) {
			setSwitchColor(sw, blue);
		}
	}
}

/*
 * Init-function for uplink map
 */
function uplinkInit()
{
	setLegend(1,"white","0 uplinks");	
	setLegend(2,red,"1 uplink");	
	setLegend(3,orange,"2 uplinks");	
	setLegend(4,green,"3 uplinks");	
	setLegend(5,blue,"4 uplinks");	
}

/*
 * Init-function for uplink map
 */
function trafficInit()
{
	var m = 1024 * 1024 / 8;
	drawGradient([lightgreen,green,orange,red]);
	setLegend(1,colorFromSpeed(0),"0 (N/A)");	
	setLegend(5,colorFromSpeed(2000 * m) , "2000Mb/s");	
	setLegend(4,colorFromSpeed(1500 * m),"1500Mb/s");	
	setLegend(3,colorFromSpeed(500 * m),"500Mb/s");	
	setLegend(2,colorFromSpeed(10 * m),"10Mb/s");	
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
				 if (!nms.switches_then["switches"][sw] ||
				     !nms.switches_then["switches"][sw]["ports"] ||
				     !nms.switches_then["switches"][sw]["ports"][port])
					 continue;
				 var t = nms.switches_then["switches"][sw]["ports"][port];
				 var n = nms.switches_now["switches"][sw]["ports"][port];
				 speed += (parseInt(t["ifhcoutoctets"]) -parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
				 speed += (parseInt(t["ifhcinoctets"]) -parseInt(n["ifhcinoctets"])) / (parseInt(t["time"] - n["time"]));
			 }
		}
                if(!isNaN(speed))
                        setSwitchColor(sw,colorFromSpeed(speed));
	}
}

/*
 * Init-function for uplink map
 */
function trafficTotInit()
{
	var m = 1024 * 1024 / 8;
	drawGradient([lightgreen,green,orange,red]);
	setLegend(1,colorFromSpeed(0),"0 (N/A)");	
	setLegend(5,colorFromSpeed(5000 * m,5) , "5000Mb/s");	
	setLegend(4,colorFromSpeed(3000 * m,5),"3000Mb/s");	
	setLegend(3,colorFromSpeed(1000 * m,5),"1000Mb/s");	
	setLegend(2,colorFromSpeed(100 * m,5),"100Mb/s");	
}

function trafficTotUpdater()
{
	if (!nms.switches_now["switches"])
		return;
	for (sw in nms.switches_now["switches"]) {
		var speed = 0;
		for (port in nms.switches_now["switches"][sw]["ports"]) {
			if (!nms.switches_then["switches"][sw] ||
			    !nms.switches_then["switches"][sw]["ports"] ||
			    !nms.switches_then["switches"][sw]["ports"][port])
				continue;
			var t = nms.switches_then["switches"][sw]["ports"][port];
			var n = nms.switches_now["switches"][sw]["ports"][port];
			speed += (parseInt(t["ifhcoutoctets"]) -parseInt(n["ifhcoutoctets"])) / (parseInt(t["time"] - n["time"]));
		}
		setSwitchColor(sw,colorFromSpeed(speed,5));
	}
}

function colorFromSpeed(speed,factor)
{
	var m = 1024 * 1024 / 8;
	if (factor == undefined)
		factor = 2;
	if (speed == 0)
		return blue;
	speed = speed < 0 ? 0 : speed;
	return getColorStop( 1000 * (speed / (factor * (1000 * m))));
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
		return blue;
	}
	t = parseInt(t) - 12;
	t = Math.floor((t / 23) * 1000);
	return getColorStop(t);
}

function tempUpdater()
{
	for (sw in nms.switches_now["switches"]) {
		var t = "white";
		var temp = "";
		if (nms.switches_now["switches"][sw]["temp"]) {
			t = temp_color(nms.switches_now["switches"][sw]["temp"]);
			temp = nms.switches_now["switches"][sw]["temp"] + "°C";
		}
		
		setSwitchColor(sw, t);
		switchInfoText(sw, temp);
	}
}

function tempInit()
{
	drawGradient(["black",blue,lightblue,lightgreen,green,orange,red]);
	setLegend(1,temp_color(15),"15 °C");	
	setLegend(2,temp_color(20),"20 °C");	
	setLegend(3,temp_color(25),"25 °C");	
	setLegend(4,temp_color(30),"30 °C");	
	setLegend(5,temp_color(35),"35 °C");	
}

function pingUpdater()
{
	if (!nms.ping_data || !nms.ping_data["switches"]) {
		resetColors();
		return;
	}
	for (var sw in nms.switches_now["switches"]) {
		var c = blue;
		if (nms.ping_data['switches'] && nms.ping_data['switches'][sw])
			c = gradient_from_latency(nms.ping_data["switches"][sw]["latency"]);
		setSwitchColor(sw, c);
	}
	for (var ln in nms.switches_now["linknets"]) {
		var c1 = blue;
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
	drawGradient([green,lightgreen,orange,red]);
	setLegend(1,gradient_from_latency(1),"1ms");	
	setLegend(2,gradient_from_latency(30),"30ms");	
	setLegend(3,gradient_from_latency(60),"60ms");	
	setLegend(4,gradient_from_latency(100),"100ms");	
	setLegend(5,gradient_from_latency(undefined) ,"No response");	
}

function commentUpdater()
{
	var realnow = Date.now();
	var now = Math.floor(realnow / 1000);
	for (var sw in nms.switches_now["switches"]) {
		var c = "white";
		var s = nms.switches_now["switches"][sw];
		if (s["comments"] && s["comments"].length > 0) {
			var then = 0;
			var active = 0;
			var persist = 0;
			c = "yellow";
			for (var v in s["comments"]) {
				var then_test = parseInt(s["comments"][v]["time"]);
				if (then_test > then && s["comments"][v]["state"] != "inactive")
					then = then_test;
				if (s["comments"][v]["state"] == "active") {
					active++;
				}
				if (s["comments"][v]["state"] == "persist")
					persist++;
			}
			if (then > (now - (60*15))) {
				c = red;
			} else if (active > 0) {
				c = orange;
			} else if (persist > 0) {
				c = blue;
			} else {
				c = green;
			}
		}
		setSwitchColor(sw, c);
	}
}


function commentInit()
{
	setLegend(1,"white","0 comments");
	setLegend(2,blue,"Persistent");
	setLegend(3,red, "New");
	setLegend(4,orange,"Active");	
	setLegend(5,green ,"Old/inactive only");	
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
	setLegend(1,blue,"Y");	
	setLegend(2,red, "M");
	setLegend(3,orange,"C");
	setLegend(4,green, "A");
	setLegend(5,"white","!");
}

