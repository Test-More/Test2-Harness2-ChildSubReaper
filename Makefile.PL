use strict;
use warnings;

use 5.014000;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    NAME             => 'Test2::Harness2::ChildSubReaper',
    DISTNAME         => 'Test2-Harness2-ChildSubReaper',
    AUTHOR           => 'Chad Granum <exodist@cpan.org>',
    ABSTRACT         => "Tiny XS wrapper around Linux's PR_SET_CHILD_SUBREAPER prctl.",
    VERSION_FROM     => 'lib/Test2/Harness2/ChildSubReaper.pm',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.014000',

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },

    TEST_REQUIRES => {
        'Test2::V0' => '0.000163',
        'POSIX'     => 0,
    },

    PREREQ_PM => {
        'XSLoader' => 0,
        'Exporter' => 0,
        'strict'   => 0,
        'warnings' => 0,
    },

    META_MERGE => {
        'meta-spec' => {version => 2},
        resources   => {
            bugtracker => {web => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper/issues'},
            repository => {
                type => 'git',
                url  => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper.git',
                web  => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper',
            },
        },
    },

    OBJECT => 'ChildSubReaper$(OBJ_EXT)',

    test => {TESTS => 't/*.t'},
);

# Older EUMM does not understand TEST_REQUIRES / CONFIGURE_REQUIRES.
unless (eval { ExtUtils::MakeMaker->VERSION('6.63_03') }) {
    my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
    $WriteMakefileArgs{PREREQ_PM} = {%{$WriteMakefileArgs{PREREQ_PM}}, %$tr};
}
delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
