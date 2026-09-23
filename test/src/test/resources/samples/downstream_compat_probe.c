/*
 * Resolves only if the link line reached libadditional_compat.a.
 * This happens through the link groups in libc.so in the /usr/lib,
 * /usr/msan/lib and /usr/asan/lib.
 */

#include <stdio.h>

#if defined(__cplusplus) && __has_feature(address_sanitizer)
#  include <__config_site>
#  if !_LIBCPP_INSTRUMENTED_WITH_ASAN
#    error "ASan C++ builds require the matching libc++ headers"
#  endif
#endif

/* clang++ compiles a .c input as C++, so the same source drives both tests. */
#ifdef __cplusplus
extern "C"
#endif
int musl_downstream_compat_probe(void);

int
main(void)
{
    if (musl_downstream_compat_probe() != 42) {
        fprintf(stderr, "unexpected probe value\n");
        return 1;
    }
    printf("downstream-compat-ok\n");
    return 0;
}
