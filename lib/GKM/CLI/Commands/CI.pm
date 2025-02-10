package GKM::CLI::Commands::CI;
use strict;
use warnings;
use JSON;
use LWP::UserAgent;
use HTTP::Request;
use Term::ReadKey;
use File::Path qw(make_path);
use Curses::UI;
use Git::Repository;
use File::Spec;
use POSIX qw(strftime);
use DateTime::Format::ISO8601;

use constant {
    GITHUB_API_URL => 'https://api.github.com',
    CONFIG_DIR => $ENV{HOME} . '/.gkm',
    CONFIG_FILE => $ENV{HOME} . '/.gkm/config.json',
};

sub DEBUG {
    my $msg = shift;
    open(my $fh, '>>', 'gkm-debug.log') or return;
    print $fh "[" . localtime() . "] $msg\n";
    close $fh;
}

sub new {
    my ($class, %args) = @_;
    my $self = {
        ui => $args{ui},
        ua => LWP::UserAgent->new,
        config => {},
        current_repo => undef,
        current_workflow => undef,
        workflows => [],
        runs => [],
        menu => undef,
        cui => undef,
    };
    bless $self, $class;
    $self->load_config();
    $self->detect_repository();
    return $self;
}

sub load_config {
    my ($self) = @_;
    if (-f CONFIG_FILE) {
        local $/;
        open(my $fh, '<', CONFIG_FILE) or die "Cannot open config file: $!";
        $self->{config} = decode_json(<$fh>);
        close $fh;
    }
}

sub save_config {
    my ($self) = @_;
    make_path(CONFIG_DIR) unless -d CONFIG_DIR;
    open(my $fh, '>', CONFIG_FILE) or die "Cannot open config file: $!";
    print $fh encode_json($self->{config});
    close $fh;
}

sub detect_repository {
    my ($self) = @_;
    eval {
        my $repo = Git::Repository->new(work_tree => '.');
        my $config = $repo->run('config', '--get', 'remote.origin.url');
        if ($config =~ m{github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$}) {
            $self->{current_repo} = $1;
        }
    };
}

sub get_github_token {
    my ($self) = @_;
    return $self->{config}{github_token} if $self->{config}{github_token};
    
    print "Please enter your GitHub token: ";
    ReadMode('noecho');
    my $token = ReadLine(0);
    ReadMode('restore');
    chomp $token;
    print "\n";
    
    $self->{config}{github_token} = $token;
    $self->save_config();
    return $token;
}

sub make_github_request {
    my ($self, $method, $endpoint, $data) = @_;
    my $token = $self->get_github_token();
    
    my $url = GITHUB_API_URL . $endpoint;
    my $req = HTTP::Request->new($method => $url);
    $req->header('Authorization' => "Bearer $token");
    $req->header('Accept' => 'application/vnd.github.v3+json');
    
    if ($data) {
        $req->header('Content-Type' => 'application/json');
        $req->content(encode_json($data));
    }
    
    my $res = $self->{ua}->request($req);
    return undef unless $res->is_success;
    
    my $content = $res->content;
    return $content if $res->header('Content-Type') =~ /application\/zip/;
    return decode_json($content);
}

sub list_workflows {
    my ($self, $repo) = @_;
    my $workflows = $self->make_github_request('GET', "/repos/$repo/actions/workflows");
    return $workflows->{workflows};
}

sub get_workflow_runs {
    my ($self, $repo, $workflow_id) = @_;
    my $runs = $self->make_github_request('GET', "/repos/$repo/actions/workflows/$workflow_id/runs");
    return $runs->{workflow_runs};
}

sub get_run_logs {
    my ($self, $repo, $run_id) = @_;
    
    # First try to get the job information
    my $jobs = $self->make_github_request('GET', "/repos/$repo/actions/runs/$run_id/jobs");
    return "No jobs found" unless $jobs && $jobs->{jobs};
    
    # Format job information
    my $log_text = "";
    foreach my $job (@{$jobs->{jobs}}) {
        $log_text .= sprintf("\nJob: %s (%s)\n", $job->{name}, $job->{status});
        $log_text .= "-" x 40 . "\n";
        
        if ($job->{steps}) {
            foreach my $step (@{$job->{steps}}) {
                $log_text .= sprintf("  Step: %s\n", $step->{name});
                $log_text .= sprintf("  Status: %s\n", $step->{status});
                $log_text .= sprintf("  Conclusion: %s\n", $step->{conclusion} || 'N/A');
                $log_text .= sprintf("  Started: %s\n", $step->{started_at} || 'N/A');
                $log_text .= sprintf("  Completed: %s\n", $step->{completed_at} || 'N/A');
                $log_text .= "\n";
            }
        } else {
            $log_text .= "  No steps information available\n\n";
        }
    }
    
    return $log_text;
}

