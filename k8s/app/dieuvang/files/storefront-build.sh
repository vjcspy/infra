#!/usr/bin/env bash
# Runs inside the dieuvang-storefront-build Job (uid 1000). Builds the unpublished release named in /srv/storefront/NEXT.
# `current` is never touched here.
set -euo pipefail

peak() {
  if [ -r /sys/fs/cgroup/memory.peak ]; then
    echo "build memory.peak=$(cat /sys/fs/cgroup/memory.peak) bytes"
  fi
}
trap peak EXIT

install -d /srv/cache/corepack /srv/cache/corepack-bin
corepack enable --install-directory /srv/cache/corepack-bin pnpm
export PATH="/srv/cache/corepack-bin:$PATH"

id="$(cat /srv/storefront/NEXT)"
cd "/srv/storefront/releases/${id}"

[ "$(pnpm --version)" = "11.24.0" ] || { echo "unexpected pnpm version: $(pnpm --version)"; exit 1; }

# The pnpm store lives on the SAME mount as the releases so installs hard-link instead of copying.
store=/srv/storefront/.pnpm-store
pnpm store prune --store-dir "$store"
pnpm install --frozen-lockfile --store-dir "$store"
pnpm build
