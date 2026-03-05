#!/usr/bin/env bash
set -euo pipefail

# Warrant Registry Signing Script
# Signs registry.toml using the Ed25519 private key from 1Password
#
# Prerequisites: pip install pynacl
# Usage: ./sign-registry.sh
#   Prompts for the private key (base64) — paste from 1Password

cd "$(dirname "$0")"

if [ ! -f registry.toml ]; then
    echo "Error: registry.toml not found" >&2
    exit 1
fi

echo -n "Private key (base64, from 1Password): "
read -rs PRIVATE_KEY_B64
echo

PRIVATE_KEY_B64="$PRIVATE_KEY_B64" python3 - <<'PY'
import base64
import os
import sys

from nacl.signing import SigningKey

seed = base64.b64decode(os.environ["PRIVATE_KEY_B64"].strip())
if len(seed) != 32:
    print("Error: invalid key length", file=sys.stderr)
    sys.exit(1)

sk = SigningKey(seed)
data = open("registry.toml", "rb").read()
sig = sk.sign(data).signature
open("registry.toml.sig", "w").write(base64.b64encode(sig).decode() + "\n")

# Verify round-trip
sig_check = open("registry.toml.sig", "r").read().strip()
sig_bytes = base64.b64decode(sig_check)
sk.verify_key.verify(data, sig_bytes)
print("✓ registry.toml signed and verified")
PY
