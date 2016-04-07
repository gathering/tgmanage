#!/bin/bash
mkdir -p tmp
ls -1 *.conf | while read file; do
	# Remove rusk & rask
	sed -E \
		-e 's/secret ".+";/secret "<removed>";/g' \
		-e 's/encrypted-password ".+";/encrypted-password "<removed>";/g' \
		-e 's/"scp:\/\/.+" password ".+";/"scp:\/\/user\@host\/some\/folder\/" password "<removed>";/g' \
		-e 's/serial-number .+;/serial-number <removed>;/g' \
		-e 's/community .+ {/community <removed> {/g' \
		-e '/\/\* dat/d' \
		-e 's/ecdsa-sha2-nistp256-key .+;/ecdsa-sha2-nistp256-key <removed>;/g' \
		-e 's/collector .+;/collector <removed>;/g' \
		-e 's/authentication-key ".+"/authentication-key "<removed>";/g' \
		-e 's/LU[0-9]+/LU1337/g' \
		-e 's/SB[0-9]+/SB1337/g' \
		$file > tmp/$file

	# Remove SSH-host-info
	sed -i '' \
		-e '/ssh-known-hosts {/ {' -e 'n; s/host .\+ {/host <removed> {/' -e '}' \
		tmp/$file
	
	# Remove stuff from ACL's
	sed -i '' \
		-e ':again' -e N -e '$!b again' \
		-e 's/prefix-list mgmt-v4 {[^}]*}/prefix-list mgmt-v4 {\'$'\n''        \/\* KANDU PA-nett (brukt på servere, infra etc) \*\/\'$'\n''        185.110.148.0\/22;\'$'\n''    }/g' \
		tmp/$file

	sed -i '' \
		-e ':again' -e N -e '$!b again' \
		-e 's/prefix-list mgmt-v6 {[^}]*}/prefix-list mgmt-v6 {\'$'\n''        \/\* KANDU PA-nett (den delen som er brukt på servere, infra etc) \*\/\'$'\n''        2a06:5841::\/32;\'$'\n''    }/g' \
		tmp/$file

	sed -i '' \
		-e ':again' -e N -e '$!b again' \
		-e 's/prefix-list mgmt {[^}]*}/prefix-list mgmt {\'$'\n''        185.110.148.0\/22;\'$'\n''        2a06:5841::\/32;\'$'\n''    }/g' \
		tmp/$file

done
