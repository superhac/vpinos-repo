#!/usr/bin/env bash
# Usage: build-repo.sh <stage-dir> <out-dir>
#
# <stage-dir> holds .deb files. Keeps only the newest version of each
# package/architecture in it (older ones are deleted), then writes the signed
# flat-repo metadata (Packages, Packages.gz, Release, InRelease, Release.gpg)
# to <out-dir>. Requires VPINOS_GPG_KEY; set VPINOS_GPG_PASSPHRASE for a
# passphrase-protected key when running non-interactively (e.g. in CI).
set -euo pipefail

stage="${1:?stage dir required}"
out="${2:?out dir required}"
: "${VPINOS_GPG_KEY:?Set VPINOS_GPG_KEY to the signing key id or fingerprint}"

for tool in apt-ftparchive dpkg-deb dpkg gpg gzip; do
  command -v "$tool" >/dev/null || { echo "$tool is required." >&2; exit 1; }
done

shopt -s nullglob
debs=("$stage"/*.deb)
(( ${#debs[@]} )) || { echo "No .deb files in $stage." >&2; exit 1; }

# Keep only the newest version of each package/arch.
declare -A best_ver best_file
for deb in "${debs[@]}"; do
  key="$(dpkg-deb -f "$deb" Package)_$(dpkg-deb -f "$deb" Architecture)"
  ver="$(dpkg-deb -f "$deb" Version)"
  if [[ -z "${best_ver[$key]:-}" ]]; then
    best_ver[$key]="$ver"; best_file[$key]="$deb"
  elif dpkg --compare-versions "$ver" gt "${best_ver[$key]}"; then
    echo "Pruning superseded $(basename "${best_file[$key]}")"
    rm -f "${best_file[$key]}"
    best_ver[$key]="$ver"; best_file[$key]="$deb"
  else
    echo "Pruning superseded $(basename "$deb")"
    rm -f "$deb"
  fi
done

rm -rf "$out"
mkdir -p "$out"

# Filenames are recorded as ./<name>.deb, resolved against the repo base URL.
(cd "$stage" && apt-ftparchive packages .) > "$out/Packages"
gzip -9nk "$out/Packages"

archs="$(awk '/^Architecture:/{print $2}' "$out/Packages" | sort -u | tr '\n' ' ')"
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=VPINOS \
  -o APT::FTPArchive::Release::Label=VPINOS \
  -o "APT::FTPArchive::Release::Architectures=${archs% }" \
  -o "APT::FTPArchive::Release::Description=VPINOS Debian packages" \
  release "$out" > "$out/Release.tmp"
mv "$out/Release.tmp" "$out/Release"

if tty -s 2>/dev/null; then GPG_TTY="$(tty)"; export GPG_TTY; fi

sign() {
  local -a args=(--batch --yes --local-user "$VPINOS_GPG_KEY")
  if [[ -n "${VPINOS_GPG_PASSPHRASE:-}" ]]; then
    args+=(--pinentry-mode loopback --passphrase-fd 3)
  fi
  gpg "${args[@]}" "$@" 3<<<"${VPINOS_GPG_PASSPHRASE:-}"
}
sign --clearsign -o "$out/InRelease" "$out/Release"
sign --armor --detach-sign -o "$out/Release.gpg" "$out/Release"

echo "Repository metadata written to $out:"
ls -1 "$out"
