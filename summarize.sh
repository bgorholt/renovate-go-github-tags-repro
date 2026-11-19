#!/usr/bin/env bash
# Summarizes the logs-<variant>.txt files written by reproduce.sh as Markdown.
#
# Usage: RENOVATE_FORK_DIR=../renovate ./summarize.sh >results.md
set -uo pipefail
cd "$(dirname "$0")"

VARIANTS=(fork-google fork-direct stock-google stock-direct)
EXPECTED_UPDATES=2 # github.com/aws/aws-sdk-go-v2/config and .../service/s3
STOCK_VERSION="${STOCK_VERSION:-44.222.5}"

# The reproduce.sh command for variant $1, e.g. fork-google -> GOPROXY=... ./run.sh fork-google FORK.
command_for() {
  local proxy cmd
  case "$1" in
  *-google) proxy=https://proxy.golang.org ;;
  *-direct) proxy=direct ;;
  esac
  case "$1" in
  fork-*) cmd=FORK ;;
  stock-*) cmd=STOCK ;;
  esac
  echo "GOPROXY=$proxy ./run.sh $1 $cmd"
}

# Number of lines in file $2 matching extended regex $1 (0 when none match).
count() {
  grep -cE -- "$1" "$2" || true
}

# Milliseconds as seconds with one decimal, "–" when empty.
fmt_s() {
  if [ -z "$1" ]; then echo "–"; else awk -v ms="$1" 'BEGIN { printf "%.1fs", ms / 1000 }'; fi
}

# Prints "<count> <reqMaxMs>" of the api.github.com entry of the "HTTP statistics" debug block.
github_stats() {
  awk '
    /DEBUG: HTTP statistics/ { stats = 1 }
    stats && /"api\.github\.com": \{/ { gh = 1 }
    gh && /"count":/ { count = $2 + 0 }
    gh && /"reqMaxMs":/ { max = $2 + 0 }
    gh && /\}/ { exit }
    END { print count + 0, max + 0 }
  ' "$1"
}

# Prints durationMs of "Repository finished", empty when missing.
run_duration() {
  awk '
    /INFO: Repository finished/ { finished = 1 }
    finished && /"durationMs":/ { print $2 + 0; exit }
  ' "$1"
}

# Runs git in the fork checkout, "unknown" when it is not available.
git_fork() {
  git -C "${RENOVATE_FORK_DIR:-/nonexistent}" "$@" 2>/dev/null || echo unknown
}

found=0
for variant in "${VARIANTS[@]}"; do
  [ -f "logs-$variant.txt" ] && found=1
done
if [ "$found" -eq 0 ]; then
  echo "No logs-<variant>.txt files found, run ./reproduce.sh first" >&2
  exit 1
fi

if [ -n "$(git_fork status --porcelain -- lib)" ]; then dirty=yes; else dirty=no; fi

cat <<EOF
# Results: fork vs. stock

Generated $(date -u '+%Y-%m-%d %H:%M UTC') from \`logs-*.txt\` by \`summarize.sh\`, one run per variant.

- Stock: \`renovate@$STOCK_VERSION\` (npx)
- Fork: \`$(git_fork rev-parse --abbrev-ref HEAD)\` @ \`$(git_fork rev-parse --short HEAD)\`, uncommitted changes in \`lib/\`: $dirty
- Repository: this one (\`go.mod\` with \`github.com/aws/aws-sdk-go-v2/config\` and \`.../service/s3\`), \`--platform=local\`, \`GITHUB_COM_TOKEN\` from \`gh auth token\`

## Commands

\`./reproduce.sh\` runs:

\`\`\`sh
EOF
for variant in "${VARIANTS[@]}"; do
  command_for "$variant"
done
cat <<'EOF'
```

## Results

A run is correct when it finishes, finds both updates and gets the GitHub tag data without any failed or empty GitHub response.

| Variant | Correct | Updates found | Failed GraphQL POSTs | Lookups with empty GraphQL data | GitHub tag errors | Lookup failures | api.github.com requests | Slowest GitHub request | Run duration |
|---|---|---|---|---|---|---|---|---|---|
EOF

for variant in "${VARIANTS[@]}"; do
  log="logs-$variant.txt"
  [ -f "$log" ] || continue

  graphql_failed=$(count '^DEBUG: POST https://api\.github\.com/graphql = ' "$log")
  graphql_no_data=$(count '"err": \{"message": "GitHub GraphQL datasource: failed to obtain' "$log")
  tag_errors=$(count '^DEBUG: Error fetching GitHub Tags for Go module' "$log")
  lookup_failures=$(count '^DEBUG: Failed to look up go package' "$log")
  repo_result=$(sed -nE 's/^DEBUG: Repository result: ([^,]+),.*/\1/p' "$log" | head -1)
  updates=$(sed -nE 's/^DEBUG: ([0-9]+) flattened updates found.*/\1/p' "$log" | head -1)
  updates=${updates:-0}
  read -r gh_count gh_max_ms <<<"$(github_stats "$log")"
  duration_ms=$(run_duration "$log")

  # Correct: the run finished, found both updates and got the GitHub tag data
  # (tag timestamps) without any failed or empty GitHub response.
  correct=no
  if [ -n "$repo_result" ]; then
    correct="no (aborted: $repo_result)"
  elif [ "$updates" -eq "$EXPECTED_UPDATES" ] &&
    [ "$graphql_failed" -eq 0 ] && [ "$graphql_no_data" -eq 0 ] &&
    [ "$tag_errors" -eq 0 ] && [ "$lookup_failures" -eq 0 ]; then
    correct=yes
  fi

  echo "| $variant | $correct | $updates/$EXPECTED_UPDATES | $graphql_failed | $graphql_no_data | $tag_errors | $lookup_failures | $gh_count | $(fmt_s "$gh_max_ms") | $(fmt_s "$duration_ms") |"
done

cat <<'EOF'

## How the numbers are taken from the logs

- Failed GraphQL POSTs: `DEBUG: POST https://api.github.com/graphql = (code=…)` lines (e.g. GitHub 502/504 timeouts). Renovate logs a request at debug level only when it fails.
- Lookups with empty GraphQL data: `GitHub GraphQL datasource: failed to obtain …` errors, one per affected package (HTTP 200 without usable `data`).
- GitHub tag errors: `Error fetching GitHub Tags for Go module` (proxy path; the versions still come from the proxy, but the GitHub tag timestamps are lost).
- Lookup failures: `Failed to look up go package …` (the package gets no versions at all).
- Aborted: `Repository result: <error>`, e.g. `external-host-error` when Renovate gives up on the repository after GitHub errors; the lookups are then not reported individually.
- api.github.com requests and slowest GitHub request: the `api.github.com` entry of the `HTTP statistics` debug block.
- Run duration: `durationMs` of `Repository finished`; it also includes proxy.golang.org time.
EOF
