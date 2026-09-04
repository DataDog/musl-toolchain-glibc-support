# CI sample: rebuild from a non-main target

This draft pull request targets a branch that changed a `musl-build-env`
input relative to `main`. CI should rebuild the image even though the pull
request itself changes only this documentation file.
