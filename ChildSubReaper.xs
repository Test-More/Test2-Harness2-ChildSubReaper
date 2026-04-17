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

int
set_child_subreaper(on)
    int on
    CODE:
        RETVAL = h2_subreaper_set(on);
    OUTPUT:
        RETVAL
