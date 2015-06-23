#! /usr/bin/perl
use DBI;
use Net::DNS;
use Net::IP;
use lib '../include';
use nms;
use strict;
use warnings;

BEGIN {
require "../include/config.pm";
	eval {
		require "../include/config.local.pm";
	};
}

my $dbh = nms::db_connect() or die "Can't connect to database";
my $res = Net::DNS::Resolver->new;

$res->nameservers("$nms::config::pri_hostname.$nms::config::tgname.gathering.org");

my $kname = 'DHCP_UPDATER';

sub get_reverse {
	my ($ip) = shift;
	$ip = new Net::IP($ip) or return 0;
	my $a = $res->query($ip->reverse_ip, 'PTR') or return 0;
	foreach my $n ($a->answer) {
		return $n->{'ptrdname'}; # Return first element, ignore the rest (=
	}
	return 0;
}

sub any_quad_a {
	my ($host) = shift;
	my $a = $res->query($host, 'AAAA') or return 0;
	foreach my $n ($a->answer) {
		return 1 if ($n->{'type'} eq 'AAAA');
	}
	return 0;
}

print "Running automagic IPv6 DNS updates\n";
while (1) {
	
	# Fetch visible IPv6 addresses from the last three minutes
	#my $q = $dbh->prepare("SELECT DISTINCT ON (ipv6.mac) ipv6.address AS v6, ipv6.mac, ipv4.address AS v4, ipv6.time - ipv6.age*'1 second'::interval FROM ipv6 LEFT JOIN ipv4 ON ipv4.mac = ipv6.mac WHERE ipv6.time > NOW()-'3 min'::interval ORDER BY ipv6.mac, ipv6.time DESC, mac")
	my $q = $dbh->prepare(
"SELECT DISTINCT ON (v6) v6, ipv6.mac, ipv6.seen, v4
FROM (SELECT DISTINCT ON (address) address AS v6, mac, seen FROM seen_mac WHERE family(address) = 6 AND seen > CURRENT_TIMESTAMP - '3 min'::interval) ipv6
LEFT JOIN (SELECT DISTINCT ON (address) address AS v4, mac, seen FROM seen_mac WHERE family(address) = 4 AND seen > CURRENT_TIMESTAMP - '3 min'::interval) ipv4 ON ipv4.mac = ipv6.mac
ORDER BY v6, ipv6.seen DESC, mac")
		or die "Can't prepare query";
	$q->execute() or die "Can't execute query";
	
	my $aaaas = 0;
	my $aaaa_errors = 0;
	my $ptrs = 0;
	my $ptr_errors = 0;
	my $update;
	my $v6;
	while (my $ref = $q->fetchrow_hashref()) {
		my $hostname = get_reverse($ref->{'v4'});
		if ($hostname) {
			$v6 = $ref->{'v6'};
			my @parts = split('\.', $hostname);
			my $hostname = shift @parts;
			my $domain = join('.', @parts);
			my $v6arpa = (new Net::IP($v6))->reverse_ip;
	
			# Don't add records for nets we don't control
			next if not $v6arpa =~ m/$nms::config::ipv6zone/;
	
			# Add IPv6 reverse
			if (!get_reverse($ref->{'v6'})) {
				$update = Net::DNS::Update->new($nms::config::ipv6zone);
				$update->push(pre => nxrrset("$v6arpa IN PTR")); # Only update if the RR is nonexistent
				$update->push(update => rr_add("$v6arpa IN PTR $hostname.$domain."));
				$update->sign_tsig($kname, $nms::config::ddns_key);
				my $reply = $res->send($update);
				if ($reply->header->rcode eq 'NOERROR') {
					$ptrs++;
				} else {
					$ptr_errors++;
				}
			}
	
			# Add IPv6 forward
			if (!any_quad_a("$hostname.$domain")) {
				$update = Net::DNS::Update->new($domain);
				$update->push(pre => nxrrset("$hostname.$domain. IN AAAA $v6")); # Only update if the RR is nonexistent
				$update->push(update => rr_add("$hostname.$domain. IN AAAA $v6"));
				$update->sign_tsig($kname, $nms::config::ddns_key);
				my $reply = $res->send($update);
				if ($reply->header->rcode eq 'NOERROR') {
					$aaaas++;
				} else {
					$aaaa_errors++;
				}
			}
		}
	}
	print "Added $ptrs PTR records. $ptr_errors errors occured.\n";
	print "Added $aaaas AAAA records. $aaaa_errors errors occured.\n";
	
	
	# Remove old PTR records, that is, for hosts we haven't seen the last four
	# hours, but not older than four and a half hours, as it would take forever to
	# try to delete everything. FIXME: Query the zone file and diff against the
	# database, to avoid running as many NS-updates as tuples in the result set.
	
	$q = $dbh->prepare("SELECT DISTINCT address AS v6 FROM seen_mac WHERE seen BETWEEN CURRENT_TIMESTAMP - '4 hours'::interval AND CURRENT_TIMESTAMP - '4 hours 30 minutes'::interval")
		or die "Can't prepare query";
	$q->execute() or die "Can't execute query";
	
	my $i = 0;
	my $errors = 0;
	while (my $ref = $q->fetchrow_hashref()) {
		$v6 = $ref->{'v6'};
		if (get_reverse($v6)) {
			my $v6arpa = (new Net::IP($v6))->reverse_ip;
			my $update = Net::DNS::Update->new($nms::config::ipv6zone);
			$update->push(pre => yxrrset("$v6arpa PTR")); # Only update if the RR exists
			$update->push(update => rr_del("$v6arpa IN PTR"));
			$update->sign_tsig($kname, $nms::config::ddns_key);
			my $reply = $res->send($update);
			if ($reply->header->rcode eq 'NOERROR') {
				$i++;
			} else {
				$errors++;
			}
		}
	}
	
	print "Deleted $i old PTR records. $errors errors occured.\n";
	print "Sleeping for two minutes.\n";
	sleep(120);
}
