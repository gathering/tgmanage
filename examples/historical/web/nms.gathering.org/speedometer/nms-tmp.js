var nms = {
	debug: true,
};

var ports_now;
var ports_5m_ago;
var ports_1h_ago;
var bandwidth = 0;
var sw;
var infra;
// var full=false;

/*
    Sets $ports_now and $ports_5m_ago - both variables' structure:
    obj(
        <host> -> <port> -> <properties>,
        <host> -> <port> -> <properties>,
        [...]
    )
    
    Properties:
        ifhcinoctets (counter64)
        ifhcoutoctets (counter64)
        ifhighbandwidth (???)
        time (unix timestamp)
*/
function fetch_switch_data(){
    mode = $('#switch').attr('data-mode');
	$.ajax({
		type: "GET",
		url: "/port-state.pl",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			ports_now = switchdata['switches'];
			var list = document.getElementById("switch-list");
			if (list) {
			var v = list.value;
			var arry = new Array();
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
		}
	});
	$.ajax({
		type: "GET",
		url: "/port-state.pl?time=5m",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			ports_5m_ago = switchdata['switches'];
		}
	})
	// console.log(ports_now);
	
	
	$.ajax({
		type: "GET",
		url: "/port-state.pl?time=1h",
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  switchdata = JSON.parse(data);
			ports_1h_ago = switchdata['switches'];
		}
	})
}

/*
    Get bandwidth average for last hour, in bytes
    mode: either "tot_agg" or "edge_ports"
    tot_agg gives total aggregation of all ports
    edge_ports gives aggregation on all client facing ports on EX2200 switches (not 100% accurate, missing a few clients directly connected on EX3300)
*/
function get_bytes_avg_1h(mode){
    var mode = $('#switch').attr('data-mode');
    var bw_usage = 0;
    for (sw in ports_now) {
        for (port in ports_now[sw]["ports"]) {
        
			if (!ports_now[sw]["ports"][port]) {
				console.log('Error - should not happen (!ports_now[sw]["ports"][port])');
				continue;
			}
			if (!ports_5m_ago[sw]["ports"][port]) {
			    console.log('Error - should not happen (!ports_5m_ago[sw]["ports"][port])');
				continue;
			}
			
	        var diff = parseInt(ports_now[sw]["ports"][port]["time"]) - parseInt(ports_1h_ago[sw]["ports"][port]["time"]);
	        var then = parseInt(ports_1h_ago[sw]["ports"][port]["ifhcinoctets"]);
	        var now =  parseInt(ports_now[sw]["ports"][port]["ifhcinoctets"]);
	        var diffval = (now - then);
	        
	        /*
	            Skips ports with no data (e.g. down)
	        */
			if (then == 0 || now == 0 || diffval == 0) {
				continue;
			}

            if (mode == 'tot_agg'){
                bw_usage += parseInt(diffval/diff);
            }else if(mode == 'edge_ports' && /ge-0\/0\/4[4-7]$/.exec(port)){
                bw_usage += parseInt(diffval/diff);
            }
	    }
	}
	return Math.round(bw_usage);
}

function update_bandwidth() {
    var mode = $('#switch').attr('data-mode');
	var bandwidth_in = parseInt(0);
	var bandwidth_kant = parseInt(0);
	var counter=0;
	var sw;
	for (sw in ports_now) {
		for (port in ports_now[sw]["ports"]) {
			if (!ports_now[sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			if (!ports_5m_ago[sw]["ports"][port]) {
				console.log("ops");
				continue;
			}
			var diff = parseInt(ports_now[sw]["ports"][port]["time"]) - parseInt(ports_5m_ago[sw]["ports"][port]["time"]);
			var then = parseInt(ports_5m_ago[sw]["ports"][port]["ifhcinoctets"]);
			var now =  parseInt(ports_now[sw]["ports"][port]["ifhcinoctets"]);
			var diffval = (now - then);
			if (then == 0 || now == 0 || diffval == 0 || diffval == NaN) {
				continue;
			}

			if (mode == 'tot_agg'){
			    bandwidth_in += parseInt(diffval/diff) / 1024 ;
			}else if(/e\d{1,2}-\d{1,2}/.exec(sw) || /sw\d-/.exec(sw)){
			    if(/ge-0\/0\/4[4-7]$/.exec(port)){
			        bandwidth_in += parseInt(diffval/diff) / 1024 ;
			    }
			}
		}
	}
	
	bandwidth = bandwidth_in;
	$('#text-bandwidth').attr('data-used_bw', bandwidth);
}

