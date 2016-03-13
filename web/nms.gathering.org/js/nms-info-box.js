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
	nmsInfoBox._show(x);
}

/*
 * Hide switch info-box and remove handler.
 */
nmsInfoBox.hide = function() {
	nmsInfoBox._hide();
	nmsData.unregisterHandler("comments","switchshower");
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
	
	swtitle.innerHTML = x + '<button type="button" class="close" aria-labe="Close" onclick="nmsInfoBox.hide();" style="float: right;"><span aria-hidden="true">&times;</span></button>';

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

