"use strict";

/* WORK
 * IN
 * PROGRESS
 *
 * Interface:
 *
 * nmsMap.init() - start things up
 * nmsMap.setSwitchColor(switch,color)
 * nmsMap.setSwitchInfo(switch,info)
 */


var nmsMap = nmsMap || {
	stats: {
		earlyDrawAll:0,
		colorChange:0,
		colorSame:0,
		resizeEvents:0,
		switchInfoUpdate:0,
		switchInfoSame:0
	},
	contexts: ["bg","link","blur","switch","text","textInfo","top","input","hidden"],
	_info: {},
	_settings: {
		fontLineFactor: 3,
		textMargin: 3,
		xMargin: 10,
		yMargin: 20
	},
	scale: 1,
	_orig: { width:1920, height:1032 },
	_canvas: {
		get width() { return nmsMap.scale * nmsMap._orig.width; },
		get height() { return nmsMap.scale * nmsMap._orig.height; }
	},

	_color: { },
	_c: {}
}

nmsMap.init = function() {
	this._initContexts();
	this._drawBG();
	nmsData.registerSource("switches","/api/public/switches");
	nmsData.addHandler("switches","nmsMap",function(){nmsMap._drawAllSwitches();});
	window.addEventListener('resize',nmsMap._resizeEvent,true);
	document.addEventListener('load',nmsMap._resizeEvent,true);
	this._drawAllSwitches();
}

nmsMap.setSwitchColor = function(sw, color) {
	if (this._color[sw] != color) {
		this._color[sw] = color;
		this._drawSwitch(sw);
		this.stats.colorChange++;
	} else {
		this.stats.colorSame++;
	}
}

nmsMap.reset = function() {
	for (var sw in this._color) {
		nmsMap.setSwitchColor(sw, undefined);
	}
	for (var sw in this._info) {
		nmsMap.setSwitchInfo(sw, undefined);
	}
}

nmsMap.setSwitchInfo = function(sw,info) {
	if (this._info[sw] != info) {
		this._info[sw] = info;
		this._drawSwitchInfo(sw);
		this.stats.switchInfoUpdate++;
	} else {
		this.stats.switchInfoSame++;
	}
}

nmsMap._initContext = function(name) {
	this._c[name] = {};
	this._c[name].c = document.getElementById(name + "Canvas");
	this._c[name].ctx = this._c[name].c.getContext('2d');
}

nmsMap._initContexts = function() {
	for (var context in this.contexts) {
		this._initContext(this.contexts[context]);
	}
}

nmsMap._resizeEvent = function() {
	var width = window.innerWidth - nmsMap._c.bg.c.offsetLeft;
	var height = window.innerHeight - nmsMap._c.bg.c.offsetTop;

	var xScale = (width / (nmsMap._orig.width + nmsMap._settings.xMargin));
	var yScale = (height / (nmsMap._orig.height + nmsMap._settings.yMargin));
	
	if (xScale > yScale) {
		nmsMap.scale = yScale;	
	} else {
		nmsMap.scale = xScale;
	}
	for (var a in nmsMap._c) {
		/*
		 * Resizing this to a too small size breaks gradients on smaller screens.
		 */
		if (a == 'hidden')
			continue;
		nmsMap._c[a].c.height = nmsMap._canvas.height;
		nmsMap._c[a].c.width = nmsMap._canvas.width;
	}
	nmsMap._drawBG();
	nmsMap._drawAllSwitches();
	nmsMap.stats.resizeEvents++;
}

nmsMap.setNightMode = function(toggle) {
	if (this._nightmode == toggle)
		return;
	this._nightmode = toggle;
	nmsMap._drawBG();
}

nmsMap._drawBG = function() {
	var imageObj = document.getElementById('source');
	this._c.bg.ctx.drawImage(imageObj, 0, 0, nmsMap._canvas.width, nmsMap._canvas.height);
	if(this._nightmode)
		nmsMap._invertBG();
}

nmsMap._invertBG = function() {
	var imageData = this._c.bg.ctx.getImageData(0, 0, nmsMap._canvas.width, nmsMap._canvas.height);
	var data = imageData.data;

	for(var i = 0; i < data.length; i += 4) {
		data[i] = 255 - data[i];
		data[i + 1] = 255 - data[i + 1];
		data[i + 2] = 255 - data[i + 2];
	}
	this._c.bg.ctx.putImageData(imageData, 0, 0);
}

