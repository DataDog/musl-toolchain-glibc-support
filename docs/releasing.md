# Releasing `musl-build-env`

## Prerequisites

Before creating a release tag, confirm that:

- the intended commit is merged into protected `main`;
- its protected-main pipeline passed the complete amd64 and arm64 matrix;
- the pipeline pushed and signed the commit-addressed internal OCI index;
- the project identity is authorized by Image Integrity;
- the project, product, production target, and releasing maintainer are
  authorized by Artifact Gateway; and
- the intended version does not already identify different content on Docker
  Hub.

## Release

Create a protected tag in the bare `MAJOR.MINOR.PATCH` form, such as `1.0.0`,
at the tested `main` commit. Creating the tag is the release action; there is no
manual publication job.

The tag pipeline:

1. resolves the existing internal index for the tagged commit without
   rebuilding it;
2. verifies its Image Integrity signature and exact amd64/arm64 platform set;
3. scans the immutable digest with `imageinspector` and fails if the centralized
   result blocks publication;
4. checks Docker Hub for a conflicting version tag;
5. invokes `dd-pkg publish-image` for the logical `public` registry group; and
6. after version publication succeeds, retags that public version as `latest`.

A pipeline retry is safe when Docker Hub's existing version tag points to the
same digest. A different digest is a hard failure and must not be overwritten.
Successful completion of the Artifact Gateway-triggered `public-images` job is
the publication success criterion.

## Failure and rollback

- Stop further publication while a release failure is investigated.
- Never overwrite or move a version tag.
- Publish corrected content under a new patch version.
- Do not advance `latest` when version publication fails.
- If a bad release advanced `latest`, restore the alias to a previously
  successful version through the same serialized Artifact Gateway flow.
