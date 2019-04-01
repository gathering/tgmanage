Disse filene brukes for � generere merking av kabler og switcher til The Gathering (Eller andre event med lignende behov)

##############
switch_lables.py:
##############
Brukes til � generere lapper som henges opp p� switcher/switchstativer for enkel identifisering.


Howto:
Endre configen i filen (Antall rader, antall switcher, filnavn + eventuell config for Creativia), og kj�r filen med python.

Den lager en HTML fil med valgt navn, som s� kan printes i en vanlig printer.


##############
cable_lables.pl
##############
Brukes til � generere teksten til lappene som settes i begge ender av alle kablene i hallen.

CSV-filen mates inn i dymo programvaren og formatteres der. Husk at alle lapper m� skrives ut i to eksemplarer.

Howto:
Kj�r filen med perl, sett variablene og pipe ut til csv med passende navn.

Variablene filen spiser er f�lgende: Antall rader, antall switcher per rad, antall kabler per switch.

Eksempel: 

perl cable_lables.pl 82 4 4 > Lapper.csv
