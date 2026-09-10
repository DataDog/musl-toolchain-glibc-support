# Contributing

Run build and test commands from the repository root. Local development
requires:

- a running Docker daemon with the Buildx plugin;
- GNU Make;
- Java 17 or newer; and
- OpenSSL, for verification of the committed Gradle wrapper JAR.

The required tests are native: the Docker host, the toolchain image, and the
test runtime images must all use the same CPU architecture.

## Build and test

Build both images for the Docker host architecture:

```sh
make build
```

This loads `musl-build-env` and `php-buildonly` into Docker. On an amd64 host
their default tags end in `latest-x86_64`; on an arm64 host they end in
`latest-aarch64`.

Build both images and run the complete native test suite:

```sh
make test
```

Run all static checks and the complete native test suite before submitting a
change:

```sh
make check
```

Use `make lint` when only the static Dockerfile, shell, and Gradle checks are
needed. `make help` lists the explicit amd64 and arm64 build and test targets.
The architecture-specific test targets fail unless the Docker host has the
matching architecture.

To build only the derived image, first make sure the corresponding local
`musl-build-env` tag exists, then run one of:

```sh
make build-php-buildonly-amd64
make build-php-buildonly-arm64
```

Set `IMAGE_MIRROR` to use a registry mirror for external base and test images:

```sh
IMAGE_MIRROR=example.com/mirror make check
```

The public default is Docker Hub. Datadog-managed CI supplies its approved
mirror and the exact internal `musl-build-env` reference independently.

See [the test documentation](test/README.md) for focused Gradle tests,
runtime-image overrides, sanitizer behavior, and dependency-lock maintenance.
