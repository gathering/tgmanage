for zone in $(pdnsutil list-all-zones); do
	pdns_control notify $zone
done
