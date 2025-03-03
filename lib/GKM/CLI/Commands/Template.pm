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
use File::Temp;

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
        print STDERR "Error: Unknown template command: $cmd\n";
        return $self->show_help();
    }
}

sub show_help {
    my ($self) = @_;
    print <<'HELP';
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
        print "No templates registered. Use 'template add' to register a template.\n";
        return 0;
    }
    
    print "Registered templates:\n";
    foreach my $name (sort keys %$templates) {
        my $template = $templates->{$name};
        printf("  %-20s %s (%s)\n", 
            $name, 
            $template->{url},
            $template->{current_version} || 'unknown'
        );
    }
    
    return 0;
}

sub add_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        print STDERR "Error: Missing template URL\n";
        return 1;
    }
    
    my $url = shift @args;
    my $name = shift @args || $self->_extract_repo_name($url);
    my $tag = shift @args || 'main';
    
    if (!$name) {
        print STDERR "Error: Could not determine template name from URL, please specify a name\n";
        return 1;
    }
    
    my $templates = $self->_load_templates();
    
    if ($templates->{$name}) {
        print STDERR "Error: Template '$name' already exists. Remove it first or use a different name.\n";
        return 1;
    }
    
    # Clone the repository temporarily to verify it exists
    my $tmp_dir = File::Temp->newdir();
    my $result = try {
        print "Cloning template repository...\n";
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
        print "Template '$name' added successfully.\n";
        return 0;
    } catch {
        print STDERR "Error: Failed to add template: $_\n";
        return 1;
    };
    
    return $result;
}

sub update_template {
    my ($self, @args) = @_;
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!%$templates) {
        print "No templates registered. Use 'template add' to register a template.\n";
        return 0;
    }
    
    my @to_update = $name ? ($name) : keys %$templates;
    
    foreach my $template_name (@to_update) {
        if (!$templates->{$template_name}) {
            print STDERR "Error: Template '$template_name' does not exist.\n";
            next;
        }
        
        my $template = $templates->{$template_name};
        print "Updating template '$template_name'...\n";
        
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
                print "Template '$template_name' updated to version $sha\n";
            } else {
                print "Template '$template_name' is already at the latest version.\n";
            }
        } catch {
            print STDERR "Error: Failed to update template '$template_name': $_\n";
        };
    }
    
    $self->_save_templates($templates);
    return 0;
}

sub template_info {
    my ($self, @args) = @_;
    
    if (!@args) {
        print STDERR "Error: Missing template name\n";
        return 1;
    }
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        print STDERR "Error: Template '$name' does not exist.\n";
        return 1;
    }
    
    my $template = $templates->{$name};
    print "Template: $name\n";
    print "URL: $template->{url}\n";
    print "Base version: $template->{base_version}\n";
    print "Current version: $template->{current_version}\n";
    print "Added: " . scalar(localtime($template->{added_at})) . "\n";
    
    if ($template->{updated_at}) {
        print "Last updated: " . scalar(localtime($template->{updated_at})) . "\n";
    }
    
    if ($template->{last_applied}) {
        print "Last applied: " . scalar(localtime($template->{last_applied})) . "\n";
        print "Applied version: $template->{applied_version}\n";
    }
    
    return 0;
}

sub remove_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        print STDERR "Error: Missing template name\n";
        return 1;
    }
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        print STDERR "Error: Template '$name' does not exist.\n";
        return 1;
    }
    
    delete $templates->{$name};
    $self->_save_templates($templates);
    print "Template '$name' removed.\n";
    
    return 0;
}

sub apply_template {
    my ($self, @args) = @_;
    
    if (!@args) {
        print STDERR "Error: Missing template name\n";
        return 1;
    }
    
    my $name = shift @args;
    my $force = grep { $_ eq '--force' } @args;
    my $templates = $self->_load_templates();
    
    if (!$templates->{$name}) {
        print STDERR "Error: Template '$name' does not exist.\n";
        return 1;
    }
    
    my $template = $templates->{$name};
    
    # Check if we're in a git repository
    my $current_repo;
    try {
        $current_repo = Git::Repository->new();
    } catch {
        print STDERR "Error: Current directory is not a git repository.\n";
        return 1;
    };
    
    # Make sure working directory is clean unless forced
    unless ($force) {
        my $git_cmd = $current_repo->command('status', '--porcelain');
        my @status = <$git_cmd>;
        $git_cmd->close;
        
        if (@status) {
            print STDERR "Error: Working directory is not clean. Commit or stash your changes, or use --force.\n";
            return 1;
        }
    }
    
    # Clone the template repository to a temporary directory
    my $tmp_dir = File::Temp->newdir();
    try {
        print "Cloning template repository...\n";
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
        
        print "Template '$name' applied successfully.\n";
    } catch {
        print STDERR "Error: Failed to apply template: $_\n";
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
            print STDERR "Error: Failed to load templates: $_\n";
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
        print STDERR "Error: Failed to save templates: $_\n";
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
            print STDERR "Warning: Failed to load template manifest: $_\n";
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
        
        print "Applying template file: $file\n";
        
        if ($manifest->{merge} && grep { $file eq $_ } @{$manifest->{merge}}) {
            # TODO: Implement smart merging for specific files
            # This would be useful for things like .gitignore, etc.
            # For now, just overwrite
            copy($src, $dst) or print STDERR "Warning: Failed to copy $file: $!\n";
        } else {
            copy($src, $dst) or print STDERR "Warning: Failed to copy $file: $!\n";
        }
    }
}

1;