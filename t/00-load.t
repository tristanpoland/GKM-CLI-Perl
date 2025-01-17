#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'GKM::CLI' ) || print "Bail out!\n";
}

diag( "Testing GKM::CLI $GKM::CLI::VERSION, Perl $], $^X" );
