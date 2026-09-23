# musl-build-env tests

This Gradle project has separate harnesses for cross-libc compatibility and
native-musl sanitizer behavior.

The cross-libc harness compiles each sample inside a selected
`musl-build-env` image and runs the resulting executable in two clean runtime
containers:

- glibc: `ubuntu:26.04`
- musl: `alpine:3.24`

The harness requires Docker and Java 17 or newer.

## Gradle verification

The wrapper pins the Gradle 9.6.1 binary distribution checksum. Dependency
locking fixes the resolved test graph, and `gradle/verification-metadata.xml`
checks the SHA-256 of both dependency artifacts and metadata. The root
Makefile's `lint-gradle` target also checks the committed wrapper JAR against
Gradle's published 9.6.1 wrapper checksum before executing it.

After an intentional dependency update, refresh the lock state and verification
metadata, then review every changed component and checksum. Gradle merges
verification data into the existing file, so this task does not remove stale
entries; remove those explicitly during review. The task implies
`--rerun-tasks`, `--write-locks`, and `--write-verification-metadata sha256`:

```sh
./gradlew resolveAndLockAll
make -C .. lint-gradle GRADLE_ARGS=--offline
```

When updating Gradle itself, obtain the new checksums from Gradle's official
checksum reference and regenerate the wrapper with the reviewed distribution:

```sh
./gradlew wrapper --gradle-version 9.6.1 --distribution-type bin \
  --gradle-distribution-sha256-sum \
  9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14
make -C .. lint-gradle
```

The runtime images and the build image are configurable:

```sh
./gradlew test \
  -PbuildEnvImage=musl-build-env:latest \
  -PglibcImage=ubuntu:26.04 \
  -PmuslImage=alpine:3.24
```

The Docker host and all three images must use the same CPU architecture. The
cross-libc harness patches a copy of each executable's interpreter for the
glibc run. Linker-only facades selected by the `libc.so` linker script already
record the portable `libc.so.6` dependency, plus any separate compatibility
DSOs needed by glibc before 2.34. The original executable is used unchanged for
the musl run, and shared libraries are used unchanged on both.

Before glibc 2.34, libpthread used dependency ordering to override libc's
non-threaded definitions with cancellable and thread-aware implementations.
The compiler wrappers therefore make explicit `-pthread` and `-lpthread`
options retain `libpthread.so.0` ahead of `libc.so.6`, even when all referenced
symbols also exist in libc. Explicit `-lm` likewise retains `libm.so.6` ahead
of `libc.so.6`. Static and relocatable links do not acquire those dynamic
dependencies.

Testcontainers also starts `testcontainers/ryuk:0.14.0` for resource cleanup
and uses `alpine:3.17` to check the Docker environment. Override those implicit
images with `ryukImage` and `tinyImage`:

```sh
./gradlew test \
  -PryukImage=testcontainers/ryuk:0.14.0 \
  -PtinyImage=alpine:3.17
```

Set `IMAGE_MIRROR` to select the approved mirror for all external runtime and
Testcontainers images at once. `buildEnvImage` remains separate because it is
the image under test rather than a mirrored third-party input:

```sh
IMAGE_MIRROR=registry.ddbuild.io/images/mirror ./gradlew test \
  -PbuildEnvImage=musl-build-env:latest
```

Managed CI sets that mirror once and supplies the exact `buildEnvImage` source
reference separately. An explicit `glibcImage`, `muslImage`, `ryukImage`, or
`tinyImage` Gradle property takes precedence over its mirror-derived default.

The oldest supported glibc is CentOS 7's, version 2.17. `glibcImage` defaults
to a current release, so checking the floor means naming it explicitly:

```sh
./gradlew compatTests -PglibcImage=centos:7
```

`compatTests` is the narrower set of classes whose names end in `CompatSpec`.

## Sanitizer tests

