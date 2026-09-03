# musl toolchain with glibc compatibility support

This repository builds a native musl toolchain image whose compiler wrappers
produce executables that can be prepared to run on both musl and glibc systems.
It provides Clang, LLVM runtimes, libc compatibility objects, and a CMake
toolchain file for projects that need this build model.

This is targeted compatibility support, not general glibc emulation. Validate
each application's complete dependency set. Executables using the included musl
sanitizer runtimes are supported only on musl.

## Images and platforms

The public image is `datadog/musl-build-env`. Releases support:

- `linux/amd64`
- `linux/arm64`

The `php-buildonly` directory contains a derived build image used by this
repository's test matrix. It is not part of the current public image contract.

Release images are copied to these public locations:

- `docker.io/datadog/musl-build-env`
- `datadoghq.azurecr.io/musl-build-env`
- `gcr.io/datadoghq/musl-build-env`
- `us-docker.pkg.dev/datadoghq/gcr.io/musl-build-env`
- `europe-docker.pkg.dev/datadoghq/eu.gcr.io/musl-build-env`
- `asia-docker.pkg.dev/datadoghq/asia.gcr.io/musl-build-env`
- `public.ecr.aws/datadog/musl-build-env`
- `registry.datad0g.com/musl-build-env`
- `registry.datadoghq.com/musl-build-env`

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
immutable; corrections receive a new patch version. The mutable `latest` alias
advances only after the corresponding version has been published successfully.

Protected release pipelines sign and scan the tested internal image digest,
then ask Datadog's Artifact Gateway to publish it. The
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

## Security

Do not report security vulnerabilities in a public issue. Follow Datadog's
[security reporting instructions](https://www.datadoghq.com/security/?tab=contact).

## License

This project is licensed under Apache License 2.0 with LLVM Exceptions. See
[LICENSE.TXT](LICENSE.TXT).
