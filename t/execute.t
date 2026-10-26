use strict;
use warnings;

use File::Spec;
use File::Temp qw( tempdir );
use Test::More;

plan skip_all => 'requires a Unix-like shebang environment'
    if $^O eq 'MSWin32';

my $lib_dir = tempdir( CLEANUP => 1 );
my $bin_dir = File::Spec->catdir( $lib_dir, 'bin' );
my $perl_lib = File::Spec->catdir( $lib_dir, 'lib', 'perl5' );

mkdir $bin_dir or die "mkdir $bin_dir: $!";
mkdir File::Spec->catdir( $lib_dir, 'lib' ) or die "mkdir lib: $!";
mkdir $perl_lib or die "mkdir $perl_lib: $!";

my $bash_program = File::Spec->catfile( $bin_dir, 'bash-program' );
write_file(
    $bash_program,
    <<'BASH',
#!/usr/bin/env bash
printf 'arg=%s\n' "$1"
printf 'path=%s\n' "$PATH"
printf 'perl5lib=%s\n' "${PERL5LIB:-}"
BASH
);

my $module_dir = File::Spec->catdir( $perl_lib, 'CpxTest' );
mkdir $module_dir or die "mkdir $module_dir: $!";
write_file(
    File::Spec->catfile( $module_dir, 'Module.pm' ),
    <<'PERL',
package CpxTest::Module;
sub value { 'loaded from local lib' }
1;
PERL
);

my $perl_program = File::Spec->catfile( $bin_dir, 'perl-program' );
write_file(
    $perl_program,
    <<'PERL',
#!/usr/bin/env perl
use CpxTest::Module;
print CpxTest::Module::value(), "\n";
PERL
);

my $cpx = File::Spec->catfile( 'bin', 'cpx' );

my $bash_output = run_cpx( $cpx, '-L', $lib_dir, 'bash-program', '-Mnot-a-perl-option' );
is( $bash_output->{status}, 0, 'shell script exits successfully' );
like( $bash_output->{stdout}, qr/^arg=-Mnot-a-perl-option$/m,
    'arguments beginning with -M are passed to the script' );
like( $bash_output->{stdout}, qr/^path=\Q$bin_dir\E:/m,
    'local bin directory is first in PATH' );
like( $bash_output->{stdout}, qr/^perl5lib=[^\n]*\Q$perl_lib\E/m,
    'local Perl library is in PERL5LIB' );

my $perl_output = run_cpx( $cpx, '-L', $lib_dir, 'perl-program' );
is( $perl_output->{status}, 0, 'Perl script exits successfully' );
like( $perl_output->{stdout}, qr/^loaded from local lib$/m,
    'Perl script can load modules from the local lib' );

done_testing;

sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $content;
    close $fh or die "close $path: $!";
    chmod 0755, $path or die "chmod $path: $!";
}

sub run_cpx {
    my (@args) = @_;
    my $pid = open my $fh, '-|';
    die "fork: $!" unless defined $pid;

    if ( !$pid ) {
        open STDERR, '>&', STDOUT or die "dup stdout: $!";
        exec $^X, '-Ilib', @args or die "exec cpx: $!";
    }

    local $/;
    my $stdout = <$fh>;
    close $fh;
    $stdout = '' unless defined $stdout;
    return { stdout => $stdout, status => $? >> 8 };
}
