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
