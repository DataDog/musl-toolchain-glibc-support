.DELETE_ON_ERROR:

DOCKER ?= docker
GRADLE ?= ./test/gradlew
GRADLE_WRAPPER_SHA256 = 497c8c2a7e5031f6aa847f88104aa80a93532ec32ee17bdb8d1d2f67a194a9c7

IMAGE_MIRROR ?=
DOCKER_BUILD_ARGS ?=
GRADLE_ARGS ?=

MUSL_BUILD_ENV_AMD64_IMAGE ?= musl-build-env:latest-x86_64
MUSL_BUILD_ENV_ARM64_IMAGE ?= musl-build-env:latest-aarch64
PHP_BUILDONLY_AMD64_IMAGE ?= php-buildonly:latest-x86_64
PHP_BUILDONLY_ARM64_IMAGE ?= php-buildonly:latest-aarch64

MIRROR_BUILD_ARG = $(if $(strip $(IMAGE_MIRROR)),\
	--build-arg IMAGE_MIRROR=$(IMAGE_MIRROR),)
MIRROR_BAKE_ARG = $(if $(strip $(IMAGE_MIRROR)),\
	--set '*.args.IMAGE_MIRROR=$(IMAGE_MIRROR)',)

SHELL_SCRIPTS = \
	musl-build-env/create-glibc-link-facades \
	musl-build-env/embed-private-archive-members \
	php-buildonly/assemble-php-sdks \
	php-buildonly/php-config \
	php-buildonly/phpize \
	test/gradlew

export IMAGE_MIRROR

.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf '%s\n' \
		'Targets:' \
		'  lint          Check Dockerfiles, shell scripts, and Gradle sources' \
		'  build         Build both images for the Docker host architecture' \
		'  build-amd64   Build both linux/amd64 images' \
		'  build-arm64   Build both linux/arm64 images' \
		'  test          Build and run all tests for the Docker host architecture' \
		'  test-amd64    Build and run all tests on an amd64 Docker host' \
		'  test-arm64    Build and run all tests on an arm64 Docker host' \
		'  check         Run lint and the complete native-platform test suite'

.PHONY: lint lint-docker lint-shell lint-gradle
lint: lint-docker lint-shell lint-gradle

lint-docker:
	$(DOCKER) buildx build --check --platform linux/amd64 \
		$(MIRROR_BUILD_ARG) musl-build-env
	$(DOCKER) buildx build --check --platform linux/amd64 \
		--build-arg BUILD_ENV_IMAGE=scratch \
		$(MIRROR_BUILD_ARG) php-buildonly

lint-shell:
	@set -e; \
	for script in $(SHELL_SCRIPTS); do \
		sh -n "$$script"; \
	done
	bash -n musl-build-env/musl-clang.sh

lint-gradle:
	@actual="$$(openssl dgst -sha256 \
		test/gradle/wrapper/gradle-wrapper.jar | awk '{print $$NF}')"; \
	if [ "$$actual" != "$(GRADLE_WRAPPER_SHA256)" ]; then \
		echo 'Gradle wrapper JAR checksum does not match Gradle 9.6.1' >&2; \
		exit 1; \
	fi
	$(GRADLE) --project-dir test testClasses $(GRADLE_ARGS)

.PHONY: build build-amd64 build-arm64
build:
	@set -e; \
	case "$$($(DOCKER) info --format '{{.Architecture}}')" in \
		amd64|x86_64) $(MAKE) build-amd64 ;; \
		arm64|aarch64) $(MAKE) build-arm64 ;; \
		*) echo 'Unsupported Docker host architecture' >&2; exit 1 ;; \
	esac

build-amd64: build-php-buildonly-amd64

build-arm64: build-php-buildonly-arm64

.PHONY: build-musl-build-env-amd64 build-musl-build-env-arm64
build-musl-build-env-amd64:
	$(DOCKER) buildx build --load --platform linux/amd64 \
		--tag $(MUSL_BUILD_ENV_AMD64_IMAGE) $(MIRROR_BUILD_ARG) \
		$(DOCKER_BUILD_ARGS) musl-build-env

build-musl-build-env-arm64:
	$(DOCKER) buildx build --load --platform linux/arm64 \
		--tag $(MUSL_BUILD_ENV_ARM64_IMAGE) $(MIRROR_BUILD_ARG) \
		$(DOCKER_BUILD_ARGS) musl-build-env

.PHONY: build-php-buildonly-amd64 build-php-buildonly-arm64
build-php-buildonly-amd64:
	$(DOCKER) buildx bake --load \
		--set '*.platform=linux/amd64' \
		--set 'musl-build-env.tags=$(MUSL_BUILD_ENV_AMD64_IMAGE)' \
		--set 'php-buildonly.tags=$(PHP_BUILDONLY_AMD64_IMAGE)' \
		$(MIRROR_BAKE_ARG) $(DOCKER_BUILD_ARGS) images

build-php-buildonly-arm64:
	$(DOCKER) buildx bake --load \
		--set '*.platform=linux/arm64' \
		--set 'musl-build-env.tags=$(MUSL_BUILD_ENV_ARM64_IMAGE)' \
		--set 'php-buildonly.tags=$(PHP_BUILDONLY_ARM64_IMAGE)' \
		$(MIRROR_BAKE_ARG) $(DOCKER_BUILD_ARGS) images

.PHONY: test test-amd64 test-arm64
test:
	@set -e; \
	case "$$($(DOCKER) info --format '{{.Architecture}}')" in \
		amd64|x86_64) $(MAKE) test-amd64 ;; \
		arm64|aarch64) $(MAKE) test-arm64 ;; \
		*) echo 'Unsupported Docker host architecture' >&2; exit 1 ;; \
	esac

test-amd64: require-amd64 build-amd64
	$(GRADLE) --project-dir test test \
		-PbuildEnvImage=$(MUSL_BUILD_ENV_AMD64_IMAGE) $(GRADLE_ARGS)

test-arm64: require-arm64 build-arm64
	$(GRADLE) --project-dir test test \
		-PbuildEnvImage=$(MUSL_BUILD_ENV_ARM64_IMAGE) $(GRADLE_ARGS)

.PHONY: check
check: lint test

.PHONY: require-amd64 require-arm64
require-amd64:
	@set -e; \
	architecture="$$($(DOCKER) info --format '{{.Architecture}}')"; \
	case "$$architecture" in \
		amd64|x86_64) ;; \
		*) echo "test-amd64 requires an amd64 Docker host (found $$architecture)" \
			>&2; exit 1 ;; \
	esac

require-arm64:
	@set -e; \
	architecture="$$($(DOCKER) info --format '{{.Architecture}}')"; \
	case "$$architecture" in \
		arm64|aarch64) ;; \
		*) echo "test-arm64 requires an arm64 Docker host (found $$architecture)" \
			>&2; exit 1 ;; \
	esac
