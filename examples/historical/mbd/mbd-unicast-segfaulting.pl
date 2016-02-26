#! /usr/bin/perl
use strict;
use warnings;
use Socket;
use Net::CIDR;
use Net::RawIP;
use Time::HiRes;
require './access_list.pl';
require './nets.pl';
require './survey.pl';
require './mbd.pm';
use lib '../include';
use nms;
use strict;
use warnings;
use threads;

# Mark packets with DSCP CS7
my $tos = 56;

my ($dbh, $q);

sub fhbits {
	my $bits = 0;
	for my $fh (@_) {
		vec($bits, fileno($fh), 1) = 1;
	}
	return $bits;
}

# used for rate limiting
my %last_sent = ();

# for own surveying
my %active_surveys = ();
my %last_survey = ();

my %cidrcache = ();
sub cache_cidrlookup {
	my ($addr, $net) = @_;
	my $key = $addr . " " . $net;

	if (!exists($cidrcache{$key})) {
		$cidrcache{$key} = Net::CIDR::cidrlookup($addr, $net);
	}
	return $cidrcache{$key};
}

my %rangecache = ();
sub cache_cidrrange {
	my ($net) = @_;

	if (!exists($rangecache{$net})) {
		my ($range) = Net::CIDR::cidr2range($net);
		$range =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)-(\d+)\.(\d+)\.(\d+)\.(\d+)/ or die "Did not understand range: $range";
		my @range = ();
		for my $l (($4+1)..($8-1)) {
			push @range, "$1.$2.$3.$l";
		}
		($rangecache{$net}) = \@range;
	}

	return @{$rangecache{$net}};
}

open LOG, ">>", "mbd.log";

my @ports = ( mbd::find_all_ports() , $Config::survey_port_low .. $Config::survey_port_high );

# Open a socket for each port
my @socks = ();
my $udp = getprotobyname("udp");
for my $p (@ports) {
	my $sock;
	socket($sock, PF_INET, SOCK_DGRAM, $udp);
	bind($sock, sockaddr_in($p, INADDR_ANY));
	push @socks, $sock;
}

my $sendsock = Net::RawIP->new({udp => {}});

print "Listening on " . scalar @ports . " ports.\n";

