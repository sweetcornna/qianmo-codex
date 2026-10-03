#!/usr/bin/env bash
# Copyright 2026 Qianmo AgentNest Team
# SPDX-License-Identifier: Apache-2.0
#
# Build qmcode natively on a Linux host (x86_64 or aarch64). Never cross-compile
# from macOS: build aarch64 artifacts on an aarch64 machine. The GitHub Actions
# workflow .github/workflows/qianmo-build-linux.yml runs this script.
#
# Usage: qianmo/build-linux.sh [output-dir]
#   output-dir defaults to codex-rs/target/qianmo-dist (ignored by git).
#
# Writes to output-dir, with NAME = qmcode-<upstream tag>-<short commit>-<arch>:
#   NAME             the release binary
#   NAME.sha256      `sha256sum` line for NAME
#   NAME.buildinfo   tag, commit, toolchain, host, build seconds, sha256, size
#   NAME.build.log   full cargo output
#
# The upstream tag is rust-v<workspace version from codex-rs/Cargo.toml>, so the
# script works in clones without upstream tags (the fork does not carry them:
# pushing a rust-v* tag would start the upstream release workflow).
#
# Environment:
#   QMCODE_ALLOW_DIRTY=1  build even when tracked files are modified; NAME gets
#                         a "-dirty" suffix.

set -euo pipefail

die() {
  printf 'build-linux: %b\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Linux" ]] || die "must run on Linux (got $(uname -s))"

case "$(uname -m)" in
  x86_64 | amd64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

for tool in git rustup sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} not found"
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codex_rs="${repo_root}/codex-rs"
target_dir="${CARGO_TARGET_DIR:-${codex_rs}/target}"
[[ "${target_dir}" == /* ]] || target_dir="${codex_rs}/${target_dir}"
out_dir="${1:-${codex_rs}/target/qianmo-dist}"

toolchain="$(sed -n 's/^channel *= *"\(.*\)"$/\1/p' "${codex_rs}/rust-toolchain.toml")"
[[ -n "${toolchain}" ]] || die "cannot read channel from codex-rs/rust-toolchain.toml"
workspace_version="$(sed -n '/^\[workspace.package\]/,/^\[/s/^version *= *"\(.*\)"$/\1/p' "${codex_rs}/Cargo.toml")"
[[ -n "${workspace_version}" ]] || die "cannot read [workspace.package] version from codex-rs/Cargo.toml"
[[ "${workspace_version}" != "0.0.0" ]] ||
  die "workspace version is 0.0.0: this tree is not based on an upstream release tag"

upstream_tag="rust-v${workspace_version}"
if git -C "${repo_root}" rev-parse -q --verify "refs/tags/${upstream_tag}^{commit}" >/dev/null; then
  git -C "${repo_root}" merge-base --is-ancestor "${upstream_tag}" HEAD ||
    die "HEAD does not contain upstream tag ${upstream_tag}"
else
  echo "build-linux: tag ${upstream_tag} is not in this clone; using the Cargo.toml version"
fi
commit="$(git -C "${repo_root}" rev-parse HEAD)"
short_commit="$(git -C "${repo_root}" rev-parse --short=10 HEAD)"

dirty_paths="$(git -C "${repo_root}" status --porcelain --untracked-files=no)"
suffix=""
if [[ -n "${dirty_paths}" ]]; then
  [[ "${QMCODE_ALLOW_DIRTY:-0}" == "1" ]] ||
    die "tracked files are modified (set QMCODE_ALLOW_DIRTY=1 to build anyway):\n${dirty_paths}"
  suffix="-dirty"
fi

name="qmcode-${upstream_tag}-${short_commit}-${arch}${suffix}"
mkdir -p "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"
log="${out_dir}/${name}.build.log"

if ! rustup run "${toolchain}" rustc --version >/dev/null 2>&1; then
  echo "build-linux: installing Rust ${toolchain} with rustup"
  rustup toolchain install "${toolchain}" --profile minimal
fi
rustc_version="$(rustup run "${toolchain}" rustc --version)"

echo "build-linux: building ${name} with ${rustc_version}"
echo "build-linux: cargo output goes to ${log}"
start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
start_epoch="$(date -u +%s)"
if ! (cd "${codex_rs}" && rustup run "${toolchain}" cargo build --release --locked --bin qmcode) \
  >"${log}" 2>&1; then
  tail -n 40 "${log}" >&2
  die "cargo build failed; see ${log}"
fi
end_epoch="$(date -u +%s)"
end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
build_seconds=$((end_epoch - start_epoch))

# --locked must leave the committed lock file untouched.
git -C "${repo_root}" diff --quiet -- codex-rs/Cargo.lock ||
  die "codex-rs/Cargo.lock changed during a --locked build"

binary="${target_dir}/release/qmcode"
[[ -x "${binary}" ]] || die "expected binary not found: ${binary}"
install -m 0755 "${binary}" "${out_dir}/${name}"
(cd "${out_dir}" && sha256sum "${name}" >"${name}.sha256")
sha256="$(cut -d' ' -f1 "${out_dir}/${name}.sha256")"
size_bytes="$(wc -c <"${out_dir}/${name}" | tr -d ' ')"

cat >"${out_dir}/${name}.buildinfo" <<EOF
name=${name}
upstream_tag=${upstream_tag}
commit=${commit}
arch=${arch}
toolchain=${toolchain}
rustc=${rustc_version}
host=$(uname -n)
kernel=$(uname -r)
start_utc=${start_utc}
end_utc=${end_utc}
build_seconds=${build_seconds}
sha256=${sha256}
size_bytes=${size_bytes}
EOF

# Verify the artifact: checksum, ELF architecture, version, and that under a
# throwaway HOME it creates nothing but HOME/.qmcode (never HOME/.codex). The
# binary refuses to create its helper directory under $TMPDIR, so an output
# directory inside $TMPDIR legitimately leaves HOME empty.
(cd "${out_dir}" && sha256sum -c "${name}.sha256")

if command -v readelf >/dev/null 2>&1; then
  machine="$(readelf -h "${out_dir}/${name}" | sed -n 's/^ *Machine: *//p')"
  case "${arch}:${machine}" in
    x86_64:*X86-64* | aarch64:*AArch64*) ;;
    *) die "ELF machine '${machine}' does not match ${arch}" ;;
  esac
  echo "build-linux: ELF machine ${machine}"
else
  echo "build-linux: readelf not found; skipped ELF architecture check"
fi

verify_home="$(mktemp -d "${out_dir}/.verify-home.XXXXXX")"
trap 'rm -rf -- "${verify_home}"' EXIT
version_output="$(env -u QMCODE_HOME -u CODEX_HOME HOME="${verify_home}" \
  "${out_dir}/${name}" --version 2>&1)"
version_line="$(tail -n 1 <<<"${version_output}")"
[[ "${version_line}" == "qmcode ${workspace_version}" ]] ||
  die "unexpected --version output: ${version_output}"
created="$(ls -A "${verify_home}")"
case "${created}" in
  .qmcode) echo "build-linux: --version created only HOME/.qmcode" ;;
  "") echo "build-linux: --version created nothing under HOME (HOME is inside \$TMPDIR)" ;;
  *) die "--version created unexpected entries under HOME: ${created}" ;;
esac

echo "build-linux: ${version_line}"
echo "build-linux: ${out_dir}/${name}"
echo "build-linux: sha256 ${sha256}, ${size_bytes} bytes, built in ${build_seconds}s"
