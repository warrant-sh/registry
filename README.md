# Warrant Registry

Signed capability manifests for common CLI tools.

Manifests use the `warrant.manifest.v1` schema — the same format parsed by `wsh`.

## Structure

```
registry.toml                   # Registry index (signed)
registry.toml.sig               # Detached ed25519 signature for registry.toml
signing/
  registry-index-public-key.b64 # Pinned ed25519 public key
bundles/
warrant-sh/
  ...
```

## Namespace

All manifests live under `warrant/`. This indicates they are maintained by the Warrant team — they are not official manifests from upstream tool authors.

## Signature

`registry.toml.sig` is a detached Ed25519 signature over the exact bytes of `registry.toml`.
Clients should verify this signature before trusting manifest hash metadata.

## Usage

```bash
wsh manifest pull    # Fetch/update manifests from this registry
wsh setup            # Pull manifests + configure environment
```

## Licence

MIT