nmsMap._getBox = function(sw) {
	var box = nmsData.switches.switches[sw]['placement'];
	box.x = parseInt(box.x);
	box.y = parseInt(box.y);
	box.width = parseInt(box.width);
	box.height = parseInt(box.height);
	return box;
}

nmsMap._drawSwitch = function(sw)
{
	// XXX: If a handler sets a color before switches are loaded... The
	// color will get set fine so this isn't a problem.
	if (nmsData.switches == undefined || nmsData.switches.switches == undefined)
		return;
	var box = this._getBox(sw);
	var color = nmsMap._color[sw];
	if (color == undefined) {
		color = blue;
	}
	this._c.switch.ctx.fillStyle = color;
	this._drawBox(this._c.switch.ctx, box['x'],box['y'],box['width'],box['height']);
	this._c.switch.ctx.shadowBlur = 0;
	this._drawSidewaysText(this._c.text.ctx, sw,box);
	/*
		if ((box['width'] + 10 )< box['height']) {
			//
		} else {
			//drawRegular(dr.text.ctx,sw,box['x'],box['y'],box['width'],box['height']);
		}
	*/
}

nmsMap._drawSwitchInfo = function(sw) {
	var box = this._getBox(sw);
	if (this._info[sw] == undefined) {
		this._clearBox(this._c.textInfo.ctx, box);
	} else {
		this._drawSidewaysText(this._c.textInfo.ctx, this._info[sw], box, "right");
	}
}

nmsMap._clearBox = function(ctx,box) {
	ctx.save();
	ctx.scale(this.scale,this.scale);
	ctx.clearRect(box['x'], box['y'], box['width'], box['height']);
	ctx.restore();
}

nmsMap._drawSidewaysText = function(ctx, text, box, align) {
	this._clearBox(ctx,box);
	ctx.save();
	ctx.scale(this.scale, this.scale); // FIXME: Do it everywhere?
	ctx.lineWidth = Math.floor(nmsMap._settings.fontLineFactor);
	if (ctx.lineWidth == 0) {
		ctx.lineWidth = Math.round(nms._settings.fontLineFactor);
	}
	ctx.fillStyle = "white";
	ctx.strokeStyle = "black";
	ctx.translate(box.x + box.width - this._settings.textMargin, box.y + box.height - this._settings.textMargin);
	ctx.rotate(Math.PI * 3/2);
	if (align == "right") {
		ctx.textAlign = "right";
		/*
		 * Margin*2 is to compensate for the margin above.
		 */
		ctx.translate(box.height - this._settings.textMargin*2,0);
	}
	ctx.strokeText(text, 0, 0);
	ctx.fillText(text, 0, 0);
	ctx.restore();
}

nmsMap._drawAllSwitches = function() {
	if (nmsData.switches == undefined) {
		this.stats.earlyDrawAll++;
		return;
	}
	for (var sw in nmsData.switches.switches) {
		this._drawSwitch(sw);
	}
}

nmsMap._drawBox = function(ctx, x, y, boxw, boxh) {
	ctx.save();
	ctx.scale(this.scale, this.scale); // FIXME
	ctx.fillRect(x,y, boxw, boxh);
	ctx.lineWidth = 1;
	ctx.strokeStyle = "#000000";
	ctx.strokeRect(x,y, boxw, boxh);
	ctx.restore();

}

nmsMap._connectSwitches = function(sw1, sw2, color1, color2) {
	nmsMap._connectBoxes(this._getBox(sw1), this._getBox(sw2),
			     color1, color2);
}

/*
 * Draw a line between two boxes, with a gradient going from color1 to
 * color2.
 */
nmsMap._connectBoxes = function(box1, box2,color1, color2) {
	var ctx = nmsMap._c.link.ctx;
	if (color1 == undefined)
		color1 = blue;
	if (color2 == undefined)
		color2 = blue;
	var x0 = Math.floor(box1.x + box1.width/2);
	var y0 = Math.floor(box1.y + box1.height/2);
	var x1 = Math.floor(box2.x + box2.width/2);
	var y1 = Math.floor(box2.y + box2.height/2);
	ctx.save();
	ctx.scale(nmsMap.scale, nmsMap.scale);
	var gradient = ctx.createLinearGradient(x1,y1,x0,y0);
	gradient.addColorStop(0, color1);
	gradient.addColorStop(1, color2);
	ctx.strokeStyle = gradient;
	ctx.moveTo(x0,y0);
	ctx.lineTo(x1,y1); 
	ctx.lineWidth = 5;
	ctx.stroke();
	ctx.restore();
}
