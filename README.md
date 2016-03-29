# tgmanage

Tools, hacks, scripts and other things used by Tech:Server to keep things running smoothly during The Gathering.

Unless stated otherwise; licensed under the GNU GPL, version 2. See the included COPYING file.

# Dependencies

For the perl stuff, you may need the following Debian packages:

- libcapture-tiny-perl
- libcgi-pm-perl
- libcommon-sense-perl
- libdata-dumper-simple-perl
- libdbi-perl
- libdigest-perl
- libgd-perl
- libgeo-ip-perl
- libhtml-parser-perl
- libhtml-template-perl
- libimage-magick-perl
- libimage-magick-q16-perl
- libjson-perl
- libjson-xs-perl
- libnetaddr-ip-perl
- libnet-cidr-perl
- libnet-ip-perl
- libnet-openssh-perl
- libnet-oping-perl
- libnet-rawip-perl
- libnet-telnet-cisco-perl
- libnet-telnet-perl
- libsnmp-perl
- libsocket6-perl
- libsocket-perl
- libswitch-perl
- libtimedate-perl
- perl
- perl-base
- perl-modules

`apt-get install libcapture-tiny-perl libcgi-pm-perl libcommon-sense-perl libdata-dumper-simple-perl libdbi-perl libdigest-perl libgd-perl libgeo-ip-perl libhtml-parser-perl libhtml-template-perl libimage-magick-perl libimage-magick-q16-perl libjson-perl libjson-xs-perl libnetaddr-ip-perl libnet-cidr-perl libnet-ip-perl libnet-openssh-perl libnet-oping-perl libnet-rawip-perl libnet-telnet-cisco-perl libnet-telnet-perl libsnmp-perl libsocket6-perl libsocket-perl libswitch-perl libtimedate-perl perl perl-base perl-modules`

You will also need SNMP mibs. For conveneince:

`tools/get_mibs.sh`
