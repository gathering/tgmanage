
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
		return '#0000ff';
	}

	var l = latency_ms / 40.0;
	if (l >= 2.0) {
		return 'rgb(255, 0, 0)';
	} else if (l >= 1.0) {
		l = 2.0 - l;
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 255.0);
		return 'rgb(255, ' + l + ', 0)';
	} else {
		l = Math.pow(l, 1.0/2.2);
		l = Math.floor(l * 255.0);
		return 'rgb(' + l + ', 255, 0)';
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

/*
 * Return a random-ish color (for testing)
 */
function getRandomColor()
{
	var i = Math.round(Math.random() * 5);
	var colors = [ "white", "red", "pink", "yellow", "orange", "green" ];
	return colors[i];	
}

