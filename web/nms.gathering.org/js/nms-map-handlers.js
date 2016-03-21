/*
 * Map handlers/updaters for NMS.
 *
 * These are functions used to determine how the map should look in NMS.
 * They represent vastly different information, but in a uniform way.
 *
 * The idea is that these updaters only parse information that's fetched by
 * NMS - they do not request additional information. E.g., ping data is
 * always present, but until the ping-handler is active, it isn't
 * displayed. This might seem redundant, but it means any handler can
 * utilize information from any aspect of NMS, and thus opens NMS up to the
 * world of intelligent maps base don multiple data sources.
 *
 * Warning: This paradigm will change. Handlers will be expected to
 * register their own callbacks for nmsData. Work in progress.
 *
 */

/*
 */

var handler_uplinks = {
	init:uplinkInit,
	tag:"uplink",
	name:"Uplink map"
};

var handler_temp = {
	init:tempInit,
	tag:"temp",
	name:"Temperature map"
};

var handler_ping = {
	init:pingInit,
	tag:"ping",
	name:"IPv4 Ping map"
};

var handler_traffic = {
	init:trafficInit,
	tag:"traffic",
	name:"Uplink traffic map"
};

var handler_traffic_tot = {
	init:trafficTotInit,
	tag:"traffictot",
	name:"Switch traffic map"
};

var handler_disco = {
	init:discoInit,
	tag:"disco",
	name:"Disco fever"
};

var handler_comment = {
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
 */
function uplinkUpdater()
{
	if (!nmsData.switches)
		return;
	if (!nmsData.switches.switches)
		return;
	if (!nmsData.switchstate)
		return;
	if (!nmsData.switchstate.switches)
		return;
	for (var sw in nmsData.switches.switches) {
		var uplinks=0;
		if (nmsData.switchstate.switches[sw] == undefined || nmsData.switchstate.switches[sw].uplinks == undefined) {
			uplinks=0;
		} else {
			uplinks = nmsData.switchstate.switches[sw].uplinks.live;
			nuplinks = nmsData.switchstate.switches[sw].uplinks.total;
		}

		if (uplinks == 0) {
			nmsMap.setSwitchColor(sw,"white");
		} else if (nuplinks == uplinks) {
			nmsMap.setSwitchColor(sw,green);
		} else if (nuplinks - uplinks == 1) {
			nmsMap.setSwitchColor(sw, orange);
		} else if (nuplinks - uplinks == 2) {
			nmsMap. setSwitchColor(sw, red);
		} else if (uplinks > 3) {
			nmsMap.setSwitchColor(sw, blue);
		}
	}
}

/*
 * Init-function for uplink map
 */
function uplinkInit()
{
	nmsData.addHandler("switches","mapHandler",uplinkUpdater);
	nmsData.addHandler("switchstate","mapHandler",uplinkUpdater);
	setLegend(1,"white","0 uplinks");	
	setLegend(2,red,"2 missing");	
	setLegend(3,orange,"1 missing");	
	setLegend(4,green,"0 missing");	
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
	for (var sw in nms.switches_now["switches"]) {
		var speed = 0;
		for (var port in nms.switches_now["switches"][sw]["ports"]) {
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
	for (var sw in nms.switches_now["switches"]) {
		var speed = 0;
		for (var port in nms.switches_now["switches"][sw]["ports"]) {
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


function temp_color(t)
{
	if (t == undefined) {
		console.log("Temp_color, but temp is undefined");
		return blue;
	}
	t = parseInt(t);
	t = Math.floor(t * 10);
	return getColorStop(t);
}

function tempUpdater()
{
	if(!nmsData.switches)
		return;

	for ( var sw in nmsData.switches["switches"]) {
		var t = "white";
		var temp = "";

		if(!nmsData.snmp || !nmsData.snmp.snmp[sw]["misc"] || !nmsData.snmp.snmp[sw]["misc"]["enterprises.2636.3.1.13.1.7.7.1.0.0"])
			continue;

		var tempObj = nmsData.snmp.snmp[sw]["misc"]["enterprises.2636.3.1.13.1.7.7.1.0.0"];
		Object.keys(tempObj).forEach(function (key) {
			if(key == "") {
				temp = tempObj[key] + "°C";
				t = temp_color(temp);
			}
		});

		nmsMap.setSwitchColor(sw, t);
		nmsMap.setSwitchInfo(sw, temp);
	}
}

function tempInit()
{ 
	//Padded the gradient with extra colors for the upper unused values
	drawGradient([blue,lightgreen,green,orange,red,red,red,red,red,red]);
	setLegend(1,temp_color(0),"0 °C");	
	setLegend(2,temp_color(15),"15 °C");	
	setLegend(3,temp_color(25),"25 °C");	
	setLegend(4,temp_color(35),"35 °C");	
	setLegend(5,temp_color(45),"45 °C");	
	nmsData.addHandler("switchstate","mapHandler",tempUpdater);
}

function pingUpdater()
{
	if (nmsData.switches == undefined || nmsData.switches.switches == undefined) {
		return;
	}
	for (var sw in nmsData.switches.switches) {
		try {
            var c;
			if (nmsData.ping.switches[sw].age > 0) {
				c = red;
			} else {
				c = gradient_from_latency(nmsData.ping.switches[sw].latency);
			}
			nmsMap.setSwitchColor(sw, c);
		} catch (e) {
			nmsMap.setSwitchColor(sw, blue);
		}
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
	nmsData.addHandler("ping","mapHandler",pingUpdater);
	nmsData.addHandler("switches","mapHandler",pingUpdater);
	nmsData.addHandler("ticker", "mapHandler", pingUpdater);
}

function commentUpdater()
{
	var realnow = Date.now();
	var now = Math.floor(realnow / 1000);
	if (nmsData.comments == undefined || nmsData.comments.comments == undefined) {
		return
	}
	for (var sw in nmsData.switches.switches) {
		var c = "white";
		if (nmsData.comments.comments[sw] == undefined) {
			nmsMap.setSwitchColor(sw,c);
			continue;
		}
		var s = nmsData.comments.comments[sw];
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
		nmsMap.setSwitchColor(sw, c);
	}
}


function commentInit()
{
	nmsData.addHandler("comments","mapHandler",commentUpdater);
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
/*	for (var i in nms.switches_now.linknets) {
		setLinknetColors(i, getRandomColor(), getRandomColor());
	}
*/
	if (nmsData.switches == undefined  || nmsData.switches.switches == undefined) {
		return;
	}
	for (var sw in nmsData.switches.switches) {
		nmsMap.setSwitchColor(sw, getRandomColor());
	}
}

function discoDo() {
	randomizeColors();
	setTimeout(randomizeColors,500);
}
function discoInit()
{
	nmsData.addHandler("ticker", "mapHandler", discoDo);
	
	setNightMode(true);
	setLegend(1,blue,"Y");	
	setLegend(2,red, "M");
	setLegend(3,orange,"C");
	setLegend(4,green, "A");
	setLegend(5,"white","!");
}

