#!/usr/bin/env bash
#
# build-index.sh — Generate registry.toml from manifest and bundle files on disk.
#
# Usage: ./scripts/build-index.sh [--check]
#
#   --check   Compare generated output against existing registry.toml.
#             Exit 0 if identical, exit 1 if stale (for CI validation).
#
# This script walks warrant-sh/*/manifest.toml and bundles/*.toml,
# computes SHA-256 hashes, and writes a fresh registry.toml.
# The generated file should be committed. Signing is handled separately.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_MODE=true
fi

# Collect manifest entries
MANIFESTS=""
for manifest_path in warrant-sh/*/manifest.toml; do
    [[ -f "$manifest_path" ]] || continue

    dir_name="$(basename "$(dirname "$manifest_path")")"
    id="warrant-sh/${dir_name}"

    # Extract version from manifest (default to 1.0.0)
    version="$(grep -m1 '^manifest_version' "$manifest_path" | sed 's/.*= *"\(.*\)"/\1/' || echo "1.0.0")"

    hash="sha256:$(sha256sum "$manifest_path" | awk '{print $1}')"

    MANIFESTS="${MANIFESTS}
[[manifests]]
id = \"${id}\"
path = \"${manifest_path}\"
version = \"${version}\"
hash = \"${hash}\"
"
done

# Collect bundle entries
BUNDLES=""
for bundle_path in bundles/*.toml; do
    [[ -f "$bundle_path" ]] || continue

    id="$(basename "$bundle_path" .toml)"

    # Extract version from bundle (default to 1.0.0)
    version="$(grep -m1 '^version' "$bundle_path" | sed 's/.*= *"\(.*\)"/\1/' || echo "1.0.0")"

    hash="sha256:$(sha256sum "$bundle_path" | awk '{print $1}')"

    BUNDLES="${BUNDLES}
[[bundles]]
id = \"${id}\"
path = \"${bundle_path}\"
version = \"${version}\"
hash = \"${hash}\"
"
done

# Generate the index
UPDATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUTPUT="# Auto-generated — do not edit manually.
# Run scripts/build-index.sh to regenerate, or let CI handle it on merge.

[registry]
schema = \"warrant.registry.v1\"
updated = \"${UPDATED}\"
${MANIFESTS}${BUNDLES}"

if $CHECK_MODE; then
    # Strip the 'updated' timestamp from both files before comparing,
    # since the generated one will always have a fresh timestamp.
    EXISTING="$(sed '/^updated = /d; /^# Auto-generated/d; /^# Run scripts/d' registry.toml 2>/dev/null || echo "")"
    GENERATED="$(echo "$OUTPUT" | sed '/^updated = /d; /^# Auto-generated/d; /^# Run scripts/d')"

    if [[ "$EXISTING" == "$GENERATED" ]]; then
        echo "✓ registry.toml is up to date."
        exit 0
    else
        echo "✗ registry.toml is stale. Run: scripts/build-index.sh"
        diff <(echo "$EXISTING") <(echo "$GENERATED") || true
        exit 1
    fi
else
    echo "$OUTPUT" > registry.toml
    echo "✓ registry.toml generated ($(grep -c '^\[\[manifests\]\]' registry.toml) manifests, $(grep -c '^\[\[bundles\]\]' registry.toml) bundles)"
fi
