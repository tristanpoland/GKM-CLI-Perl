package GKM::CLI::Commands::Template;
use strict;
use warnings;
use Git::Repository;
use JSON::PP;
use File::Path qw(make_path);
use File::Spec;
use File::Copy;
use File::Find;
use Try::Tiny;

# Templates metadata file location
use constant TEMPLATE_METADATA_FILE => '.gkm-templates.json';

sub new {
    my ($class, %args) = @_;
    return bless { 
        ui => $args{ui},
        config => $args{config} || {},
        git_client => $args{git_client},
    }, $class;
}

sub execute {
    my ($self, @args) = @_;
    
    # No arguments provided, show help
    unless (@args) {
        return $self->show_help();
    }
    
    my $cmd = shift @args;
    
    if ($cmd eq 'list') {
        return $self->list_templates(@args);
    }
    elsif ($cmd eq 'add') {
        return $self->add_template(@args);
    }
    elsif ($cmd eq 'update') {
        return $self->update_template(@args);
    }
    elsif ($cmd eq 'info') {
        return $self->template_info(@args);
    }
    elsif ($cmd eq 'remove') {
        return $self->remove_template(@args);
    }
    elsif ($cmd eq 'apply') {
        return $self->apply_template(@args);
    }
    else {
        $self->{ui}->error("Unknown template command: $cmd");
        return $self->show_help();
    }
}

sub show_help {
    my ($self) = @_;
    $self->{ui}->output(<<'HELP');
Template management commands:

  template list                   - List all registered templates
  template add URL [NAME] [TAG]   - Add a template from a Git repository
  template update [NAME]          - Update template(s) to latest version
  template info NAME              - Show detailed information about a template
  template remove NAME            - Remove a template
  template apply NAME [--force]   - Apply a template to the current repository

Templates allow you to maintain consistency across multiple repositories
and easily update common files and structures.
HELP
    return 0;
}

sub list_templates {
    my ($self, @args) = @_;
    
    my $templates = $self->_load_templates();
    
    if (!$templates || !%$templates) {
        $self->{ui}->output("No templates registered. Use 'template add' to register a template.");
        return 0;
    }
    
    $self->{ui}->output("Registered templates:");
    foreach my $name (sort keys %$templates) {
        my $template = $templates->{$name};
        $self->{ui}->output(sprintf("  %-20s %s (%s)", 
            $name, 
            $template->{url},
            $template->{current_version} || 'unknown'
        ));
    }
    
    return 0;
}

sub add_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        $self->{ui}->error("Missing template URL");
        return 1;
    }
    
    my $url = shift @args;
    my $name = shift @args || $self->_extract_repo_name($url);
    my $tag = shift @args || 'main';
    
    if (!$name) {
        $self->{ui}->error("Could not determine template name from URL, please specify a name");
        return 1;
    }
    
    my $templates = $self->_load_templates();
    
    if ($templates->{$name}) {
        $self->{ui}->error("Template '$name' already exists. Remove it first or use a different name.");
        return 1;
    }
    
    # Clone the repository temporarily to verify it exists
    my $tmp_dir = File::Temp->newdir();
    my $result = try {
        $self->{ui}->info("Cloning template repository...");
        my $repo = Git::Repository->clone($url, $tmp_dir, { quiet => 1 });
        
        # Check if the tag/branch exists
        my $git_cmd = $repo->command('rev-parse', '--verify', $tag);
        my $sha = <$git_cmd>;
        $git_cmd->close;
        chomp $sha if $sha;
        
        # Store the template metadata
        $templates->{$name} = {
            url => $url,
            added_at => time(),
            base_version => $tag,
            current_version => $sha || $tag,
        };
        
        $self->_save_templates($templates);
        $self->{ui}->success("Template '$name' added successfully.");
        return 0;
    } catch {
        $self->{ui}->error("Failed to add template: $_");
        return 1;
    };
    
    return $result;
}

