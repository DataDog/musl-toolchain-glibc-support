# musl toolchain with glibc compatibility support

This repository builds a native musl toolchain image whose compiler wrappers
produce executables that can be prepared to run on both musl and glibc systems.
It provides Clang, LLVM runtimes, libc compatibility objects, and a CMake
toolchain file for projects that need this build model. Development headers for
OpenSSL, PCRE, PCRE2, and zlib are included, together with Perl.

This is targeted compatibility support, not general glibc emulation. Validate
each application's complete dependency set. Executables using the included musl
sanitizer runtimes are supported only on musl.

## Images and platforms

This repository publishes two images:

- `datadog/musl-build-env`, the base musl toolchain; and
- `datadog/php-buildonly`, a derived image containing build-only PHP SDKs for
  PHP 7.0 through 8.5.

Both images support:

- `linux/amd64`
- `linux/arm64`

`musl-build-env` releases are copied to these public locations:

- `docker.io/datadog/musl-build-env`
- `datadoghq.azurecr.io/musl-build-env`
- `gcr.io/datadoghq/musl-build-env`
- `us-docker.pkg.dev/datadoghq/gcr.io/musl-build-env`
- `europe-docker.pkg.dev/datadoghq/eu.gcr.io/musl-build-env`
- `asia-docker.pkg.dev/datadoghq/asia.gcr.io/musl-build-env`
- `public.ecr.aws/datadog/musl-build-env`
- `registry.datad0g.com/musl-build-env`
- `registry.datadoghq.com/musl-build-env`

`php-buildonly` releases are copied only to
`docker.io/datadog/php-buildonly`.

## Usage

Use an immutable version or digest in automation:

```sh
docker pull docker.io/datadog/musl-build-env:1.0.0

docker run --rm \
  --volume "$PWD:/work" \
  --workdir /work \
  docker.io/datadog/musl-build-env:1.0.0 \
  musl-clang -o app app.c
```

The C++ wrapper is `musl-clang++`. CMake projects can select
`/usr/local/share/musl/Toolchain.cmake` as their toolchain file.

Executables run natively on musl. Running one on glibc requires setting the
copy's ELF interpreter to the target architecture's glibc loader. The test
suite demonstrates this without modifying the original musl executable. See
[the test documentation](test/README.md) for the compatibility boundary,
sanitizer behavior, and test commands.

## Tags and releases

Stable releases use bare semantic versions such as `1.0.0`. Version tags are
immutable; corrections receive a new patch version. The mutable `latest`
aliases advance only after both versioned images have been published
successfully.

Protected release pipelines verify and scan both tested internal image digests,
then ask Datadog's Artifact Gateway to publish them. The
[`DataDog/public-images`](https://github.com/DataDog/public-images) project owns
the public-registry credentials and performs the final copies; this repository
does not contain those credentials.

Maintainers should follow [the release procedure](docs/releasing.md).

## Development

Docker with Buildx and Java 17 or newer are required. Run the complete native
suite with:

```sh
make check
```

Use `make help` to list the architecture-specific build and test targets.

When only derived-image inputs change, CI builds `php-buildonly` against the
newest relevant `musl-build-env` index. Validation pipelines compare the
checked-out commit with its merge base with `main`; protected `main` pipelines
compare the current commit with its first parent. CI verifies the selected
index's signature and pins the build to its immutable digest. Every protected
`main` pipeline tags that digest with its own commit, even when the image is
reused. CI does not interpret the public `latest` tag as a build input.

## Security

Do not report security vulnerabilities in a public issue. Follow Datadog's
[security reporting instructions](https://www.datadoghq.com/security/?tab=contact).

## License

This project is licensed under Apache License 2.0 with LLVM Exceptions. See
[LICENSE.TXT](LICENSE.TXT).
