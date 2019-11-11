#!/bin/bash

curl --user tech:<Removed> https://gondul.tg19.gathering.org/api/templates/dhcpd.conf > /etc/dhcp/automatic_zones_v4.conf
curl --user tech:<Removed> https://gondul.tg19.gathering.org/api/templates/dhcpd6.conf > /etc/dhcp/automatic_zones_v6.conf
curl --user tech:<Removed> https://gondul.tg19.gathering.org/api/templates/fap_dhcp4.conf > /etc/dhcp/automatic_zones_fap4.conf

/usr/sbin/dhcpd -4 -t -cf /etc/dhcp/dhcpd.conf
if [ $? -eq 0 ]
then
    /usr/sbin/service isc-dhcp-server4 restart
    if [ $? -eq 0 ]
    then
        echo "Restarted isc-dhcp-server4 success!"
    else
        echo "Failed to restart DHCPv4, panic!"
	exit 1
    fi
else
    echo "DHCPv4 failed! Not restarted"
    exit 1
fi
/usr/sbin/dhcpd -6 -t -cf /etc/dhcp/dhcpd6.conf
if [ $? -eq 0 ]
then
    /usr/sbin/service isc-dhcp-server6 restart
    if [ $? -eq 0 ]
    then
        echo "Restarted isc-dhcp-server6 success!"
    else
        echo "Failed to restart DHCPv6, panic!"
	exit 1
    fi
else
    echo "DHCPv6 failed! Not restarted"
    exit 1
fi
