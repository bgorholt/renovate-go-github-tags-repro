# Reproduction: GitHub GraphQL tag query fails for `aws/aws-sdk-go-v2` submodules

Minimal reproduction for the Renovate pull request that scopes the GitHub tag
lookup of Go modules by submodule prefix:
https://github.com/renovatebot/renovate/pull/48226. Discussion:
https://github.com/renovatebot/renovate/discussions/48043

## Current behavior

For Go modules hosted in `github.com/aws/aws-sdk-go-v2` (about 400 independently
tagged submodules, tens of thousands of tags), the GitHub GraphQL tag query sent
by Renovate is unscoped: `refs(refPrefix:"refs/tags/", orderBy:{field:TAG_COMMIT_DATE})`.
GitHub cannot resolve it in time. It answers HTTP 502/504 after about 10 s,
sometimes HTTP 200 without `data`, and after repeated attempts a 403 secondary
rate limit. Renovate retries with smaller page sizes, so one lookup can cost
up to five ~10 s requests.

The query is reached in two ways, with different consequences:

- With the default `GOPROXY`, through `addGithubTimestamps`: Renovate logs
  `Error fetching GitHub Tags for Go module`. The versions still come from the
  proxy, but the GitHub tag timestamps are lost (the proxy's commit time is used
  instead).
- With `GOPROXY=direct`, through `GithubTagsDatasource`: the GitHub tags are the
  only version source, so the lookup fails (`Failed to look up go package …:
  no-result`) and no update is found.

## Expected behavior

The tag query is scoped to the submodule prefix (`refs(query: "service/s3/")`).
GitHub answers it in about 1 s, both lookups find their updates, and the GitHub
tag timestamps are applied.

## Reproduce

`go.mod` pins old versions of two aws-sdk-go-v2 submodules, so Renovate has
lookups to do. The scripts run Renovate locally (`--platform=local`, no
branches or PRs are created) and need:

- the [`gh` CLI](https://cli.github.com/), logged in (`gh auth login`). The
  token is passed as `GITHUB_COM_TOKEN`. `RENOVATE_TOKEN` does not work here,
  because with `--platform=local` it is not used for github.com lookups, so the
  GraphQL API would be called unauthenticated.
- Node.js, and a checkout of the PR branch, built with
  `pnpm install && pnpm build`.

Run all four variants (fork vs. stock `renovate@44.222.5`, Google proxy vs.
`GOPROXY=direct`) and write [`results.md`](results.md):

```sh
RENOVATE_FORK_DIR=../renovate ./reproduce.sh
```

Or run a single variant; the debug log goes to `logs-<label>.txt`:

```sh
GOPROXY=direct ./run.sh stock-direct STOCK
GOPROXY=direct RENOVATE_FORK_DIR=../renovate ./run.sh fork-direct FORK
```

[`results.md`](results.md) lists the failed GitHub requests, tag errors, lookup
failures, updates found and timings per variant, and explains how each number
is taken from the logs. GitHub's behavior varies from run to run; the
difference between fork and stock does not.

## Query without Renovate

The effect of scoping can be checked directly against the GitHub API with the
`gh` CLI. (The variable is called `prefix` here because `query` is reserved for
the GraphQL document by `gh api graphql`; it is passed to `refs(query: ...)`.)

```sh
q='query($prefix:String){repository(owner:"aws",name:"aws-sdk-go-v2"){refs(refPrefix:"refs/tags/",first:100,query:$prefix,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name}}}}'

# unscoped: GitHub answers with a 5xx error page after about 10 s
time gh api graphql -f query="$q"

# scoped by submodule prefix: HTTP 200 with data in about 1 s
time gh api graphql -f query="$q" -f prefix="config/"
```

Note: GitHub's `refs(query:)` is a substring match on the ref name, not a prefix
match, so `config/` also returns e.g. `service/appconfig/...`. The result is a
superset (969 refs for `config/`, 348 for `service/s3/`, against tens of
thousands unscoped). It is not anchorable: `^config/` returns nothing. Exact
prefix matching therefore still has to happen client-side, which Renovate
already does.
