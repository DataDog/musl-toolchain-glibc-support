#!/bin/bash

set -euo pipefail

driver=clang
cxx=false
case "${0##*/}" in
    *++)
        driver=clang++
        cxx=true
        ;;
esac

# Derived images can install a declarative policy without editing this script.
# The file may assign MUSL_CLANG_SANITIZE and the two Bash arrays below.
MUSL_CLANG_COMPILE_FLAGS=()
MUSL_CLANG_LINK_FLAGS=()
if [[ -r /etc/musl-clang.conf ]]; then
    # shellcheck source=/dev/null
    source /etc/musl-clang.conf
fi

common_flags=(-fno-omit-frame-pointer)
cxx_header_flags=()
cxx_link_flags=()
if $cxx; then
    cxx_link_flags=(-stdlib=libc++)
fi

sanitizer_root=
sanitizer_lib_dir=
sanitized_cxx=false
case "${MUSL_CLANG_SANITIZE:-}" in
    *address*) sanitizer_root=/usr/asan ;;
    *memory*) sanitizer_root=/usr/msan ;;
esac
if [[ -n $sanitizer_root ]]; then
    sanitizer_lib_dir="$sanitizer_root/lib"
    if $cxx; then
        sanitized_cxx=true
        cxx_header_flags=(
            -stdlib++-isystem "$sanitizer_root/include/c++/v1")
    fi
fi

# Do not pass link-only policy to dependency generation, preprocessing,
# assembly, syntax checks, or object compilation.
compile_only=false
for arg in "$@"; do
    case "$arg" in
        -c|-S|-E|-M|-MM|-fsyntax-only)
            compile_only=true
            break
            ;;
    esac
done

if $compile_only; then
    cxx_compile_flags=("${cxx_header_flags[@]}")
    if $cxx && ! $sanitized_cxx; then
        # -stdlib=libc++ has two functions 1) include the libc++ headers and 2)
        # its libraries. In sanitized compile-only builds, we pass
        # -stdlib++-isystem, and there is no linking to do, so -stdlibc=libc++
        # is not consumed and errors with -Werror. But in non-sanitized builds,
        # we can add it to include the libc++ headers.
        cxx_compile_flags=(-stdlib=libc++)
    fi
    exec "$driver" \
        "${common_flags[@]}" \
        "${cxx_compile_flags[@]}" \
        "${MUSL_CLANG_COMPILE_FLAGS[@]}" \
        "$@"
fi

# ASan/MSan links search /usr/{asan,msan}/lib before /usr/lib. Their libc.so
# linker scripts omit libglibc_compat.a so its strong wrappers cannot replace
# compiler-rt's weak interceptors. Native-musl sanitizer binaries need only the
# libc.so.6 facade, not the pthread/rt/m/dl/util compatibility facades (running
# instrumented binaries in glibc is a non-goal).
#
# Only MUSL_CLANG_SANITIZE drives the choice; explicit -fsanitize=address or
# -fsanitize=memory arguments are deliberately not inspected.

# In sanitized C++ mode, omit explicit runtime libraries supplied by build
# systems. Clang's implicit -lc++ will resolve to the sanitizer directory, and
# that DSO already depends on its matching libc++abi and libunwind DSOs.
link_args=("$@")
if $sanitized_cxx; then
    filtered_args=()
    previous_was_l=false
    for arg in "$@"; do
        if $previous_was_l; then
            case "$arg" in
                c++|c++abi|unwind) ;;
                *) filtered_args+=(-l "$arg") ;;
            esac
            previous_was_l=false
            continue
        fi
        case "$arg" in
            -l)
                previous_was_l=true
                ;;
            -lc++|-lc++abi|-lunwind)
                ;;
            *)
                filtered_args+=("$arg")
                ;;
        esac
    done
    $previous_was_l && filtered_args+=(-l)
    link_args=("${filtered_args[@]}")
fi

# glibc has symbols overlapping in libc and, say, libpthread or libm, and these
# have different definitions in each. Consequently, we must honour requests to
# explicitly link the split libraries.
pthread_driver_flag=false
pthread_library_flag=false
math_library_flag=false
link_cxx_sanitizer_runtime=false
default_libraries=true
dynamic_output=true
shared_output=false
previous_was_l=false
link_options=(
    "${MUSL_CLANG_COMPILE_FLAGS[@]}"
    "${link_args[@]}"
    "${MUSL_CLANG_LINK_FLAGS[@]}"
)
for arg in "${link_options[@]}"; do
    if $previous_was_l; then
        case "$arg" in
            pthread) pthread_library_flag=true ;;
            m) math_library_flag=true ;;
        esac
        previous_was_l=false
        continue
    fi
    case "$arg" in
        -l)
            previous_was_l=true
            ;;
        -pthread)
            pthread_driver_flag=true
            ;;
        -lpthread)
            pthread_library_flag=true
            ;;
        -lm)
            math_library_flag=true
            ;;
        -fsanitize-link-c++-runtime)
            link_cxx_sanitizer_runtime=true
            ;;
        -fno-sanitize-link-c++-runtime)
            link_cxx_sanitizer_runtime=false
            ;;
        -nostdlib|-nodefaultlibs)
            default_libraries=false
            ;;
        -shared)
            shared_output=true
            ;;
        -static|-static-pie|-r|-Wl,-r|-Wl,-r,*|-Wl,--relocatable|\
        -Wl,--relocatable,*)
            dynamic_output=false
            ;;
    esac
