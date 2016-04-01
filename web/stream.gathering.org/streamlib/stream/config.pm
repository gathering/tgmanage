package stream::config; 
use strict;
use warnings;
use NetAddr::IP;

our $v4net = NetAddr::IP->new("151.216.128.0/17");
our $v6net = NetAddr::IP->new("2a02:ed02::/32");
our $multicast = "udp://\@233.191.12.1";
our $video_url = "http://cubemap.tg16.gathering.org/event.flv";
our $video_url_mp4 = "http://cubemap.tg16.gathering.org/event.mp4";
our $video_url_fallback = "http://stream.tg16.gathering.org/hls/event.m3u8";
our $tg = 16;
our $tg_full = 2016;


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
			'main_url' => 'http://cubemap.tg15.gathering.org/event.flv',
			'ts_enabled' => 1,
			'online' => 0,
			'external' => 1,
			'interlaced' => 0,
			'has_multicast' => 0,
			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::15]:2015',
			'source' => 'Event',
			'title' => 'Event HD (720p50 H.264) 6Mbit/s'
		},
                'creativia-hd' => {
                        'type' => 'event',
                        'quality' => 'hd',
                        'priority' => 100,
                        'port' => 80,
                        'main_url' => 'http://cubemap.tg15.gathering.org/creativia.flv',
                        'ts_enabled' => 1,
                        'online' => 0,
                        'external' => 1,
                        'interlaced' => 0,
                        'has_multicast' => 0,
                        'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::15]:2015',
                        'source' => 'Event',
                        'title' => 'Creativia HD (1080p50 H.264) 10Mbit/s'
                },
                'game-hd' => {
                        'type' => 'event',
                        'quality' => 'hd',
                        'priority' => 110,
                        'port' => 80,
                        'main_url' => 'http://cubemap.tg15.gathering.org/game.flv',
                        'ts_enabled' => 1,
                        'online' => 0,
                        'external' => 1,
                        'interlaced' => 0,
                        'has_multicast' => 0,
                        'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::15]:2015',
                        'source' => 'Event',
                        'title' => 'Game HD (720p50 H.264) 6Mbit/s'
                },
		'event-sd' => {
			'type' => 'event',
			'quality' => 'sd',
			'priority' => 24,
			'port' => 80,
			'online' => 0,
			'main_url' => '/event-sd.ts',
			'interlaced' => 0,
			'has_multicast' => 0,
			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::14]',
			'source' => 'Event',
			'title' => 'Event SD (576p) (2mbps)'
		},
		'event-superlow' => {
			'type' => 'event',
			'quality' => 'sd',
			'priority' => 25,
			'port' => 80,
			'online' => 0,
			'main_url' => '/event-superlow.ts',
			'interlaced' => 0,
			'has_multicast' => 0,
			'multicast_ip' => 'udp://@[ff7e:a40:2a02:ed02:ffff::16]',
			'source' => 'Event',
			'title' => 'Event Superlow SD (360p) (500kbit)'
		},
#		'event-flash' => {
#			'type' => 'event',
#			'quality' => 'sd',
#			'priority' => 25,
#			'interlaced' => 0,
#			'external' => 1,
#			'main_url' => 'http://www.gathering.org/tg13/no/live-tv/',
#			'source' => 'Event',
#			'title' => 'Event SD (gathering.org flash player)',
#		},
		'roofcam-raw' => { 
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 118,
			'main_url' => "/roofcam.ts",
			'port' => 80,
			'ts_enabled' => 0,
			'interlaced' => 1,
			'online' => 0,
			'has_multicast' => 0,
			#'multicast_ip' => "udp://\@[ff7e:a40:2a02:ed02:ffff::15]",
			'source' => 'Tech',
			'title' => 'Webcam Roof (HD) (1536x1536 H.264) 8mbps',
		},

		'south-raw' => { 
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 40,
			'main_url' => "http://cubemap.tg16.gathering.org/southcam.flv", # <-- In use (Need to rebuild row 67 in index.pl)
			'fallback_url' => 'http://stream.tg16.gathering.org/hls/southcam.m3u8',
			'port' => 80,
			'ts_enabled' => 1,
			'interlaced' => 0,
			'has_multicast' => 0,
			'external' => 1, # <-- In use (Need to rebuild row 67 in index.pl)
			'online' => 1,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => "Webcam South (720p H.264 6Mbit/s)",
		},

		'noccam-raw' => {
			'type' => 'camera',
			'quality' => 'hd',
			'priority' => 130,
			'main_url' => 'http://cubemap.tg16.gathering.org/noccam.flv',
			'fallback_url' => 'http://stream.tg16.gathering.org/hls/noccam.m3u8',
			'port' => 80, # <-- Safe to remove
			'external' => 1,
			'ts_enabled' => 1,
			'has_multicast' => 0, # <-- Safe to remove
			'interlaced' => 0, # <-- Safe to remove
			'online' => 1,
			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::18]:2018",# <-- Safe to remove
			'source' => "Tech", # <-- Safe to remove
			'title' => "Webcam NOC (720p H.264 6Mbit/s)"
		},

		'Event' => { 
			'type' => 'event',
			'quality' => 'hd',
			'priority' => 12,
			'main_url' => 'http://cubemap.tg16.gathering.org/event.flv',
			'mp4_url' => 'http://cubemap.tg16.gathering.org/event.mp4',
			'fallback_url' => 'http://stream.tg16.gathering.org/hls/event.m3u8',
			'port' => 80,
			'ts_enabled' => 1,
			'interlaced' => 0,
			'has_multicast' => 0,
			'external' => 1, # <-- In use (Need to rebuild row 67 in index.pl)
			'online' => 1,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => "Event/Stage (720p H.264 6Mbit/s)",
		},

		'Game' => { 
			'type' => 'event',
			'quality' => 'hd',
			'priority' => 13,
			'main_url' => 'http://cubemap.tg16.gathering.org/game.flv',
			'fallback_url' => 'http://stream.tg16.gathering.org/hls/game.m3u8',
			'port' => 80,
			'ts_enabled' => 1,
			'interlaced' => 0,
			'has_multicast' => 0,
			'external' => 1, # <-- In use (Need to rebuild row 67 in index.pl)
			'online' => 0,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => "Game (720p H.264 6Mbit/s)",
		},

		'Creative' => { 
			'type' => 'event',
			'quality' => 'hd',
			'priority' => 14,
			'main_url' => 'http://cubemap.tg16.gathering.org/creativia.flv',
			'fallback_url' => 'http://stream.tg16.gathering.org/hls/creativia.m3u8',
			'port' => 80,
			'ts_enabled' => 1,
			'interlaced' => 0,
			'has_multicast' => 0,
			'external' => 1, # <-- In use (Need to rebuild row 67 in index.pl)
			'online' => 1,
#			'multicast_ip' => "udp://@[ff7e:a40:2a02:ed02:ffff::16]",
			'source' => 'Tech',
			'title' => "Creative (720p H.264 6Mbit/s)",
		}

);

1;
