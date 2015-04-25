
/*
 * Some stolen colors that look OK.
 *
 * PS: Stolen from boostrap, because we use bootstrap and these look good
 * and match.
 */
var lightblue = "#d9edf7";
var lightgreen = "#dff0d8";
var lightred = "#f2dede";
var lightorange = "#fcf8e3";
var blue = "#337ab7";
var green = "#5cb85c";
var teal = "#5bc0de"; // Or whatever the hell that is
var orange = "#f0ad4e";
var red = "#d9534f";

function gradient_from_latency(latency_ms, latency_secondary_ms)
{
	if (latency_secondary_ms === undefined) {
		return rgb_from_latency(latency_ms);
	}
	return 'linear-gradient(' +
		rgb_from_latency(latency_ms) + ', ' +
		rgb_from_latency(latency_secondary_ms) + ')';
}

function rgb_from_latency(latency_ms)
{
	if (latency_ms === null || latency_ms === undefined) {
		return blue;
	}

	var l = latency_ms / 50.0;
	if (l >= 2.0) {
		return 'rgb(255, 0, 0)';
	} else if (l >= 1.0) {
		l = 2.0 - l;
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 205.0);
		return 'rgb(255, ' + l + ', 0)';
	} else {
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 255.0);
		return 'rgb(' + l + ', 205, 0)';
	}
}

/*
 * Give us a color from blue (0) to red (100).
 */
function rgb_from_max(x)
{
	x = x/100;
	var colorred = 255 * x;
	var colorblue = 255 - colorred;

	return 'rgb(' + Math.floor(colorred) + ", 0, " + Math.floor(colorblue) + ')';
}

function rgb_from_max2(x)
{
	x = x/100;
	var colorred = 255 * x;
	var colorgreen = 250 - colorred;

	return 'rgb(' + Math.floor(colorred) + "," + Math.floor(colorgreen) + ', 0 )';
}
/*
 * Return a random-ish color (for testing)
 */
function getRandomColor()
{
	var colors = [ "white", red, teal, orange, green, blue ];
	var i = Math.round(Math.random() * (colors.length-1));
	return colors[i];	
}

