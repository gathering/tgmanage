"use strict";

/*
 * NMS info window controller
 *
 * Interface: nmsInfoBox.showWindow(windowType,optionalParameter), nmsInfoBox.hide(), nmsInfoBox.refresh()
 *
 * Any windowTypes should at a minimum implement load, update, unload, getTitle, getContent, getChildContent
 *
 */

var nmsInfoBox = nmsInfoBox || {
  stats: {},
  _container: false, //Container window
  _window: false, //Active window (reference to _windowTypes object or false)
  _windowTypes: [] //List of all avaliable window types
};

/*
 * Shows a window from the _windowTypes list
 */
nmsInfoBox.showWindow = function (windowName,argument) {
	if(windowName == "switchInfo" && argument != '' && argument == this._window.sw) {
		nmsInfoBox.hide();
		return;
	}
  nmsInfoBox.hide();
  for(var win in this._windowTypes) {
    if(windowName == win) {
      this._window = this._windowTypes[win];
      this._show(argument);
      return;
    }
  }
};

/*
 * Refresh the active window
 */
nmsInfoBox.refresh = function(argument) {
	if(!nmsInfoBox._window)
		return;
  nmsInfoBox._show(argument);
};
nmsInfoBox.update = function(argument) {
	if(!nmsInfoBox._window)
		return;
	nmsInfoBox._window.update(argument);
}

/*
 * Internal function to show the active _window and pass along any arguments
 */
nmsInfoBox._show = function(argument) {
  nmsData.addHandler("comments","switchshower",nmsInfoBox.update,'comments');
  nmsData.addHandler("switches","switchshower",nmsInfoBox.update,'switches');
  nmsData.addHandler("smanagement","switchshower",nmsInfoBox.update,'smanagement');
  nmsData.addHandler("snmp","switchshower",nmsInfoBox.update,'snmp');

	if(argument != "soft")
		this._window.load(argument);

  this._container = document.getElementById("info-panel-container");
  var panel = document.createElement("div");
  panel.classList.add("panel", "panel-default");
  var title = document.createElement("div");
  title.classList.add("panel-heading");
  var body = document.createElement("div");
  body.classList.add("panel-body");

  title.innerHTML = this._window.getTitle() + '<button type="button" class="close" aria-label="Close" onclick="nmsInfoBox.hide();" style="float: right;"><span aria-hidden="true">&times;</span></button>';
  var content = this._window.getContent();
  if(!content.nodeName) {
    body.innerHTML = this._window.content;
  } else {
    body.appendChild(content);
  }
  var childContent = this._window.getChildContent();
  if(childContent != false) {
    body.appendChild(childContent);
  }

  panel.appendChild(title);
  panel.appendChild(body);
  while(this._container.firstChild) {
    this._container.removeChild(this._container.firstChild);
  }
  this._container.appendChild(panel);
  this._container.style.display = "block";
	$('[data-toggle="popover"]').popover({placement:"top",container:'body'});
	$(".collapse-controller").on("click", function(e) {
		$(e.target.dataset.target).collapse('toggle');
	});
};

/*
 * Hide the active window and tell it to unload
 */
nmsInfoBox.hide = function() {
  if(!this._container || !this._window)
    return;
  this._container.style.display = "none";
  this._window.unload();
  this._window = false;
	nmsData.unregisterHandler("comments","switchshower");
	nmsData.unregisterHandler("switches","switchshower");
	nmsData.unregisterHandler("smanagement","switchshower");
	nmsData.unregisterHandler("snmp","switchshower");
};

/*
 * Window type: Add Switch
 *
 * Basic window that lets you create a new switch
 *
 */
nmsInfoBox._windowTypes.addSwitch = {
  title: 'Add new switch',
  content:  '<input type="text" class="form-control" id="create-sysname" placeholder="Sysname id"><button class="btn btn-default" onclick="nmsInfoBox._windowTypes.addSwitch.save();">Add switch</button>',
  childContent: false,
  getTitle: function() {
    return this.title;
  },
  getContent: function() {
    return this.content;
  },
  getChildContent: function() {
    return this.childContent;
  },
  load: function(argument) {
  },
	update: function(type) {
	},
  unload: function() {
  },
  save: function() {
    var sysname = document.getElementById('create-sysname').value;
    var myData = JSON.stringify([{'sysname':sysname}]);
    $.ajax({
      type: "POST",
      url: "/api/write/switch-add",
      dataType: "text",
      data:myData,
      success: function (data, textStatus, jqXHR) {
        var result = JSON.parse(data);
        if(result.switches_addded.length > 0) { // FIXME unresolved variable switches_addded
          nmsInfoBox.hide();
        }
        nmsData.invalidate("switches");
        nmsData.invalidate("smanagement");
      }
    });
  }
};

