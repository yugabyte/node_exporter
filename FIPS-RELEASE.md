# FIPS 140-3 releases of node_exporter

This fork publishes node_exporter builds linked against the FIPS 140-3 validated
Go Cryptographic Module (`GOFIPS140=v1.0.0`, CMVP certificate #5247), which
upstream does not ship. YugabyteDB Anywhere installs them on database nodes.

Each release is an **unmodified upstream release tag** built with `GOFIPS140`
set. Only `VERSION` gets a `-fips` suffix, so the binary, the tarball names and
the release tag all read `1.12.1-fips` for upstream `v1.12.1`. Nothing else in
this fork diverges from upstream apart from `scripts/`, the `FIPS release`
workflow, this file, a `.gitignore` line and the root `Dockerfile` (below).

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

## Container image

The root `Dockerfile` is upstream's with YugabyteDB's changes. It builds the
image the YugabyteDB Helm chart runs as its node_exporter sidecar: this fork's
FIPS binary on a UBI9 base instead of busybox, squashed to one layer, run as
user 10001, with the base's `rf-*` package repo files removed. The build fails
unless the binary reports the `fips140v1.0` build tag. Upstream's
`Dockerfile.distroless` is left as is.

As upstream, the binary comes from the build context at
`.build/<os>-<arch>/node_exporter`. Stage the FIPS one there first, from a
release tarball, or from the tarball `scripts/build-fips-release.sh` leaves in
`.fips-build/dist`:

```sh
mkdir -p .build/linux-amd64
curl -fsSL https://github.com/yugabyte/node_exporter/releases/download/v1.12.1-fips/node_exporter-1.12.1-fips.linux-amd64.tar.gz |
  tar -xz -C .build/linux-amd64 --strip-components=1 node_exporter-1.12.1-fips.linux-amd64/node_exporter
docker build -t node-exporter-fips:local .
docker run --rm node-exporter-fips:local --version   # version 1.12.1-fips, tags fips140v1.0
```

Build on the architecture of the staged binary (amd64 or arm64), since the
FIPS check runs it. Build arguments, each with a public default:

| Argument | Default |
| --- | --- |
| `BASE_IMAGE` | `registry.access.redhat.com/ubi9/ubi-minimal:latest` |
| `ARCH`, `OS` | `amd64`, `linux`, as upstream |
| `USER` | `10001` |

The `org.opencontainers.image.base.name` label records the `BASE_IMAGE` an
image was built from.

`make docker` at the root now builds this image rather than upstream's, so
upstream's `CI` workflow, which runs it on every pull request for six
architectures, cannot pass here.

## Keeping the fork current

`yb-master` is the default branch: upstream `master` plus the fork-only files
above. `master` is left as it was. To refresh `yb-master`, merge rather than
rebase, so nothing is force-pushed:
`git fetch https://github.com/prometheus/node_exporter.git master && git merge FETCH_HEAD`.
On a conflict in `Dockerfile`, keep this fork's version. Releases never depend
on the branch's content beyond the workflow file, since the workflow builds the
upstream tag it is given.

Upstream's `CI` (`ci.yml`) and `bsd` (`bsd.yml`) workflows are disabled in this
repository's Actions settings: their publish jobs need upstream's secrets, and
`CI` builds the root `Dockerfile` for architectures it doesn't support. Keep
`FIPS release` enabled.
