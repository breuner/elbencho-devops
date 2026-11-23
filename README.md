# elbencho-devops

<img src="https://raw.githubusercontent.com/breuner/elbencho/master/graphics/elbencho-logo.svg" width="50%" height="50%" alt="elbencho logo" align="center"/>

GitHub Actions workflows for [elbencho](https://github.com/breuner/elbencho).
They build draft-release artifacts, test open pull requests, and publish the
package repositories.

The draft-release workflows are started with `workflow_dispatch`. They check
out an elbencho git tag, create or reuse a draft release on
`breuner/elbencho`, and attach artifacts. A published release for that tag is
left unchanged.

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

[`elbencho-pr-watch.yml`](.github/workflows/elbencho-pr-watch.yml) checks every
fifteen minutes for an open pull request in `breuner/elbencho` whose head commit
has not been tested yet. It starts
[`elbencho-pr-test.yml`](.github/workflows/elbencho-pr-test.yml) for that
commit. A newer commit on the same request replaces the run that is already
going. The elbencho repository is not changed. The run is reported on the
pull request, and GitHub shows its console to signed-in users.

The test workflow builds three configurations: without S3, with S3, and with
the AWS CRT S3 client. Each build turns backtrace, ibverbs and rdmacm off,
turns mimalloc on, and then runs `tests/run-tests.sh -a -j 4` and
`tools/test-examples.sh -b`. The CRT build also runs the random I/O examples.
The S3 build additionally runs the single-host and two-service S3 examples
against a libreFS server started for that run.

## Package repositories

The latest stable packages are published for RHEL 8, 9 and 10 (built on Rocky
Linux) and for Ubuntu 24.04 and 26.04, each for x86_64 and aarch64. One yum
repository file selects the release and the architecture. Apt reads the Ubuntu
codename from the machine and selects the architecture itself. The same
commands are published at https://breuner.github.io/elbencho-devops/.

RHEL, Rocky Linux, and AlmaLinux:

```bash
sudo curl -fsSL https://breuner.github.io/elbencho-devops/elbencho.repo -o /etc/yum.repos.d/elbencho.repo
sudo dnf install elbencho
```

Ubuntu:

```bash
curl -fsSL https://breuner.github.io/elbencho-devops/elbencho.gpg | sudo tee /etc/apt/keyrings/elbencho.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/elbencho.asc] https://breuner.github.io/elbencho-devops/apt $(. /etc/os-release && echo $VERSION_CODENAME) main" | sudo tee /etc/apt/sources.list.d/elbencho.list >/dev/null
sudo apt update && sudo apt install elbencho
```

