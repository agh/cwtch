#!/bin/bash
set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends \
  curl \
  git \
  shellcheck \
  ca-certificates

# Install bats-core
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
/tmp/bats-core/install.sh /usr/local
rm -rf /tmp/bats-core

# Install shfmt
curl -sS https://webi.sh/shfmt | sh

echo "=== Setup complete ==="
bats --version
shellcheck --version
