#!/usr/bin/env bash
# Build node_exporter release tarballs against the FIPS 140-3 Go Cryptographic
# Module from an unmodified upstream release tag, and optionally publish them
# as a <tag>-fips GitHub release of this fork.
#
# Usage: scripts/build-fips-release.sh [--publish] [upstream-tag]
#   upstream-tag defaults to v$(cat VERSION). Artifacts land in .fips-build/dist.
#
# The upstream tree is built as-is; only VERSION gets a -fips suffix so promu
# stamps it into the binary and the tarball names. The Go minor version must
# match the .promu.yml of the tag, like upstream's own release builds.
#
# Publishing needs the v<version>-fips tag pushed to the fork beforehand, at
# the upstream tag's commit, by a person (SSH or a workflow-scoped token):
# GITHUB_TOKEN is refused when the pushed commit carries workflow files.
set -euo pipefail

FIPS_MODULE=${GOFIPS140:-v1.0.0}
PLATFORMS=${PLATFORMS:-"linux/amd64 linux/arm64"}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/prometheus/node_exporter.git}

publish=0
if [[ "${1:-}" == "--publish" ]]; then
  publish=1
  shift
fi

root=$(git rev-parse --show-toplevel)
tag=${1:-v$(tr -d '[:space:]' < "${root}/VERSION")}
build_dir=${FIPS_BUILD_DIR:-${root}/.fips-build}
src=${build_dir}/src
dist=${build_dir}/dist

echo ">> fetching ${tag} from ${UPSTREAM_URL}"
git -C "${root}" fetch --no-tags "${UPSTREAM_URL}" "refs/tags/${tag}:refs/tags/${tag}"
commit=$(git -C "${root}" rev-parse "${tag}^{commit}")
fips_tag="v$(tr -d '[:space:]' < <(git -C "${root}" show "${tag}:VERSION"))-fips"
if [[ ${publish} -eq 1 ]]; then
  existing=$(git -C "${root}" ls-remote origin "refs/tags/${fips_tag}" | awk '{print $1}')
  if [[ "${existing}" != "${commit}" ]]; then
    echo "!! origin needs ${fips_tag} at ${commit} (found '${existing}'); push it first:" >&2
    echo "   git push origin ${commit}:refs/tags/${fips_tag}" >&2
    exit 1
  fi
fi

rm -rf "${build_dir}"
mkdir -p "${dist}"
git -C "${root}" worktree prune
git -C "${root}" worktree add --detach "${src}" "${tag}"
trap 'git -C "${root}" worktree remove --force "${src}"' EXIT

version=$(tr -d '[:space:]' < "${src}/VERSION")
fips_version="${version}-fips"
echo "${fips_version}" > "${src}/VERSION"

want_go=$(sed -n 's/^ *version: *//p' "${src}/.promu.yml" | head -1)
have_go=$(go env GOVERSION | sed 's/^go//')
if [[ "${have_go}" != "${want_go}" && "${have_go}" != "${want_go}".* ]]; then
  echo "!! Go ${have_go} in PATH, but ${tag} .promu.yml wants ${want_go}" >&2
  exit 1
fi

host_platform="$(go env GOHOSTOS)/$(go env GOHOSTARCH)"

for platform in ${PLATFORMS}; do
  goos=${platform%%/*}
  goarch=${platform##*/}
  prefix=".build/${goos}-${goarch}"
  echo ">> building ${platform} with GOFIPS140=${FIPS_MODULE}"
  (cd "${src}" && GOOS="${goos}" GOARCH="${goarch}" GOFIPS140="${FIPS_MODULE}" make build PREFIX="${prefix}")

  bin="${src}/${prefix}/node_exporter"
  buildinfo=$(go version -m "${bin}")
  # DefaultGODEBUG is a comma-separated list; fips140=on must be in it.
  for expected in 'build[[:space:]]GOFIPS140=' 'DefaultGODEBUG=(.*,)?fips140=on(,|$)' '-tags=fips140v'; do
    grep -Eq -- "${expected}" <<< "${buildinfo}" || {
      echo "!! ${bin} lacks ${expected} in its build info" >&2
      exit 1
    }
  done
  fips_module=$(sed -n 's/^[[:space:]]*build[[:space:]]GOFIPS140=//p' <<< "${buildinfo}")
  if [[ "${platform}" == "${host_platform}" ]]; then
    # Runs the FIPS module's init-time integrity check and self-tests.
    "${bin}" --version 2>&1 | grep -q "version ${fips_version} " || {
      echo "!! ${bin} --version did not report ${fips_version}" >&2
      exit 1
    }
  fi

  # Same layout as promu tarball (which needs GNU cp): <name>/{node_exporter,LICENSE,NOTICE}.
  name="node_exporter-${fips_version}.${goos}-${goarch}"
  stage="${build_dir}/stage/${name}"
  mkdir -p "${stage}"
  cp "${bin}" "${src}/LICENSE" "${src}/NOTICE" "${stage}/"
  tar -C "${build_dir}/stage" -czf "${dist}/${name}.tar.gz" "${name}"
  echo " >   ${name}.tar.gz"
done

(
  cd "${dist}"
  if command -v sha256sum > /dev/null; then
    sha256sum ./*.tar.gz > sha256sums.txt
  else
    shasum -a 256 ./*.tar.gz > sha256sums.txt
  fi
)
sed -i.bak 's#\./##' "${dist}/sha256sums.txt" && rm -f "${dist}/sha256sums.txt.bak"

cat > "${build_dir}/release.env" <<ENV
UPSTREAM_TAG=${tag}
UPSTREAM_COMMIT=${commit}
VERSION=${version}
FIPS_VERSION=${fips_version}
FIPS_TAG=${fips_tag}
GO_VERSION=${have_go}
FIPS_MODULE=${fips_module}
ENV

echo ">> artifacts in ${dist}"
cat "${dist}/sha256sums.txt"

if [[ ${publish} -eq 0 ]]; then
  exit 0
fi

notes="${build_dir}/notes.md"
cat > "${notes}" <<NOTES
node_exporter ${version} built against the FIPS 140-3 validated Go Cryptographic Module.

- Source: prometheus/node_exporter ${tag} (${commit}), unmodified except for the \`-fips\` VERSION suffix.
- Build: \`GOFIPS140=${FIPS_MODULE}\`, \`CGO_ENABLED=0\`, Go ${have_go}. The binary defaults to \`GODEBUG=fips140=on\`; \`node_exporter --version\` reports the \`fips140v1.0\` build tag.
- In FIPS mode \`crypto/tls\` negotiates only FIPS-approved TLS versions, cipher suites, curves and signature algorithms, regardless of \`web-config.yml\`. See https://go.dev/doc/security/fips140.
- Linux only: Go does not support FIPS 140-3 mode on OpenBSD, AIX, Wasm or 32-bit Windows.

Archive digests are in \`sha256sums.txt\`.
NOTES

echo ">> creating release ${fips_tag}"
gh release create "${fips_tag}" --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
  --title "node_exporter ${fips_version}" --notes-file "${notes}" --verify-tag \
  "${dist}"/*.tar.gz "${dist}/sha256sums.txt"
