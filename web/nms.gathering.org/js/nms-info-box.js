"use strict";

/*
 * NMS info window controller
 *
 * Interface: nmsInfoBox.showWindow(windowType,optionalParameter), nmsInfoBox.hide(), nmsInfoBox.refresh()
 *
 * Any windowTypes should at a minimum implement load, unload, getTitle, getContent, getChildContent
 *
 * TODO: Implement useful update methods on windowTypes
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
 *
 * Todo: Could use a less aggressive refresh that doesn't hide-show everything
 *
 */
nmsInfoBox.refresh = function() {
  nmsInfoBox._show();
};

/*
 * Internal function to show the active _window and pass along any arguments
 */
nmsInfoBox._show = function(argument) {
  nmsData.addHandler("comments","switchshower",nmsInfoBox.update,argument);
  nmsData.addHandler("switches","switchshower",nmsInfoBox.update,argument);
  nmsData.addHandler("smanagement","switchshower",nmsInfoBox.update,argument);
  nmsData.addHandler("snmp","switchshower",nmsInfoBox.update,argument);

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
};

/*
 * Hide the active window and tell it to unload
 */
nmsInfoBox.hide = function() {
  if(this._container == false || this._window == false)
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
  unload: function() {
  },
  save: function() {
    var sysname = document.getElementById('create-sysname').value;
    var myData = JSON.stringify([{'sysname':sysname}]);
    $.ajax({
      type: "POST",
      url: "/api/private/switch-add",
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
 * Custom interfaces: showComments, showSNMP, showEdit, save
 *
 */
nmsInfoBox._windowTypes.switchInfo = {
  title: '',
  content: '',
  childContent: false,
  sw: '',
  swi: '',
  swm: '',
  load: function(sw) {
    if(sw) {
      this.sw = sw;
    }
    this.swi = nmsData.switches["switches"][this.sw];
    this.swm = nmsData.smanagement.switches[this.sw];

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

  },
  getTitle: function() {
    return '<button type="button" class="edit btn btn-xs btn-warning" onclick="nmsInfoBox._windowTypes.switchInfo.showEdit(\'' + this.sw + '\');">Edit</button> <button type="button" class="comments btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showComments(\'' + this.sw + '\');">Comments</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showSNMP(\'ports\');">Ports</button> <button type="button" class="edit btn btn-xs btn-default" onclick="nmsInfoBox._windowTypes.switchInfo.showSNMP(\'misc\');">Misc</button> ' + this.sw + '';
  },
  getContent: function() {
    return this.content;
  },
  getChildContent: function() {
    return this.childContent;
  },
  showComments: function() {
      var domObj = document.createElement("div");
      var comments = [];
      if (nmsData.comments.comments != undefined && nmsData.comments.comments[this.sw] != undefined) {
        for (var c in nmsData.comments.comments[this.sw]["comments"]) {
          var comment = nmsData.comments.comments[this.sw]["comments"][c];
          if (comment["state"] == "active" || comment["state"] == "persist" || comment["state"] == "inactive") {
            comments.push(comment);
          }
        }
      }

      if (comments.length > 0) {
        var commenttable = nmsInfoBox._makeCommentTable(comments);
        commenttable.id = "info-switch-comments-table";
        domObj.appendChild(commenttable);
        $(function () { $('[data-toggle="popover"]').popover({placement:"top",continer:'body'}) })
      }
      var commentbox = document.createElement("div");
      commentbox.id = "commentbox";
      commentbox.className = "panel-body";
      commentbox.style.width = "100%";
      commentbox.innerHTML = '<div class="input-group"><input type="text" class="form-control" placeholder="Comment" id="' + this.sw + '-comment"><span class=\"input-group-btn\"><button class="btn btn-default" onclick="addComment(\'' + this.sw + '\',document.getElementById(\'' + this.sw + '-comment\').value); document.getElementById(\'' + this.sw + '-comment\').value = \'\'; document.getElementById(\'' + this.sw + '-comment\').placeholder = \'Comment added. Wait for next refresh.\'; nmsInfoBox.hide();">Add comment</button></span></div>';
      domObj.appendChild(commentbox);

      this.childContent = domObj;
      nmsInfoBox.refresh();
  },
  showEdit: function() {
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

    this.childContent = domObj;
    nmsInfoBox.refresh();
  },
  showSNMP: function(tree) {
    var domObj = document.createElement("div");

    var output = document.createElement("output");
    output.id = "edit-output";
    output.style = "white-space: pre;";
    try {
      output.value = JSON.stringify(nmsData.snmp.snmp[this.sw][tree],null,4);
    } catch(e) {
      output.value = "(no recent data (yet)?)";
    }
    domObj.appendChild(output);

    this.childContent = domObj;
    nmsInfoBox.refresh();
  },
  unload: function() {
    this.childContent = false;
  },
  save: function() {
    var myData = nmsInfoBox._editStringify(this.sw);
    console.log(myData);
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
    nmsInfoBox.hide();
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
		id = el.value;
	}
	if(id) {
		for(var sw in nmsData.switches.switches) {
			if (id[0] == "/") {
				if (nmsInfoBox._searchSmart(id.slice(1),sw)) {
					matches.push(sw);
					nmsMap.setSwitchHighlight(sw,true);
				} else {
					nmsMap.setSwitchHighlight(sw,false);
				}
			} else {
				if(sw.indexOf(id) > -1) {
					matches.push(sw);
					nmsMap.setSwitchHighlight(sw,true);
				} else {
					nmsMap.setSwitchHighlight(sw,false);
				}
			}
		}
	} else {
		nmsMap.removeAllSwitchHighlights();
	}
	if(matches.length == 1) {
		document.getElementById("searchbox-submit").classList.add("btn-primary");
		document.getElementById("searchbox").dataset.match = matches[0];
		document.getElementById("searchbox").addEventListener("keydown",nmsInfoBox._searchKeyListener,false);
	} else {
		document.getElementById("searchbox-submit").classList.remove("btn-primary");
		document.getElementById("searchbox").dataset.match = '';
		document.getElementById("searchbox").removeEventListener("keydown",nmsInfoBox._searchKeyListener,false);
	}
};

nmsInfoBox._searchKeyListener = function(e) {
	if(e.keyCode == 13) {
		var sw = document.getElementById("searchbox").dataset.match;
		nmsInfoBox.showWindow("switchInfo",sw);
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
