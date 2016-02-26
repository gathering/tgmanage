
package Config;

sub game_id {
  my ($data, $offset) = @_;
  my $id = ((ord(substr($data, $offset, 1)) << 8) | ord(substr($data, $offset + 1, 1)));
  return $id;
}

our @access_list = (
	# half-life - untested (packet dump only)
	{
		name => 'Half-Life',
		ports => [ 27015 ],
		sizes => [ 16 ]
	},

	# cs 1.6 - verified
	# (funker muligens for _alle_ source-spill inkl. hl2/cs:s)
	{
		name => 'CS:Source',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 25 ],
		filter => sub { return (game_id(shift, 4) == 0x4325); }
	},
	{
		name => 'Left 4 Dead',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 25 ],
		filter => sub { return (game_id(shift, 4) == 0x43f3); }
	},
	{
		name => 'CS 1.6',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 25 ],
		filter => sub { return (game_id(shift, 4) == 0x5453); }
	},
	{
		name => 'Unknown Source-based game (ID 0x4326)',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 25 ],
		filter => sub { return (game_id(shift, 4) == 0x4326); }
	},
	{
		name => 'Other Source game (unknown game ID)',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 25 ],
	},
	{
		name => 'Other Source game (unknown game ID, odd length 33)',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 33 ],
	},
	{
		name => 'Other Source game (unknown game ID, odd length 58)',
		ports => [ "26900..26903", "27015..27017" ],
		sizes => [ 58 ],
	},
	{
                name => 'Other Source game (unknown game ID, odd length 15)',
                ports => [ "26900..26903", "27015..27017" ],
                sizes => [ 15 ],
        },

	# doom 3 - verified
	{
		name => 'Doom 3',
		ports => [ "27666" ],
		sizes => [ 14 ]
	},

	# quake 1 - verified
	{
		name => 'Quake 1',
		ports => [ 26000 ],
		sizes => [ 12 ]
	},

	# q3a - tested with demo only
	# rtcw: enemy territory - untested (packet dump only)
	{
		name => 'Quake 3 Arena, RTCW: ET',
#		ports => [ "27960..27969" ],
		ports => [ "27960..27961" ],
		sizes => [ 15 ]
	},
	
	# bf2 - tested with demo only
	# bf2142 reportedly uses same engine
	{
		name => 'BF2/BF2142',
		ports => [ "29900" ],
		sizes => [ 8 ]
	},

	# bf1942 - unverified (packet dump only)
	{
		name => 'BF1942',
		ports => [ "22000..22010" ],
		sizes => [ 8 ]
	},
	
	# quake 4 - tested with demo only, MUST select "internet"
	{
		name => 'Quake 4',
		ports => [ 27950, 28004 ],
		sizes => [ 14 ]
	},

	# quake 2 - untested (packet dump only)
	{
		name => 'Quake 2',
		ports => [ 27910 ],
		sizes => [ 11 ]
	},

	# warcraft 3 - untested (packet dump only)
	{
		name => 'Warcraft 3: Reign of Chaos (1.00)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352 && ord(substr($data, 8, 1)) == 0; }
	},
	{
		name => 'Warcraft 3: Reign of Chaos (1.07)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352 && ord(substr($data, 8, 1)) == 7; }
	},
	{
		name => 'Warcraft 3: Reign of Chaos (1.20)',
     		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352 && ord(substr($data, 8, 1)) == 20; }
	},
	{
		name => 'Warcraft 3: Reign of Chaos (1.22)',
     		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352 && ord(substr($data, 8, 1)) == 22; }
	},
	{
		name => 'Warcraft 3: Reign of Chaos (1.23)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352 && ord(substr($data, 8, 1)) == 23; }
	},
	{
		name => 'Warcraft 3: Reign of Chaos (other patch level)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x3352; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.17)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 17; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.18)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 18; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.20)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 20; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.21)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 21; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.22)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 22; }
	},
	{
		name => 'Warcraft 3: The Frozen Throne (1.23)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 23; }
	},
	{
                name => 'Warcraft 3: The Frozen Throne (1.26)',
      		ports => [ 6112 ],
                sizes => [ 16 ],
                filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058 && ord(substr($data, 8, 1)) == 26; }
        },
	{
		name => 'Warcraft 3: The Frozen Throne (other patch level)',
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) == 0x5058; }
	},
	{
		name => 'Warcraft 3 (unknown version)',
#		ports => [ "6112..6119" ],
      		ports => [ 6112 ],
		sizes => [ 16 ],
		filter => sub { my $data = shift; return (ord(substr($data, 1, 1)) == 0x2f) && game_id($data, 4) != 0x5058 && game_id($data, 4) != 0x3352; }
	},
	{
		name => 'Warcraft 3 (unknown version, odd length)',
		ports => [ 6112 ],
		sizes => [ 19 ],
	},

	# ut2003/ut2004 - untested (packet dump only)
	{
		name => 'UT2003/UT2004',
		ports => [ 10777 ],
		sizes => [ 5 ]
	},

	# soldat - untested (packet dump only)
	{
		name => 'Soldat',
		ports => [ 23073 ],
		sizes => [ 8 ]
	},

	# starcraft - untested (packet dump only)
	{
		name => 'Starcraft',
		ports => [ 6111, 6112 ],
		sizes => [ 8 ],
		filter => sub { return (game_id(shift, 0) == 0x08ef); }
	},
   {
		name => 'Starcraft: Brood War',
		ports => [ 6111, 6112 ],
		sizes => [ 8 ],
		filter => sub { return (game_id(shift, 0) == 0xf733); }
	},
	{
		name => 'Starcraft (unknown game ID)',
		ports => [ 6111, 6112 ],
		sizes => [ 8 ],
		filter => sub { my $id = game_id(shift, 0); return ($id != 0x08ef && $id != 0xf733); }
	},

	# trackmania nations - untested (packet dump only)
	{
		name => 'Trackmania Nations',
		ports => [ "2350" ],
		sizes => [ 42, 30 ]
	},

	# company of heroes - untested (packet dump only)
	{
		name => 'Company of Heroes',
		ports => [ 9100 ],
		sizes => [ 39 ]
	},

	# command & conquer 3 - untested (packet dump only, reported to have some kind
	# of chat functionality)
#	{
#		name => 'Command & Conquer 3',
#		ports => [ "8086..8093" ],
#		sizes => [ 476 ],
#		filter => sub { return 0; }
#	},

	# openttd
	{
		name => 'OpenTTD',
		ports => [ 3979 ],
		sizes => [ 3 ]
	},

	# CoD4
	{
		name => 'Call of Duty 4',
		ports => [ 28960 ],
		sizes => [ 15 ],
	},
	
   # Far Cry 2
	{
		name => 'Far Cry 2',
		ports => [ 9004 ],
		sizes => [ 114, 118, 122, 126 ],
	},

	# unreal tournament, port 9777?
)