sub update_template {
    my ($self, @args) = @_;
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!%$templates) {
        $self->{ui}->output("No templates registered. Use 'template add' to register a template.");
        return 0;
    }
    
    my @to_update = $name ? ($name) : keys %$templates;
    
    foreach my $template_name (@to_update) {
        if (!$templates->{$template_name}) {
            $self->{ui}->error("Template '$template_name' does not exist.");
            next;
        }
        
        my $template = $templates->{$template_name};
        $self->{ui}->info("Updating template '$template_name'...");
        
        my $tmp_dir = File::Temp->newdir();
        try {
            # Clone the repository
            my $repo = Git::Repository->clone($template->{url}, $tmp_dir, { quiet => 1 });
            
            # Get the latest commit SHA for the branch/tag
            my $git_cmd = $repo->command('rev-parse', '--verify', $template->{base_version});
            my $sha = <$git_cmd>;
            $git_cmd->close;
            chomp $sha if $sha;
            
            if ($sha && $sha ne $template->{current_version}) {
                $templates->{$template_name}->{current_version} = $sha;
                $templates->{$template_name}->{updated_at} = time();
                $self->{ui}->success("Template '$template_name' updated to version $sha");
            } else {
                $self->{ui}->info("Template '$template_name' is already at the latest version.");
            }
        } catch {
            $self->{ui}->error("Failed to update template '$template_name': $_");
        };
    }
    
    $self->_save_templates($templates);
    return 0;
}

sub template_info {
    my ($self, @args) = @_;
    
    if (!@args) {
        $self->{ui}->error("Missing template name");
        return 1;
    }
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        $self->{ui}->error("Template '$name' does not exist.");
        return 1;
    }
    
    my $template = $templates->{$name};
    $self->{ui}->output("Template: $name");
    $self->{ui}->output("URL: $template->{url}");
    $self->{ui}->output("Base version: $template->{base_version}");
    $self->{ui}->output("Current version: $template->{current_version}");
    $self->{ui}->output("Added: " . scalar(localtime($template->{added_at})));
    
    if ($template->{updated_at}) {
        $self->{ui}->output("Last updated: " . scalar(localtime($template->{updated_at})));
    }
    
    if ($template->{last_applied}) {
        $self->{ui}->output("Last applied: " . scalar(localtime($template->{last_applied})));
        $self->{ui}->output("Applied version: $template->{applied_version}");
    }
    
    return 0;
}

sub remove_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        $self->{ui}->error("Missing template name");
        return 1;
    }
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        $self->{ui}->error("Template '$name' does not exist.");
        return 1;
    }
    
    delete $templates->{$name};
    $self->_save_templates($templates);
    $self->{ui}->success("Template '$name' removed.");
    
    return 0;
}

sub apply_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        $self->{ui}->error("Missing template name");
        return 1;
    }
    
    my $name = shift @args;
    my $force = grep { $_ eq '--force' } @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        $self->{ui}->error("Template '$name' does not exist.");
        return 1;
    }
    
    my $template = $templates->{$name};
    
    # Check if we're in a git repository
    my $current_repo;
    try {
        $current_repo = Git::Repository->new();
    } catch {
        $self->{ui}->error("Current directory is not a git repository.");
        return 1;
    };
    
    # Make sure working directory is clean unless forced
    unless ($force) {
        my $git_cmd = $current_repo->command('status', '--porcelain');
        my @status = <$git_cmd>;
        $git_cmd->close;
        
        if (@status) {
            $self->{ui}->error("Working directory is not clean. Commit or stash your changes, or use --force.");
            return 1;
        }
    }
    
    # Clone the template repository to a temporary directory
    my $tmp_dir = File::Temp->newdir();
    try {
        $self->{ui}->info("Cloning template repository...");
        my $repo = Git::Repository->clone($template->{url}, $tmp_dir, { quiet => 1 });
        
        # Checkout the right version
        my $git_cmd = $repo->command('checkout', $template->{current_version}, { quiet => 1 });
        $git_cmd->close;
        
        # Apply the template files
        $self->_apply_template_files($tmp_dir, $current_repo->work_tree);
        
        # Update template metadata
        $templates->{$name}->{last_applied} = time();
        $templates->{$name}->{applied_version} = $template->{current_version};
        $self->_save_templates($templates);
        
        $self->{ui}->success("Template '$name' applied successfully.");
    } catch {
        $self->{ui}->error("Failed to apply template: $_");
        return 1;
    };
    
    return 0;
}

