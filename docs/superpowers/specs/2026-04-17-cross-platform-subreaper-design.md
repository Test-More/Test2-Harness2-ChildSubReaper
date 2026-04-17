# Cross-platform child subreaper support

**Status:** Design approved, awaiting implementation plan
**Version bump:** 0.000002 → 0.000003

## Summary

Extend `Test2::Harness2::ChildSubReaper` from a Linux-only wrapper around
`prctl(PR_SET_CHILD_SUBREAPER)` to a cross-platform module that also
supports FreeBSD and DragonFlyBSD via `procctl(PROC_REAP_ACQUIRE /
PROC_REAP_RELEASE)`. Add a `subreaper_mechanism()` introspection
function. Fix a brittleness bug in `t/10-have-support.t` that surfaces
on some Linux build environments.

The existing two-function API stays source-compatible. Consumers of
`have_subreaper_support()` (notably `Test2::Harness2::HAS_CHILD_SUBREAPER`)
need no changes and automatically pick up the new backends.

## Motivation

Today the module compiles as a stub on every non-Linux platform and
reports `have_subreaper_support() == 0`, even on systems that have a
fully functional subreaper primitive. FreeBSD 10.2+ (via `procctl`) and
DragonFlyBSD (via the same syscall and macro names) implement the same
abstract behavior: "make the current process the adoptive parent of any
orphaned descendant." Teaching the module about these backends lets
`Test2-Harness2` recover grandchild processes on BSDs without any
change on the caller side.

## Scope

**In scope**

- Linux via `prctl(PR_SET_CHILD_SUBREAPER, ...)` (existing).
- FreeBSD via `procctl(P_PID, getpid(), PROC_REAP_ACQUIRE | PROC_REAP_RELEASE, NULL)`.
- DragonFlyBSD via the same `procctl` interface and macro names.
- A new `subreaper_mechanism()` function returning `"prctl"`,
  `"procctl"`, or `undef`.
- Generalizing the test suite so runtime behavior tests run on any
  platform that advertises support.
- Fixing `t/10-have-support.t`: it currently hard-asserts that Linux
  advertises support, but some Linux build environments lack the
  `PR_SET_CHILD_SUBREAPER` macro at compile time, producing "Dubious,
  test returned 1" while `t/20` skips cleanly. The new test asserts
  the real invariant instead.

**Out of scope**

- macOS, OpenBSD, NetBSD, AIX, HP-UX, Windows — no native subreaper.
  The stub path continues to handle them.
- illumos/Solaris process contracts (`contract(4)`) — conceptually
  similar but a very different API shape, significantly larger surface,
  and not worth chasing until someone actually needs it.
- Any additional procctl or prctl operations beyond enable/disable of
  the subreaper flag. The module's "tiny and targeted" charter
  continues to apply.
- Renaming the distribution. The current name generalizes cleanly.

## Architecture

**Approach chosen: approach 3** — XS remains a thin dispatcher; all
platform resolution lives behind a small C API in a new header file
`subreaper_impl.h`. The header exposes exactly three contract points:

| Symbol | Kind | Meaning |
|---|---|---|
| `H2_SUBREAPER_HAVE` | int macro, 0 or 1 | Whether a real backend compiled in. |
| `H2_SUBREAPER_MECHANISM` | C string literal or `NULL` | Short backend name for diagnostics. |
| `h2_subreaper_set(int on)` | `static int` | Enable/disable; returns 1 on success, 0 on failure with `errno` set. |

Rationale: one XS file plus one header, no `Makefile.PL` changes, and
the platform `#ifdef` noise stays out of the XS. Alternatives
considered: a single stacked-`#ifdef` XS file (fine but keeps mixing
Perl glue and platform logic), and per-backend `.c` files (ceremony for
~40 lines of real code, requires `OBJECT` tweaks in `Makefile.PL`).

## File layout

```
Changes                              -- add v0.000003 entry
Makefile.PL                          -- no logic change
MANIFEST / MANIFEST.SKIP             -- include subreaper_impl.h
subreaper_impl.h                     -- NEW: platform resolution + static helpers
ChildSubReaper.xs                    -- slimmed to dispatcher over H2_SUBREAPER_* macros
lib/Test2/Harness2/ChildSubReaper.pm -- version bump, new export, POD updates
t/00-load.t                          -- also imports subreaper_mechanism
t/10-have-support.t                  -- rewritten (see Tests section)
t/15-mechanism.t                     -- NEW: consistency between have_*/mechanism
t/20-set-success.t                   -- generalize: any supported platform
t/30-set-without-support.t           -- unchanged
t/40-subreaper-behavior.t            -- generalize: any supported platform
```

## Component details

