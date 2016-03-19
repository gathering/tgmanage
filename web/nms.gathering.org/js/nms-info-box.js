"use strict";

/*
 * Handle the info-box for switches (e.g.: what's shown when a switch is
 * clicked).
 *
 * Interfaces: show(switch), hide(), click(switch).
 */


var nmsInfoBox = nmsInfoBox || {
	stats: {},
	_showing:"" // Which switch we are displaying (if any).
}

/*
 * Show the infobox for a switch.
 *
 * Just a wrapper for _show, but adds a handler for comments. Could easily
 * add a handler for other events too. E.g.: switches.
 */
nmsInfoBox.show = function(x) {
	nmsData.addHandler("comments","switchshower",nmsInfoBox._show,x);
	nmsData.addHandler("switches","switchshower",nmsInfoBox._show,x);
	nmsData.addHandler("smanagement","switchshower",nmsInfoBox._show,x);
	nmsInfoBox._show(x);
}

/*
 * Hide switch info-box and remove handler.
 */
nmsInfoBox.hide = function() {
	nmsInfoBox._hide();
	nmsData.unregisterHandler("comments","switchshower");
	nmsData.unregisterHandler("switches","switchshower");
	nmsData.unregisterHandler("smanagement","switchshower");
}

/*
 * Click a switch: If it's currently showing: hide it, otherwise display
 * it.
 */
nmsInfoBox.click = function(sw)
{
	if (nmsInfoBox._showing == sw)
		nmsInfoBox.hide();
	else
		nmsInfoBox.show(sw);
}

nmsInfoBox._hide = function()
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
	nmsInfoBox._showing = "";
	nmsInfoBox._editHide();
	nmsInfoBox._snmpHide();
	nmsInfoBox._createHide();
}

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
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = content[v][0];
		td2.innerHTML = content[v][1];
	}
	return table;
}

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
}

nmsInfoBox._searchSmart = function(id, sw) {
	if (nmsData.smanagement.switches[sw].distro == id) {
		console.log("ieh");
		return true;
	}
	if (id.match("[a-z]+.active")) {
		console.log("hei: " + sw);
		var family = id.match("[a-z]+");
		var limit = id;
		limit = limit.replace(family + ".active>","");
		limit = limit.replace(family + ".active<","");
		limit = limit.replace(family + ".active=","");
		var operator = id.replace(family + ".active","")[0];
		if (limit == parseInt(limit)) {
			if (operator == ">" ) {
				if (nmsData.switchstate.switches[sw][family].live > limit) {
					return true;
				}
			} else if (operator == "<") {
				if (nmsData.switchstate.switches[sw][family].live < limit) {
					return true;
				}
			} else if (operator == "=") {
				if (nmsData.switchstate.switches[sw][family].live == limit) {
					return true;
				}
			}
		}
	}
	return false;
}

/*
 * FIXME: Not sure this belongs here, it's really part of the "Core" ui,
 * not just the infobox.
 */
nmsInfoBox._search = function() {
	var el = document.getElementById("searchbox");
	var id = false;
	var hits = 0;
	if (el) {
		id = el.value;
	}
	if(id) {
		for(var sw in nmsData.switches.switches) {
			if (id[0] == "/") {
				if (nmsInfoBox._searchSmart(id.slice(1),sw)) {
					nmsMap.setSwitchHighlight(sw,true);
				} else {
					nmsMap.setSwitchHighlight(sw,false);
				}
			} else {
				if(sw.indexOf(id) > -1) {
					hits++;
					nmsMap.setSwitchHighlight(sw,true);
				} else {
					nmsMap.setSwitchHighlight(sw,false);
				}
			}
		}
	} else {
		nmsMap.removeAllSwitchHighlights();
	}
}

nmsInfoBox._snmp = function(x,tree)
{

	nmsInfoBox._snmpHide();
	var container = document.createElement("div");
	container.id = "nmsInfoBox-snmp-show";
	
	var swtop = document.getElementById("info-switch-parent");
	var output = document.createElement("output");
	output.id = "edit-output";
	output.style = "white-space: pre;";
	try {
		output.value = JSON.stringify(nmsData.snmp.snmp[x][tree],null,4);
	} catch(e) {
		output.value = "(no recent data (yet)?)";
	}
	container.appendChild(output);
	swtop.appendChild(container);
}
/*
 * Display info on switch "x" in the info-box
 *
 * Use nmsInfoBox.show(), otherwise changes wont be picked up.
 */
