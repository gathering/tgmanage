"use strict";

/**************************************************************************
 *                                                                        *
 * THIS IS WORK IN PROGRESS, NOT CURRENTLY USED!                          *
 *                                                                        *
 * It WILL eventually replace large chunks of nms.js. But we're not there *
 * yet.                                                                   *
 *                                                                        *
 **************************************************************************/


/*
 * This file/module/whatever is an attempt to gather all data collection in
 * one place.
 *
 * It is work in progress.
 *
 * The basic idea is to have all periodic data updates unified here, with
 * stats, tracking of "ajax overflows" and general-purpose error handling
 * and callbacks and whatnot, instead of all the custom stuff that we
 * started out with.
 *
 * Public interfaces:
 * nmsData.data[name] - actual data
 * nmsData.registerSource() - add a source, will be polled periodicall
 * nmsData.updateSource() - issue a one-off update, outside of whatever
 * 			    periodic polling might take place
 */


var nmsData = nmsData || {
	data: {}, // Actual data
	sources: {},

	// Tracks metdata (hashes/timestamps)
	poller: {
		hashes:{}, 
		time:{}
	},
	// setInterval handlers (and more?)
	pollers: {

	},
	stats: {
		identicalFetches:0,
		outstandingAjaxRequests:0,
		ajaxOverflow:0,
		pollClears:0,
		pollSets:0
	}
};

/*
 * Register a source.
 *
 * name: "Local" name. Maps to nmsData.data[name]
 * remotename: The primary attribute to get from the remote source.
 * target: URL of the source
 * cb: Optional callback
 * cbdata: Optional callback data
 *
 * Update frequency will (eventually) be handled by parsing max-age from
 * the source. Right now it's hardcoded.
 *
 * FIXME: Should be unified with nmsTimers() somehow.
 */
nmsData.registerSource = function(name, remotename, target, cb, cbdata) {
	if(this.pollers[name]) {
		clearInterval(this.pollers[name]);
		this.stats.pollClears++;
	}
	this.sources[name] = { remotename: remotename, target: target, cb: cb, cbdata: cbdata };
	this.pollers[name] = setInterval(function(){nmsData.updateSource(name)}, 1000);
	this.stats.pollSets++;
}

/*
 * Updates a source.
 *
 * Called on interval, but can also be used to update a source after a
 * known action that updates the underlying data (e.g: update comments
 * after a comment is posted).
 */
nmsData.updateSource = function(name) {
	nmsData.genericUpdater(name,
		this.sources[name].remotename,
		this.sources[name].target,
		this.sources[name].cb,
		this.sources[name].cbdata);
}

/*
 * Updates nmsData.data[name] with data fetched from remote target in
 * variable "remotename". If a callback is provided, it is called with
 * argument meh.
 *
 * This also populates nms.pollers[name] with the server-provided hash.
 * Only if a change is detected is the callback issued.
 *
 * Used by registerSource.
 */
nmsData.genericUpdater = function(name, remotename, target, cb, meh) {
	if (this.stats.outstandingAjaxRequests > 5) {
		this.stats.ajaxOverflow++;
		return;
	}
	this.stats.outstandingAjaxRequests++;
	var now = "";
	/*
	if (nms.now != false)
		now = "now=" + nms.now;
	if (now != "") {
		if (target.match("\\?"))
			now = "&" + now;
		else
			now = "?" + now;
	}
	*/
	$.ajax({
		type: "GET",
		url: target + now,
		dataType: "text",
		success: function (data, textStatus, jqXHR) {
			var  indata = JSON.parse(data);
			if (nmsData.poller.hashes[name] != indata['hash']) {
				nmsData.data[name] = indata[remotename];
				nmsData.poller.hashes[name] = indata['hash'];
				nmsData.poller.time[name] = indata['time'];
				if (cb != undefined) {
					cb(meh);
				}
			} else {
				nmsData.stats.identicalFetches++;
			}
		},
		complete: function(jqXHR, textStatus) {
			nmsData.stats.outstandingAjaxRequests--;
			//updateAjaxInfo();
		}
	});
};
