while :; do
        (
                for i in $( cut -d" " -f1 pingswitches.txt ); do
			ADMINADDR=$( echo $i | perl -pi -le '@x = split /\./; $x[3] += 2; $_ = join(".", @x);' )
                        ( (
                                if ping -c2 -W3 -q $ADMINADDR >/dev/null; then
                                        grep $i pingswitches.txt | sed 's/^/PONGER: /'
                                else
                                        grep $i pingswitches.txt | sed 's/^/PONGER IKKE: /'
                                fi
                        ) & )
                done
        ) > pong.new
	while pidof ping > /dev/null; do sleep 1; done
        mv pong.new pong
        echo "sleeping"
        sleep 10
done

