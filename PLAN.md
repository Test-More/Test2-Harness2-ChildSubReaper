# Test2::Harness2::ChildSubReaper — Build Plan

## What this distribution is

A minimal XS wrapper around Linux's `PR_SET_CHILD_SUBREAPER` prctl(2)
operation. It exists so that `Test2-Harness2` can stop depending on
`Linux::Prctl` (which exposes the entire prctl(2) surface) and depend on
a narrow, targeted module instead.

The only thing this module does is let a process ask the kernel to act
as the subreaper for its descendants. Any descendant that gets orphaned
(its immediate parent dies, typically via double-fork or `setsid` +
parent exit) reparents to the subreaper process instead of `init(1)`.
The harness service uses this so it can `waitpid` grandchildren and
guarantee no test-descendant survives after a hard stop.

## Why a new dist instead of inlining into Test2-Harness2

This functionality is a thin, stable, OS-specific primitive. Keeping it
separate means:

- The XS build is isolated. A Test2-Harness2 user on non-Linux does not
  need a C toolchain to install the harness.
- Callers can install just this one thing without pulling anything else
  from CPAN.
- The API surface is tiny, so the module will effectively never need to
  change after the first release.

It is an **optional** runtime dep of Test2-Harness2. Without it the
harness still works, but orphaned grandchildren may escape cleanup.

## Repository layout

Create files under `/home/exodist/projects/Test2/Test2-Harness2-ChildSubReaper/`:

```
Changes                              -- release notes
Makefile.PL                          -- ExtUtils::MakeMaker
MANIFEST.SKIP                        -- manifest exclusions
README                               -- short top-level README
cpanfile                             -- prereqs mirror of Makefile.PL
dist.ini                             -- Dist::Zilla (only if you use it; MakeMaker alone is fine)
ChildSubReaper.xs                    -- the XS source
lib/Test2/Harness2/ChildSubReaper.pm -- Perl-side loader + docs
t/00-load.t                          -- basic use_ok
t/10-have-support.t                  -- advertises support correctly per platform
t/20-set-success.t                   -- enabling/disabling works (Linux only)
t/30-set-without-support.t           -- behavior on platforms without support
t/40-subreaper-behavior.t            -- integration test via double-fork (Linux only, optional)
```

Do **not** use `Dist::Zilla` unless you have a strong reason; a plain
`Makefile.PL` is simpler for a one-file XS module and matches the style
most of Chad's CPAN work uses when there is no author-only machinery
needed.

## API

```perl
use Test2::Harness2::ChildSubReaper qw/set_child_subreaper have_subreaper_support/;

# Probe at runtime
if (have_subreaper_support()) {
    set_child_subreaper(1) or warn "prctl failed: $!";
}
```

### Functions

- `have_subreaper_support()` — returns 1 if this build of the module was
  compiled with support for `PR_SET_CHILD_SUBREAPER` and the runtime
  kernel is expected to honor it (i.e. compiled on Linux with the macro
  available). Returns 0 otherwise. Safe to call on any platform.

- `set_child_subreaper($bool)` — enables (truthy) or disables (falsy)
  the subreaper flag on the current process. Returns 1 on success, 0 on
  failure with `$!` (`errno`) set by the kernel. On platforms where
  support was not compiled in, returns 0 and sets `$!` to `ENOSYS`.

Both functions are exportable via `Exporter`. Do not export them by
default (`@EXPORT_OK`, not `@EXPORT`).

### No other API

Do **not** expose any other prctl operations, no process-name helpers,
nothing. This module has exactly two entry points. Callers who want
more can reach for a different distribution.

### Error handling

Follow the syscall-style Perl convention: numeric `1`/`0` returns, with
`$!` carrying the failure reason. Do not croak from XS on EPERM or
similar runtime failures; let the caller decide whether to warn, die,
or carry on. Croak only if called with a clearly wrong argument (e.g.
wrong number of args, but that is caught by the XS signature anyway).

## Portability matrix

| Platform              | Compile                             | `have_subreaper_support()` | `set_child_subreaper(1)` |
|-----------------------|-------------------------------------|---------------------------|--------------------------|
| Linux, kernel >= 3.4  | XS compiles with full support       | 1                         | returns 1, prctl set     |
| Linux, kernel < 3.4   | XS compiles, but prctl returns EINVAL at runtime | 1              | returns 0, `$!` = EINVAL |
| non-Linux (BSD / macOS / Win32) | XS compiles as stub, no real call | 0                         | returns 0, `$!` = ENOSYS |

The module must **install cleanly on all platforms** so that a
`cpanfile` listing it as a suggestion does not fail an install on, say,
macOS. The XS file should use `#ifdef __linux__` and
`#ifdef PR_SET_CHILD_SUBREAPER` guards so the build succeeds everywhere
and the stub path kicks in where the real prctl is unavailable.

## XS implementation sketch