/*
 * Window type: Switch info
 *
 * Advanced window with information about a specific switch, and basic editing options
 *
 * Custom interfaces: showSummary, showInfoTable, showComments, showSNMP, showEdit, save
 *
 */
nmsInfoBox._windowTypes.switchInfo = {
	title: '',
	content: '',
	childContent: false,
	sw: '',
	swi: '',
	swm: '',
	commentsHash: false,
	activeView: '',
	load: function(sw) {
		if(sw) {
			this.sw = sw;
		}
		if(!this.swi) {
			try {
				this.swi = nmsData.switches["switches"][this.sw];
			} catch(e) {
				this.swi = [];
			}
		}
		if(!this.swm) {
			try {
				this.swm = nmsData.smanagement.switches[this.sw];
			} catch(e) {
				this.swm = [];
			}
		}
		nmsInfoBox._windowTypes.switchInfo.showSummary();
		nmsData.addHandler("ticker","switchInfo",nmsInfoBox._windowTypes.switchInfo.update,"tick");
	},
	update: function(type) {
		switch (type) {
			case 'comments':
				if(this.activeView == "summary" && this.commentsHash != nmsData.comments.hash) {
					nmsInfoBox._windowTypes.switchInfo.showComments();
				}
				break;
		}
	},
	getTitle: function() {
		var sshButton = '';
		try {
			var mgmt = nmsInfoBox._window.swm.mgmt_v4_addr;
			sshButton = mgmt.split("/")[0];
		} catch(e) {}
		if(sshButton != null && sshButton != undefined && sshButton != '') {
			sshButton = ' <button type="button" class="ssh btn btn-xs btn-default"><a href="ssh://' + sshButton + '">SSH</a></button>';
		}
		return '<h4>' + this.sw + '</h4><button type="button" class="edit btn btn-xs btn-warning" onclick="nmsInfoBox._windowTypes.switchInfo.showEdit();">Edit</button> <button type="button" class="summary btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showSummary();">Summary</button> <button type="button" class="details btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showInfoTable();">Details</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showSNMP(\'ports\');">Ports</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showSNMP(\'misc\');">Misc</button>' + sshButton;
	},
	getContent: function() {
		return this.content;
	},
	getChildContent: function() {
		return this.childContent;
	},
	showSummary: function(argument) {
		this.activeView = "summary";
		var content = [];

		//Get DHCP info
		var lastDhcp = undefined;
		try {
			var tempDhcp = nmsData.dhcp.dhcp[this.sw];
			var now = Date.now();
			now = Math.floor(now / 1000);
			tempDhcp = now - parseInt(tempDhcp);
			tempDhcp = tempDhcp + " s";
		} catch(e) {}

		//Get SNMP status
		var snmpStatus = undefined;
		try {
			if (nmsData.snmp.snmp[this.sw].misc.sysName[0] != sw) {
				snmpStatus = "Sysname mismatch";
			} else {
				snmpStatus = "OK";
			}
		} catch(e) {}

		//Get CPU usage
		var cpuUsage = undefined;
		try {
			var cpu = 0;
			for (var u in nmsData.snmp.snmp[this.sw].misc.jnxOperatingCPU) {
				var local = nmsData.snmp.snmp[this.sw].misc['jnxOperatingCPU'][u];
				cpu = Math.max(nmsData.snmp.snmp[this.sw].misc.jnxOperatingCPU[u],cpu);
			}
			cpuUsage = cpu + " %";
		} catch (e) {}

		//Get traffic data
		var uplinkTraffic = undefined;
		try {
			var speed = 0;
			var t = parseInt(nmsData.switchstate.then[this.sw].uplinks.ifHCOutOctets);
			var n = parseInt(nmsData.switchstate.switches[this.sw].uplinks.ifHCOutOctets);
			var tt = parseInt(nmsData.switchstate.then[this.sw].time);
			var nt = parseInt(nmsData.switchstate.switches[this.sw].time);
			var tdiff = nt - tt;
			var diff = n - t;
			speed = diff / tdiff;
			if(!isNaN(speed)) {
				uplinkTraffic = byteCount(speed*8,0);
			}
		} catch (e) {};

		//Get uptime data
		var uptime = "";
		try {
			uptime = nmsData.snmp.snmp[this.sw]["misc"]["sysUpTimeInstance"][""] / 60 / 60 / 100;
			uptime = Math.floor(uptime) + " t";
		} catch(e) {}

		//Get temperature data
		var temp = "";
		try {
			temp = nmsData.switchstate.switches[this.sw].temp + " °C";
		} catch(e) {}

		content.push(["Ping latency:",(nmsData.ping.switches[this.sw].latency + " ms" || undefined)]);
		content.push(["Last DHCP lease:",lastDhcp]);
		content.push(["SNMP status:",snmpStatus]);
		content.push(["CPU usage:",cpuUsage]);
		content.push(["Uplink traffic:",uplinkTraffic]);
		content.push(["System uptime:",uptime]);
		content.push(["Temperature",temp]);
		content.push(["Management (v4):",(this.swm.mgmt_v4_addr || '')]);
		content.push(["Management (v6):",(this.swm.mgmt_v6_addr || '')]);
		content.push(["Subnet (v4):",(this.swm.subnet4 || '')]);
		content.push(["Subnet (v6):",(this.swm.subnet6 || '')]);

		var contentCleaned = [];
		for(var i in content) {
			if(content[i][1] == '' || content[i][1] == null)
				continue;
			if(content[i][1] == undefined || content[i][1])
				content[i][1] == "No data";
			contentCleaned.push(content[i]);
		}

		var table = nmsInfoBox._makeTable(contentCleaned);
		table.id = this.sw + "-summary";

		this.content = table;

		if(argument == "tick") {
			var myObj = document.getElementById(this.sw + "-summary");
			var oldObj = myObj.parentNode.replaceChild(this.content,myObj);
			return;
		}

		this.childContent = '';
		nmsInfoBox._windowTypes.switchInfo.showComments();
		nmsInfoBox.refresh("soft");
	},
	showInfoTable: function() {
		this.activeView = "infotable";
		var content = [];

		for (var v in this.swi) { 
			if (v == "placement") {
				var place = JSON.stringify(this.swi[v]);
				content.push([v,place]);
				continue;
			}
			content.push([v, this.swi[v]]);
		}

		for (var v in this.swm) { 
			content.push([v, this.swm[v]]);
		}
		content.sort();

		var infotable = nmsInfoBox._makeTable(content);
		infotable.id = "info-switch-table";

		this.content = infotable;
		this.childContent = '';
		nmsInfoBox.refresh("soft");
	},
	update: function(type) {
		switch (type) {
			case 'comments':
				if(nmsInfoBox._windowTypes.switchInfo.activeView == "summary" && this.commentsHash != nmsData.comments.hash) {
					nmsInfoBox._windowTypes.switchInfo.showComments();
				}
				break;
			case 'tick':
				if(nmsInfoBox._windowTypes.switchInfo.activeView == "summary")
					nmsInfoBox._windowTypes.switchInfo.showSummary("tick");
				break;
		}
	},
	showComments: function() {
		var domObj = document.createElement("div");
		var comments = [];

		var commentbox = document.createElement("div");
		commentbox.id = "commentbox";
		commentbox.className = "panel-body";
		commentbox.style.width = "100%";
		commentbox.innerHTML = '<div class="input-group"><input type="text" class="form-control" placeholder="Comment" id="' + this.sw + '-comment"><span class=\"input-group-btn\"><button class="btn btn-default" onclick="addComment(\'' + this.sw + '\',document.getElementById(\'' + this.sw + '-comment\').value); document.getElementById(\'' + this.sw + '-comment\').value = \'\'; document.getElementById(\'' + this.sw + '-comment\').placeholder = \'Comment added. Wait for next refresh.\';">Add comment</button></span></div>';

		// If we have no switch data, so just show comment form
		if(!nmsData.comments || !nmsData.comments.comments) {
			this.commentsHash = false;

			// We have data, refresh
		} else if(nmsData.comments.comments[this.sw]) {
			this.commentsHash = nmsData.comments.hash;
			for (var c in nmsData.comments.comments[this.sw]["comments"]) {
				var comment = nmsData.comments.comments[this.sw]["comments"][c];
				if (comment["state"] == "active" || comment["state"] == "persist" || comment["state"] == "inactive") {
					comments.push(comment);
				}
			}

			if (comments.length > 0) {
				var commenttable = nmsInfoBox._makeCommentTable(comments);
				commenttable.id = "info-switch-comments-table";
				domObj.appendChild(commenttable);
			}

			// We have no data for this switch, but its still correct
		} else {
			this.commentsHash = nmsData.comments.hash;
		}

		domObj.appendChild(commentbox);
		this.childContent = domObj;
		nmsInfoBox.refresh("soft");
	},
	showEdit: function() {
		this.activeView = "edit";
		var domObj = document.createElement("div");
		var template = {};

		nmsInfoBox._editValues = {};
		var place;
		for (var v in this.swi) {
			if (v == "placement") {
				place = JSON.stringify(this.swi[v]);
				template[v] = place;
				continue;
			}
			template[v] = nmsInfoBox._nullBlank(this.swi[v]);
		}
		for (var v in this.swm) {
			template[v] = nmsInfoBox._nullBlank(this.swm[v]);
		}
		var content = [];
		for (v in template) {
			var tmpsw = '\'' + this.sw + '\'';
			var tmpv = '\'' + v + '\'';
			var tmphandler = '"nmsInfoBox._editChange(' + tmpsw + ',' + tmpv + ');"';
			var html = "<input type=\"text\" class=\"form-control\" value='" + template[v] + "' id=\"edit-"+ this.sw + "-" + v + '" onchange=' + tmphandler + ' oninput=' + tmphandler + '/>';
			content.push([v, html]);
		}

		content.sort();

		var table = nmsInfoBox._makeTable(content, "edit");
		domObj.appendChild(table);

		var submit = document.createElement("button");
		submit.innerHTML = "Save changes";
		submit.classList.add("btn", "btn-primary");
		submit.id = "edit-submit-" + this.sw;
		submit.onclick = function(e) { nmsInfoBox._windowTypes.switchInfo.save(); };
		domObj.appendChild(submit);

		var output = document.createElement("output");
		output.id = "edit-output";
		domObj.appendChild(output);

		if (place) {
			var pval = document.getElementById("edit-" + this.sw + "-placement");
			if (pval) {
				pval.value = place;
			}
		}

		this.content = domObj;
		this.childContent = '';
		nmsInfoBox.refresh("soft");
	},
	showSNMP: function(tree) {
		this.activeView = "snmp";
		var domObj = document.createElement("div");
		domObj.classList.add("panel-group");

		try {
			var snmpJson = nmsData.snmp.snmp[this.sw][tree];
		} catch(e) {
			this.content = "(no recent data (yet)?)";
			return;
		}

		/*
		 * This html-generation code seems unnecessary complex. Must be a
		 * cleaner way to do this. But not today.
		 */
		for(var obj in snmpJson) {

			var cleanObj = obj.replace(/\W+/g, "");

			var groupObj = document.createElement("div");
			groupObj.classList.add("panel","panel-default");
			groupObj.innerHTML = '<a class="panel-heading collapse-controller" style="display:block;" role="button" data-toggle="collapse" href="#'+cleanObj+'-group">' + obj + '</a>';

			var groupObjCollapse = document.createElement("div");
			groupObjCollapse.id = cleanObj + "-group";
			groupObjCollapse.classList.add("collapse");

			var panelBodyObj = document.createElement("div");
			panelBodyObj.classList.add("panel-body");

			var tableObj = document.createElement("table");
			tableObj.classList.add("table","table-condensed");

			var tbody = document.createElement("tbody");

			for(var prop in snmpJson[obj]) {
				var propObj = document.createElement("tr");
				propObj.innerHTML = '<td>' + prop + '</td><td>' + snmpJson[obj][prop] + '</td>';
				tbody.appendChild(propObj);
			}

			tableObj.appendChild(tbody);
			panelBodyObj.appendChild(tableObj);
			groupObjCollapse.appendChild(panelBodyObj);
			groupObj.appendChild(groupObjCollapse);
			domObj.appendChild(groupObj);

		}
		this.content = domObj;
		this.childContent = '';

		nmsInfoBox.refresh("soft");
	},
	unload: function() {
		this.title = '';
		this.content = '';
		this.childContent = false;
		this.sw = '';
		this.swi = '';
		this.swm = '';
		this.commentsHash = false;
		this.activeView = '';
		nmsData.unregisterHandler("ticker","switchInfo");
	},
	save: function() {
		var myData = nmsInfoBox._editStringify(this.sw);
		$.ajax({
			type: "POST",
			url: "/api/write/switch-update",
			dataType: "text",
			data:myData,
			success: function (data, textStatus, jqXHR) {
				var result = JSON.parse(data);
				if(result.switches_updated.length > 0) { // FIXME unresolved variable switches_addded
					nmsInfoBox.hide();
				}
				nmsData.invalidate("switches");
				nmsData.invalidate("smanagement");
			}
		});
	}
};