Sanitizer binaries use a dedicated harness. It selects `/usr/msan/lib` for
MSan, `/usr/asan/lib` when ASan is enabled (including the usual
ASan/UBSan/vptr combination), and `/usr/lib` for other runtimes such as LSan
and standalone UBSan. The two sanitizer directories hold a reduced `libc.so`
linker script that omits `libglibc_compat.a`, whose wrappers would otherwise
override the weak ASan and MSan interceptors, while still supplying the
downstream `libadditional_compat.a`. Because sanitizer binaries are native-musl
only, the reduced scripts select only the libc facade from `/usr/lib`; linker
traces verify that path. Shared libraries from the selected directory are
copied alongside the executable before it runs in the musl container.

Running binaries built with the musl LLVM sanitizer runtimes on glibc is a
non-goal. Sanitizer binaries are supported and tested only on native musl.

### `MUSL_CLANG_SANITIZE`

`MUSL_CLANG_SANITIZE` is a build-environment policy setting, not a Clang
option. Derived images set it in `/etc/musl-clang.conf`, which is sourced by
the `musl-clang` wrappers and the native CMake toolchain. Supported values are:

| Value | C++ root | C++ runtime |
| --- | --- | --- |
| `address` | `/usr/asan` | ASan-instrumented shared DSOs and headers |
| `memory` | `/usr/msan` | MSan-instrumented shared DSOs and headers |

For every C and C++ link, the selected value adds its directory to the library
search path and runtime search path. This selects the reduced sanitizer
`libc.so` instead of the default cross-libc entry. Both directories also contain
matching shared `libc++`, `libc++abi`, and `libunwind` DSOs, which C++ links use
in place of the plain static archives. The MSan `libc++` and `libc++abi` are
instrumented because uninstrumented standard library code reports as
uninitialized; its `libunwind` is intentionally uninstrumented so sanitizer
reporting cannot recurse through the unwinder.

For every C++ compile, the policy also replaces the default libc++ include path
with the matching `<root>/include/c++/v1` directory. Sanitizer-specific inline
code in those headers must match the selected shared library.

The setting does **not** enable sanitizer instrumentation. Compile and link
flags remain explicit and normally live in the same configuration file:

```sh
MUSL_CLANG_SANITIZE=address
MUSL_CLANG_COMPILE_FLAGS=(
    -fsanitize=address,undefined,vptr
    -fno-sanitize=function
)
MUSL_CLANG_LINK_FLAGS=(
    -fsanitize=address,undefined,vptr
    -fno-sanitize=function
)
```

An MSan policy selects `memory` and supplies the flags MSan requires:

```sh
MUSL_CLANG_SANITIZE=memory
MUSL_CLANG_COMPILE_FLAGS=(
    -fsanitize=memory
    -fPIE
)
MUSL_CLANG_LINK_FLAGS=(
    -fsanitize=memory
    -fPIE
    -pie
)
```

Conversely, passing `-fsanitize=address` or `-fsanitize=memory` by itself does
not make the wrapper infer this policy. A derived sanitizer image should set
`MUSL_CLANG_SANITIZE`; a one-off link must select `/usr/asan/lib` or
`/usr/msan/lib` and the matching C++ headers explicitly if no policy is
installed.

#### Why ASan and MSan require selection

Leaving either runtime on the default library path degrades silently, so the
failure mode is worth spelling out. `libglibc_compat.a` defines its wrappers as
strong hidden symbols, while compiler-rt defines its interceptors as weak ones.
A link that reaches the default `/usr/lib/libc.so` pulls in the archive, and the
strong definition wins: calls land in the compatibility wrapper and the
interceptor is never entered. These names are defined by both, so each one loses
its interception:

| Wrapper | Intercepted by |
| --- | --- |
| `sendmsg`, `recvmsg`, `sendmmsg`, `recvmmsg` | ASan, MSan |
| `stat`, `lstat`, `strerror_r`, `realpath` | ASan, MSan |
| `fstat`, `fstatat`, `atexit` | MSan |

