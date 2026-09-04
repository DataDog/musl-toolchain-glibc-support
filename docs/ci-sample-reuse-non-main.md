# CI sample: reuse from a non-main target

This draft pull request targets another branch but has no changes to
`musl-build-env` inputs relative to its merge base with `main`. CI should reuse
the signed image published by `main`.
