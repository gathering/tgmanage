$(function () {
	
    $('#container').highcharts({
	    exporting: {
		enabled: false
	    },	
	    chart: {
	        type: 'gauge',
	        plotBackgroundColor: null,
	        plotBackgroundImage: null,
	        plotBorderWidth: 0,
	        plotShadow: false
	    },
	    
	    title: {
	        text: ''
	    },
	    
	    pane: {
	        startAngle: -150,
	        endAngle: 150,
	        background: [{
	            backgroundColor: {
	                linearGradient: { x1: 0, y1: 0, x2: 0, y2: 1 },
	                stops: [
	                    [0, '#FFF'],
	                    [1, '#333']
	                ]
	            },
	            borderWidth: 0,
	            outerRadius: '109%'
	        }, {
	            backgroundColor: {
	                linearGradient: { x1: 0, y1: 0, x2: 0, y2: 1 },
	                stops: [
	                    [0, '#333'],
	                    [1, '#FFF']
	                ]
	            },
	            borderWidth: 1,
	            outerRadius: '107%'
	        }, {
	            // default background
	        }, {
	            backgroundColor: '#DDD',
	            borderWidth: 0,
	            outerRadius: '105%',
	            innerRadius: '103%'
	        }]
	    },
	       
	    // the value axis
	    yAxis: {
	        min: 0,
	        max: 50,
	        
	        tickPixelInterval: 30,
	        tickWidth: 2,
	        tickPosition: 'inside',
	        tickLength: 20,
	        tickColor: '#666',
	        labels: {
	            step: 2,
	            rotation: 'auto',
		    distance: -40,
		    style: {
			fontSize: '20px'
		    }
	        },
	        plotBands: [{
	            from: 0,
	            to: 20,
	            color: '#55BF3B', // green
		    thickness: 20
	        }, {
	            from: 20,
	            to: 40,
	            color: '#DDDF0D', // yellow
		    thickness: 20
	        }, {
	            from: 40,
	            to: 50,
	            color: '#DF5353', // red
		    thickness: 20
	        }]        
	    },
	    plotOptions: {
		gauge: {
			dial: {
				baseWidth: 5,
			},
			pivot: {
				radius: 8,
			},
			dataLabels: {
				borderWidth: 0,
				format: '{y} Gbps',
				style: {
					fontSize: '40px'
				},
				y: 50
			}
		}
	    },			
	
	    series: [{
	        name: 'Speed',
	        data: [0],
	        tooltip: {
	            valueSuffix: ' Gbps'
	        }
	    }]
	
	},
	// Add some life
        function (chart) {
                if (!chart.renderer.forExport) {
                    setInterval(function () {
			$.getJSON('speedometer.json', function(data) {
				var point = chart.series[0].points[0];
				if(data.speed > 1){
					point.update(data.speed);
				}
				if(data.speed > 55){
					point.update(55);
				}
			});
                    }, 1000);
                }
        });
});
