package stream::config; 
use strict;
use warnings;
use NetAddr::IP;

our $v4net = NetAddr::IP->new("151.216.0.0/17");
our $v6net = NetAddr::IP->new("2a02:ed02::/32");
our $multicast = "udp://\@233.191.12.1";
our $vlc_base_host = "http://stream.tg13.gathering.org";
our $tg = 13;
our $tg_full = 2013;


# priority = sorting order in streaming list
# port , "post port number"
# has_external , shows on OVH/.fr reflector if set
# external , replaces static url link 
# source , video source pew pew
# title , title doh \:D/
our %streams =  (
# Deaktivert 31.mars kl 05.30 iush
#		'event-ios' => {
#			'type' => 'event',
#			'quality' => 'hd',
#			'priority' => 26,
#			'external' => 1,
#			'url' => "$vlc_base_host/ios/event.m3u8",
#			'source' => 'Event',
#			'title' => 'Event HD Stream for iOS devices (Apple)',
#		},
#		'event-hd' => {
#			'type' => 'event',
#			'quality' => 'hd',
#			'priority' => 20,
#			'port' => 13,
#			'interlaced' => 0,
#			'has_multicast' => 1,
#			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::13]',
#			'source' => 'Event',
#			'title' => 'Event HD (720p50)'
#		},
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
			'location' => 3,
			'quality' => 'hd',
			'priority' => 40,
			'port' => 16,
			'interlaced' => 1,
			'has_multicast' => 0,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => 'Webcam South (HD) (1080i25)',
		},

		'south-transcode' => {
			'type' => 'camera',
			'location' => 3,
			'quality' => 'hd',
			'priority' => 50,
			'port' => 17,
			'interlaced' => 0,
			'has_multicast' => 1,
			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::17]",
			'source' => 'Tech',
			'title' => 'Webcam South (HD) (720p50)',
		},


		'fuglecam' => { 
			'type' => 'camera',
			'location' => 2,
			'quality' => 'hd',
			'priority' => 118,
			'port' => 15,
			'interlaced' => 1,
			'has_multicast' => 1,
			'multicast_ip' => "udp://\@[ff7e:a40:2a02:ed02:ffff::15]",
			'source' => 'Tech',
			'title' => 'Webcam Fugleberget (HD) (1080i50)',
		},

	

		'fuglecam-flv-sd' => {
			'location' => 2,
			'type' => 'camera',
			'quality' => 'sd',
			'priority' => 121,
			'interlaced' => 1,
			'external' => 1,
			'url' => 'http://www.gathering.org/tg13/no/webcam/',
			'title' => 'Webcam Fugleberget (SD) (gathering.org flash player)',
		},

		'noc-fisheye' => {
			'type' => 'camera',
			'location' => 1,
			'quality' => 'hd',
			'priority' => 130,
			'port' => 18,
			'has_multicast' => 1,
			'interlaced' => 0,
			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::18]:2018",
			'source' => "Tech",
			'title' => "Webcam NOC Fisheye (HD)"
		},
		'noc-fisheye-transcode' => {
			'type' => 'camera',
			'location' => 1,
			'quality' => 'hd',
			'priority' => 131,
			'port' => 19,
			'has_multicast' => 1,
			'interlaced' => 0,
			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::19]:2019",
			'source' => "Tech",
			'title' => "Webcam NOC Fisheye (HD transcoded)"
		},


		'south-still' => {
			'location' => 3,
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 110,
			'external' => 1,
			'url' => 'http://stillcam.tg13.gathering.org/',
			'title' => 'Webcam South (Image)',
			'source' => 'Tech'
		},


			);


1;