sub trigger_workflow {
    my ($self, $repo, $workflow_id, $ref, $inputs) = @_;
    my $data = {
        ref => $ref,
        inputs => $inputs,
    };
    return $self->make_github_request('POST', "/repos/$repo/actions/workflows/$workflow_id/dispatches", $data);
}

sub cleanup_windows {
    my ($self, $cui, @windows) = @_;
    foreach my $win (@windows) {
        eval { $cui->delete($win) if $cui->getobj($win) };
    }
}

sub create_tui {
    my ($self) = @_;
    
    $self->{cui} = Curses::UI->new(
        -color_support => 1,
        -clear_on_exit => 1,
    );

    my $win = $self->{cui}->add('window_id', 'Window',
        -border => 1,
        -y    => 0,
        -bfg  => 'green',
    );

    my $status = $self->{cui}->add('status', 'Window',
        -y => -1,
        -height => 1,
        -bfg => 'blue',
    );
    $status->set_color_fg('white');

    $self->show_workflow_selector($self->{cui});
    $self->{menu} = $win->add(
        'menu', 'Listbox',
        -y => 1,
        -border => 1,
        -title => 'GitHub Actions Manager',
        -values => [
            'View Workflows',
            'View Workflow Runs',
            'View Run Logs',
            'Trigger Workflow',
            'Exit',
        ],
        -labels => {
            'View Workflows' => 'View Workflows         (F1)',
            'View Workflow Runs' => 'View Workflow Runs     (F2)',
            'View Run Logs' => 'View Run Logs          (F3)',
            'Trigger Workflow' => 'Trigger Workflow       (F4)',
            'Exit' => 'Exit                  (ESC)',
        },
        -onselchange => sub {
            my $sel = $self->{menu}->get();
            $self->handle_menu_selection($self->{cui}, $sel);
        },
    );

    $self->{cui}->set_binding(sub { $self->view_workflows($self->{cui}) }, "F1");
    $self->{cui}->set_binding(sub { $self->view_runs($self->{cui}) }, "F2");
    $self->{cui}->set_binding(sub { $self->view_logs($self->{cui}) }, "F3");
    $self->{cui}->set_binding(sub { $self->trigger_workflow_dialog($self->{cui}) }, "F4");
    $self->{cui}->set_binding(sub { exit(0) }, "\cC", "\cQ");

    $self->update_status($status);

    return $self->{cui};
}

sub update_status {
    my ($self, $status) = @_;
    my $repo_text = $self->{current_repo} ? "Current repo: " . $self->{current_repo} : "No repository detected";
    $status->add(
        'status_text', 'Label',
        -text => $repo_text,
        -width => -1,
    );
}

sub handle_menu_selection {
    my ($self, $cui, $selection) = @_;
    return unless defined $selection;
    
    $self->cleanup_windows($cui, 'workflow_list', 'runs_list', 'runs_selector', 'logs_viewer', 'trigger_dialog');
    
    if ($selection eq 'View Workflows') {
        $self->view_workflows($cui);
    }
    elsif ($selection eq 'View Workflow Runs') {
        $self->view_runs($cui);
    }
    elsif ($selection eq 'View Run Logs') {
        $self->view_logs($cui);
    }
    elsif ($selection eq 'Trigger Workflow') {
        $self->trigger_workflow_dialog($cui);
    }
    elsif ($selection eq 'Exit') {
        exit(0);
    }
    $cui->draw();
}

