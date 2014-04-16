package stream::config; 
use strict;
use warnings;
use NetAddr::IP;

our $v4net = NetAddr::IP->new("151.216.128.0/17");
our $v6net = NetAddr::IP->new("2a02:ed02::/32");
our $multicast = "udp://\@233.191.12.1";
our $vlc_base_host = "http://cubemap.tg14.gathering.org";
our $tg = 14;
our $tg_full = 2014;


# priority = sorting order in streaming list
# port , "post port number"
# has_external , shows on OVH/.fr reflector if set
# external , replaces static url link 
# source , video source pew pew
# title , title doh \:D/
our %streams =  (
		'event-hd' => {
			'type' => 'event',
			'quality' => 'hd',
			'priority' => 20,
			'port' => 80,
			'url' => '/event.ts',
			'interlaced' => 0,
			'has_multicast' => 0,
			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::15]:2015',
			'source' => 'Event',
			'title' => 'Event HD (720p50)'
		},
#		'event-sd' => {
#			'type' => 'event',
#			'quality' => 'sd',
#			'priority' => 24,
#			'port' => 14,
#			'interlaced' => 0,
#			'has_multicast' => 1,
#			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::14]',
#			'source' => 'Event',
#			'title' => 'Event SD (576p) (2mbps)'
#		},
#		'event-flash' => {
#			'type' => 'event',
#			'quality' => 'sd',
#			'priority' => 25,
#			'interlaced' => 0,
#			'external' => 1,
#			'url' => 'http://www.gathering.org/tg13/no/live-tv/',
#			'source' => 'Event',
#			'title' => 'Event SD (gathering.org flash player)',
#		},
#


		'south-raw' => { 
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 40,
			'url' => "/southcam.ts",
                        'port' => 80,
			'interlaced' => 0,
			'has_multicast' => 0,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => 'Webcam South (HD) (1920x1080 H.264) 10mbps',
		},

		'roofcam-raw' => { 
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 118,
			'url' => "/roofcam.ts",
			'port' => 80,
			'interlaced' => 1,
			'has_multicast' => 0,
			#'multicast_ip' => "udp://\@[ff7e:a40:2a02:ed02:ffff::15]",
			'source' => 'Tech',
			'title' => 'Webcam Roof (HD) (1536x1536 H.264) 8mbps',
		},

		'noccam-raw' => {
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 130,
                        'url' => '/noccam.ts',
			'port' => 80,
			'has_multicast' => 0,
			'interlaced' => 0,
			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::18]:2018",
			'source' => "Tech",
			'title' => "Webcam NOC (HD) (1280x720 H.264) 5mbps"
		},

			);


1;
