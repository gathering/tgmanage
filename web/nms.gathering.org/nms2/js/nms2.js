var nms = {
	debug: true,
};

var ports_now;
var ports_then;
var speed = 0;
var sw;
var infra;


function updateSwitches()
{
	$.ajax({
		type: "GET",
		url: "/switches-json2.pl",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			infra = JSON.parse(data);
		}
	});
}

function updatePorts()
{
	$.ajax({
		type: "GET",
		url: "/port-state.pl",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			var list = document.getElementById("switch-list");
			var v = list.value;
			var arry = new Array();
			ports_now = switchdata;
			for (x in switchdata) {
				arry.push(x);
			}
			arry.sort();
			list.options.length = 0;
			for (x in arry) {
				list.add(new Option(arry[x]));
			}
			if (v)
				list.value = v;
		}
	});
	$.ajax({
		type: "GET",
		url: "/port-state.pl?time=5m",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			ports_then = switchdata;
		}
	})
}

function switchChange()
{
	var sw = document.getElementById("switch-list").value;
	var list = document.getElementById("port-list");
	var v = list.value;
	var array = new Array();
	for (x in ports_now[sw]["ports"]) {
		array.push(x);
	}
	array.sort();
	list.options.length = 0;
	for (x in array) {
		list.add(new Option(array[x]));
	}
	if (v)
		list.value = v;
	var info = document.getElementById("switch-info");
	info.value = "Temp: " +  infra["switches"][sw]["temp"] + " °C";	
	
}

function portChange()
{
	var sw = document.getElementById("switch-list").value;
	var port = document.getElementById("port-list").value;
	var out = document.getElementById("foo");
	var diff = parseInt(parseInt(ports_now[sw]["ports"][port]["time"]) - parseInt(ports_then[sw]["ports"][port]["time"]));
	var tmp2 = "time diff: " + diff + "s\n";
	for (x in ports_now[sw]["ports"][port]) {
		then = parseInt(ports_then[sw]["ports"][port][x]);
		now = parseInt(ports_now[sw]["ports"][port][x]);
		diffval = (now - then);
		if (diffval<0) {
			diffval = (now + Math.pow(2,32)) - then;
		}
		tmp2 +=  x + ": " + now;
		tmp2 +=  "      (" + then + ")\n";
		tmp2 +=  "diff: " + x + ": " + (diffval) + " : ";
		tmp2 +=  parseInt(((diffval)/diff)/1024) + " k/s\n";
		tmp2 += "---------\n";

	}
	out.innerHTML = tmp2;
}

function updateSpeed()
{
	var speed_in = parseInt(0);
	var counter=0;
	var sw;
	for (sw in ports_now) {
		for (port in ports_now[sw]["ports"]) {
			if (!ports_now[sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			if (!ports_then[sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			var diff = parseInt(parseInt(ports_now[sw]["ports"][port]["time"]) - parseInt(ports_then[sw]["ports"][port]["time"]));
			var then = parseInt(ports_then[sw]["ports"][port]["ifhcinoctets"]) / 1024;
			var now =  parseInt( ports_now[sw]["ports"][port]["ifhcinoctets"]) / 1024;
			var diffval = (now - then);
			if (then == 0 || now == 0 || diffval == 0 || diffval == NaN) {
				continue;
			}
			speed_in += parseInt(diffval/diff) / 1024 ;
			counter++;
		}
	}
	var out = document.getElementById("speed");
	speed = speed_in;
	out.innerHTML = "Aggregated speed: " + ((speed_in) / 1024).toPrecision(5) + " GB/s";

}
updateSwitches();
setInterval(function(){updateSwitches()},5000);
setInterval(function(){updatePorts()},2000);
setInterval(function(){updateSpeed()},2000);