sub show_workflow_selector {
    my ($self, $cui) = @_;
    return unless $self->{current_repo};
    
    $self->cleanup_windows($cui, 'workflow_selector');
    
    eval {
        my $workflows = $self->list_workflows($self->{current_repo});
        $self->{workflows} = $workflows;
        
        my $dialog = $cui->add(
            'workflow_selector', 'Window',
            -border => 1,
            -title => 'Select Workflow',
            -width => 70,
            -height => 15,
            -centered => 1
        );

        my @values = map { $_->{id} } @$workflows;
        my %labels = map { $_->{id} => sprintf("%s (%s)", $_->{name}, $_->{state}) } @$workflows;

        my $listbox = $dialog->add(
            'list', 'Listbox',
            -values => \@values,
            -labels => \%labels,
            -onselchange => sub {
                $self->{current_workflow} = $_[0]->get();
                $self->cleanup_windows($cui, 'workflow_selector');
                $cui->draw;
            }
        );

        $dialog->focus();
    };
    if ($@) {
        $self->show_error($cui, "Error: $@");
    }
}

sub view_workflows {
    my ($self, $cui) = @_;
    return unless $self->{current_repo};
    
    $self->cleanup_windows($cui, 'workflow_list');
    
    eval {
        my $workflows = $self->list_workflows($self->{current_repo});
        $self->{workflows} = $workflows;

        my $win_height = $cui->height - 4;
        my $win_width = $cui->width - 4;
        
        my $dialog = $cui->add(
            'workflow_list', 'Window',
            -border => 1,
            -title => 'Workflows',
            -width => $win_width,
            -height => $win_height,
            -x => 2,
            -y => 2,
            -ipad => 1
        );

        my @values = map { $_->{id} } @$workflows;
        my %labels = map { $_->{id} => sprintf("%s (%s)", $_->{name}, $_->{state}) } @$workflows;
        
        my $listbox = $dialog->add(
            'workflows_list', 'Listbox',
            -border => 1,
            -values => \@values,
            -labels => \%labels,
            -onselchange => sub {
                $self->{current_workflow} = $_[0]->get();
            }
        );

        $listbox->focus();
        
        $cui->set_binding(
            sub { 
                $self->cleanup_windows($cui, 'workflow_list');
                $cui->draw;
            },
            "\cX", "q", "Q"
        );
    };
    if ($@) {
        $self->show_error($cui, "Error: $@");
    }
}

sub view_runs {
    my ($self, $cui) = @_;
    return unless $self->{current_workflow};
    
    $self->cleanup_windows($cui, 'runs_list');
    
    eval {
        my $runs = $self->get_workflow_runs($self->{current_repo}, $self->{current_workflow});
        $self->{runs} = $runs;

        my $dialog = $cui->add(
            'runs_list', 'Window',
            -border => 1,
            -title => 'Workflow Runs',
            -width => 70,
            -height => 15,
            -centered => 1
        );

        my @values = map { $_->{id} } @$runs;
        my %labels = map {
            $_->{id} => sprintf(
                "#%d - %s (%s) - %s",
                $_->{run_number},
                $_->{status},
                $_->{conclusion} || 'N/A',
                strftime("%Y-%m-%d %H:%M", localtime(DateTime::Format::ISO8601->parse_datetime($_->{created_at})->epoch))
            )
        } @$runs;

        my $listbox = $dialog->add(
            'list', 'Listbox',
            -values => \@values,
            -labels => \%labels
        );

        $dialog->focus();
        
        $cui->set_binding(
            sub { 
                $self->cleanup_windows($cui, 'runs_list');
                $cui->draw;
            }, 
            "\cX"
        );
    };
    if ($@) {
        $self->show_error($cui, "Error: $@");
    }
}

sub view_logs {
    my ($self, $cui) = @_;
    return unless $self->{current_workflow};
    
    $self->cleanup_windows($cui, 'runs_selector', 'logs_viewer');
    
    eval {
        my $runs = $self->get_workflow_runs($self->{current_repo}, $self->{current_workflow});
        
        my $dialog = $cui->add(
            'runs_selector', 'Window',
            -border => 1,
            -title => 'Select Run',
            -width => 70,
            -height => 15,
            -centered => 1
        );

        my @values = map { $_->{id} } @$runs;
        my %labels = map {
            $_->{id} => sprintf(
                "#%d - %s (%s) - %s",
                $_->{run_number},
                $_->{status},
                $_->{conclusion} || 'N/A',
                strftime("%Y-%m-%d %H:%M", localtime(DateTime::Format::ISO8601->parse_datetime($_->{created_at})->epoch))
            )
        } @$runs;

        my $listbox = $dialog->add(
            'list', 'Listbox',
            -values => \@values,
            -labels => \%labels,
            -onselchange => sub {
                my $run_id = $_[0]->get();
                $self->cleanup_windows($cui, 'runs_selector');
                $self->show_run_logs($cui, $run_id);
            }
        );

        $dialog->focus();
        
        $cui->set_binding(
            sub { 
                $self->cleanup_windows($cui, 'runs_selector');
                $cui->draw;
            }, 
            "\cX"
        );
    };
    if ($@) {
        $self->show_error($cui, "Error: $@");
    }
}

