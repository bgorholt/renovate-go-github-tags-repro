# Results: fork vs. stock

Generated 2026-11-19 12:43 UTC from `logs-*.txt` by `summarize.sh`, one run per variant.

- Stock: `renovate@44.222.5` (npx)
- Fork: `feat/go-scope-github-tags-by-prefix` @ `6a59ba9313`, uncommitted changes in `lib/`: no
- Repository: this one (`go.mod` with `github.com/aws/aws-sdk-go-v2/config` and `.../service/s3`), `--platform=local`, `GITHUB_COM_TOKEN` from `gh auth token`

## Commands

`./reproduce.sh` runs:

```sh
GOPROXY=https://proxy.golang.org ./run.sh fork-google FORK
GOPROXY=direct ./run.sh fork-direct FORK
GOPROXY=https://proxy.golang.org ./run.sh stock-google STOCK
GOPROXY=direct ./run.sh stock-direct STOCK
```

## Results

A run is correct when it finishes, finds both updates and gets the GitHub tag data without any failed or empty GitHub response.

| Variant | Correct | Updates found | Failed GraphQL POSTs | Lookups with empty GraphQL data | GitHub tag errors | Lookup failures | api.github.com requests | Slowest GitHub request | Run duration |
|---|---|---|---|---|---|---|---|---|---|
| fork-google | yes | 2/2 | 0 | 0 | 0 | 0 | 27 | 1.3s | 11.3s |
| fork-direct | yes | 2/2 | 0 | 0 | 0 | 0 | 27 | 1.0s | 12.0s |
| stock-google | no | 2/2 | 5 | 0 | 2 | 0 | 21 | 11.2s | 86.4s |
| stock-direct | no (aborted: external-host-error) | 0/2 | 5 | 0 | 0 | 0 | 5 | 11.1s | 54.3s |

## How the numbers are taken from the logs

- Failed GraphQL POSTs: `DEBUG: POST https://api.github.com/graphql = (code=…)` lines (e.g. GitHub 502/504 timeouts). Renovate logs a request at debug level only when it fails.
- Lookups with empty GraphQL data: `GitHub GraphQL datasource: failed to obtain …` errors, one per affected package (HTTP 200 without usable `data`).
- GitHub tag errors: `Error fetching GitHub Tags for Go module` (proxy path; the versions still come from the proxy, but the GitHub tag timestamps are lost).
- Lookup failures: `Failed to look up go package …` (the package gets no versions at all).
- Aborted: `Repository result: <error>`, e.g. `external-host-error` when Renovate gives up on the repository after GitHub errors; the lookups are then not reported individually.
- api.github.com requests and slowest GitHub request: the `api.github.com` entry of the `HTTP statistics` debug block.
- Run duration: `durationMs` of `Repository finished`; it also includes proxy.golang.org time.
