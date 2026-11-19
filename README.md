# Reproduction: GitHub GraphQL tag query fails for `aws/aws-sdk-go-v2` submodules

Minimal reproduction for the Renovate pull request that scopes the GitHub tag
lookup of Go modules by submodule prefix. Discussion:
https://github.com/renovatebot/renovate/discussions/48043

## Problem

For Go modules hosted in `github.com/aws/aws-sdk-go-v2` (about 400 independently
tagged submodules, tens of thousands of tags), the GitHub GraphQL tag query sent
by Renovate is unscoped: `refs(refPrefix:"refs/tags/", orderBy:{field:TAG_COMMIT_DATE})`.
GitHub cannot resolve it in time and answers HTTP 502 after about 10 s, or the
request hits a short `hostRules` timeout. Renovate catches the error and logs
`Error fetching GitHub Tags for Go module`, so every affected module costs
about 10 s per run and loses the GitHub release/tag timestamps.

The query is reached in two ways:

- with the default `GOPROXY`, through `addGithubTimestamps`
- with `GOPROXY=direct`, through `GithubTagsDatasource`

## Reproduce

`go.mod` pins old versions of several aws-sdk-go-v2 submodules, so Renovate has
lookups to do. Run Renovate locally. A GitHub token is required, because the
GraphQL API does not work unauthenticated.

```sh
export RENOVATE_TOKEN=<github token>   # no special scopes needed
LOG_LEVEL=debug npx renovate --platform=local
# and the direct path:
GOPROXY=direct LOG_LEVEL=debug npx renovate --platform=local
```

Look for:

```sh
... | grep -E 'api.github.com/graphql|Error fetching GitHub Tags for Go module'
```

Without the change you see `POST https://api.github.com/graphql` failing
(HTTP 502 after about 10 s, or `ETIMEDOUT` with a short host rule timeout) and
`Error fetching GitHub Tags for Go module` for each submodule. With the change
the same lookups finish in about 0.3 to 0.9 s with no errors.

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

Observed on 2026-11-16: unscoped returned the GitHub "Unicorn" error page after
about 12 s, scoped returned the `config/*` tags after about 1 s.
