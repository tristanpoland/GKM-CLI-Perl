#!/usr/bin/env perl
# bin/gkm-cli.pl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use GKM::CLI;

my $cli = GKM::CLI->new();
exit $cli->run(@ARGV);