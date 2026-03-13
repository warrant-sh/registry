#!/usr/bin/env bash
#
# validate.sh — Validate registry integrity.
#
# Checks:
#   1. All TOML files parse correctly
#   2. Every manifest referenced in a bundle exists on disk
#   3. No duplicate manifest IDs
#   4. registry.toml index matches files on disk (via build-index.sh --check)
#
# Exit 0 if all checks pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ERRORS=0

echo "=== Registry Validation ==="
echo ""

# 1. Check all TOML files parse
echo "Checking TOML syntax..."
for f in warrant-sh/*/manifest.toml bundles/*.toml; do
    [[ -f "$f" ]] || continue
    if ! python3 -c "import tomllib; tomllib.load(open('$f','rb'))" 2>/dev/null; then
        if ! python3 -c "import toml; toml.load('$f')" 2>/dev/null; then
            echo "  ✗ $f — invalid TOML"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done
if [[ $ERRORS -eq 0 ]]; then
    echo "  ✓ All TOML files parse correctly."
fi

# 2. Check bundle manifest references
echo ""
echo "Checking bundle references..."
BUNDLE_ERRORS=0
for bundle in bundles/*.toml; do
    [[ -f "$bundle" ]] || continue
    bundle_name="$(basename "$bundle" .toml)"

    # Extract manifest IDs from include list
    in_include=false
    while IFS= read -r line; do
        # Detect start of include block
        if [[ "$line" =~ include\ *=\ *\[ ]]; then
            in_include=true
        fi
        if $in_include; then
            # Extract quoted strings
            while [[ "$line" =~ \"([^\"]+)\" ]]; do
                ref="${BASH_REMATCH[1]}"
                manifest_path="${ref}/manifest.toml"
                if [[ ! -f "$manifest_path" ]]; then
                    echo "  ✗ Bundle '$bundle_name' references '$ref' but $manifest_path does not exist."
                    BUNDLE_ERRORS=$((BUNDLE_ERRORS + 1))
                    ERRORS=$((ERRORS + 1))
                fi
                # Remove matched string to find next
                line="${line#*\"${ref}\"}"
            done
            # Detect end of include block
            if [[ "$line" =~ \] ]]; then
                in_include=false
            fi
        fi
    done < "$bundle"
done
if [[ $BUNDLE_ERRORS -eq 0 ]]; then
    echo "  ✓ All bundle references point to existing manifests."
fi

# 3. Check for duplicate manifest IDs
echo ""
echo "Checking for duplicate manifest IDs..."
DUPES=$(grep -h '^id = ' warrant-sh/*/manifest.toml 2>/dev/null | sort | uniq -d)
if [[ -n "$DUPES" ]]; then
    echo "  ✗ Duplicate manifest IDs found:"
    echo "$DUPES" | while read -r line; do echo "    $line"; done
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ No duplicate manifest IDs."
fi

# 4. Check registry.toml is up to date
echo ""
echo "Checking registry.toml index..."
if bash scripts/build-index.sh --check; then
    :  # Message already printed by build-index.sh
else
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo "=== FAILED: $ERRORS error(s) found ==="
    exit 1
else
    echo "=== PASSED: All checks OK ==="
    exit 0
fi
