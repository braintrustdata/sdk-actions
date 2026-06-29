# Design: Release actions v2 — phase taxonomy

**Status:** Proposed (future refactor). **Not blocking** the current v1 adoptions — autoevals
and braintrust-pi-extension ship on the v1 shape (`validate → prepare → notify-pending →
publish` + a consumer `compute-metadata` job). v2 is a deliberate rename/reshape, migrated
later via a SHA bump.

## Why

Onboarding real repos surfaced overloaded responsibilities in v1:

- `validate` *computes* (read-version), *checks*, **and** *builds* — three verbs in one action.
- `prepare` is just release notes — a vague name, and it runs *after* validate.
- Consumers hand-roll a `compute-metadata` job (duplicated across autoevals + pi-extension) to
  derive version/channel from `release_type`.

v2 codifies the fault lines those repos revealed.

## Principle

Provide the **simplest opinionated turn-key by default**, with seams/levers so parts can be
customized, decomposed, and reused. This is evolutionary — we discover where the seams belong
from real repos. The most important thing to get right is the **fault lines**, not the names
(names can change).

**Core invariant — one verb per phase:**

> **configure** derives · **prepare** produces · **validate** judges · **request-approval**
> notifies · **ship** executes.

The moment a phase does another phase's verb, the fault line has leaked. (This is exactly the
v1 problem — `validate` both computing and judging.)

## Pipeline (5 phases)

```
configure → prepare → validate → request-approval → [environment gate] → ship
```

| phase | verb | does | lang? | perms |
|---|---|---|---|---|
| **configure** | derive **facts** (scalars) | version (incl. rc), channel, tag, prev_release, branch, commit_message, on_release_branch, github_release, release_type | lang | **read-only, no token** |
| **prepare** | produce **artifacts/content** | release notes, pr_list (later: SBOM, draft release, reserved version) | lang wraps agnostic | token-scoped (the only privileged pre-step) |
| **validate** | **judge** | toggleable checks (below) | lang | read-only |
| **request-approval** | **notify** (issue the approval request) | Slack pending + job summary | agnostic | none |
| *[environment gate on `ship`]* | — | approval | consumer-side | — |
| **ship** | **execute** | build → publish → release → announce | lang wraps agnostic | contents: write + id-token: write |

### The facts-vs-artifacts cut (`configure` vs `prepare`)

`configure` derives **facts** (scalars from `package.json` + git — all local reads). `prepare`
produces **artifacts/content** (notes now; SBOM / draft release / reserved version later). That
cut coincides with **read-only vs privileged**: artifact generation tends to need a token
(`generate-notes`) or write. Splitting them this way keeps `configure` **unconditionally
read-only** and *dissolves* the "does `generate-notes` need read or write?" question — `prepare`
owns the token, `configure` never touches it. It also fixes `prepare`'s only v1 sin (running
*after* validate); here it sits between configure and validate, and is the abstract, extensible
bucket for any privileged pre-release prep.

### `ship` inner vocabulary (deliberate)

| step | does | lang/agnostic |
|---|---|---|
| `build` | produce the artifact | lang — skippable via `build: false` |
| `publish` | **push** the artifact to the package registry (OIDC + provenance + dist-tag) | lang — pushing only |
| `release` | git tag + GitHub Release (gated by `github_release`; tag ⊆ release) | agnostic |
| `announce` | **declare** the release (Slack / PR comments) | agnostic |

### `notify` vs `announce`

The shared primitive is `slack/send` (the low-level poster). Two distinct semantic wrappers sit
on it:

- **`notify`** (used by `request-approval`): a *request for input/approval*.
- **`announce`** (used by `ship`): a *declaration that the release happened*. The failure path
  also announces.

Reuse the primitive, not the verb.

### Why `request-approval` (not `review`)

The job succeeds the moment the request is *issued*, not when approval is *granted* (the actual
gate is the `environment:` on `ship`). So a green `request-approval ✓` is truthful — and the
next job is visibly parked at the gate. `review ✓` would falsely read as "approved." This name
presumes the gated default; an ungated consumer simply omits the job.

### Toggleable validate checks (opinionated default-on)

Every guard in `validate` is a boolean input, **default `true`**, with an escape hatch — so a
repo owner can opt out of any individual check:

| input | default | check |
|---|---|---|
| `check_tag_unused` | `true` | the release tag doesn't already exist |
| `check_version_unpublished` | `true` | the version isn't already on the registry |
| `check_channel_allowed` | `true` | channel ∈ `allowed_channels` |
| `check_notes_not_blank` | `true` | notes are non-empty (warn on a genuine first/no-PR release) |
| `build` | `true` | the package builds (build-compiles; already shipped in v1) |
| `enforce_release_branch` | `false` | hard-fail off the release branch (otherwise a non-blocking ⚠️) |

Consistent `check_*` boolean convention; the *parameters* those checks use (`allowed_channels`,
`tag_format`, `release_branch`) stay as plain inputs. `on_release_branch` remains a non-blocking
**warn** by default — releasing off-branch is allowed but flagged — and only hard-fails when
`enforce_release_branch: true`.

### `compute-metadata` absorbed into `configure`

`configure` owns the release-model mapping (`release_type` → version/channel/tag/github_release),
with explicit `version`/`channel`/`tag_format` overrides that win. The duplicated consumer
`compute-metadata` glue disappears. The opinionated default model is stable→`latest`+release,
prerelease→`rc`+no-release, rc version `${base}-rc.${n}`; a repo wanting `beta`/`next` or a
different scheme overrides via the explicit inputs.

## Cost / trade-offs

- **5 jobs → ~4 checkouts + 2 builds per release** (configure, prepare, validate, ship each check
  out; request-approval doesn't; validate + ship each build). Acceptable for a manual, infrequent
  release — it's the price of clean separation.
- **Build runs twice** — pre-approval (validate) *and* post-approval (ship) — on purpose: no point
  seeking approval for a build likely to break. The two aren't identical (validate builds the
  committed tree; ship builds the patched/rc tree), and that's fine — validate only proves
  "nothing obviously broken," not the exact artifact.
- **`request-approval` presumes the gate**; ungated consumers omit it.

## Migration

- v1 actions (`validate`/`prepare`/`notify-pending`/`publish`) stay until consumers migrate.
- Build v2 actions alongside; migrate autoevals + pi-extension via a SHA bump + rewire.
- Name deltas: `validate` splits into **`configure`** (derive) + **`validate`** (judge);
  `prepare` becomes the **artifacts** bucket (notes move under it); `notify-pending` →
  **`request-approval`**; `publish` → **`ship`** (umbrella), with `publish` demoted to the inner
  registry-push step.
- The `build: false` toggle (shipped in v1) and the `check_*` toggles are forward-compatible.

## Relationship to build-ownership / provenance

`ship`'s **build ⟷ publish** seam is exactly where the build-ownership design splits it: the
consumer owns the build and hands a packed, attested artifact to a publish-only path
(`pack` / `publish-artifact`). See `docs/design/js-build-ownership-provenance.md`. `build: false`
is the first crack in that seam; v2's `ship` decomposition and the artifact-handoff flow should
be designed together.
