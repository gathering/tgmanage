tgmanage -- tools and hacks by Tech:Server
========

## planning.txt? patchlist.txt? netlist.txt? bootstrap? SETUP?!

See tools/README…

## dlink-ng usage

> Update A/AAAA/PTR for dlink switches 
dlink-ng/make-dlink-config.pl switches.txt patchlist.txt | tools/dlink-ng2dns.pl | head -n 30

> Delete records for creative1 in DNS
dlink-ng/make-dlink-config.pl switches.txt patchlist.txt | grep '^creative1 ' | tools/dlink-ng2dns.pl -d

> Configure both dlink and cisco side
dlink-ng/make-dlink-config.pl switches.txt patchlist.txt | grep 'creative[12]' | perl dlink-ng/dlink-ng.pl

> Configuring dlink switches for a single dlink switch
dlink-ng/make-dlink-config.pl switches.txt patchlist.txt | grep 'creative[1-8+] ' | dlink-ng/dlink-ng.pl -s creative3

> Configuring dlink switches from cisco side only
dlink-ng/make-dlink-config.pl switches.txt patchlist.txt | grep creative | perl dlink-ng/dlink-ng.pl -c

> Configures all switches with lots of threads love <3
dlink-ng/dlink-ng.pl switches.txt patchlist.txt 

> DNS for all switches pewpew
dlink-ng/dlink-ng.pl switches.txt patchlist.txt | tools/dlink-ng2dns.pl