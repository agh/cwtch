#!/bin/bash
# Provision the cwtch devcontainer.
#
# Every tool is pinned to the version CI uses and verified against a SHA-256
# recorded here, so `make check` in the container is the same check CI runs.
# Nothing comes from apt except the basics: Debian bookworm ships shellcheck
# 0.9.0 and jq 1.6, both older than the versions cwtch's CI and its own
# toolchain gate require.

set -euo pipefail

SHELLCHECK_VERSION="0.11.0"
SHFMT_VERSION="3.14.1"
ACTIONLINT_VERSION="1.7.12"
YQ_VERSION="4.53.6"
JQ_VERSION="1.8.2"
BATS_VERSION="1.14.0"

ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
  amd64)
    SC_ARCH="x86_64" GO_ARCH="amd64"
    SC_SHA256="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
    SHFMT_SHA256="76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf"
    ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
    YQ_SHA256="c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385"
    JQ_SHA256="b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"
    ;;
  arm64)
    SC_ARCH="aarch64" GO_ARCH="arm64"
    SC_SHA256="12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588"
    SHFMT_SHA256="5f2db09dae91fca848f7adbdd014632e921a383863a2ad7e0450ad3aba0c6489"
    ACTIONLINT_SHA256="325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
    YQ_SHA256="88a1016bc1d657375a35864e4f44b6f333df8ff97b559f51bba0adcb2169df09"
    JQ_SHA256="8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309"
    ;;
  *)
    printf 'unsupported architecture: %s\n' "${ARCH}" >&2
    exit 1
    ;;
esac

fetch() { curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors -o "$1" "$2"; }
verify() { printf '%s  %s\n' "$2" "$1" | sha256sum -c -; }

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git make xz-utils

fetch /tmp/sc.tar.xz \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${SC_ARCH}.tar.xz"
verify /tmp/sc.tar.xz "${SC_SHA256}"
tar -xJf /tmp/sc.tar.xz -C /tmp
install -m 0755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
rm -rf /tmp/sc.tar.xz "/tmp/shellcheck-v${SHELLCHECK_VERSION}"

fetch /tmp/shfmt \
  "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${GO_ARCH}"
verify /tmp/shfmt "${SHFMT_SHA256}"
install -m 0755 /tmp/shfmt /usr/local/bin/shfmt
rm -f /tmp/shfmt

fetch /tmp/actionlint.tar.gz \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${GO_ARCH}.tar.gz"
verify /tmp/actionlint.tar.gz "${ACTIONLINT_SHA256}"
tar -xzf /tmp/actionlint.tar.gz -C /tmp actionlint
install -m 0755 /tmp/actionlint /usr/local/bin/actionlint
rm -f /tmp/actionlint.tar.gz /tmp/actionlint

# jq and yq are hard runtime dependencies of cwtch, and the test suite uses the
# real binaries rather than mocks.
fetch /tmp/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${GO_ARCH}"
verify /tmp/jq "${JQ_SHA256}"
install -m 0755 /tmp/jq /usr/local/bin/jq
rm -f /tmp/jq

fetch /tmp/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${GO_ARCH}"
verify /tmp/yq "${YQ_SHA256}"
install -m 0755 /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq

git clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
  https://github.com/bats-core/bats-core.git /tmp/bats-core
/tmp/bats-core/install.sh /usr/local
rm -rf /tmp/bats-core

printf '=== Setup complete ===\n'
bats --version
shellcheck --version | sed -n '2p'
shfmt --version
actionlint --version | head -1
yq --version
jq --version
