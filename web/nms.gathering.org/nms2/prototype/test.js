var c = document.getElementById("myCanvas");
var ctx = c.getContext("2d");
var fontSize = 20;
var fontFace = "Arial Black";
var nightMode = false;
var nightBlur = {};
var orig = {
	width:1920,
	height:1032
	};

var canvas = { 
	width:0,
	height:0,
	scale:1
};
var margin = {
	x:40,
	y:100,
	text:3
};

var switches = {
	"e3-1": { placement: { x:300,y:200,w:20,h:150} },
	"e5-1": { placement: { x:500,y:200,w:20,h:150} },
	"e7-1": { placement: { x:700,y:200,w:20,h:150} },
	"e9-1": { placement: { x:900,y:200,w:20,h:150} },
	"e3-5": { placement: { x:300,y:500,w:20,h:150} },
	"e5-5": { placement: { x:500,y:500,w:20,h:150} },
	"e7-5": { placement: { x:700,y:500,w:20,h:150} },
	"e9-5": { placement: { x:900,y:500,w:20,h:150} },
	"e11-5": { placement: { x:1100,y:500,w:20,h:150} },
	"distro0": { placement: { x:400,y:415,w:100,h:23} },
	"distro1": { placement: { x:800,y:415,w:100,h:23} },
};

var linknets = [
	{sw1:"e3-1",sw2:"distro0"},
	{sw1:"e5-1",sw2:"distro0"},
	{sw1:"e3-5",sw2:"distro0"},
	{sw1:"e5-5",sw2:"distro0"},
	{sw1:"e7-1",sw2:"distro1"},
	{sw1:"e9-1",sw2:"distro1"},
	{sw1:"e7-5",sw2:"distro1"},
	{sw1:"e9-5",sw2:"distro1"},
	{sw1:"e11-5",sw2:"distro1"},
	{sw1:"distro0",sw2:"distro1"}
]

/*
 * Draw a linknet with index i.
 *
 * XXX: Might have to change the index here to match backend
 */
function drawLinknet(i)
{
	var c1 = linknets[i].c1 ? linknets[i].c1 : "blue";
	var c2 = linknets[i].c2 ? linknets[i].c2 : "blue";
	connectSwitches(linknets[i].sw1,linknets[i].sw2, c1, c2);
}

/*
 * Draw all linknets
 */
function drawLinknets()
{
	for (var i in linknets) {
		drawLinknet(i);
	}
}

/*
 * Change both colors of a linknet.
 *
 * XXX: Probably have to change this to better match the backend data
 */
function setLinknetColors(i,c1,c2)
{
	linknets[i].c1 = c1;
	linknets[i].c2 = c2;
}

/*
 * (Re)draw a switch 'sw'.
 *
 * Color defaults to 'blue' if it's not set in the data structure.
 */
function drawSwitch(sw)
{
		var box = switches[sw]['placement'];
		var color = switches[sw]['color'];
		if (color == undefined) {
			color = "blue";
		}
		ctx.fillStyle = color;
		if (nightMode && nightBlur[sw] != true) {
			ctx.shadowBlur = 10;
			ctx.shadowColor = "#00EE00";
			nightBlur[sw] = true;
		} else {
			ctx.shadowBlur = 0;
			ctx.shadowColor = "#000000";
		}
		drawBox(box['x'],box['y'],box['w'],box['h']);
		ctx.shadowBlur = 0;
		if ((box['w'] + 10 )< box['h'] )
			drawSideways(sw,box['x'],box['y'],box['w'],box['h']);
		else
			drawRegular(sw,box['x'],box['y'],box['w'],box['h']);
}

/*
 * Draw all switches
 */
function drawSwitches()
{
	for (var sw in switches) {
		drawSwitch(sw);
	}
}

/*
 * Draw foreground/scene.
 *
 * This is used so linknets are drawn before switches. If a switch is all
 * that has changed, we just need to re-draw that, but linknets require
 * scene-redrawing.
 */
function drawScene()
{
	drawLinknets();
	drawSwitches();
}

/*
 * Set the scale factor and (re)draw the scene and background.
 * Uses canvas.scale and updates canvas.height and canvas.width.
 */
function setScale()
{
	c.height = canvas.height =  orig.height * canvas.scale ;
	c.width = canvas.width = orig.width * canvas.scale ;
	drawBG();
	nightBlur = {};
	drawScene();
	document.getElementById("scaler").value = canvas.scale;
	document.getElementById("scaler-text").innerHTML = (parseFloat(canvas.scale)).toPrecision(3);
}

