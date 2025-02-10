#!/bin/bash

# Install dependencies
cpan install JSON LWP::UserAgent Term::ReadKey Curses::UI Git::Repository DateTime::Format::ISO8601

# Create installation directory
sudo mkdir -p /usr/local/lib/gkm-cli
sudo mkdir -p /usr/local/bin

# Copy files
sudo cp -r lib/* /usr/local/lib/gkm-cli/
sudo cp bin/gkm-cli.pl /usr/local/bin/gkm-cli
sudo chmod +x /usr/local/bin/gkm-cli

# Update script shebang
sudo sed -i '1i#!/usr/bin/env perl\nuse lib "/usr/local/lib/gkm-cli";' /usr/local/bin/gkm-cli