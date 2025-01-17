# lib/GKM/CLI.pm
package GKM::CLI;

use strict;
use warnings;
use 5.010;

use GKM::CLI::UI;
use GKM::CLI::Commands::Repipe;
use GKM::CLI::Commands::Template;
use GKM::CLI::Commands::CI;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self = {
        ui => GKM::CLI::UI->new(),
    };
    bless $self, $class;
    return $self;
}

sub run {
    my ($self, @args) = @_;
    my $command = shift @args || '';

    $self->{ui}->display_welcome();

    if ($command eq 'repipe') {
        GKM::CLI::Commands::Repipe->new(ui => $self->{ui})->execute(@args);
    }
    elsif ($command eq 'template') {
        GKM::CLI::Commands::Template->new(ui => $self->{ui})->execute(@args);
    }
    elsif ($command eq 'ci') {
        GKM::CLI::Commands::CI->new(ui => $self->{ui})->execute(@args);
    }
    else {
        say "Please specify a command. Use --help for usage information.";
        return 1;
    }
    return 0;
}

1;

__END__

=head1 NAME

GKM::CLI - Genesis Kit Manager CLI Tool

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    use GKM::CLI;
    my $cli = GKM::CLI->new();
    exit $cli->run(@ARGV);

=head1 DESCRIPTION

A CLI tool for managing Genesis Kits, including pipeline management, template versioning, and CI configuration.

=head1 AUTHOR

Your Name, C<< <your@email.com> >>

=cut