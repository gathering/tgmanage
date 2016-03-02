#!/usr/bin/env
use strict;
use warnings;
use Capture::Tiny ':all';

$! = 1;
print "Content-Type: video/mp4\n\n";

my ($stdout, $stderr) = tee {
	system('wget', '-qO-', 'http://stream.tg13.gathering.org:3013');
};
