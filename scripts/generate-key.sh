#!/usr/bin/env bash
# One-time: create the repo signing key and export the public half to keys/.
set -euo pipefail

uid="${1:-VPINOS Repo <superhac007@gmail.com>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if gpg --list-secret-keys "$uid" >/dev/null 2>&1; then
  echo "A secret key for '$uid' already exists; exporting it." >&2
else
  gpg --quick-generate-key "$uid" rsa4096 sign never
fi

fpr="$(gpg --list-keys --with-colons "$uid" | awk -F: '/^fpr:/{print $10; exit}')"
gpg --armor --export "$fpr" > "$root/keys/vpinos.asc"

echo "Fingerprint: $fpr"
echo "Public key:  $root/keys/vpinos.asc"
echo "Use it with: export VPINOS_GPG_KEY=$fpr"
