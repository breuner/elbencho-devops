# elbencho-devops

GitHub Actions workflows that build draft-release artifacts for
[elbencho](https://github.com/breuner/elbencho).

The workflows are started with `workflow_dispatch`. They check out an elbencho
git tag, create or reuse a draft release on `breuner/elbencho`, and attach
artifacts. A published release for that tag is left unchanged.

## Workflow

[`elbencho-draft-release.yml`](.github/workflows/elbencho-draft-release.yml)
takes three inputs:

- `tag` — an existing elbencho git tag
- `release_title` — draft title, used only when the draft is created
- `components` — `all`, `static-amd64`, `static-arm64`, `windows`,
  `docker-amd64`, or `docker-arm64`

`all` builds every artifact. Any other value rebuilds only that artifact and
replaces its files on the existing draft. Release notes for a new draft are
copied from the latest published stable elbencho release. An existing draft
keeps its title and notes.

## Artifacts

- `elbencho-static-x86_64.tar.gz`, `elbencho-static.x86_64.rpm`,
  `elbencho-static_amd64.deb`
- `elbencho-static-aarch64.tar.gz`, `elbencho-static.aarch64.rpm`,
  `elbencho-static_arm64.deb`
- `elbencho-windows.zip`
- `elbencho-docker-archive-amd64.tar.gz`
- `elbencho-docker-archive-arm64.tar.gz`

The docker archives are gzip-compressed `docker save` images of
`elbencho:latest`. The arm64 image uses the same
`-march=armv8-a+crc+crypto+simd` baseline as the static arm64 package, so it
runs on Cortex-A72 and Cortex-A78AE. Load one directly:

```bash
docker load -i elbencho-docker-archive-amd64.tar.gz
```

Static Linux executables are tested with `tests/run-tests.sh -a -j 4` before
upload. The Windows executable is tested with `tests/run-tests.sh -j 4` before
upload.

## Pull requests

[`elbencho-pr-test.yml`](.github/workflows/elbencho-pr-test.yml) builds and
tests an elbencho ref on a GitHub-hosted runner. A pull request in
`breuner/elbencho` starts it through `.github/workflows/pr-test.yml` in that
repository. The run replaces the previous run for the same request.

It builds the same three configurations as the `elbencho-github-pr-test`
Jenkins job: without S3, with S3, and with the AWS CRT S3 client. Each build
turns backtrace, ibverbs and rdmacm off, turns mimalloc on, and then runs
`tests/run-tests.sh -a -j 4` and `tools/test-examples.sh -b`. The CRT build
also runs the random I/O examples. The S3 build additionally runs the
single-host and two-service S3 examples against a private libreFS server.
The hosted runner is the isolation boundary, so the tests do not use the
chroot from the Jenkins job.
