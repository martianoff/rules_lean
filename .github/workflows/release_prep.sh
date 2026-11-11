#!/usr/bin/env bash
# Called by the reusable release workflow with the tag (e.g. v0.1.0). Writes the
# release archive and API docs to the working directory and the release notes
# to stdout.
set -o errexit -o nounset -o pipefail

TAG=$1
VERSION=${TAG#v}
# The prefix matches GitHub's own source archives, so strip_prefix is the same
# for both.
PREFIX="rules_lean-${VERSION}"
ARCHIVE="rules_lean-${TAG}.tar.gz"
LEAN_VERSION="$(sed -n 's/^DEFAULT_LEAN_VERSION = "\(.*\)"$/\1/p' lean/private/versions.bzl)"

git archive --format=tar --prefix="${PREFIX}/" "${TAG}" | gzip > "${ARCHIVE}"

# API docs for the Bazel Central Registry (registry.bazel.build renders them).
docs="$(mktemp -d)"
targets="$(mktemp)"
bazel --output_base="$docs" query --output=label 'kind("starlark_doc_extract rule", //...)' > "$targets"
bazel --output_base="$docs" build --target_pattern_file="$targets"
tar --create --auto-compress \
  --directory "$(bazel --output_base="$docs" info bazel-bin)" \
  --file "${GITHUB_WORKSPACE}/${ARCHIVE%.tar.gz}.docs.tar.gz" .

cat <<NOTES
## Using rules_lean ${VERSION}

Add to your \`MODULE.bazel\`:

\`\`\`starlark
bazel_dep(name = "rules_lean", version = "${VERSION}")

lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")
lean.toolchain(version = "${LEAN_VERSION}")  # optional: the default of this release
\`\`\`

Lean toolchains are downloaded from Lean's own release hosts and verified by
checksum; this release contains only rules_lean's sources.
NOTES
