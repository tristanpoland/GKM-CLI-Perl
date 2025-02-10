package GKM::CLI::UI;

use strict;
use warnings;
use Term::ANSIColor;
use Term::ReadKey;

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
    my $self = {};
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
    
    while (1) {
        print "\n" . $self->param($prompt) . "\n\n";
        
        for (my $i = 0; $i < @$options; $i++) {
            printf("%d) %s\n", $i + 1, $options->[$i]);
        }
        
        print "\nEnter selection (1-" . scalar(@$options) . "): ";
        my $choice = <STDIN>;
        chomp($choice);
        
        if ($choice =~ /^\d+$/ && $choice >= 1 && $choice <= scalar(@$options)) {
            return $options->[$choice - 1];
        }
        
        print $self->style_text("Invalid selection. Please try again.\n", 'red', 0);
    }
}

1;