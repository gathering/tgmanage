var switches = [];
var linknets = [];
var last_dataset = [];
get_switches();
get_ping();

function json_request(url, func, repeat_ms) {
	var request = new XMLHttpRequest();
	request.open('GET', url, true);

	request.onload = function() {
		if (this.status >= 200 && this.status < 400) {
			func(JSON.parse(this.response));
		} else if (this.status != 410) {
			json_request(url, func, repeat_ms);
		}
	};
	request.onerror = function() {
		json_request(url, func, repeat_ms);
	};
	request.send();
}

function get_switches() {
	json_request(switches_url, draw_switches, 1000);
}

function get_ping() {
	json_request(ping_url, update_ping, 1000);
}

function draw_switches(json) {
	for (var switchnum in switches) {
		document.body.removeChild(switches[switchnum]);
	}
	switches = [];
	var lines = document.getElementById("lines");
	for (var linknetnum in linknets) {
		lines.removeChild(linknets[linknetnum][0]);
		lines.removeChild(linknets[linknetnum][1]);
		lines.removeChild(linknets[linknetnum][2]);
	}
	linknets = [];
	
	for (var switchnum in json['switches']) {
		var s = json['switches'][switchnum];
		create_switch(switchnum,
	  	              s['sysname'],
		              parseInt(s['x']),
			      parseInt(s['y']),
			      parseInt(s['zorder']),
		              parseInt(s['width']),
		              parseInt(s['height']));
	}

	if (draw_linknets) {
		for (var i = 0; i < json['linknets'].length; ++i) {
			var linknet = json['linknets'][i];
			create_linknet(linknet['linknet'], linknet['switch1'], linknet['switch2']);
		}
	}

	setTimeout(get_switches, 60000);
	really_update_ping(last_dataset);
}

function create_linknet(linknetnum, switch1, switch2) {
	var s1 = switches[switch1];
	var s2 = switches[switch2];
	var s1x = parseInt(s1.style.left.replace("px", "")) + 0.5 * parseInt(s1.style.width.replace("px", ""));
	var s1y = parseInt(s1.style.top.replace("px", "")) + 0.5 * parseInt(s1.style.height.replace("px", ""));
	var s2x = parseInt(s2.style.left.replace("px", "")) + 0.5 * parseInt(s2.style.width.replace("px", ""));
	var s2y = parseInt(s2.style.top.replace("px", "")) + 0.5 * parseInt(s2.style.height.replace("px", ""));

	var midx = 0.5 * (s1x + s2x);
	var midy = 0.5 * (s1y + s2y);

	var outline = document.createElementNS("http://www.w3.org/2000/svg", "line");
	outline.setAttribute("x1", s1x);
	outline.setAttribute("y1", s1y);
	outline.setAttribute("x2", s2x);
	outline.setAttribute("y2", s2y);
	outline.style.stroke = "rgb(0, 0, 0)";
	outline.style.strokeWidth = 4;
	document.getElementById("lines").appendChild(outline);

	var line1 = document.createElementNS("http://www.w3.org/2000/svg", "line");
	line1.setAttribute("x1", s1x);
	line1.setAttribute("y1", s1y);
	line1.setAttribute("x2", midx);
	line1.setAttribute("y2", midy);
	line1.style.stroke = "rgb(0, 0, 255)";
	line1.style.strokeWidth = 3;
	document.getElementById("lines").appendChild(line1);

	var line2 = document.createElementNS("http://www.w3.org/2000/svg", "line");
	line2.setAttribute("x1", midx);
	line2.setAttribute("y1", midy);
	line2.setAttribute("x2", s2x);
	line2.setAttribute("y2", s2y);
	line2.style.stroke = "rgb(0, 0, 255)";
	line2.style.strokeWidth = 3;
	document.getElementById("lines").appendChild(line2);

	linknets[linknetnum] = [ line1, line2, outline ];
}

function update_ping(json) {
	last_dataset = json;
	really_update_ping(json);
	setTimeout(get_ping, 1000);
}

function gradient_from_latency(latency_ms, latency_secondary_ms) {
	if (latency_secondary_ms === undefined) {
		return rgb_from_latency(latency_ms);
	}
	return 'linear-gradient(' +
		rgb_from_latency(latency_ms) + ', ' +
		rgb_from_latency(latency_secondary_ms) + ')';
}

function rgb_from_latency(latency_ms) {
	if (latency_ms === null || latency_ms === undefined) {
		return '#0000ff';
	}

	// 10ms is max
	var l = latency_ms / 50.0;
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

function really_update_ping(json) {
	if (json['switches']) {
		for (var switchnum in switches) {
			if (json['switches'][switchnum]) {
				if (json['switches'][switchnum]['color']) {
					switches[switchnum].style.background = json['switches'][switchnum]['color'];
				} else {
					switches[switchnum].style.background =
						gradient_from_latency(json['switches'][switchnum]['latency'],
								 json['switches'][switchnum]['latency_secondary']);
				}
			} else {
				switches[switchnum].style.background = '#0000ff';
			}
		}		
	}
	if (json['linknets']) {
		for (var linknetnum in linknets) {
			linknets[linknetnum][0].style.stroke = rgb_from_latency(json['linknets'][linknetnum][0]);
			linknets[linknetnum][1].style.stroke = rgb_from_latency(json['linknets'][linknetnum][1]);
		}
	}
}

function create_switch(switchnum, sysname, x, y, zorder, width, height) {
	var s = document.createElement("div");
	var map = document.getElementById('map');
	var top_offset = map.getBoundingClientRect().top;
	var left_offset = map.getBoundingClientRect().left;

	s.style.position = 'absolute';
	s.style.left = (left_offset + x) + 'px';
	s.style.top = (top_offset + y) + 'px';
	s.style.width = width + 'px';
	s.style.height = height + 'px';
	s.style.backgroundColor = '#0000ff';
	s.style.border = '1px solid black';
	s.style.padding = "0";
	s.style.zIndex = zorder + 100;
	switches[switchnum] = s;

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

	s.setAttribute("data-switchnum", switchnum);

	document.body.appendChild(s);
}

var dragging_switch = null;
var delta_x = null, delta_y = null;

if (can_edit) {
	document.onmousedown = function(e) {
		var switchnum = e.target.getAttribute("data-switchnum");
		if (switchnum === null) {
			return;
		}
		dragging_switch = switchnum;
		delta_x = parseInt(e.target.style.left.replace("px", "")) - e.clientX;
		delta_y = parseInt(e.target.style.top.replace("px", "")) - e.clientY;
	}

	document.onmousemove = function(e) {
		if (dragging_switch === null) {
			return;
		}
		switches[dragging_switch].style.left = (e.clientX + delta_x) + 'px';
		switches[dragging_switch].style.top = (e.clientY + delta_y) + 'px';
	}

	document.onmouseup = function(e) {
		if (dragging_switch === null) {
			return;
		}
		var x = e.clientX + delta_x - map.getBoundingClientRect().top;
		var y = e.clientY + delta_y - map.getBoundingClientRect().left;

		var request = new XMLHttpRequest();
		request.open('POST', '/change-switch-pos.pl', true);
		request.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
		request.send("switch=" + dragging_switch + "&x=" + x + "&y=" + y);

		dragging_switch = null;
	}
}