### `subreaper_impl.h`

Responsibility: resolve the platform at compile time and expose the
three contract points listed above. No other symbol should leak.

Structure:

```c
#ifndef H2_SUBREAPER_IMPL_H
#define H2_SUBREAPER_IMPL_H

#include <errno.h>
#include <unistd.h>

#if defined(__linux__)
#  include <sys/prctl.h>
#  ifdef PR_SET_CHILD_SUBREAPER
#    define H2_SUBREAPER_HAVE 1
#    define H2_SUBREAPER_MECHANISM "prctl"
     static int h2_subreaper_set(int on) {
         return prctl(PR_SET_CHILD_SUBREAPER, on ? 1 : 0, 0, 0, 0) == 0 ? 1 : 0;
     }
#  endif

#elif defined(__FreeBSD__) || defined(__DragonFly__)
#  include <sys/types.h>
#  include <sys/procctl.h>
#  if defined(PROC_REAP_ACQUIRE) && defined(PROC_REAP_RELEASE)
#    define H2_SUBREAPER_HAVE 1
#    define H2_SUBREAPER_MECHANISM "procctl"
     static int h2_subreaper_set(int on) {
         int cmd = on ? PROC_REAP_ACQUIRE : PROC_REAP_RELEASE;
         return procctl(P_PID, getpid(), cmd, NULL) == 0 ? 1 : 0;
     }
#  endif
#endif

#ifndef H2_SUBREAPER_HAVE
#  define H2_SUBREAPER_HAVE 0
#  define H2_SUBREAPER_MECHANISM NULL
   static int h2_subreaper_set(int on) {
       (void)on;
       errno = ENOSYS;
       return 0;
   }
#endif

#endif /* H2_SUBREAPER_IMPL_H */
```

Invariants:

- The enable/disable function always returns `1` on success or `0` on
  failure with `errno` set (POSIX-style). `errno` is never modified on
  success.
- On platforms with no macro-based backend match (including old
  FreeBSD, old Linux, or any unsupported OS), the stub branch is the
  single fallback and sets `errno = ENOSYS`.
- `static` (not `static inline`) keeps the translation unit simple;
  the header is included from exactly one `.c` (the XS-generated file).

Verification at implementation time:

- Confirm DragonFlyBSD ships `PROC_REAP_ACQUIRE`/`PROC_REAP_RELEASE`
  with the same spelling as FreeBSD. The `#ifdef` on the macro names is
  the safety net; if the spelling diverges on some DragonFly version,
  the build falls through to the stub and we split the branch.

### `ChildSubReaper.xs`

Responsibility: marshal Perl values to the C contract. No platform
knowledge.

```c
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "subreaper_impl.h"

MODULE = Test2::Harness2::ChildSubReaper   PACKAGE = Test2::Harness2::ChildSubReaper

int
have_subreaper_support()
    CODE:
        RETVAL = H2_SUBREAPER_HAVE;
    OUTPUT:
        RETVAL

SV *
subreaper_mechanism()
    CODE:
#if H2_SUBREAPER_HAVE
        RETVAL = newSVpv(H2_SUBREAPER_MECHANISM, 0);
#else
        RETVAL = newSV(0); /* fresh undef */
#endif
    OUTPUT:
        RETVAL

int
set_child_subreaper(on)
    int on
    CODE:
        RETVAL = h2_subreaper_set(on);
    OUTPUT:
        RETVAL
```

Notes:

- `subreaper_mechanism` returns a Perl undef on unsupported platforms
  so that `if (my $m = subreaper_mechanism()) { ... }` works naturally.
  `newSV(0)` produces a fresh undef SV that XS handles cleanly.
- The XS no longer references `errno`, `ENOSYS`, `prctl`, or `procctl`
  — all platform concerns live in the header.

### `lib/Test2/Harness2/ChildSubReaper.pm`

Changes:

- `$VERSION` → `'0.000003'`.
- `@EXPORT_OK` gains `subreaper_mechanism`.
- POD:
  - NAME: cross-platform child subreaper flag (drop Linux specificity).
  - DESCRIPTION: lead with the abstract concept (subreaping of
    orphaned descendants); then list supported backends (Linux prctl,
    FreeBSD/DragonFly procctl).
  - EXPORTS: add `subreaper_mechanism` — returns `"prctl"` on Linux,
    `"procctl"` on FreeBSD/DragonFlyBSD, `undef` when no backend
    compiled in. Never throws.
  - PORTABILITY: replace the Linux-only matrix with rows for Linux,
    FreeBSD, DragonFlyBSD, and "any other OS" (stub).

## API reference

```perl
use Test2::Harness2::ChildSubReaper qw/
    set_child_subreaper
    have_subreaper_support
    subreaper_mechanism
/;
```

