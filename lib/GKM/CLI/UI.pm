# lib/GKM/CLI/UI.pm
package GKM::CLI::UI;

use strict;
use warnings;
use Term::ANSIColor;
use Term::ReadLine;

our $LOGO = q{
 ██████╗ ██╗  ██╗███╗   ███╗
██╔════╝ ██║ ██╔╝████╗ ████║
██║  ███╗█████╔╝ ██╔████╔██║
██║   ██║██╔═██╗ ██║╚██╔╝██║
╚██████╔╝██║  ██╗██║ ╚═╝ ██║
 ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝
    Concept-0.0.1-alpha
};

our @AVAILABLE_KITS = qw(shield-v2 vault-v2 bosh-v2 concourse-v6);
our @ENVIRONMENTS = qw(sandbox dev staging prod);

sub new {
    my $class = shift;
    my $self = {
        term => Term::ReadLine->new('Genesis Kit Manager'),
    };
    bless $self, $class;
    return $self;
}

sub style_text {
    my ($self, $text, $color, $bold) = @_;
    return colored([$color, ($bold ? 'bold' : ())], $text);
}

sub heading { shift->style_text(shift, 'magenta', 1) }
sub param { shift->style_text(shift, 'yellow', 0) }
sub command { shift->style_text(shift, 'blue', 1) }
sub info { shift->style_text(shift, 'cyan', 0) }
sub style_logo { shift->style_text(shift, 'cyan', 1) }
sub style_version { shift->style_text(shift, 'white', 0) }

sub display_welcome {
    my $self = shift;
    system('clear');
    print $self->style_logo($LOGO);
    print $self->heading("Genesis Kit Manager - DevOps Automation Tools\n");
    print $self->style_version("Version 0.01\n\n");
    
    print $self->heading("Available Commands:\n");
    print "  " . $self->command("gk repipe") . " - " . $self->info("Update Concourse pipelines\n");
    print "  " . $self->command("gk template") . " - " . $self->info("Manage kit template versions\n");
    print "  " . $self->command("gk ci") . " - " . $self->info("Manage CI configuration\n\n");
}

sub prompt_select {
    my ($self, $prompt, $options) = @_;
    my $term = $self->{term};
    my $reply = $term->get_reply(
        prompt  => $self->param($prompt),
        choices => $options,
        default => $options->[0],
    );
    return $reply;
}

1;

__END__

=head1 NAME

GKM::CLI::UI - User interface components for the Genesis Kit Manager CLI