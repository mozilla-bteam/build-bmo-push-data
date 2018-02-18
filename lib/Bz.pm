package Bz;
use strict;
use warnings;
use autodie;

use Bz::Util;
use Carp;
use Cwd 'abs_path';
use Data::Dumper;
use File::Spec;

my %_OLD_SIG;
sub init {
    @_OLD_SIG{qw(__DIE__ __WARN__)} = @SIG{qw(__DIE__ __WARN__)};
    $SIG{__DIE__} = sub {
        my $message = "@_";
        for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
            return if $sub =~ /^\(eval\)/;
        }
        # urgh
        $message =~ s/^(?:isa check|coercion) for "[^"]+" failed: //;
        $message =~ s/\n+$//;
        if ($ENV{DEBUG}) {
            die Bz::Util::die_coloured($message) . "\n" . _stack();
        } else {
            die Bz::Util::die_coloured($message) . "\n";
        }
    };
    $SIG{__WARN__} = sub {
        print Bz::Util::warn_coloured(@_);
    };

    $Data::Dumper::Sortkeys = 1;
    binmode(STDOUT, ':utf8');
    binmode(STDERR, ':utf8');
}

BEGIN {
    init();
}

END {
    @SIG{qw(__DIE__ __WARN__)} = @_OLD_SIG{qw(__DIE__ __WARN__)};
}

sub _stack {
    my @stack = split(/\n/, Carp::longmess());
    foreach my $line (@stack) {
        $line =~ s/^\s+/  /;
    }
    return join("\n", @stack) . "\n";
}

sub import {
    # enable strict, warnings, and autodie
    strict->import();
    warnings->import(FATAL => 'all');
    autodie->import();

    # re-export Bz::Util exports, and Data::Dumper
    my $dest_pkg = caller();
    eval "package $dest_pkg; Bz::Util->import(); Data::Dumper->import()";
}

my $_config;
sub config {
    require Bz::Config;
    return $_config ||= Bz::Config->new();
}

my $_bugzilla;
sub bugzilla {
    require Bz::Bugzilla;
    return $_bugzilla ||= Bz::Bugzilla->new();
}

my $_mysql;
sub mysql {
    require Bz::MySql;
    return $_mysql ||= Bz::MySql->new();
}

my $_boiler_plate;
sub boiler_plate {
    require Bz::BoilerPlate;
    return $_boiler_plate ||= Bz::BoilerPlate->new();
}

#

sub current_workdir {
    require Bz::Workdir;
    my $path = _current_path();
    die "invalid working directory\n"
        unless "$path/" =~ m#/htdocs/([^/]+)/#;
    return Bz::Workdir->new({ dir => $1 });
}

sub current_repo {
    require Bz::Repo;
    return Bz::Repo->new({ path => _current_path() });
}

sub current {
    my ($class) = @_;
    my $current = eval { $class->current_workdir() };
    return $current if $current;
    $current = eval { $class->current_repo() };
    return $current if $current;
    die "invalid working directory\n";
}

sub _current_path {
    my $path = abs_path('.')
        or die "failed to find current working directory\n";
    while (!-d "$path/.git") {
        my @dirs = File::Spec->splitdir($path);
        pop @dirs;
        $path = File::Spec->catdir(@dirs);
        die "invalid working directory\n" if $path eq '/';
    }
    return $path;
}

my $_workdirs;
sub workdirs {
    require Bz::Workdir;
    chdir(Bz->config->htdocs_path);
    if (!$_workdirs) {
        my @dirs =
            map { Bz::Workdir->new({ dir => $_ }) }
            grep { !-l $_ && -d $_ }
            glob('*');
        my (@bug_dirs, @non_bug_dirs);
        foreach my $workdir (@dirs) {
            if ($workdir->bug_id) {
                push @bug_dirs, $workdir;
            } else {
                push @non_bug_dirs, $workdir;
            }
        }
        $_workdirs = [
            (sort { $a->dir cmp $b->dir } @non_bug_dirs),
            (sort { $a->bug_id <=> $b->bug_id } @bug_dirs),
        ];
    }
    return $_workdirs;
}

sub preload_bugs {
    my ($class, $workdirs) = @_;
    my @bug_ids = map { $_->bug_id } grep { $_->bug_id } @$workdirs;
    Bz->bugzilla->bugs(\@bug_ids);
}

#

sub workdir {
    my ($class, $dir) = @_;
    require Bz::Workdir;
    return Bz::Workdir->new({ dir => $dir });
}

sub bug {
    my ($class, $bug_id) = @_;
    require Bz::Bug;
    return Bz::Bug->new({ id => $bug_id });
}

1;
