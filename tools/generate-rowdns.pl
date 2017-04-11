#!/usr/bin/perl
use strict;

BEGIN {
        require "include/config.pm";
}

use JSON -support_by_pp;
use LWP 5.64;
use LWP::UserAgent;
use Net::SSL; # needed, else LWP goes into emo-mode
use Net::IP;
use NetAddr::IP;
use Getopt::Long;

my ($delete);

if (@ARGV > 0) {
        GetOptions(
        'del|delete'            => \$delete,
        )
}

# Use this to generate nsupdate for all edge switches

# fetch PI API content
sub get_url{
        my $url = shift;

	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0; # just to be sure :-D
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(GET => $url);
	$req->authorization_basic($nms::config::gondul_user, $nms::config::gondul_pass);

	return $ua->request($req)->content();
}

my $json_obj = new JSON;
my $json_content = get_url($nms::config::gondul_url . "/api/read/switches-management");
if($json_content){
	my $json = $json_obj->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($json_content);
	
	print "server $nms::config::pri_v4\n";
	
	foreach my $switch (values %{$json->{switches}}){
		next unless ($switch->{subnet4}); # require at least IPv4 client subnet
		next unless ($switch->{sysname} =~ m/^e[0-9]+?\-/); # only rows
		
		(my $v4mgmt = $switch->{mgmt_v4_addr}) =~ s/\/[0-9]{1,2}//;
		(my $v6mgmt = $switch->{mgmt_v6_addr}) =~ s/\/[0-9]{1,2}//;
		(my $v4gw = NetAddr::IP->new($switch->{subnet4})->first()) =~ s/\/[0-9]{1,2}//;
		(my $v6gw = NetAddr::IP->new($switch->{subnet6})->first()) =~ s/\/[0-9]{1,2}//;
		
		my $fqdn = $switch->{sysname} . "." . $nms::config::tgname . ".gathering.org.";
		my $sw_fqdn = "sw." . $fqdn;
		my $gw_fqdn = "gw." . $fqdn;
	
		# A and AAAA-record to the switch
		if($delete){
			print "update delete $sw_fqdn \t IN A\n";
			print "update delete $sw_fqdn \t IN AAAA\n";
		} else {
			print "update add $sw_fqdn \t 3600 IN A \t $v4mgmt\n";
			print "update add $sw_fqdn \t 3600 IN AAAA \t $v6mgmt\n";
		}
		print "send\n";

		# PTR to the switch
		if($delete){
			print "update delete " . Net::IP->new($v4mgmt)->reverse_ip() . " \t IN PTR\n" if $v4mgmt;
			print "send\n" if $v4mgmt;
			print "update delete " . Net::IP->new($v6mgmt)->reverse_ip() . " \t IN PTR\n" if $v6mgmt
		} else {
			print "update add " . Net::IP->new($v4mgmt)->reverse_ip() . " \t 3600 IN PTR \t $sw_fqdn\n" if $v4mgmt;
			print "send\n" if $v4mgmt;
			print "update add " . Net::IP->new($v6mgmt)->reverse_ip() . " \t 3600 IN PTR \t $sw_fqdn\n" if $v6mgmt;
		}
		print "send\n";

		# A and AAAA-record to the gateway/router
		if($delete){
			print "update delete $gw_fqdn \t IN A\n";
			print "update delete $gw_fqdn \t IN AAAA\n";
		} else {
		        print "update add $gw_fqdn \t 3600 IN A \t $v4gw\n" if $v4gw;
		        print "update add $gw_fqdn \t 3600 IN AAAA \t $v6gw\n" if $v6gw;
		}
		print "send\n";

		# PTR to the gateway/router
		if($delete){
			print "update delete " . Net::IP->new($v4gw)->reverse_ip() . " \t IN PTR\n" if $v4gw;
			print "send\n" if $v4gw;
			print "update delete " . Net::IP->new($v6gw)->reverse_ip() . " \t IN PTR\n" if $v6gw;
		} else {
		        print "update add " . Net::IP->new($v4gw)->reverse_ip() . " \t 3600 IN PTR \t $gw_fqdn\n" if $v4gw;
			print "send\n" if $v4gw;
		        print "update add " . Net::IP->new($v6gw)->reverse_ip() . " \t 3600 IN PTR \t $gw_fqdn\n" if $v6gw;
		}
	        print "send\n";
	}
}
