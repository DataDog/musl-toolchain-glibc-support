#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

int
main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s library\n", argv[0]);
        return EXIT_FAILURE;
    }

    void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!module) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        return EXIT_FAILURE;
    }

    dlerror();
    int (*run)(void) =
        (int (*)(void))dlsym(module, "sanitizer_cxx_dso_run");
    const char *error = dlerror();
    if (error) {
        fprintf(stderr, "dlsym: %s\n", error);
        return EXIT_FAILURE;
    }

    int result = run();
    if (dlclose(module) != 0) {
        fprintf(stderr, "dlclose: %s\n", dlerror());
        return EXIT_FAILURE;
    }
    if (result != 42) {
        fprintf(stderr, "unexpected C++ DSO result: %d\n", result);
        return EXIT_FAILURE;
    }

    puts("sanitizer-cxx-dso-ok");
    return EXIT_SUCCESS;
}