/*
 * Returns true if the coordinates (x,y) is inside the box defined by
 * box.{x,y,w.h} (e.g.: placement of a switch).
 */
function isin(box, x, y)
{
	if ((x >= box.x) && (x <= (box.x + box.w)) && (y >= box.y) && (y <= (box.y + box.h))) {
		return true;
	}
	return false;

}

/*
 * Return the name of the switch found at coordinates (x,y), or 'undefined'
 * if none is found.
 */
function findSwitch(x,y) {
	x = parseInt(parseInt(x) / canvas.scale);
	y = parseInt(parseInt(y) / canvas.scale);
	console.log ("x: " + x + " y: " + y);

	for (var v in switches) {
		if(isin(switches[v]['placement'],x,y)) {
			return v;
		}
	}
	return undefined;
}

/*
 * Set switch color of 'sw' to 'c', then re-draw the switch.
 */
function setSwitchColor(sw, c)
{
	switches[sw]['color'] = c;
	drawSwitch(sw);
}

/*
 * Return a random-ish color (for testing)
 */
function getRandomColor()
{
	var c;
	var i = Math.round(Math.random() * 5);
	if (i < 1) {
		c = "white";
	} else if(i < 2) {
		c = "red"; 
	} else if (i < 3) {
		c = "pink";
	} else if (i < 4) {
		c = "yellow";
	} else if (i < 5) {
		c = "orange";
	} else {
		c = "green";
	}
	return c;
}

/*
 * Helper functions for the front-end testing.
 */
function hideBorder()
{
	c.style.border = "";
}

function showBorder()
{
	c.style.border = "1px solid #000000";
}

/*
 * Event handler for the front-end drag bar to change scale
 */
function scaleChange()
{
	var scaler = document.getElementById("scaler").value;
	canvas.scale = scaler;
	setScale();
}

/*
 * Draw a "cross hair" at/around (x,y).
 *
 * Used for testing.
 */
function crossHair(x,y)
{
	ctx.fillStyle = "yellow";
	ctx.fillRect(x,y,-100,10);
	ctx.fillStyle = "red";
	ctx.fillRect(x,y,100,10);
	ctx.fillStyle = "blue";
	ctx.fillRect(x,y,10,-100);
	ctx.fillStyle = "green";
	ctx.fillRect(x,y,10,100);
}

/*
 * Called when a switch is clicked
 */
function switchClick(sw)
{
	setSwitchColor(sw, "white");
}

/*
 * Testing-function to randomize colors of linknets and switches
 */
function randomizeColors()
{
	for (var i in linknets) {
		setLinknetColors(i, getRandomColor(), getRandomColor());
	}
	drawLinknets();
	for (var sw in switches) {
		setSwitchColor(sw, getRandomColor());
	}
}

/*
 * Resets the colors of linknets and switches.
 *
 * Useful when mode changes so we don't re-use colors from previous modes
 * due to lack of data or bugs.
 */
function resetColors()
{
	for (var i in linknets) {
		setLinknetColors(i, "blue","blue");
	}
	drawLinknets();
	for (var sw in switches) {
		setSwitchColor(sw, "blue");
	}
}

/*
 * onclick handler for the canvas
 */
function canvasClick(e)
{
	console.log(e);
	var sw = findSwitch(e.pageX - e.target.offsetLeft, e.pageY - e.target.offsetTop);
	if (sw != undefined) {
		switchClick(sw);
	}
}

/*
 * Resize event-handler.
 *
 * Recomputes the scale and applies it.
 *
 * The recomputation is pretty bad, since it doesn't take the size of the
 * header/toolbar into account at all, except through margin.*
 */
function resizeEvent()
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	if (width / (orig.width + margin.x) > height  /  (orig.height + margin.y)) {
		canvas.scale = height / (orig.height + margin.y);
	} else {
		canvas.scale = width / (orig.width + margin.x);
	}
	setScale();
}

/*
 * Draws the background image (scaled).
 */
function drawBG()
{
	var image = document.getElementById('source');
	image.style.webkitFilter = "invert(100%)";
	ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
	if (nightMode) {
		invertCanvas();
	}
}

function setNightMode(toggle) {
	nightMode = toggle;
	var body = document.getElementById("bdy");
	bdy.style.background = toggle ? "black" : "white";
	bdy.style.color = toggle ? "#00FF00" : "black";
	setScale();
}
/*
 * Draw a box (e.g.: switch).
 */
