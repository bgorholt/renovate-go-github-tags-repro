#!/bin/sh
# Runs Renovate once against this repository and writes the debug log to
# logs-<label>.txt.
#
# Usage: ./run.sh <label> <STOCK|FORK>
#
#   STOCK  renovate@$STOCK_VERSION from npm (default: 44.222.5)
#   FORK   the build in $RENOVATE_FORK_DIR (a checkout of the PR branch after
#          `pnpm install && pnpm build`)
#
# The GitHub token is taken from `gh auth token`. It must be GITHUB_COM_TOKEN:
# with --platform=local, RENOVATE_TOKEN is not used for github.com lookups.
set -eu
cd "$(dirname "$0")"

LABEL="${1?label is missing, usage: ./run.sh <label> <STOCK|FORK>}"
VARIANT="${2?variant is missing, usage: ./run.sh <label> <STOCK|FORK>}"
STOCK_VERSION="${STOCK_VERSION:-44.222.5}"

case "$VARIANT" in
STOCK)
  set -- npx --yes "renovate@$STOCK_VERSION"
  ;;
FORK)
  : "${RENOVATE_FORK_DIR?set RENOVATE_FORK_DIR to a built checkout of the PR branch}"
  set -- node "$RENOVATE_FORK_DIR/dist/renovate.js"
  ;;
*)
  echo "unknown variant '$VARIANT', expected STOCK or FORK" >&2
  exit 1
  ;;
esac

GITHUB_COM_TOKEN="$(gh auth token)"
export GITHUB_COM_TOKEN

cache_dir="$(mktemp -d)"
log="logs-$LABEL.txt"
echo "== $LABEL: $* (GOPROXY=${GOPROXY:-<unset>}) -> $log"
RENOVATE_CACHE_DIR="$cache_dir" LOG_LEVEL=debug "$@" --platform=local >"$log" 2>&1 || true
rm -rf "$cache_dir"