```c
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <errno.h>

#if defined(__linux__)
#  include <sys/prctl.h>
#  ifdef PR_SET_CHILD_SUBREAPER
#    define HARNESS_HAVE_SUBREAPER 1
#  endif
#endif

#ifndef HARNESS_HAVE_SUBREAPER
#  define HARNESS_HAVE_SUBREAPER 0
#endif

MODULE = Test2::Harness2::ChildSubReaper   PACKAGE = Test2::Harness2::ChildSubReaper

int
have_subreaper_support()
    CODE:
        RETVAL = HARNESS_HAVE_SUBREAPER;
    OUTPUT:
        RETVAL

int
set_child_subreaper(int on)
    CODE:
#if HARNESS_HAVE_SUBREAPER
        RETVAL = (prctl(PR_SET_CHILD_SUBREAPER, on ? 1 : 0, 0, 0, 0) == 0) ? 1 : 0;
#else
        errno = ENOSYS;
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL
```

The Perl-side file just does `XSLoader::load` and the `Exporter` setup;
no Perl-side logic is needed.

## Makefile.PL sketch

```perl
use 5.014000;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'Test2::Harness2::ChildSubReaper',
    AUTHOR             => 'Chad Granum <exodist@cpan.org>',
    VERSION_FROM       => 'lib/Test2/Harness2/ChildSubReaper.pm',
    ABSTRACT_FROM      => 'lib/Test2/Harness2/ChildSubReaper.pm',
    LICENSE            => 'perl_5',
    MIN_PERL_VERSION   => '5.014000',
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 0 },
    TEST_REQUIRES      => { 'Test2::V0' => 0 },
    PREREQ_PM          => {},
    META_MERGE         => {
        'meta-spec' => { version => 2 },
        resources   => {
            bugtracker => { web => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper/issues' },
            repository => {
                type => 'git',
                url  => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper.git',
                web  => 'https://github.com/Test-More/Test2-Harness2-ChildSubReaper',
            },
        },
    },
);
```

No extra `CCFLAGS` or `LIBS` are needed; the prctl prototype lives in
`<sys/prctl.h>` which ships with glibc on Linux.

## Test strategy

Four focused test files plus an optional integration test.

### `t/00-load.t`

```perl
use Test2::V0;
use ok 'Test2::Harness2::ChildSubReaper', qw/set_child_subreaper have_subreaper_support/;
done_testing;
```

### `t/10-have-support.t`

```perl
use Test2::V0;
use Test2::Harness2::ChildSubReaper qw/have_subreaper_support/;

if ($^O eq 'linux') {
    ok(have_subreaper_support(), 'Linux build advertises support');
}
else {
    ok(!have_subreaper_support(), "$^O build does not advertise support");
}

done_testing;
```

### `t/20-set-success.t` (Linux only)

Set in a fork so the test process itself isn't permanently flagged:

```perl
use Test2::V0;
use Test2::Harness2::ChildSubReaper qw/set_child_subreaper have_subreaper_support/;

skip_all "Linux-only" unless $^O eq 'linux';
skip_all "no subreaper support in this build" unless have_subreaper_support();

my $pid = fork // die "fork: $!";
if (!$pid) {
    my $ok = set_child_subreaper(1);
    POSIX::_exit($ok ? 0 : 1);
}
waitpid($pid, 0);
is($? >> 8, 0, 'set_child_subreaper(1) succeeded in a fresh process');

$pid = fork // die "fork: $!";
if (!$pid) {
    set_child_subreaper(1);
    my $ok = set_child_subreaper(0);
    POSIX::_exit($ok ? 0 : 1);
}
waitpid($pid, 0);
is($? >> 8, 0, 'set_child_subreaper(0) succeeded');

done_testing;
```

### `t/30-set-without-support.t`

Runs everywhere. Verifies that if support is missing, `set_child_subreaper`
returns 0 with `$!` = `ENOSYS`. This test is useful on Linux builds too
via a hidden-module mechanism, but the simpler form is:

```perl
use Test2::V0;
use POSIX qw/ENOSYS/;
use Test2::Harness2::ChildSubReaper qw/set_child_subreaper have_subreaper_support/;

skip_all "support is present; this test covers the no-support path"
    if have_subreaper_support();

$! = 0;
my $ret = set_child_subreaper(1);
ok(!$ret, 'returns falsy without support');
is(0 + $!, ENOSYS, 'errno set to ENOSYS without support');

done_testing;
```

### `t/40-subreaper-behavior.t` (optional, Linux only)

Actually exercise the subreaper behavior end-to-end:

1. Main process calls `set_child_subreaper(1)`.
2. Fork a child, which forks a grandchild and exits.
3. Grandchild should reparent to the main process (PR_SET_CHILD_SUBREAPER)
   instead of PID 1.
4. Main process `waitpid(-1, 0)`s and reaps the grandchild.

This requires Linux and kernel >= 3.4. Skip otherwise. The test is worth
having once the module is stable because it demonstrates the primitive
actually works end-to-end.

## Integration into Test2-Harness2