done

runtime_selection_flags=()
if $default_libraries; then
    runtime_selection_flags=(-rtlib=compiler-rt -unwindlib=libunwind)
fi

force_pthread=false
if $pthread_library_flag ||
   { $pthread_driver_flag && $default_libraries; }; then
    force_pthread=true
fi

pthread_link_flags=()
if $dynamic_output && $force_pthread; then
    pthread_link_flags=(
        -Wl,--push-state
        -Wl,-Bdynamic
        -Wl,--no-as-needed
        /usr/lib/glibc-compat-libpthread.so.0
        -Wl,--pop-state
    )
fi

math_link_flags=()
if $dynamic_output && $math_library_flag; then
    math_link_flags=(
        -Wl,--push-state
        -Wl,-Bdynamic
        -Wl,--no-as-needed
        /usr/lib/glibc-compat-libm.so.6
        -Wl,--pop-state
    )
fi

# An explicit -lc from the caller (e.g. libtool's C++ tag links with -nostdlib
# and spells out the runtime libraries itself) must not be resolved inside the
# -Bstatic region
rewritten_args=()
previous_was_l=false
for arg in "${link_args[@]}"; do
    if $previous_was_l; then
        previous_was_l=false
        if [[ $arg == c ]]; then
            rewritten_args+=(-Wl,--push-state -Wl,-Bdynamic -lc -Wl,--pop-state)
        else
            rewritten_args+=(-l "$arg")
        fi
        continue
    fi
    case "$arg" in
        -l)
            previous_was_l=true
            ;;
        -lc)
            rewritten_args+=(-Wl,--push-state -Wl,-Bdynamic -lc -Wl,--pop-state)
            ;;
        *)
            rewritten_args+=("$arg")
            ;;
    esac
done
$previous_was_l && rewritten_args+=(-l)
link_args=("${rewritten_args[@]}")

sanitizer_link_flags=()
if [[ -n $sanitizer_lib_dir ]]; then
    sanitizer_link_flags=(
        -L"$sanitizer_lib_dir" -Wl,-rpath,"$sanitizer_lib_dir")
fi

# In sanitized C++ mode the instrumented shared libc++ comes from the directory
# above instead of the plain static one.
cxx_runtime_flags=()
if $cxx && ! $sanitized_cxx; then
    cxx_runtime_flags=(-static-libstdc++)
fi

# A C executable can request the C++ sanitizer archives (it may load C++ DSOs).
# They need the matching shared C++ ABI, which the C driver does not add.
# However, -fsanitize-link-c++-runtime is effectively a no-op when -shared is
# passed (libclang_rt.asan_cxx.a and libclang_rt.ubsan_standalone_cxx.a are not
# linked into the DSO, so we don't need to link libc++abi either)
c_sanitizer_abi_flags=()
if ! $cxx &&
   [[ -n $sanitizer_root ]] &&
   $link_cxx_sanitizer_runtime &&
   $default_libraries &&
   $dynamic_output &&
   ! $shared_output; then
    c_sanitizer_abi_flags=(
        -Wl,--push-state
        -Wl,-Bdynamic
        -lc++abi
        -Wl,--pop-state
    )
fi

# Start user-specified libraries in static mode, while allowing an explicit
# -Bdynamic from the caller to override that preference. Pop the state before
# Clang emits its implicit compiler runtimes and dynamic libc.
exec "$driver" \
    "${common_flags[@]}" \
    "${cxx_header_flags[@]}" \
    "${cxx_link_flags[@]}" \
    "${MUSL_CLANG_COMPILE_FLAGS[@]}" \
    "${runtime_selection_flags[@]}" \
    -Wl,--gc-sections \
    -Wl,-z,nocopyreloc \
    "${sanitizer_link_flags[@]}" \
    "${cxx_runtime_flags[@]}" \
    -Wl,--push-state \
    -Wl,-Bstatic \
    "${link_args[@]}" \
    -Wl,--pop-state \
    "${c_sanitizer_abi_flags[@]}" \
    "${MUSL_CLANG_LINK_FLAGS[@]}" \
    "${pthread_link_flags[@]}" \
    "${math_link_flags[@]}"
