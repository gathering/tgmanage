var switches = [];
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
	json_request('/switches-json.pl', draw_switches, 1000);
}

function get_ping() {
	json_request('/ping-json.pl', update_ping, 1000);
}

function draw_switches(json) {
	for (var switchnum in switches) {
		document.body.removeChild(switches[switchnum]);
	}
	switches = [];
	
	for (var switchnum in json) {
		var s = json[switchnum];
		create_switch(switchnum,
	  	              s['sysname'],
		              parseInt(s['x']),
			      parseInt(s['y']),
		              parseInt(s['width']),
		              parseInt(s['height']));
	}
	setTimeout(get_switches, 60000);
	really_update_ping(last_dataset);
}

function update_ping(json) {
	last_dataset = json;
	really_update_ping(json);
	setTimeout(get_ping, 1000);
}

function really_update_ping(json) {
	for (var switchnum in switches) {
		if (json[switchnum] === null || json[switchnum] === undefined) {
			switches[switchnum].style.backgroundColor = '#0000ff';
		} else {
			// 10ms is max
			var l = json[switchnum] / 10.0;
			if (l >= 1.0) { l = 1.0; }
			l = Math.pow(l, 1.0/2.2);
			l = Math.round(l * 255.0);

			switches[switchnum].style.backgroundColor = 'rgb(' + l + ', 255, 0)';
		}
	}
}

function create_switch(switchnum, sysname, x, y, width, height) {
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
	switches[switchnum] = s;

	var text = document.createTextNode(sysname);
	s.appendChild(text);

	//var attr = document.createAttribute("data-switchnum", switchnum);
	s.setAttribute("data-switchnum", switchnum);

	document.body.appendChild(s);
}

var dragging_switch = null;
var delta_x = null, delta_y = null;

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
	var x = e.clientX + delta_x;
	var y = e.clientY + delta_y;

	var request = new XMLHttpRequest();
	request.open('POST', '/change-switch-pos.pl', true);
	request.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
	request.send("switch=" + dragging_switch + "&x=" + x + "&y=" + y);

	dragging_switch = null;
}
