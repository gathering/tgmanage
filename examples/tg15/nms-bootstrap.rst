Bostrappe NMS
==============

1. Lag en maskin. Kall den, f.eks, Noget. Installer Debian på den. Tips:
   "Web Server"-rollen fungerer bra.
2. Legg inn git, få inn tgmanage repoet. Legg det under /root om du ønsker
   å spare deg selv for litt arbeid.
3. Gjør tgmanage tilgjengelig for andre brukere (type: chmod a+rx /root
   f.eks)
4. Link::
        ln -s /root/tgmanage/web/etc/apache2/nms-public.tg15.gathering.org \
                /etc/apache2/sites-enabled/
        ln -s /root/tgmanage/web/etc/apache2/nms.tg15.gathering.org \
                /etc/apache2/sites-enabled/
5. Fjern::
        
        rm /etc/apache2/sites-enabled/000*

6. Installer postgresql. Lag en bruker og mat databasen::
       
       su - postgres
       # (som postgres)
       createuser nms
       psql < /root/tgmanage/sql/nms.sql

7. Sørg for at du har ``include/cofig.pm`` satt opp korrekt, dette henger
   typisk sammen med bootstrappingen av TG, vel og merke. Det viktigste for
   oss foreløpig er databaseinformasjonen.

8. Installer Diverse dependencies::

        cd /root/tgmanage/web/nms.gathering.org
        ./nettkart.pl
        # Hmm, den mangler Foo/Bar!
        apt-get install libfoo-bar-perl
        # Rinse and repeat til feilmeldinger magisk forsvinner

9. Test: http://nms.tg15.gathering.org (her kan /etc/hosts være nyttig)

10. Fiks det du gjorde feil. Du vil nå ha en nms-side som delvis funker,
    men har null data og dermed bare viser tomme kart.

11. Ta en velfortjent pause. Nyt f.eks http://i.imgur.com/n5Sx4Bx.gif litt

12. Populer ``/srv/www/nms-public.tg15.gathering.org/``::

        FOO=/srv/www/nms-public.tg15.gathering.org
        mkdir -p ${FOO}
        cp /root/tgmanage/web/nms-public.gathering.org/* ${FOO}

13. Kjør ``/root/tgmanage/clients/update-public-nms.sh`` og fiks eventuel
    whine om dependencies.

14. Link opp cron::
        
        ln -s /root/tgmanage/web/etc/cron/update-public-nms \
                /etc/cron/

15. Begynn det artige populeringsarbeidet