# Main loop
while (1) {
	my $rin = fhbits(@socks);
	my $rout;

	my $nfound = select($rout=$rin, undef, undef, undef);
	my $now = [Time::HiRes::gettimeofday];

	# First of all, close any surveys that are due.
	for my $sport (keys %active_surveys) {
		my $age = Time::HiRes::tv_interval($active_surveys{$sport}{start}, $now);
		if ($age > $Config::survey_time && $active_surveys{$sport}{active}) {
			my $hexdump = join(' ', map { sprintf "0x%02x", ord($_) } (split //, $active_surveys{$sport}{data}));
			print "Survey ($hexdump) for '" . $Config::access_list[$active_surveys{$sport}{entry}]->{name} . "'/" .
				$active_surveys{$sport}{dport} . ": " . $active_surveys{$sport}{num} . " active servers.\n";
			$active_surveys{$sport}{active} = 0;
	
			# (re)connect to the database if needed	
			if (!defined($dbh) || !$dbh->ping) {
				$dbh = nms::db_connect();
				$q = $dbh->prepare("INSERT INTO mbd_log (ts,game,port,description,active_servers) VALUES (CURRENT_TIMESTAMP,?,?,?,?)")
					or die "Couldn't prepare query";
			}
			$q->execute($active_surveys{$sport}{entry}, $active_surveys{$sport}{dport}, $Config::access_list[$active_surveys{$sport}{entry}]->{name}, $active_surveys{$sport}{num});
		}
		if ($age > $Config::survey_time * 3.0) {
			delete $active_surveys{$sport};
		}
	}

	for my $sock (@socks) {
		next unless (vec($rout, fileno($sock), 1) == 1);

		my $data;
		my $addr = recv($sock, $data, 8192, 0);   # jumbo broadcast! :-P
		my ($sport, $saddr) = sockaddr_in($addr);
		my ($dport, $daddr) = sockaddr_in(getsockname($sock));
		my $size = length($data);

		# Check if this is a survey reply
		if ($dport >= $Config::survey_port_low && $dport <= $Config::survey_port_high) {
			if (!exists($active_surveys{$dport})) {
				print "WARNING: Unknown survey port $dport, ignoring\n";
				next;
			}
			if (!$active_surveys{$dport}{active}) {
				# remains
				next;
			}
			
			++$active_surveys{$dport}{num};

			next;
		}
		
		# Rate limiting
		if (exists($last_sent{$saddr}{$dport})) {
			my $elapsed = Time::HiRes::tv_interval($last_sent{$saddr}{$dport}, $now);
			if ($elapsed < 1.0) {
				print LOG "$dport $size 2\n";
				print inet_ntoa($saddr), ", $dport, $size bytes => rate-limited ($elapsed secs since last)\n";
				next;
			}
		}
		
		# We don't get the packet's destination address, but I guess this should do...
		# Check against the ACL.
		my $pass = 0;
		my $entry = -1;
		for my $rule (@Config::access_list) {
			++$entry;

			next unless (mbd::match_ranges($dport, $rule->{'ports'}));
			next unless (mbd::match_ranges($size, $rule->{'sizes'}));

			if ($rule->{'filter'}) {
				next unless ($rule->{'filter'}($data));
			}

			$pass = 1;
			last;
		}

		print LOG "$dport $size $pass\n";

		if (!$pass) {
			print inet_ntoa($saddr), ", $dport, $size bytes => filtered\n";
			next;
		}

		$last_sent{$saddr}{$dport} = $now;

		# The packet is OK! Do we already have a recent enough survey
		# for this port, or should we use this packet?
		my $survey = 1;
		if (exists($last_survey{$entry . "/" . $dport})) {
			my $age = Time::HiRes::tv_interval($last_survey{$entry . "/" . $dport}, $now);
			if ($age < $Config::survey_freq) {
				$survey = 0;
			}
		}

		# New survey; find an unused port
		my $survey_sport;
		if ($survey) {
			for my $port ($Config::survey_port_low..$Config::survey_port_high) {
				if (!exists($active_surveys{$port})) {
					$survey_sport = $port;

					$active_surveys{$port} = {
						start => $now,
						active => 1,
						dport => $dport,
						entry => $entry,
						num => 0,
						data => $data,
					};
					$last_survey{$entry . "/" . $dport} = $now;

					last;
				}
			}

			if (!defined($survey_sport)) {
				print "WARNING: no free survey source ports, not surveying.\n";
				$survey = 0;
			}
		}

		# precache
		for my $net (@Config::networks) {
			cache_cidrrange($net);
			cache_cidrlookup(inet_ntoa($saddr), $net);
		}

		threads->create(sub {
			my $sendsock = Net::RawIP->new({udp => {}});
			my ($survey_sport, $dport, $data) = @_;

			my $num_nets = 0;
			for my $net (@Config::networks) {
				my @daddrs = cache_cidrrange($net);

				if ($survey) {
					for my $daddr (@daddrs) {
						$sendsock->set({
							ip => {
								saddr => $Config::survey_ip,
								daddr => $daddr,
								tos => $tos
							},
							udp => {
								source => $survey_sport,
								dest => $dport,
								data => $data
							}
						});
						$sendsock->send;
					}
				}

				next if (cache_cidrlookup(inet_ntoa($saddr), $net));

				for my $daddr (@daddrs) {
					$sendsock->set({
						ip => {
							saddr => inet_ntoa($saddr),
							daddr => $daddr,
							tos => $tos
						},
						udp => {
							source => $sport,
							dest => $dport,
							data => $data
						}
					});
					$sendsock->send;
				}

				++$num_nets;
			}
			if ($survey) {
				print inet_ntoa($saddr), ", $dport, $size bytes => ($num_nets networks) [+survey from port $survey_sport]\n";
			} else {
				print inet_ntoa($saddr), ", $dport, $size bytes => ($num_nets networks)\n";
			}
		}, $survey_sport, $dport, $data)->detach();
	}
}

