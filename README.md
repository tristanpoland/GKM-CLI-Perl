# GKM CLI (Genesis Kit Manager)

A command-line interface tool for managing Genesis Kits, including pipeline management, template versioning, and CI configuration.

## Requirements

- Perl 5.6.0 or later
- Required external tools:
  - `spruce` - For pipeline configuration management
  - `fly` - Concourse CI CLI tool
  - `jq` - JSON processor

## Installation

### Windows

1. Install Strawberry Perl from https://strawberryperl.com/

2. Install dependencies:
```powershell
cpanm Term::ANSIColor Term::ReadKey Term::ReadLine Term::UI YAML::XS IPC::Run3 JSON File::Path
```

3. Clone and build:
```powershell
git clone https://github.com/yourusername/GKM-CLI.git
cd GKM-CLI
perl Makefile.PL
dmake
dmake test
dmake install
```

### Linux/Unix/macOS

1. Install Perl (if not already installed):

Ubuntu/Debian:
```bash
sudo apt-get install perl perl-base perl-modules
```

macOS (using Homebrew):
```bash
brew install perl
```

2. Install dependencies:
```bash
sudo cpanm Term::ANSIColor Term::ReadKey Term::ReadLine Term::UI YAML::XS IPC::Run3 JSON File::Path
```

3. Clone and build:
```bash
git clone https://github.com/tristanpoland/GKM-CLI-Perl.git
cd GKM-CLI
perl Makefile.PL
make
make test
sudo make install
```

### Development Installation (Any Platform)

To run without installing system-wide:

```bash
git clone https://github.com/yourusername/GKM-CLI.git
cd GKM-CLI
cpanm --installdeps .
perl -Ilib bin/gkm-cli.pl
```

## Usage

The GKM CLI provides three main commands:

### Pipeline Management

Update or manage Concourse pipelines:
```bash
gkm-cli.pl repipe
```

### Template Version Management

View and update kit template versions:
```bash
gkm-cli.pl template
```

### CI Configuration

Manage CI configuration, view status, trigger builds:
```bash
gkm-cli.pl ci
```

This provides an interactive menu with options to:
- View CI Status
- Update Configuration
- Trigger Build
- View Logs

## Troubleshooting

### Windows Line Endings

If you encounter this error on Unix-like systems:
```
/usr/bin/env: 'perl\r': No such file or directory
```

Fix it by running:
```bash
sed -i 's/\r$//' bin/gkm-cli.pl
```

### Permission Issues

If you get permission errors running the script:
```bash
chmod +x bin/gkm-cli.pl
```

### Common Issues

1. **Missing Dependencies**
   ```
   Can't locate Term/ANSIColor.pm in @INC
   ```
   Solution: Run `cpanm --installdeps .`

2. **Fly CLI Not Found**
   ```
   Failed to check fly CLI
   ```
   Solution: Install the Concourse fly CLI and ensure it's in your PATH

## Development

### Running Tests

```bash
make test
```

### Adding New Commands

New commands can be added by:
1. Creating a new module in `lib/GKM/CLI/Commands/`
2. Adding the command to the run method in `lib/GKM/CLI.pm`

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

If you encounter any issues, please file them in the GitHub issue tracker.