nmsInfoBox._show = function(x)
{
	var sw = nmsData.switches["switches"][x];
	var swm = nmsData.smanagement.switches[x];
	var swtop = document.getElementById("info-switch-parent");
	var swpanel = document.getElementById("info-switch-panel-body");
	var swtitle = document.getElementById("info-switch-title");
	var content = [];

	
	nmsInfoBox._hide();	
	nmsInfoBox._showing = x;
	
	swtitle.innerHTML = ' <button type="button" class="edit btn btn-xs btn-warning" onclick="nmsInfoBox._edit(\'' + x + '\');">Edit</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._snmp(\'' + x + '\',\'ports\');">Ports</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._snmp(\'' + x + '\',\'misc\');">Misc</button> ' + x + ' <button type="button" class="close" aria-label="Close" onclick="nmsInfoBox.hide();" style="float: right;"><span aria-hidden="true">&times;</span></button>';

	for (var v in sw) { 
		if (v == "placement") {
			var place = JSON.stringify(sw[v]);
			content.push([v,place]);
			continue;
		}
		content.push([v, sw[v]]);
	}

	for (var v in swm) { 
		content.push([v, swm[v]]);
	}
	content.sort();

	var comments = [];
	if (nmsData.comments.comments != undefined && nmsData.comments.comments[x] != undefined) {
		for (var c in nmsData.comments.comments[x]["comments"]) {
			var comment = nmsData.comments.comments[x]["comments"][c];
			if (comment["state"] == "active" || comment["state"] == "persist" || comment["state"] == "inactive") {
				comments.push(comment);
			}
		}
	}

	var infotable = nmsInfoBox._makeTable(content);
	infotable.id = "info-switch-table";
	swtop.appendChild(infotable);
	if (comments.length > 0) {
		var commenttable = nmsInfoBox._makeCommentTable(comments);
		commenttable.id = "info-switch-comments-table";
		swtop.appendChild(commenttable);
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

nmsInfoBox._nullBlank = function(x) {
	if (x == null || x == false || x == undefined)
		return "";
	return x;
}

nmsInfoBox._editHide = function() {
	var container = document.getElementById("nmsInfoBox-edit-box");
	if (container != undefined)
		container.parentNode.removeChild(container);
}
nmsInfoBox._snmpHide = function() {
	var container = document.getElementById("nmsInfoBox-snmp-show");
	if (container != undefined)
		container.parentNode.removeChild(container);
}

nmsInfoBox._edit = function(sw) {
	var template = {};
	var place = false;
	nmsInfoBox._editHide();
	nmsInfoBox._snmpHide();
	var container = document.createElement("div");
	container.id = "nmsInfoBox-edit-box";

	nmsInfoBox._editValues = {};
	if (nmsData.switches.switches[sw] != undefined) {
		for (var v in nmsData.switches.switches[sw]) {
			if (v == "placement") {
				place = JSON.stringify(nmsData.switches.switches[sw][v]);
				template[v] = "";
				continue;
			}
			template[v] = this._nullBlank(nmsData.switches.switches[sw][v]);
		}
	}
	if (nmsData.smanagement.switches[sw] != undefined) {
		for (var v in nmsData.smanagement.switches[sw]) {
			template[v] = this._nullBlank(nmsData.smanagement.switches[sw][v]);
		}
	}
	var content = [];
	for (v in template) {
		var tmpsw = '\'' + sw + '\'';
		var tmpv = '\'' + v + '\'';
		var tmphandler = '"nmsInfoBox._editChange(' + tmpsw + ',' + tmpv + ');"';
		var html = "<input type=\"text\" class=\"form-control\" value=\"" + template[v] + "\" id=\"edit-"+ sw + "-" + v + '" onchange=' + tmphandler + ' oninput=' + tmphandler + '/>';
		content.push([v, html]);
	}
	var table = nmsInfoBox._makeTable(content, "edit");
	var swtop = document.getElementById("info-switch-parent");
	container.appendChild(table);
	var submit = document.createElement("button");
	submit.innerHTML = "Save changes";
	submit.classList.add("btn", "btn-primary");
	submit.id = "edit-submit-" + sw;
	submit.onclick = function(e) { nmsInfoBox._editSave(sw, e); };
	container.appendChild(submit);
	var output = document.createElement("output");
	output.id = "edit-output";
	container.appendChild(output);
	swtop.appendChild(container);
	if (place) {
		var pval = document.getElementById("edit-" + sw + "-placement");
		if (pval) {
			pval.value = place;
		}
	}
}

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
}

nmsInfoBox._editStringify = function(sw) {
	for (var key in nmsInfoBox._editValues) {
		var val = nmsInfoBox._editValues[key];
	}
	nmsInfoBox._editValues['sysname'] = sw;
	var myData = JSON.stringify([nmsInfoBox._editValues]);
	return myData;
}
nmsInfoBox._editSave = function(sw, e) {
	var myData = nmsInfoBox._editStringify(sw);
	$.ajax({
		type: "POST",
		url: "/api/private/switch-update",
		dataType: "text",
		data:myData,
		success: function (data, textStatus, jqXHR) {
			nmsData.invalidate("switches");
			nmsData.invalidate("smanagement");
		}
	});
	nmsInfoBox._editHide();
}


/*
 * Display infobox for new switch
 *
 * TODO: Integrate and rebuild info-box display logic
 */
nmsInfoBox._createShow = function()
{
	var container = document.createElement("div");
  container.className = "col-md-5";
	container.id = "nmsInfoBox-create";
  container.style.zIndex = "999";

	var swtop = document.getElementById("wrap");
	nmsInfoBox._hide();	

  container.innerHTML = '<div class="panel panel-default"> <div class="panel-heading">Add new switch <button type="button" class="close" aria-label="Close" onclick="nmsInfoBox._createHide();" style="float: right;">X</button></div> <div class="panel-body"><input type="text" class="form-control" id="create-sysname" placeholder="Sysname id"><button class="btn btn-default" onclick="nmsInfoBox._createSave(document.getElementById(\'create-sysname\').value);">Add switch</button></div><div id="create-switch-feedback"></div> </div>';

	swtop.appendChild(container);
}
nmsInfoBox._createSave = function(sw) {
  var feedback = document.getElementById("create-switch-feedback");
  var myData = JSON.stringify([{'sysname':sw}]);
  $.ajax({
    type: "POST",
    url: "/api/private/switch-add",
    dataType: "text",
    data:myData,
    success: function (data, textStatus, jqXHR) {
      var result = JSON.parse(data);
      if(result.switches_addded.length > 0) {
        nmsInfoBox._createHide();
      }
    }
  });
}
nmsInfoBox._createHide = function() {
	var container = document.getElementById("nmsInfoBox-create");
	if (container != undefined)
		container.parentNode.removeChild(container);
}