sub show_run_logs {
    my ($self, $cui, $run_id) = @_;
    return unless defined $run_id;
    
    $self->cleanup_windows($cui, 'logs_window');

    eval {
        my $logs = $self->get_run_logs($self->{current_repo}, $run_id);
        
        my $window = $cui->add(
            'logs_window', 'Window',
            -border => 1,
            -title => 'Run Logs',
            -width => 80,
            -height => 20,
            -centered => 1,
            -padtop => 1,
            -padbottom => 1,
            -padleft => 1,
            -padright => 1
        );

        my $viewer = $window->add(
            'logs_viewer', 'TextViewer',
            -text => $logs,
            -wrapping => 1,
            -vscrollbar => 1
        );

        $window->focus();
        
        $cui->set_binding(
            sub { 
                $self->cleanup_windows($cui, 'logs_window');
                $cui->draw;
            }, 
            "\cX", "q", "Q"
        );
    };
    if ($@) {
        $self->show_error($cui, "Error displaying logs: $@");
    }
}

sub trigger_workflow_dialog {
    my ($self, $cui) = @_;
    return unless $self->{current_workflow};
    
    $self->cleanup_windows($cui, 'trigger_dialog');

    my $values = {
        ref => 'main',
        version => 'patch'
    };

    my $dialog = $cui->add(
        'trigger_dialog', 'Window',
        -border => 1,
        -title => 'Trigger Workflow',
        -width => 50,
        -height => 10,
        -centered => 1
    );

    my $ref_label = $dialog->add(
        'ref_label', 'Label',
        -text => 'Git Reference:',
        -y => 1,
        -x => 2
    );

    my $ref_entry = $dialog->add(
        'ref', 'TextEntry',
        -y => 1,
        -x => 15,
        -width => 20,
        -text => $values->{ref}
    );

    my $version_label = $dialog->add(
        'version_label', 'Label',
        -text => 'Version Bump:',
        -y => 3,
        -x => 2
    );

    my $version_select = $dialog->add(
        'version', 'Listbox',
        -y => 3,
        -x => 15,
        -width => 20,
        -height => 3,
        -values => ['patch', 'minor', 'major'],
        -selected => 0
    );

    my $buttons = $dialog->add(
        'buttons', 'Buttonbox',
        -y => 7,
        -buttons => [
            { 
                -label => '< Trigger >',
                -onpress => sub {
                    eval {
                        $self->trigger_workflow(
                            $self->{current_repo},
                            $self->{current_workflow},
                            $ref_entry->get(),
                            { version_bump => $version_select->get() }
                        );
                        $self->show_message($cui, "Workflow triggered successfully");
                    };
                    if ($@) {
                        $self->show_error($cui, "Error triggering workflow: $@");
                    }
                    $self->cleanup_windows($cui, 'trigger_dialog');
                    $cui->draw;
                },
            },
            {
                -label => '< Cancel >',
                -onpress => sub {
                    $self->cleanup_windows($cui, 'trigger_dialog');
                    $cui->draw;
                },
            },
        ],
    );

    $dialog->focus();
}

sub show_error {
    my ($self, $cui, $message) = @_;
    
    my $dialog = $cui->dialog(
        -message => $message,
        -title => 'Error',
        -buttons => ['ok'],
    );
}

sub show_message {
    my ($self, $cui, $message) = @_;
    
    my $dialog = $cui->dialog(
        -message => $message,
        -title => 'Success',
        -buttons => ['ok'],
    );
}

sub execute {
    my ($self, @args) = @_;

    unless ($ENV{TERM} && $ENV{TERM} ne 'dumb') {
        print "Error: Terminal does not support full-screen interface.\n";
        return 1;
    }

    my $cui = $self->create_tui();
    $cui->mainloop();

    return 0;
}

1;