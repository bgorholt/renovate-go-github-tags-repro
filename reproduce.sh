#!/bin/sh
# Runs the four variants (fork vs. stock, Google proxy vs. direct) once each
# and writes the comparison to results.md.
#
# Prerequisites: `gh auth login`, and RENOVATE_FORK_DIR pointing to a checkout
# of the PR branch after `pnpm install && pnpm build`.
#
# Usage: RENOVATE_FORK_DIR=../renovate ./reproduce.sh
set -eu
cd "$(dirname "$0")"

: "${RENOVATE_FORK_DIR?set RENOVATE_FORK_DIR to a built checkout of the PR branch}"

# Keep the comparison free of config that is unrelated to the lookup.
unset RENOVATE_MINIMUM_RELEASE_AGE

rm -f logs-*.txt

GOPROXY=https://proxy.golang.org ./run.sh fork-google FORK
GOPROXY=direct ./run.sh fork-direct FORK
GOPROXY=https://proxy.golang.org ./run.sh stock-google STOCK
GOPROXY=direct ./run.sh stock-direct STOCK

./summarize.sh >results.md
echo "Wrote results.md"