| Function | Return | Notes |
|---|---|---|
| `have_subreaper_support()` | `1` or `0` | True iff a real backend compiled in. |
| `subreaper_mechanism()` | `"prctl"`, `"procctl"`, or `undef` | Diagnostic label. `defined` iff `have_subreaper_support()` is true. |
| `set_child_subreaper($bool)` | `1` or `0` | POSIX-style. Sets `$!` on failure; `$!` is `ENOSYS` on stub platforms. |

Invariant: `!!have_subreaper_support() == defined(subreaper_mechanism())`.
Tests enforce this.

## Error handling

Unchanged from the current design:

- `set_child_subreaper` follows the `1`/`0` + `$!` Perl syscall
  convention. Never croaks on runtime failures (EPERM, EINVAL, etc.).
- XS-level wrong-argument errors (wrong arg count) are still caught by
  the XS prototype.
- The header guarantees `errno` is set to `ENOSYS` when the stub runs.

## Tests

### `t/00-load.t`

Also imports `subreaper_mechanism` to guarantee it's exportable.

### `t/10-have-support.t` (rewritten)

The current test hard-asserts Linux advertises support, which fails on
build environments where `<sys/prctl.h>` lacks `PR_SET_CHILD_SUBREAPER`.
The rewrite asserts the real invariants instead:

- For each `$^O` in a known set (`linux`, `freebsd`, `dragonfly`): if
  `have_subreaper_support()` is true, assert `subreaper_mechanism()`
  equals the expected string for that OS (`"prctl"` for Linux,
  `"procctl"` for FreeBSD/DragonFly). If false, emit a `diag()`
  explaining that the build environment lacked the relevant macro —
  do not fail the test.
- For all other platforms: assert `!have_subreaper_support()` *and*
  `!defined subreaper_mechanism()`.
- Always: the two functions agree on truthiness.

This aligns the test with reality: support is a build-time property,
not a platform-time property, and `t/20` already handles the runtime
side correctly.

### `t/15-mechanism.t` (new)

Focused consistency test, independent of `$^O`:

- `!!have_subreaper_support() == defined(subreaper_mechanism())`.
- When defined, `subreaper_mechanism()` is a member of
  `{"prctl", "procctl"}`.

### `t/20-set-success.t` (generalized)

Drop the `$^O eq 'linux'` guard. Skip only when
`!have_subreaper_support()`. The fork-and-set pattern already isolates
the permanent flag change from the test process.

### `t/30-set-without-support.t`

Unchanged.

### `t/40-subreaper-behavior.t` (generalized)

Drop the `$^O eq 'linux'` guard. Skip only when
`!have_subreaper_support()`. The double-fork reparenting test is
POSIX-level behavior; if the kernel advertises the flag, the test
should exercise it. This gives CPAN Testers on FreeBSD and DragonFly
real end-to-end coverage for free.

## Build and packaging

- `Makefile.PL`: no logic change. MakeMaker automatically picks up
  headers included by the XS.
- `MANIFEST`: add `subreaper_impl.h`.
- `MANIFEST.SKIP`: verify no unintended exclusion of `*.h`, and add
  `^docs/` so the internal spec directory is kept out of the CPAN
  tarball (the spec is a dev artifact, not end-user doc).
- `Changes`: add a `0.000003` entry describing the FreeBSD/DragonFly
  support, the new function, and the t/10 fix.

## Integration with Test2-Harness2

No code change is required in `Test2-Harness2`. The existing
`HAS_CHILD_SUBREAPER` constant is defined as:

```perl
use constant HAS_CHILD_SUBREAPER => eval {
    require Test2::Harness2::ChildSubReaper;
    Test2::Harness2::ChildSubReaper::have_subreaper_support() ? 1 : 0;
} || 0;
```

This automatically becomes truthy on FreeBSD and DragonFlyBSD once
this release is installed. The call site in `run_on_start` continues
to work unchanged.

A separate, optional follow-up (not in this spec): log
`subreaper_mechanism()` once at harness startup for diagnostic
clarity. That is a Test2-Harness2 change, committed separately there,
and should not be bundled with this release.

## Deliverables

1. `subreaper_impl.h` per the sketch above.
2. Slimmed `ChildSubReaper.xs`.
3. Updated `lib/Test2/Harness2/ChildSubReaper.pm`: version bump,
   new export, refreshed POD.
4. Tests: `t/10` rewritten, `t/15` new, `t/20` and `t/40` generalized,
   `t/00` updated.
5. `Changes` and `MANIFEST` entries.
6. `make test` passes clean on this Linux workstation.
7. Tag `0.000003`.
