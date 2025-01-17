package GKM::CLI::Commands::Template;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless { ui => $args{ui} }, $class;
}

sub execute {
    my ($self, @args) = @_;
    # Template implementation will go here
    return 0;
}

1;