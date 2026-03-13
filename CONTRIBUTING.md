# Contributing to the Warrant Registry

## How the Registry Works

The registry contains **manifests** (tool-level access policies) and **bundles** (curated collections of manifests for specific agent setups). Users install bundles via `wsh pull`.

- **Manifests** live in `warrant-sh/<tool-name>/manifest.toml`
- **Bundles** live in `bundles/<name>.toml`
- **`registry.toml`** is a generated index of all manifests and bundles with SHA-256 hashes
- **`registry.toml.sig`** is the Ed25519 signature of the index

## Making Changes

### What You Edit

Only edit manifest files (`warrant-sh/*/manifest.toml`) and bundle files (`bundles/*.toml`).

**Do not edit `registry.toml` or `registry.toml.sig` manually.** These are generated and signed automatically.

### Workflow

1. Create a feature branch
2. Add or modify manifest and/or bundle files
3. Run `scripts/build-index.sh` to regenerate `registry.toml`
4. Run `scripts/validate.sh` to check everything is correct
5. Commit all changes including the regenerated `registry.toml`
6. Open a PR against `main`

CI will run `validate.sh` on your PR automatically. On merge to `main`, a GitHub Action regenerates the index and signs it.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build-index.sh` | Regenerate `registry.toml` from manifest and bundle files |
| `scripts/build-index.sh --check` | Verify `registry.toml` matches files on disk (used by CI) |
| `scripts/validate.sh` | Full validation: TOML syntax, bundle references, duplicates, index freshness |

### Adding a New Manifest

1. Create `warrant-sh/<tool-name>/manifest.toml`
2. Follow the `warrant.manifest.v1` schema (see existing manifests for examples)
3. Run `scripts/build-index.sh` to add it to the index
4. If it should be included in a baseline bundle, add it to the relevant `bundles/*.toml`

### Adding a New Bundle

1. Create `bundles/<name>.toml`
2. Reference only manifests that exist in `warrant-sh/`
3. Run `scripts/build-index.sh` to add it to the index

## Signing

Signing is handled by GitHub Actions on merge to `main`. You do not need the signing key to contribute. The `sign-on-merge` workflow regenerates the index, signs it, and commits the result.

## Validation

CI checks on every PR:
- All TOML files parse correctly
- Every manifest referenced in a bundle exists on disk
- No duplicate manifest IDs
- `registry.toml` matches the files on disk