function drawBox(x,y,boxw,boxh)
{
	var myX = Math.round(x * canvas.scale);
	var myY = Math.round(y * canvas.scale);
	var myX2 = Math.round((boxw) * canvas.scale);
	var myY2 = Math.round((boxh) * canvas.scale);
	ctx.fillRect(myX,myY, myX2, myY2);
	ctx.lineWidth = Math.round(0.5 * canvas.scale);
	if (canvas.scale < 1.0) {
		ctx.lineWidth = 0.5;
	}
	ctx.strokeStyle = "#000000";
	ctx.strokeRect(myX,myY, myX2, myY2);
}

/*
 * Draw text on a box - sideways!
 *
 * XXX: This is pretty nasty and should also probably take a box as input.
 */
function drawSideways(text,x,y,w,h)
{
	ctx.rotate(Math.PI / 2);
	ctx.rotate(Math.PI)
	ctx.fillStyle = "white";
	ctx.strokeStyle = "black";
	ctx.lineWidth = Math.round(1 * canvas.scale);
	if (canvas.scale < 0.7) {
		ctx.lineWidth = 0.5;
	}
	ctx.font = Math.round(fontSize * canvas.scale) + "px " + fontFace;
	ctx.fillText(text, - canvas.scale * (y + h - margin.text),canvas.scale * (x + w - margin.text) );
	ctx.strokeText(text, - canvas.scale * (y + h - margin.text),canvas.scale * (x + w - margin.text) );

	ctx.rotate(Math.PI / 2);
}

/*
 * Draw background inverted (wooo)
 *
 * XXX: This is broken for chromium on local file system (e.g.: file:///)
 * Seems like a chromium bug?
 */
function invertCanvas() {
	var canvas = document.getElementById('myCanvas');
	var context = canvas.getContext('2d');
	var canvas2 = document.getElementById('mySecretCanvas');
	var context2 = canvas.getContext('2d');

	var imageObj = document.getElementById('source');
	context2.drawImage(imageObj, 0, 0, canvas.width, canvas.height);

	var imageData = context2.getImageData(0, 0, canvas.width, canvas.height);
	var data = imageData.data;

	for(var i = 0; i < data.length; i += 4) {
		data[i] = 255 - data[i];
		data[i + 1] = 255 - data[i + 1];
		data[i + 2] = 255 - data[i + 2];
	}
	context.putImageData(imageData, 0, 0);
}

/*
 * Draw regular text on a box.
 *
 * Should take the same format as drawSideways()
 *
 * XXX: Both should be renamed to have 'text' or something in them
 */
function drawRegular(text,x,y,w,h) {

	ctx.fillStyle = "white";
	ctx.strokeStyle = "black";
	ctx.lineWidth = Math.round(1 * canvas.scale);
	if (canvas.scale < 0.7) {
		ctx.lineWidth = 0.5;
	}
	ctx.font = Math.round(fontSize * canvas.scale) + "px " + fontFace;
	ctx.fillText(text, (x + margin.text) * canvas.scale, (y + h - margin.text) * canvas.scale);
	ctx.strokeText(text, (x + margin.text) * canvas.scale, (y + h - margin.text) * canvas.scale);
}

/*
 * Draw a line between switch "insw1" and "insw2", using a gradiant going
 * from color1 to color2.
 *
 * XXX: beginPath() and closePath() is needed to avoid re-using the
 * gradient/color 
 */
function connectSwitches(insw1, insw2,color1, color2) {
	var sw1 = switches[insw1].placement;
	var sw2 = switches[insw2].placement;
	if (color1 == undefined)
		color1 = "blue";
	if (color2 == undefined)
		color2 = "blue";
	var x0 = Math.round((sw1.x + sw1.w/2) * canvas.scale);
	var y0 = Math.round((sw1.y + sw1.h/2) * canvas.scale);
	var x1 = Math.round((sw2.x + sw2.w/2) * canvas.scale);
	var y1 = Math.round((sw2.y + sw2.h/2) * canvas.scale);
	var gradient = ctx.createLinearGradient(x1,y1,x0,y0);
	gradient.addColorStop(0, color1);
	gradient.addColorStop(1, color2);
	ctx.beginPath();
	ctx.strokeStyle = gradient
	ctx.moveTo(x0,y0);
	ctx.lineTo(x1,y1); 
	ctx.lineWidth = Math.round(2 * canvas.scale);
	ctx.closePath();
	ctx.stroke();
	ctx.moveTo(0,0);
}

window.addEventListener('resize',resizeEvent,true);
document.addEventListener('load',resizeEvent,true);

