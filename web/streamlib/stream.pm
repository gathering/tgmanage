package stream;
use strict;
use warnings;

BEGIN {
	use Exporter();

        our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

        @ISA         = qw(Exporter);
	$VERSION     = 1.00;
	@EXPORT      = qw(&is_ip_local);
	
}

sub is_ip_local($$$) {
	my $clip = shift;
	my $v4net = shift;
	my $v6net = shift;
	return 0 unless defined($clip);
	
	my $is_local = 0;
	if ($clip =~ m/\:/){
		if (NetAddr::IP->new($clip)->within($v6net)){
			$is_local = 1;
		}
	} else {
		if (NetAddr::IP->new($clip)->within($v4net)){
			$is_local = 1;
		}
	}
	return $is_local;
}


1;