/*
 * Window type: Show inventory listing
 *
 * Basic window that displays a list of all devices with simple summary information
 *
 * TODO: Set up more complex views with more columns, sorting, etc.
 *
 */
nmsInfoBox._windowTypes.inventoryListing = {
  content:  '',
  childContent: false,
	activeView: '',
	activeFilter: '',
  getTitle: function() {
    return '<h4>Inventory listing</h4><button type="button" class="distro-name btn btn-xs btn-default" onclick="nmsInfoBox.showWindow(\'inventoryListing\',\'distro_name\');">Distro name</button> <button type="button" class="distro-name btn btn-xs btn-default" onclick="nmsInfoBox.showWindow(\'inventoryListing\',\'sysDescr\');">System Description</button>';
  },
  getContent: function() {
    return this.content;
  },
  getChildContent: function() {
    return this.childContent;
  },
	setFilter: function(filter) {
		this.activeFilter = filter.toLowerCase();
		nmsInfoBox._windowTypes.inventoryListing.load("refresh");
	},
	getFilter: function() {
		return this.activeFilter;
	},
  load: function(list) {
		var hasSnmp = false;
		var targetArray = [];
		var listTitle = '';
		var needRefresh = false;
		var needSnmp = false;
		var contentObj = document.createElement("div");
		var inputObj = document.createElement("div");
		inputObj.innerHTML = '<div class="input-group"><input type="text" class="form-control" placeholder="Filter" id="inventorylisting-filter" value="' + this.activeFilter + '" onkeyup="if (event.keyCode == 13) {nmsInfoBox._windowTypes.inventoryListing.setFilter(document.getElementById(\'inventorylisting-filter\').value);}"><span class=\"input-group-btn\"><button class="btn btn-default" onclick="nmsInfoBox._windowTypes.inventoryListing.setFilter(document.getElementById(\'inventorylisting-filter\').value);">Filtrer</button></span></div>';
		contentObj.appendChild(inputObj);


		if(!nmsData.switches || !nmsData.switches.switches)
			return;
		if(!(!nmsData.snmp || !nmsData.snmp.snmp)) {
			hasSnmp = true;
		}
		if(list == "refresh") {
			list = this.activeView;
			needRefresh = true;
		}

		switch (list) {
			case 'distro_name':
				listTitle = 'Distro names';
				break;
			case 'sysDescr':
				if(hasSnmp)
				listTitle = 'System description';
				needSnmp = true;
				break;
			default:
				listTitle = 'Distro names';
				list = 'distro_name';
		}
		this.activeView = list;

		if(needSnmp && !hasSnmp) {
			this.content = "No SNMP data loaded. Reloading shortly.";
			nmsData.addHandler("snmp","inventoryListing",nmsInfoBox._windowTypes.inventoryListing.update,"snmp-request");
			return;
		}

		var resultArray = [];
		for(var sw in nmsData.switches.switches) {
			var value = '';
			if(this.activeFilter != '') {
				if(sw.toLowerCase().indexOf(this.activeFilter) == -1 && !nmsInfoBox._searchSmart(this.activeFilter,sw))
					continue;
			}
			try {
				switch (list) {
					case 'distro_name':
						value = nmsData.switches.switches[sw]["distro_name"];
						break;
					case 'sysDescr':
						value = nmsData.snmp.snmp[sw]["misc"]["sysDescr"][0];
						break;
				}
			} catch (e) {
				//console.log(e);
			}
			resultArray.push([sw, value]);
		}

		resultArray.sort();

		var infotable = nmsInfoBox._makeTable(resultArray,listTitle);
		infotable.id = "inventory-table";

		contentObj.appendChild(infotable);
		this.content = contentObj;
		if(needRefresh)
			nmsInfoBox.refresh("soft");
  },
	update: function(type) {
		if(type == "snmp-request") {
			nmsData.unregisterHandler("snmp","inventoryListing");
			nmsInfoBox._windowTypes.inventoryListing.load("refresh");
		}
	},
  unload: function() {
		nmsData.unregisterHandler("snmp","inventoryListing");
		this.content = '';
		this.activeView = '';
		this.activeFilter = '';
  },
  save: function() {
	}
};

