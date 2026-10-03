#!/usr/bin/env bash
# Copyright 2026 Qianmo AgentNest Team
# SPDX-License-Identifier: Apache-2.0
#
# Fetch the Codex-built rusty_v8 archive and binding that codex-code-mode-host
# links, verified against the trusted manifest checked into third_party/v8.
# Same source and checks as the upstream composite action
# .github/actions/setup-rusty-v8 (which only runs inside GitHub Actions), so
# qianmo/build-linux.sh and a local macOS build share one implementation.
#
# Why: the workspace enables the v8 crate's v8_enable_sandbox feature, so the
# v8 build script asks for a "ptrcomp_sandbox" prebuilt. denoland/rusty_v8 does
# not publish that variant, and without these overrides cargo fails to build
# codex-code-mode-host. qmcode itself does not link V8.
#
# Usage: qianmo/fetch-rusty-v8.sh <rust target triple> [dir]
#   dir defaults to codex-rs/target/qianmo-rusty-v8 (ignored by git).
# Prints the cargo build environment on stdout, one KEY=path per line:
#   RUSTY_V8_ARCHIVE=<dir>/librusty_v8_ptrcomp_sandbox_release_<target>.a.gz
#   RUSTY_V8_SRC_BINDING_PATH=<dir>/src_binding_ptrcomp_sandbox_release_<target>.rs
# Files already in dir are reused only when they pass the checksum check.
# Needs curl and python3 >= 3.11 (tomllib, for the upstream version resolver).

set -euo pipefail

die() {
  printf 'fetch-rusty-v8: %b\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || die "usage: qianmo/fetch-rusty-v8.sh <rust target triple> [dir]"
target="$1"

for tool in curl python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} not found"
done
if command -v sha256sum >/dev/null 2>&1; then
  sha256=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  sha256=(shasum -a 256)
else
  die "sha256sum or shasum not found"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${2:-${repo_root}/codex-rs/target/qianmo-rusty-v8}"

version="$(python3 "${repo_root}/.github/scripts/rusty_v8_bazel.py" resolved-v8-crate-version)"
[[ -n "${version}" ]] || die "cannot resolve the v8 crate version from codex-rs/Cargo.lock"
release_tag="rusty-v8-v${version}"
base_url="https://github.com/openai/codex/releases/download/${release_tag}"
profile="ptrcomp_sandbox_release"

case "${target}" in
  *-pc-windows-msvc) die "Windows targets are not supported by this script" ;;
esac
archive_name="librusty_v8_${profile}_${target}.a.gz"
binding_name="src_binding_${profile}_${target}.rs"
checksums_name="rusty_v8_${profile}_${target}.sha256"
trusted_checksums="${repo_root}/third_party/v8/rusty_v8_${version//./_}_release_manifests.sha256"
[[ -f "${trusted_checksums}" ]] || die "trusted manifest list not found: ${trusted_checksums}"
expected_manifest_checksum="$(grep -F "  ${checksums_name}" "${trusted_checksums}" | cut -d ' ' -f 1)"
[[ -n "${expected_manifest_checksum}" ]] ||
  die "no trusted checksum for ${checksums_name} in ${trusted_checksums}"

mkdir -p "${dir}"
dir="$(cd "${dir}" && pwd)"

curl -fsSL --retry 3 "${base_url}/${checksums_name}" -o "${dir}/${checksums_name}"
# Check the original manifest bytes (upstream manifests may use CRLF).
actual_manifest_checksum="$("${sha256[@]}" "${dir}/${checksums_name}" | cut -d ' ' -f 1)"
[[ "${actual_manifest_checksum}" == "${expected_manifest_checksum}" ]] ||
  die "checksum mismatch for ${checksums_name}: expected ${expected_manifest_checksum}, got ${actual_manifest_checksum}"
[[ "$(wc -l <"${dir}/${checksums_name}" | tr -d ' ')" -eq 2 ]] ||
  die "expected exactly two checksums in ${checksums_name}"

check_pair() {
  (cd "${dir}" && tr -d '\r' <"${checksums_name}" | "${sha256[@]}" --check "$@" -)
}

if [[ -f "${dir}/${archive_name}" && -f "${dir}/${binding_name}" ]] && check_pair --status; then
  echo "fetch-rusty-v8: reusing verified ${release_tag} ${profile} files for ${target}" >&2
else
  echo "fetch-rusty-v8: downloading ${release_tag} ${profile} files for ${target}" >&2
  curl -fsSL --retry 3 "${base_url}/${archive_name}" -o "${dir}/${archive_name}"
  curl -fsSL --retry 3 "${base_url}/${binding_name}" -o "${dir}/${binding_name}"
  check_pair >&2 || die "checksum check failed for ${target} files in ${dir}"
fi

echo "RUSTY_V8_ARCHIVE=${dir}/${archive_name}"
echo "RUSTY_V8_SRC_BINDING_PATH=${dir}/${binding_name}"
