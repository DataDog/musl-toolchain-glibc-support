# Releasing the toolchain images

## Prerequisites

Before creating a release tag, confirm that:

- the intended commit is merged into protected `main`;
- its protected-main pipeline passed the complete amd64 and arm64 matrix;
- the pipeline pushed and signed both commit-addressed internal OCI indexes;
- the project identity is authorized by Image Integrity;
- the project, product, production target, and releasing maintainer are
  authorized by Artifact Gateway; and
- the intended version does not already identify different content on Docker
  Hub.

## Release

To release, create a bare `MAJOR.MINOR.PATCH` tag, such as `1.0.0`, at the
tested `main` commit. GitHub repository rulesets restrict who may create these
tags and prevent them from being updated or deleted. Codesync then mirrors the
tag to GitLab, where DDCI's repository-specific allowlist starts a pipeline
only for the same stable-version pattern. Because GitLab cannot represent the
GitHub ruleset state on the mirrored tag, the release jobs intentionally do
not require `CI_COMMIT_REF_PROTECTED`. Creating the tag starts the entire
release; there is no manual publication job.

The tag pipeline:

1. resolves both existing internal indexes for the tagged commit without
   rebuilding them;
2. verifies their Image Integrity signatures and exact amd64/arm64 platform
   sets;
3. scans both immutable digests with `imageinspector` and fails if either
   centralized result blocks publication;
4. checks Docker Hub for a conflicting version tag in each image's separate
   publication job;
5. publishes `musl-build-env` to the logical `public` registry group and
   `php-buildonly` to the logical `dev` registry group (Docker Hub and
   `registry.datadoghq.com`) in parallel; and
6. after both version publication jobs succeed, independently retags each
   public version as `latest` in its respective registry set.

A pipeline retry is safe when each existing Docker Hub version tag points to
the corresponding internal digest. A different digest is a hard failure and
must not be overwritten. Successful completion of every Artifact
Gateway-triggered `public-images` job is the publication success criterion.

## Failure and rollback

- Stop further publication while a release failure is investigated.
- Never overwrite or move a version tag.
- Publish corrected content under a new patch version.
- Do not advance either `latest` alias when a version publication fails.
- If a bad release advanced `latest`, restore the alias to a previously
  successful version through the same serialized Artifact Gateway flow.