There is no diagnostic. A program that writes to poisoned memory and hands it
to `sendmsg` exits 0 and prints nothing, which reads as "no bug found"; the
same program built with the policy exits 1 with a `use-after-poison` report.
Nor does it take an unusual program to trigger. A trivial `main` built with
ASan or MSan already extracts the object and displaces the corresponding
wrappers above; the same program linked without either runtime does not extract
it at all.

LSan and standalone UBSan do not have the conflicting interceptors above, so
they intentionally use the default `/usr/lib` path. Policy values other than
`address` and `memory` are unsupported and select no special directory.

The base `musl-build-env` image deliberately has no derived-image policy. The
normal and detection harnesses explicitly select `/usr/asan/lib`,
`/usr/msan/lib`, or `/usr/lib` for each sample. The toolchain tests omit that
explicit selection to prove that both supported `MUSL_CLANG_SANITIZE` values
make the wrapper and CMake toolchain perform it.

There are three intentionally separate sanitizer test categories:

- Normal tests verify that ASan, LSan, and MSan operate without false positives
  or runtime failures. These include the regression tests for the local
  compiler-rt patches, a C++ program that MSan only accepts when it links the
  instrumented standard library, and an ASan/UBSan C++ program that requires
  matching libc++ headers and shared libraries.
- Detection tests trigger deliberate memory and undefined-behavior bugs and
  verify that ASan, LSan, MSan, and UBSan produce the expected reports and
  nonzero exits.
- Toolchain tests cover the link policy the other two rely on: that
  `MUSL_CLANG_SANITIZE` alone selects the sanitizer directory for C and C++
  links, and that the directory's `libc.so` drops `libglibc_compat.a` while
  keeping `libadditional_compat.a`. They use a container-scoped stand-in
  downstream archive and remove `/etc/musl-clang.conf` after each policy case.

Select all three categories by package. They need only the build and musl
images:

```sh
./gradlew test --tests 'com.datadoghg.musl.sanitizer.*' \
  -PbuildEnvImage=musl-build-env:latest \
  -PmuslImage=alpine:3.24
```

The sanitizer runtime container uses an unconfined seccomp profile because
x86_64 MSan must call `personality(ADDR_NO_RANDOMIZE)` during startup. Docker's
default seccomp profile blocks that call.

## Compiler-rt patch red/green checks

`test` is deliberately a positive, fast suite. To establish that an individual
compiler-rt patch is necessary, build a temporary image omitting exactly that
patch and run its normal-condition spec. Omitting one patch at a time prevents
an earlier compiler or linker failure from masking another regression.

For example:

```sh
docker build -t musl-build-env:patched musl-build-env
docker build \
  --build-arg OMIT_COMPILER_RT_PATCH=msghdr \
  -t musl-build-env:without-msghdr musl-build-env

./gradlew test \
  --tests '*CompilerRtMsghdrPatchSpec' \
  -PbuildEnvImage=musl-build-env:without-msghdr \
  -PmuslImage=alpine:3.24

./gradlew test \
  --tests '*CompilerRtMsghdrPatchSpec' \
  -PbuildEnvImage=musl-build-env:patched \
  -PmuslImage=alpine:3.24
```

The first Gradle invocation must fail for the regression exercised by the
spec; the second must pass. Supported omission names and their specs are:

| Omitted patch | Expected failing spec |
| --- | --- |
| `msghdr` | `CompilerRtMsghdrPatchSpec` |
| `tls` | `CompilerRtTlsPatchSpec` |
| `stat` | `CompilerRtStatPatchSpec` |
| `rlimit64` | `CompilerRtRlimit64PatchSpec` |

Run the omission matrix on both supported CPU architectures. The TLS case must
also cover Alpine 3.12 and Alpine 3.24 because those releases use different
musl pthread layouts.

The general `test` task runs both harnesses. `patchTests` continues to select
classes whose names end in `PatchSpec`.