After the distribution is building and tested, update `Test2-Harness2`
to use it instead of `Linux::Prctl`.

### Files to change in Test2-Harness2

`~/projects/Test2/Test2-Harness/`:

- `lib/Test2/Harness2.pm`

  - Remove `use constant HAS_LINUX_PRCTL => eval { require Linux::Prctl; 1 } ? 1 : 0;`
  - Replace with a similar optional-load constant for the new module:

    ```perl
    use constant HAS_CHILD_SUBREAPER => eval {
        require Test2::Harness2::ChildSubReaper;
        Test2::Harness2::ChildSubReaper::have_subreaper_support() ? 1 : 0;
    } || 0;
    ```

  - Replace the call site in `run_on_start`:

    ```perl
    # old:
    if (HAS_LINUX_PRCTL && Linux::Prctl->can('set_child_subreaper')) {
        Linux::Prctl::set_child_subreaper(1);
    }

    # new:
    if (HAS_CHILD_SUBREAPER) {
        Test2::Harness2::ChildSubReaper::set_child_subreaper(1)
            or warn "set_child_subreaper failed: $!";
    }
    ```

  - Remove the AI comment above the old block once the replacement lands.

- `dist.ini`

  - Remove `Linux::Prctl = 0` from `[Prereqs / RuntimeSuggests]`.
  - Add `Test2::Harness2::ChildSubReaper = 0.000001` to
    `[Prereqs / RuntimeSuggests]` (or whichever version you tag).

- `cpanfile` (if auto-generated by dist.ini, regenerate; if hand-kept,
  make the same change).

### Tests in Test2-Harness2

Add tests under `t/unit/` that exercise both the "module installed" and
"module hidden" paths. The existing harness test suite does not
currently exercise `run_on_start`'s subreaper call, so there is room to
add coverage here.

Suggested file: `t/unit/Harness2/subreaper.t`. Sketch:

```perl
use Test2::V0;
use Test2::Harness2;

subtest 'subreaper call is attempted when the module is available' => sub {
    skip_all "ChildSubReaper not installed"
        unless Test2::Harness2->HAS_CHILD_SUBREAPER;

    my @calls;
    no warnings 'redefine';
    local *Test2::Harness2::ChildSubReaper::set_child_subreaper
        = sub { push @calls => [@_]; 1 };

    # ... build a harness and call run_on_start, verify a call was made ...
};

subtest 'hidden module path is a silent no-op' => sub {
    # Stub HAS_CHILD_SUBREAPER to 0 and confirm no call is attempted.
    # (Use a sub-process or override the constant via redefine.)
};
```

"Hidden module" can be tested by:

- Setting `$INC{'Test2/Harness2/ChildSubReaper.pm'} = undef` **before**
  Test2::Harness2 is loaded (but the `use constant` is evaluated at
  compile time, so this has to run in a fresh `system perl -e ...`
  subprocess), **or**
- Redefining `Test2::Harness2::HAS_CHILD_SUBREAPER` via the usual
  `local *Test2::Harness2::HAS_CHILD_SUBREAPER = sub () { 0 }`
  pattern before `run_on_start` is called.

The sub-process approach is closer to the real "module is not installed"
scenario; the constant-override approach is simpler and probably
sufficient for unit test purposes.

## Coding style (carry over from Test2-Harness2 CLAUDE.md)

When writing the Perl side of the distribution, match Chad's style:

- Use `Object::HashBase` for any object attributes (unlikely to be needed
  here since this is a functional module, but mention for completeness).
- Use `Carp qw/croak/` for user-facing errors.
- Use `parent` for inheritance, not `base`. (Unlikely to be needed.)
- No trailing whitespace. No emojis.
- Use `perltidy` with the `.perltidyrc` from Test2-Harness2 if possible;
  otherwise match its settings (4-space indent, no tabs, no line-length
  cap, tight parens/brackets/hashes).
- `use 5.014000;` at the top.
- Single-statement conditionals in postfix form.

## Deliverables for the implementing Claude

1. Build out the file layout described above.
2. Implement the XS and the Perl loader.
3. Write the five test files. Make them pass on this Linux workstation
   with `perl Makefile.PL && make && make test`.
4. Confirm the test suite passes cleanly on Linux and that a cross-build
   attempt (faking non-Linux by editing the `#ifdef` guards temporarily)
   produces a module where `have_subreaper_support()` returns 0 and the
   support-less tests pass.
5. Tag the first version `0.000001`.
6. Apply the Test2-Harness2 integration changes described above. Do this
   as a **separate commit** in that repo, not as part of this one. The
   Test2-Harness2 `CLAUDE.md` says to make one commit per change.
7. Add the subreaper-path tests to Test2-Harness2.

## Out of scope

- Expanding the API beyond `set_child_subreaper` / `have_subreaper_support`.
- Supporting any other prctl operation.
- Shipping a pure-Perl fallback that uses `syscall()` instead of XS;
  calling the prctl syscall number directly is fragile across arches.
- Renaming or relocating the module. The name is set.
