#ifndef FINAINCE_LIBXLS_CONFIG_H
#define FINAINCE_LIBXLS_CONFIG_H

// iOS provides locale APIs we can use directly. Keep iconv disabled to minimize
// integration surface; libxls falls back to its non-iconv paths.
#undef HAVE_ICONV
#undef HAVE_XLOCALE_H
#undef HAVE_WCSTOMBS_L

#define PACKAGE_VERSION "libxls"

#endif
