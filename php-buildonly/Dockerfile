# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32

ARG BUILD_ENV_IMAGE=musl-build-env:latest
ARG IMAGE_MIRROR=docker.io/library

# Official PHP 8.6+ images are always ZTS, so the NTS 8.6 SDK is built from
# source. GA releases are under https://www.php.net/distributions/.
ARG PHP86_VERSION=8.6.0RC3
ARG PHP86_URL=https://downloads.php.net/~svpernova09/php-${PHP86_VERSION}.tar.xz
ARG PHP86_SHA256=131f87a206bdd90c178d8e44e80243ae0c333c4cee8531f63d1caa9acdd8696a

FROM ${IMAGE_MIRROR}/php:7.0-cli-alpine AS php70
FROM ${IMAGE_MIRROR}/php:7.1-cli-alpine AS php71
FROM ${IMAGE_MIRROR}/php:7.2-cli-alpine AS php72
FROM ${IMAGE_MIRROR}/php:7.3-cli-alpine AS php73
FROM ${IMAGE_MIRROR}/php:7.4-cli-alpine AS php74
FROM ${IMAGE_MIRROR}/php:8.0-cli-alpine AS php80
FROM ${IMAGE_MIRROR}/php:8.1-cli-alpine AS php81
FROM ${IMAGE_MIRROR}/php:8.2-cli-alpine AS php82
FROM ${IMAGE_MIRROR}/php:8.3-cli-alpine AS php83
FROM ${IMAGE_MIRROR}/php:8.4-cli-alpine AS php84
FROM ${IMAGE_MIRROR}/php:8.5-cli-alpine AS php85

# Mirror the official php:8.6-rc-cli-alpine build, minus --enable-zts and
# --disable-zend-signals.
FROM ${IMAGE_MIRROR}/alpine:3.23 AS php86
ARG PHP86_VERSION
ARG PHP86_URL
ARG PHP86_SHA256
# configure also reads PHP_LDFLAGS, which ends up in php-config --ldflags.
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"
RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c \
        argon2-dev coreutils curl curl-dev gnu-libiconv-dev libsodium-dev \
        libxml2-dev linux-headers openssl-dev readline-dev sqlite-dev \
        tar xz; \
    rm -vf /usr/include/iconv.h; \
    mkdir -p /usr/src/php; \
    cd /usr/src; \
    curl -fsSL -o php.tar.xz "${PHP86_URL}"; \
    echo "${PHP86_SHA256} *php.tar.xz" | sha256sum -c -; \
    tar -xJf php.tar.xz -C php --strip-components=1; \
    cd php; \
    export \
        CFLAGS="${PHP_CFLAGS}" \
        CPPFLAGS="${PHP_CPPFLAGS}" \
        LDFLAGS="${PHP_LDFLAGS}" \
        PHP_BUILD_PROVIDER='https://github.com/docker-library/php' \
        PHP_UNAME='Linux - Docker'; \
    ./configure \
        --build="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
        --sysconfdir=/usr/local/etc \
        --with-config-file-path=/usr/local/etc/php \
        --with-config-file-scan-dir=/usr/local/etc/php/conf.d \
        --enable-option-checking=fatal \
        --with-mhash \
        --enable-pic \
        --enable-mysqlnd \
        --with-password-argon2 \
        --with-sodium=shared \
        --with-pdo-sqlite=/usr \
        --with-sqlite3=/usr \
        --with-curl \
        --with-iconv=/usr \
        --with-openssl \
        --with-readline \
        --with-zlib \
        --enable-phpdbg \
        --enable-phpdbg-readline \
        --enable-embed; \
    make -j "$(nproc)"; \
    make install; \
    test "$(/usr/local/bin/php -r 'echo PHP_VERSION;')" = "${PHP86_VERSION}"; \
    test "$(/usr/local/bin/php -r 'echo (int) PHP_ZTS;')" = 0

FROM ${BUILD_ENV_IMAGE}

# phpize is a shell script, but it needs Autoconf to generate an extension's
# configure script. The compiler and remaining native build tools come from
# musl-build-env.
RUN apk --no-cache add autoconf

# Add the php_pcre2_* stub layer to the compatibility extension archive already
# referenced by the build environment's libc.so linker script. This applies to
# wrappers, raw Clang, CMake, and other compiler frontends without editing them.
COPY pcre2_compat.c pcre2_compat.S /tmp/
RUN clang \
        -fpie -O2 -fno-omit-frame-pointer -ggdb3 \
        -c /tmp/pcre2_compat.c -o /tmp/pcre2_compat_resolve.o && \
    clang \
        -c /tmp/pcre2_compat.S -o /tmp/pcre2_compat_stubs.o && \
    llvm-ar rcs /usr/lib/libadditional_compat.a \
        /tmp/pcre2_compat_resolve.o /tmp/pcre2_compat_stubs.o && \
    rm /tmp/pcre2_compat.c /tmp/pcre2_compat.S \
       /tmp/pcre2_compat_resolve.o /tmp/pcre2_compat_stubs.o