# Helper methods

sub _load_templates {
    my ($self) = @_;
    
    my $config_dir = $self->{config}->{config_dir} || "$ENV{HOME}/.gkm";
    my $templates_file = File::Spec->catfile($config_dir, TEMPLATE_METADATA_FILE);
    
    if (-f $templates_file) {
        try {
            open my $fh, '<', $templates_file or die "Cannot open $templates_file: $!";
            local $/;
            my $json = <$fh>;
            close $fh;
            
            return decode_json($json);
        } catch {
            $self->{ui}->error("Failed to load templates: $_");
            return {};
        };
    }
    
    return {};
}

sub _save_templates {
    my ($self, $templates) = @_;
    
    my $config_dir = $self->{config}->{config_dir} || "$ENV{HOME}/.gkm";
    make_path($config_dir) unless -d $config_dir;
    
    my $templates_file = File::Spec->catfile($config_dir, TEMPLATE_METADATA_FILE);
    
    try {
        open my $fh, '>', $templates_file or die "Cannot open $templates_file: $!";
        print $fh encode_json($templates);
        close $fh;
    } catch {
        $self->{ui}->error("Failed to save templates: $_");
    };
}

sub _extract_repo_name {
    my ($self, $url) = @_;
    
    if ($url =~ m{/([^/]+?)(?:\.git)?$}) {
        return $1;
    }
    
    return undef;
}

sub _apply_template_files {
    my ($self, $template_dir, $target_dir) = @_;
    
    # Check for template manifest which can control which files to apply
    my $manifest_file = File::Spec->catfile($template_dir, '.template-manifest.json');
    my $manifest = {};
    
    if (-f $manifest_file) {
        try {
            open my $fh, '<', $manifest_file or die "Cannot open $manifest_file: $!";
            local $/;
            my $json = <$fh>;
            close $fh;
            
            $manifest = decode_json($json);
        } catch {
            $self->{ui}->warn("Failed to load template manifest: $_");
        };
    }
    
    # Determine which files to copy
    my @files_to_copy;
    my @dirs_to_exclude = qw(.git .github/workflows); # Default excludes
    
    if ($manifest->{files}) {
        # Use explicit file list from manifest
        @files_to_copy = @{$manifest->{files}};
    } else {
        # Copy all files except those in exclude list
        if ($manifest->{exclude}) {
            push @dirs_to_exclude, @{$manifest->{exclude}};
        }
        
        find(
            {
                wanted => sub {
                    my $rel_path = File::Spec->abs2rel($_, $template_dir);
                    return if $rel_path eq '.';
                    
                    # Skip excluded directories
                    foreach my $exclude (@dirs_to_exclude) {
                        return if $rel_path =~ /^$exclude(?:\/|$)/;
                    }
                    
                    # Skip the manifest itself
                    return if $rel_path eq '.template-manifest.json';
                    
                    push @files_to_copy, $rel_path;
                },
                no_chdir => 1,
            },
            $template_dir
        );
    }
    
    # Copy the files
    foreach my $file (@files_to_copy) {
        my $src = File::Spec->catfile($template_dir, $file);
        my $dst = File::Spec->catfile($target_dir, $file);
        
        if (-d $src) {
            make_path($dst) unless -d $dst;
            next;
        }
        
        # Create parent directory if needed
        my ($volume, $directories, $filename) = File::Spec->splitpath($dst);
        make_path(File::Spec->catpath($volume, $directories, '')) unless -d File::Spec->catpath($volume, $directories, '');
        
        $self->{ui}->info("Applying template file: $file");
        
        if ($manifest->{merge} && grep { $file eq $_ } @{$manifest->{merge}}) {
            # TODO: Implement smart merging for specific files
            # This would be useful for things like .gitignore, etc.
            # For now, just overwrite
            copy($src, $dst) or $self->{ui}->warn("Failed to copy $file: $!");
        } else {
            copy($src, $dst) or $self->{ui}->warn("Failed to copy $file: $!");
        }
    }
}

1;