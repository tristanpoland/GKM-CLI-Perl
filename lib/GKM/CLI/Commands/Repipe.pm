package GKM::CLI::Commands::Repipe;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless { ui => $args{ui} }, $class;
}

sub execute {
    my ($self, @args) = @_;
    # Repipe implementation will go here
    return 0;
}

1;