/*
 * Click a switch and display it
 * it.
 */
nmsInfoBox.click = function(sw)
{
  this.showWindow("switchInfo",sw);
};

/*
 * General-purpose table-maker?
 *
 * Takes an array of arrays as input, and an optional caption.
 *
 * E.g.: _makeTable([["name","Kjell"],["Age","five"]], "Age list");
 */
nmsInfoBox._makeTable = function(content, caption) {
	var table = document.createElement("table");
	var tr;
	var td1;
	var td2;
	table.className = "table";
	table.classList.add("table");
	table.classList.add("table-condensed");
	if (caption != undefined) {
		var cap = document.createElement("caption");
		cap.textContent = caption;
		table.appendChild(cap);
	}
	for (var v in content) { 
		tr = table.insertRow(-1);
		tr.className = content[v][0].toLowerCase();
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = content[v][0];
		td2.innerHTML = content[v][1];
	}
	return table;
};

/*
 * Create and return a table for comments.
 *
 * Input is an array of comments.
 */
nmsInfoBox._makeCommentTable = function(content) {
	var table = document.createElement("table");
	table.className = "table";
	table.classList.add("table");
	table.classList.add("table-condensed");
	var cap = document.createElement("caption");
	cap.textContent = "Comments"
	table.appendChild(cap);
	for (var commentid in content) { 
		var tr;
		var td1;
		var td2;
		var comment = content[commentid];
		var col;
		if (comment["state"] == "active")
			col = "danger";
		else if (comment["state"] == "inactive")
			col = false;
		else
			col = "info";
		tr = table.insertRow(-1);
		tr.id = "commentRow" + comment["id"];
		tr.className = col;

		td1 = tr.insertCell(0);
		td1.style.whiteSpace = "nowrap";
		td1.style.width = "8em";
		td2 = tr.insertCell(1);
		var txt =  '<div class="btn-group" role="group" aria-label="..."><button type="button" class="btn btn-xs btn-default" data-trigger="focus" data-toggle="popover" title="Info" data-content="Comment added ' + comment["time"] + " by user " + comment["username"] + ' and listed as ' + comment["state"] + '"><span class="glyphicon glyphicon-info-sign" aria-hidden="true"></span></button>';
		txt += '<button type="button" class="btn btn-xs btn-danger" data-trigger="focus" data-toggle="tooltip" title="Mark as deleted" onclick="commentDelete(' + comment["id"] + ');"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></button>';
		txt += '<button type="button" class="btn btn-xs btn-success" data-trigger="focus" data-toggle="tooltip" title="Mark as inactive/fixed" onclick="commentInactive(' + comment["id"] + ');"><span class="glyphicon glyphicon-ok" aria-hidden="true"></span></button>';
		txt += '<button type="button" class="btn btn-xs btn-info" data-trigger="focus" data-toggle="tooltip" title="Mark as persistent" onclick="commentPersist(' + comment["id"] + ');"><span class="glyphicon glyphicon-star" aria-hidden="true"></span></button></div>';
		td1.innerHTML = txt;
		td2.innerHTML = comment["comment"];
	}
	return table;
};

