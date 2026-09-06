#!/usr/bin/env bash
#
# Downloads the Tailwind and esbuild binaries if they're missing.
#
# Why not let `mix tailwind.install` do it? Because on OTP 27 it can't: GitHub's
# release CDN (release-assets.githubusercontent.com) serves a certificate that
# OTP's validation rejects with `key_usage_mismatch`, so the download from
# Elixir dies with "Unsupported Certificate". `curl` uses the system trust store
# and goes through without complaint.
#
# It surfaces as a runtime error the first time you open a page — the endpoint
# is already up and serving, so it doesn't look like a build problem at all.
#
# Idempotent: if the binaries are there it does nothing. It leaves them in
# `_build/`, exactly where `Tailwind.bin_path/1` and `Esbuild.bin_path/0` look.
set -euo pipefail

cd "$(dirname "$0")/.."

TAILWIND_VERSION="${TAILWIND_VERSION:-4.3.0}"
ESBUILD_VERSION="${ESBUILD_VERSION:-0.25.4}"
TARGET="${TARGET:-linux-x64}"

tailwind_bin="_build/tailwind-${TARGET}-${TAILWIND_VERSION}"
esbuild_bin="_build/esbuild-${TARGET}"

mkdir -p _build

if [ ! -x "$tailwind_bin" ]; then
  echo "==> Downloading Tailwind ${TAILWIND_VERSION}..."
  curl -sSL -o "$tailwind_bin" \
    "https://github.com/tailwindlabs/tailwindcss/releases/download/v${TAILWIND_VERSION}/tailwindcss-${TARGET}"
  chmod +x "$tailwind_bin"
fi

if [ ! -x "$esbuild_bin" ]; then
  echo "==> Downloading esbuild ${ESBUILD_VERSION}..."
  tmp="$(mktemp -d)"
  curl -sSL -o "$tmp/esbuild.tgz" \
    "https://registry.npmjs.org/@esbuild/${TARGET/-/}/-/${TARGET/-/}-${ESBUILD_VERSION}.tgz" \
    || curl -sSL -o "$tmp/esbuild.tgz" \
      "https://registry.npmjs.org/esbuild-${TARGET}/-/esbuild-${TARGET}-${ESBUILD_VERSION}.tgz"
  tar -xzf "$tmp/esbuild.tgz" -C "$tmp"
  mv "$tmp/package/bin/esbuild" "$esbuild_bin"
  chmod +x "$esbuild_bin"
  rm -rf "$tmp"
fi

echo "==> Asset binaries ready."
