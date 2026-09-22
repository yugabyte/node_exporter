#!/usr/bin/env bash
# Mirror an upstream prometheus/node_exporter release tag into this fork and
# create the matching v<version>-fips tag the FIPS release workflow releases from.
#
# Usage: scripts/sync-upstream-tag.sh <upstream-tag> [--dispatch]
#   --dispatch also starts the "FIPS release" workflow for that tag.
#
# Run this with a personal credential (SSH remote or a workflow-scoped token):
# the pushed commit carries workflow files, which GITHUB_TOKEN may not push.
set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/prometheus/node_exporter.git}

tag=${1:?usage: $0 <upstream-tag> [--dispatch]}
dispatch=0
[[ "${2:-}" == "--dispatch" ]] && dispatch=1

root=$(git rev-parse --show-toplevel)

echo ">> fetching ${tag} from ${UPSTREAM_URL}"
git -C "${root}" fetch --no-tags "${UPSTREAM_URL}" "refs/tags/${tag}:refs/tags/${tag}"
commit=$(git -C "${root}" rev-parse "${tag}^{commit}")
version=$(git -C "${root}" show "${tag}:VERSION" | tr -d '[:space:]')
fips_tag="v${version}-fips"
if [[ "${tag}" != "v${version}" ]]; then
  echo "!! ${tag} has VERSION ${version}; expected a release tag v${version}" >&2
  exit 1
fi

# git refuses to move an existing tag, so a re-run is a no-op or a loud failure.
echo ">> pushing ${tag} and ${fips_tag} -> ${commit}"
git -C "${root}" push origin "refs/tags/${tag}:refs/tags/${tag}" "${commit}:refs/tags/${fips_tag}"

if [[ ${dispatch} -eq 1 ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  echo ">> dispatching FIPS release for ${tag} on ${repo}"
  gh workflow run fips-release.yml -R "${repo}" -f "upstream_tag=${tag}"
  echo "   follow it with: gh run list -R ${repo} --workflow fips-release.yml"
fi
