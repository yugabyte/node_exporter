# FIPS 140-3 releases of node_exporter

This fork publishes node_exporter builds linked against the FIPS 140-3 validated
Go Cryptographic Module (`GOFIPS140=v1.0.0`, CMVP certificate #5247), which
upstream does not ship. YugabyteDB Anywhere installs them on database nodes.

Each release is an **unmodified upstream release tag** built with `GOFIPS140`
set. Only `VERSION` gets a `-fips` suffix, so the binary, the tarball names and
the release tag all read `1.12.1-fips` for upstream `v1.12.1`. Nothing else in
this fork diverges from upstream apart from `scripts/`, the `FIPS release`
workflow, this file and a `.gitignore` line.

Artifacts per release, linux amd64 and arm64:

```
node_exporter-<version>-fips.linux-<arch>.tar.gz   # <name>/{node_exporter,LICENSE,NOTICE}
sha256sums.txt
```

## Cutting a release

1. Pick the upstream tag, e.g. `v1.13.0`, and mirror it plus its `-fips` tag
   into the fork. This needs your own GitHub credential (SSH remote or a token
   with `workflow` scope); the workflow token is refused for these pushes because
   the commit carries workflow files.

   ```sh
   scripts/sync-upstream-tag.sh v1.13.0 --dispatch
   ```

   Without `--dispatch`, start the workflow yourself:

   ```sh
   gh workflow run fips-release.yml -R yugabyte/node_exporter -f upstream_tag=v1.13.0
   ```

2. The `FIPS release` workflow (`.github/workflows/fips-release.yml`) checks out
   the tag in a worktree, installs the Go minor version the tag's `.promu.yml`
   pins, runs `scripts/build-fips-release.sh --publish`, and creates the GitHub
   release `v1.13.0-fips` with the tarballs and `sha256sums.txt`. Set the
   `publish` input to false for a dry run; the artifacts are then only uploaded
   to the workflow run.

3. Check the release page, then point the consumer at the new URLs, e.g.
   `https://github.com/yugabyte/node_exporter/releases/download/v1.13.0-fips/node_exporter-1.13.0-fips.linux-amd64.tar.gz`.

## What the build verifies

`scripts/build-fips-release.sh` fails unless every binary's `go version -m`
output shows a `GOFIPS140=` module, `fips140=on` in `DefaultGODEBUG` and the
`fips140v1.0` build tag. On the runner it also executes the amd64 binary
(`--version`), which runs the module's integrity check and self-tests. You can
repeat the check on a downloaded artifact:

```sh
go version -m node_exporter | grep -E 'GOFIPS140|DefaultGODEBUG|-tags'
./node_exporter --version      # reports version 1.13.0-fips and tags fips140v1.0
```

## Building locally

Same script, same output, no publishing. Go must match the minor version in the
tag's `.promu.yml` (`GOTOOLCHAIN=go1.26.8` works if a newer Go is installed).

```sh
scripts/build-fips-release.sh v1.13.0        # artifacts in .fips-build/dist
PLATFORMS="linux/amd64" scripts/build-fips-release.sh v1.13.0
```

## Behaviour differences of the FIPS build

- `crypto/tls` only negotiates FIPS-approved TLS versions (1.2, 1.3), cipher
  suites (AES-GCM with ECDHE), curves (P-256, P-384) and signature algorithms,
  whatever `web-config.yml` lists. Non-approved entries are dropped silently.
- Basic auth (bcrypt) keeps working; `fips140=on` does not block non-approved
  algorithms outside TLS.
- Linux only. Go refuses to start FIPS mode on OpenBSD, AIX, Wasm and 32-bit
  Windows, so those upstream platforms are not built.

See https://go.dev/doc/security/fips140 for the full list.

## Keeping the fork current

`master` tracks upstream `master` plus the fork-only files above. To refresh
it: `git fetch https://github.com/prometheus/node_exporter.git master && git merge FETCH_HEAD`.
Releases never depend on `master`'s content beyond the workflow file, since the
workflow builds the upstream tag it is given.

Pushes to the fork also trigger upstream's own `CI` and `bsd` workflows, whose
publish jobs fail without upstream's secrets. Cancel them or disable those
workflows in the repository's Actions settings.
