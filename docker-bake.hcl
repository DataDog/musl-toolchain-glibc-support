group "images" {
  targets = ["musl-build-env", "php-buildonly"]
}

target "musl-build-env" {
  context    = "musl-build-env"
  dockerfile = "Dockerfile"
}

target "php-buildonly" {
  context    = "php-buildonly"
  dockerfile = "Dockerfile"
  contexts = {
    "musl-build-env" = "target:musl-build-env"
  }
  args = {
    BUILD_ENV_IMAGE = "musl-build-env"
  }
}
