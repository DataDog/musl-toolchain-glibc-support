#include <errno.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    char buffer[128];

    /* musl's strerror_r is the POSIX variant and returns 0 on success. The
     * GNU compiler-rt interceptor would treat that 0 as a null char * and
     * crash in internal_strlen. */
    if (strerror_r(ECONNREFUSED, buffer, sizeof buffer) != 0)
        return 1;
    /* Branching on the buffer makes MSan report it if it is still poisoned. */
    if (buffer[0] == '\0')
        return 2;

    puts("msan-strerror_r-ok");
    return 0;
}
