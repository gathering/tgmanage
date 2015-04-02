#!/usr/bin/perl -I /root/tgmanage/web/streamlib
use warnings;
use strict;
use CGI;
use Geo::IP;
use NetAddr::IP;
use Net::IP;
# apt-get install libnet-ip-perl libnetaddr-ip-perl 
use HTML::Template;
use stream;
use stream::config;

my $client = CGI->new;

my $v4net = $stream::config::v4net;
my $v6net = $stream::config::v6net;
my $tg = $stream::config::tg;
my $tg_full = $stream::config::tg_full;
my %streams = %stream::config::streams;

my $force_unicast = $client->param('forceunicast');
my $no_header = $client->param('noheader');

my $location = undef;

print $client->header();

my $clip = $client->remote_addr();
my $template = HTML::Template->new(filename => 'embed.tmpl');
my $is_local = &is_ip_local($clip, $v4net, $v6net);

my @streams = &html_local_test();
$template->param(TG => $tg);
$template->param(TG_FULL => $tg_full);
$template->param(STREAMS => \@streams);
$template->param(NOHEADER => $no_header);
print $template->output();


sub html_local_test() {
	my @s = ();
	foreach my $name (sort { $streams{$a}->{priority} <=> $streams{$b}->{priority} } keys %streams) {
		my $title_link = "http://stream.tg$tg.gathering.org/stream.pl?delivery=%s&stream=${name}&interlaced=%s";
		my $multicast_link = $streams{$name}->{has_multicast} ? "multicast" : "unicast";
		$multicast_link = "unicast" if ($force_unicast == 1 || not $is_local);

		if ($streams{$name}->{external}) {
			 $title_link = $streams{$name}->{url};
		} else {
			$title_link = sprintf($title_link, $multicast_link, $streams{$name}->{interlaced});
		}
		my %hash = (
			'title_link' => $title_link,
			'title' => $streams{$name}->{title},
			'quality' => $streams{$name}->{quality},
			'type' => $streams{$name}->{type},
		);
		if ($multicast_link eq "multicast") {
			$hash{'is_multicast'} .= 1; 
			my $unicast_link = $title_link;
			$unicast_link=~s/multicast/unicast/g;
			$hash{'unicast_link'} .= $unicast_link;
		}
		$hash{'description'} .= $streams{$name}->{description} if exists($streams{$name}->{description});
		push(@s, \%hash);

	}
	return @s;
}