nmsInfoBox._searchSmart = function(id, sw) {
	try {
		try {
			if (nmsData.switches.switches[sw].distro_name.toLowerCase() == id) {
				return true;
			}
		} catch (e) {}
		if (id.match("active")) {
			var limit = id;
			limit = limit.replace("active>","");
			limit = limit.replace("active<","");
			limit = limit.replace("active=","");
			var operator = id.replace("active","")[0];
			if (limit == parseInt(limit)) {
				if (operator == ">" ) {
					if (nmsData.switchstate.switches[sw]['totals'].live > limit) {
						return true;
					}
				} else if (operator == "<") {
					if (nmsData.switchstate.switches[sw]['totals'].live < limit) {
						return true;
					}
				} else if (operator == "=") {
					if (nmsData.switchstate.switches[sw]['totals'].live == limit) {
						return true;
					}
				}
			}
		}
		try {
			if (nmsData.smanagement.switches[sw].mgmt_v4_addr.match(id)) {
				return true;
			}
			if (nmsData.smanagement.switches[sw].mgmt_v6_addr.match(id)) {
				return true;
			}
		} catch (e) {}
		try {
			if (nmsData.smanagement.switches[sw].subnet4.match(id)) {
				return true;
			}
			if (nmsData.smanagement.switches[sw].subnet6.match(id)) {
				return true;
			}
		} catch (e) {}
		if (nmsData.snmp.snmp[sw].misc.sysDescr[0].toLowerCase().match(id)) {
			return true;
		}
	} catch (e) {
		return false;
	}
	return false;
};

