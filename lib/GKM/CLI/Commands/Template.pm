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

# Store templates metadata in a standard location
# Should be gitignored if inside repo
use constant TEMPLATE_METADATA_DIR => '.github/kit-meta/';
use constant TEMPLATE_METADATA_FILE => '.gkm-templates.json';

# Constructor - needs UI for messages and config for paths
sub new {
    my ($class, %args) = @_;
    return bless { 
        ui => $args{ui},
        config => $args{config} || {},
        git_client => $args{git_client},
    }, $class;
}

# Main entry point - parses commands and routes to appropriate handlers
sub execute {
    my ($self, @args) = @_;
    
    # No args? Just show help
    unless (@args) {
        return $self->show_help();
    }
    
    my $cmd = shift @args;
    
    # Route to appropriate subcommand
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

# Print help text
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

# List all registered templates
sub list_templates {
    my ($self, @args) = @_;
    
    my $templates = $self->_load_templates();
    
    # Nothing to show
    if (!$templates || !%$templates) {
        print "No templates registered. Use 'template add' to register a template.\n";
        return 0;
    }
    
    # Display template list with versions
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

# Add a new template from git repo
sub add_template {
    my ($self, @args) = @_;
    
    # Need at least a URL
    if (!@args) {
        print STDERR "Error: Missing template URL\n";
        return 1;
    }
    
    my $url = shift @args;
    # Auto-name from repo if not specified, fallback to 'main' branch
    my $name = shift @args || $self->_extract_repo_name($url);
    my $tag = shift @args || 'main';
    
    # Bail if we can't figure out a name
    if (!$name) {
        print STDERR "Error: Could not determine template name from URL, please specify a name\n";
        return 1;
    }
    
    my $templates = $self->_load_templates();
    
    # Don't allow duplicates
    if ($templates->{$name}) {
        print STDERR "Error: Template '$name' already exists. Remove it first or use a different name.\n";
        return 1;
    }
    
    # Clone to temp dir to validate repo & get commit SHA 
    my $tmp_dir = File::Temp->newdir();
    my $result = try {
        print "Cloning template repository...\n";
        my $repo = Git::Repository->clone($url, $tmp_dir, { quiet => 1 });
        
        # Get SHA for the tag/branch - allows tracking specific commit
        my $git_cmd = $repo->command('rev-parse', '--verify', $tag);
        my $sha = <$git_cmd>;
        $git_cmd->close;
        chomp $sha if $sha;
        
        # Store template data
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

# Update template(s) to latest version from origin
sub update_template {
    my ($self, @args) = @_;
    
    my $name = shift @args;
    my $templates = $self->_load_templates();
    
    # Nothing to update
    if (!%$templates) {
        print "No templates registered. Use 'template add' to register a template.\n";
        return 0;
    }
    
    # If name is provided, update just that one, otherwise update all
    my @to_update = $name ? ($name) : keys %$templates;
    
    foreach my $template_name (@to_update) {
        if (!$templates->{$template_name}) {
            print STDERR "Error: Template '$template_name' does not exist.\n";
            next;
        }
        
        my $template = $templates->{$template_name};
        print "Updating template '$template_name'...\n";
        
        # Use temp dir for the clone
        my $tmp_dir = File::Temp->newdir();
        try {
            # Fetch latest from origin
            my $repo = Git::Repository->clone($template->{url}, $tmp_dir, { quiet => 1 });
            
            # Get SHA of latest commit on the template's base branch
            my $git_cmd = $repo->command('rev-parse', '--verify', $template->{base_version});
            my $sha = <$git_cmd>;
            $git_cmd->close;
            chomp $sha if $sha;
            
            # Only update if SHA changed
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

# Display detailed info about a template
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
    
    # Show all the metadata we have about this template
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

# Remove a template from registry
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
    
    # Just delete it from the registry - doesn't touch any applied files
    delete $templates->{$name};
    $self->_save_templates($templates);
    print "Template '$name' removed.\n";
    
    return 0;
}

# Apply files from the template to target directory
sub _apply_template_files {
    my ($self, $template_dir, $target_dir) = @_;

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

    # Default excluded directories
    my @dirs_to_exclude = qw(.git .github/workflows);
    push @dirs_to_exclude, @{$manifest->{exclude} || []};

    # File list from manifest or find all files
    my @files_to_copy;
    if ($manifest->{files}) {
        @files_to_copy = @{$manifest->{files}};
    } else {
        find(
            {
                wanted => sub {
                    my $rel_path = File::Spec->abs2rel($_, $template_dir);
                    return if $rel_path eq '.';

                    foreach my $exclude (@dirs_to_exclude) {
                        return if $rel_path =~ /^$exclude(?:\/|$)/;
                    }

                    push @files_to_copy, $rel_path if -f $_;
                },
                no_chdir => 1,
            },
            $template_dir
        );
    }

    # Copy files to target
    foreach my $file (@files_to_copy) {
        my $src = File::Spec->catfile($template_dir, $file);
        my $dst = File::Spec->catfile($target_dir, $file);

        if (-d $src) {
            make_path($dst) unless -d $dst;
            next;
        }

        my ($volume, $directories, $filename) = File::Spec->splitpath($dst);
        make_path(File::Spec->catpath($volume, $directories, '')) unless -d File::Spec->catpath($volume, $directories, '');

        print "Applying template file: $file\n";
        copy($src, $dst) or print STDERR "Warning: Failed to copy $file: $!\n";
    }
}


# ----- Private helper methods -----

# Load template registry from JSON file
sub _load_templates {
    my ($self) = @_;
    
    my $metadata_dir = File::Spec->catdir($self->_repo_root(), TEMPLATE_METADATA_DIR);
    my $templates_file = File::Spec->catfile($metadata_dir, TEMPLATE_METADATA_FILE);

    # Check if file exists
    return {} unless -f $templates_file;

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

# Save template registry to JSON file
sub _save_templates {
    my ($self, $templates) = @_;

    my $metadata_dir = File::Spec->catdir($self->_repo_root(), TEMPLATE_METADATA_DIR);
    my $templates_file = File::Spec->catfile($metadata_dir, TEMPLATE_METADATA_FILE);

    # Create directory if missing
    make_path($metadata_dir) unless -d $metadata_dir;

    try {
        open my $fh, '>', $templates_file or die "Cannot open $templates_file: $!";
        print $fh encode_json($templates);
        close $fh;
    } catch {
        print STDERR "Error: Failed to save templates: $_\n";
    };
}

# Extract repo name from git URL
# e.g. https://github.com/user/repo.git -> repo
sub _extract_repo_name {
    my ($self, $url) = @_;
    
    if ($url =~ m{/([^/]+?)(?:\.git)?$}) {
        return $1;
    }
    
    return undef;
}

# Get the root of the git repo
sub _repo_root {
    my ($self) = @_;

    try {
        my $repo = Git::Repository->new();
        my $git_cmd = $repo->command('rev-parse', '--show-toplevel');
        my $root = <$git_cmd>;
        $git_cmd->close;
        chomp $root;
        return $root if -d $root;
    } catch {
        die "Error: Cannot determine repository root.\n";
    };

    die "Error: Not inside a valid git repository.\n";
}


# Copy files from template to target dir
# Handles manifest-based filtering if present
sub _apply_template_files {
    my ($self, $template_dir, $target_dir) = @_;
    
    # Check if template has a manifest for controlling what gets copied
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
    
    # Determine file set to copy based on manifest or defaults
    my @files_to_copy;
    # Defaults - don't copy .git or CI workflow files
    my @dirs_to_exclude = qw(.git .github/workflows); 
    
    if ($manifest->{files}) {
        # Explicit file list from manifest
        @files_to_copy = @{$manifest->{files}};
    } else {
        # Recursive find with exclusions
        if ($manifest->{exclude}) {
            push @dirs_to_exclude, @{$manifest->{exclude}};
        }
        
        find(
            {
                wanted => sub {
                    my $rel_path = File::Spec->abs2rel($_, $template_dir);
                    return if $rel_path eq '.';
                    
                    # Skip excluded paths (dot-dirs, etc)
                    foreach my $exclude (@dirs_to_exclude) {
                        return if $rel_path =~ /^$exclude(?:\/|$)/;
                    }
                    
                    # Don't copy the manifest itself
                    return if $rel_path eq '.template-manifest.json';
                    
                    push @files_to_copy, $rel_path;
                },
                no_chdir => 1,
            },
            $template_dir
        );
    }
    
    # Copy each file, preserving relative paths
    foreach my $file (@files_to_copy) {
        my $src = File::Spec->catfile($template_dir, $file);
        my $dst = File::Spec->catfile($target_dir, $file);
        
        # Just ensure dir exists for directories
        if (-d $src) {
            make_path($dst) unless -d $dst;
            next;
        }
        
        # Make sure target dir exists
        my ($volume, $directories, $filename) = File::Spec->splitpath($dst);
        make_path(File::Spec->catpath($volume, $directories, '')) unless -d File::Spec->catpath($volume, $directories, '');
        
        print "Applying template file: $file\n";
        
        if ($manifest->{merge} && grep { $file eq $_ } @{$manifest->{merge}}) {
            # TODO: Smart merge for files like .gitignore
            # Could append unique lines or use a more complex merge strategy
            # For now just overwrite - implement this when needed
            copy($src, $dst) or print STDERR "Warning: Failed to copy $file: $!\n";
        } else {
            copy($src, $dst) or print STDERR "Warning: Failed to copy $file: $!\n";
        }
    }
}

1;