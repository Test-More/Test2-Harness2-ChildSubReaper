# Claude instructions for this repo

You are building a new Perl/XS distribution named
`Test2::Harness2::ChildSubReaper`. The complete plan lives in
[`PLAN.md`](./PLAN.md). Read it before doing anything.

## Context

This module replaces the harness service's use of `Linux::Prctl`. The
goal is a tiny, targeted XS wrapper around one prctl operation
(`PR_SET_CHILD_SUBREAPER`). The consuming project lives at
`~/projects/Test2/Test2-Harness/` and its `CLAUDE.md` describes the
broader style rules Chad follows. When you work here, apply those
rules. When you come back to the harness repo to do the integration
step, respect its `CLAUDE.md` (separate commit per logical change,
never suppress exceptions, etc.).

## The user

You are working for "Exodist" (Chad Granum), the author of the Test2
ecosystem. Write idiomatic Perl/XS that looks like his other CPAN work.
The final code will be released to CPAN under his name.

## Working directory

This repo is fresh. You own the whole layout. Create files as you need
them; there is no pre-existing code to preserve.

## Two-phase work

The plan has two phases:

1. **Build this distribution.** Files, XS, tests, a passing
   `make test` on Linux.

2. **Integrate it into Test2-Harness2.** That edit happens in
   `~/projects/Test2/Test2-Harness/`. It replaces a `Linux::Prctl`
   call site and adds coverage. Commit it separately in that repo; do
   not mix it with work in this repo.

Phase 1 can be done and committed before phase 2 starts.

## After each phase

Run the test suite and confirm it passes before committing. The
Test2-Harness2 side uses `prove -Ilib -r t/unit/`; this repo uses the
standard `perl Makefile.PL && make && make test`.