/*
 * FIXME: Not sure this belongs here, it's really part of the "Core" ui,
 * not just the infobox.
 */
nmsInfoBox._search = function() {
	var el = document.getElementById("searchbox");
	var id = false;
	var matches = [];
	if (el) {
		id = el.value.toLowerCase();
	}
	if(id) {
		nmsMap.enableHighlights();
		for(var sw in nmsData.switches.switches) {
			if(sw.toLowerCase().indexOf(id) > -1) {
				matches.push(sw);
				nmsMap.setSwitchHighlight(sw,true);
			} else if (nmsInfoBox._searchSmart(id,sw)) {
				matches.push(sw);
				nmsMap.setSwitchHighlight(sw,true);
			} else {
				nmsMap.setSwitchHighlight(sw,false);
			}
		}
	} else {
		nmsMap.disableHighlights();
	}
	if(matches.length == 1) {
		document.getElementById("searchbox-submit").classList.add("btn-primary");
		document.getElementById("searchbox").dataset.match = matches[0];
	} else {
		document.getElementById("searchbox-submit").classList.remove("btn-primary");
		document.getElementById("searchbox").dataset.match = '';
	}
};

nmsInfoBox._searchKeyListener = function(e) {
	switch (e.keyCode) {
		case 13:
			var sw = document.getElementById("searchbox").dataset.match;
			if(sw != '') {
				nmsInfoBox.showWindow("switchInfo",sw);
			}
			break;
		case 27:
			document.getElementById("searchbox").dataset.match = '';
			document.getElementById("searchbox").value = '';
			nmsInfoBox._search();
			nmsInfoBox.hide();
			break;
	}
};

nmsInfoBox._nullBlank = function(x) {
	if (x == null || x == false || x == undefined)
		return "";
	return x;
};


nmsInfoBox._editChange = function(sw, v) {
	var el = document.getElementById("edit-" + sw + "-" + v);
	var val = el.value;
	if (v == "placement") {
		try {
			val = JSON.parse(val);
			el.parentElement.classList.remove("has-error");
			el.parentElement.classList.add("has-success");
		} catch (e) {
			el.parentElement.classList.add("has-error");
			return;
		}
	}
	nmsInfoBox._editValues[v] = val;
	el.classList.add("has-warning");
	var myData = nmsInfoBox._editStringify(sw);
	var out = document.getElementById("edit-output");
	out.value = myData;
};

nmsInfoBox._editStringify = function(sw) {
    nmsInfoBox._editValues['sysname'] = sw;
    return JSON.stringify([nmsInfoBox._editValues]);
};