# Assemble all SDK paths in one OCI layer. This lets the variant-independent
# headers be hard-linked without repeating their contents in the image archive.
# Hard links cannot portably refer to files in a previous OCI layer.
RUN --mount=type=bind,source=assemble-php-sdks,target=/tmp/assemble-php-sdks,ro \
    --mount=type=bind,source=libtool-clang-rt-static-archives.patch,target=/tmp/libtool-clang-rt-static-archives.patch,ro \
    --mount=type=bind,source=libtool-2.5-clang-rt-static-archives.patch,target=/tmp/libtool-2.5-clang-rt-static-archives.patch,ro \
    --mount=type=bind,source=php-7.0-builtin-offsetof.patch,target=/tmp/php-7.0-builtin-offsetof.patch,ro \
    --mount=from=php70,source=/usr/local,target=/mnt/php70,ro \
    --mount=from=php71,source=/usr/local,target=/mnt/php71,ro \
    --mount=from=php72,source=/usr/local,target=/mnt/php72,ro \
    --mount=from=php73,source=/usr/local,target=/mnt/php73,ro \
    --mount=from=php74,source=/usr/local,target=/mnt/php74,ro \
    --mount=from=php80,source=/usr/local,target=/mnt/php80,ro \
    --mount=from=php81,source=/usr/local,target=/mnt/php81,ro \
    --mount=from=php82,source=/usr/local,target=/mnt/php82,ro \
    --mount=from=php83,source=/usr/local,target=/mnt/php83,ro \
    --mount=from=php84,source=/usr/local,target=/mnt/php84,ro \
    --mount=from=php85,source=/usr/local,target=/mnt/php85,ro \
    --mount=from=php86,source=/usr/local,target=/mnt/php86,ro \
    sh /tmp/assemble-php-sdks

COPY phpize php-config /usr/local/bin/
COPY musl-clang.conf /etc/musl-clang.conf

ENV CC=musl-clang \
    CXX=musl-clang++ \
    PHP_SDK_ROOT=/opt/php \
    PHP_SDK_VERSION=8.5

# Validate the installed selectors and verify that OCI extraction preserved
# common headers as hard links while keeping generated headers independent.
RUN set -eux; \
    chmod +x /usr/local/bin/phpize /usr/local/bin/php-config; \
    for version in \
        7.0 7.1 7.2 7.3 7.4 \
        8.0 8.1 8.2 8.3 8.4 8.5 8.6; \
    do \
        release_prefix="/opt/php/${version}"; \
        release_inode=$(stat -c %i \
            "${release_prefix}/include/php/main/php.h"); \
        release_config_inode=$(stat -c %i \
            "${release_prefix}/include/php/main/php_config.h"); \
        grep -qx '#define ZEND_DEBUG 0' \
            "${release_prefix}/include/php/main/php_config.h"; \
        ! grep -qx '#define ZTS 1' \
            "${release_prefix}/include/php/main/php_config.h"; \
        "${release_prefix}/bin/phpize" --version; \
        test "$("${release_prefix}/bin/php-config" --include-dir)" = \
            "${release_prefix}/include/php"; \
        for variant in debug release-zts; do \
            prefix="/opt/php/${version}-${variant}"; \
            test "$(stat -c %i "${prefix}/include/php/main/php.h")" = \
                "${release_inode}"; \
            test "$(stat -c %i \
                "${prefix}/include/php/main/php_config.h")" != \
                "${release_config_inode}"; \
            case "${variant}" in \
                debug) \
                    grep -qx '#define ZEND_DEBUG 1' \
                        "${prefix}/include/php/main/php_config.h"; \
                    ! grep -qx '#define ZTS 1' \
                        "${prefix}/include/php/main/php_config.h"; \
                    ;; \
                release-zts) \
                    grep -qx '#define ZEND_DEBUG 0' \
                        "${prefix}/include/php/main/php_config.h"; \
                    grep -qx '#define ZTS 1' \
                        "${prefix}/include/php/main/php_config.h"; \
                    ;; \
            esac; \
            "${prefix}/bin/phpize" --version; \
            test "$("${prefix}/bin/php-config" --include-dir)" = \
                "${prefix}/include/php"; \
        done; \
    done
