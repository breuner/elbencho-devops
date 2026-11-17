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

The docker archives are gzip-compressed images produced with
`docker build --output type=docker`. Load one directly:

```bash
docker load -i elbencho-docker-archive-amd64.tar.gz
```

Static Linux executables are tested with `tests/run-tests.sh -a -j 4` before
upload. The Windows executable is tested with `tests/run-tests.sh -j 4` before
upload.

## Credentials

The workflow uses the Actions secret `ELBENCHO_RELEASE_TOKEN`: a fine-grained
personal access token for `breuner/elbencho` with Contents read and write.
That token creates the draft and uploads assets. The repository's own
`GITHUB_TOKEN` cannot write to another repository.
