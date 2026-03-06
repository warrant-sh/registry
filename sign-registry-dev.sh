#!/usr/bin/env bash
set -euo pipefail
# Sign registry.toml using the local dev signing key.
# For use during development and by automated agents (Codex, etc.)
# On release, regenerate the keypair and use sign-registry.sh with the production key.

cd "$(dirname "$0")"

KEY_FILE="signing/registry-index-signing-key.b64"
if [ ! -f "$KEY_FILE" ]; then
  echo "Error: signing key not found at $KEY_FILE" >&2
  echo "This key is local-only (gitignored). Ask Peter for the dev key or generate a new one." >&2
  exit 1
fi

if [ ! -f registry.toml ]; then
  echo "Error: registry.toml not found" >&2
  exit 1
fi

PRIVATE_KEY_B64="$(cat "$KEY_FILE")" python3 - <<'PY'
import base64, os, sys

try:
    from nacl.signing import SigningKey
except ImportError:
    print("Error: pynacl not installed. Run: pip install pynacl", file=sys.stderr)
    sys.exit(1)

seed = base64.b64decode(os.environ["PRIVATE_KEY_B64"].strip())
if len(seed) != 32:
    print("Error: invalid key length", file=sys.stderr)
    sys.exit(1)

sk = SigningKey(seed)
data = open("registry.toml", "rb").read()
sig = sk.sign(data).signature
open("registry.toml.sig", "w").write(base64.b64encode(sig).decode() + "\n")

# Verify round-trip
sig_bytes = base64.b64decode(open("registry.toml.sig", "r").read().strip())
sk.verify_key.verify(data, sig_bytes)
print("✓ registry.toml signed and verified")
PY
