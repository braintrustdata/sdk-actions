# Design: Release actions v2 — taxonomy reshape + custom builds

**Status:** Approved plan (implementation in progress on `release_actions_v2`).

> Milestone 1 (SBOM, all languages) shipped in [#60](https://github.com/braintrustdata/sdk-actions/pull/60):
> signed CycloneDX SBOMs bound to the published artifact, attested before publish, for js/py/ruby.
> This is Milestone 2. Roadmap: **SBOM ✓ → v2 (this) → workflow-generation** (built later on the
> settled v2 names).

## Why

Onboarding real repos surfaced two problems v1 can't serve cleanly:

1. **Overloaded phases.** v1 `validate` *computes* (read-version), *checks*, **and** *builds* — three
   verbs in one action; `prepare` is just release notes but is vaguely named and runs *after* validate;
   consumers hand-roll a duplicated `compute-metadata` job to derive version/channel from a
   `release_type`. The fault lines are in the wrong places.
2. **No custom-build path.** js-sdk (turbo/tsup/`workspace:` monorepo), the opencode plugin (Bun), and
   lingua's npm packages build their own artifact. v1 only offers a turnkey build-and-publish in one
   job — there's no way for a consumer to build their own artifact and still get **all** the security
   characteristics (trusted publishing, approval gate, provenance, signed SBOM, attestation).

v2 reshapes the pipeline into one-verb-per-phase and adds a **custom-build ("build-ownership") path**
that keeps every security guarantee turnkey — *especially* for repos that customize. Breaking changes
are acceptable: all consumers pin our actions by SHA and stay on v1 until they migrate deliberately.

**Rollout targets:** Ruby / Python / JS SDKs, pi-extension, autoevals, braintrust-opencode-plugin,
lingua.

## Principles

- Provide the **simplest opinionated turn-key by default**, with seams/levers so parts can be
  customized, decomposed, and reused. Get the **fault lines** right; names can change.
- **Trusted/official publishers only** for every tool/action (GitHub, npm/pnpm, PyPA/astral, RubyGems,
  OWASP CycloneDX); handroll natively where no trusted-official option exists. Less is more unless it
  meaningfully compromises security.
- **Post-publish attestation is unacceptable** — never leave a published version without its
  signatures. Attest *before* publish, everywhere.

---

## The v2 pipeline (taxonomy)

```
configure → prepare → validate → request-approval → [environment gate] → ship
```

**Core invariant — one verb per phase:** *configure* derives · *prepare* produces · *validate* judges ·
*request-approval* notifies · *ship* executes. The moment a phase does another phase's verb, the fault
line has leaked (exactly the v1 problem — `validate` both computing and judging).

| phase | verb | does | perms |
|---|---|---|---|
| **configure** | derive **facts** (scalars) | reads base version; derives channel, tag, rc-suffix, prev_release, branch, on_release_branch, github_release from `release_type` + overrides | **read-only, no token** |
| **prepare** | produce **content** | release notes, pr_list (the privileged pre-step — owns the token) | token-scoped |
| **validate** | **judge** | toggleable `check_*` guards (below) | read-only |
| **request-approval** | **notify** | Slack pending + job summary; green the moment the request is *issued* | none |
| *[gate on ship]* | — | approval (`environment:`) | consumer-side |
| **ship** | **execute** | build → **attest** → publish → release → announce | contents + id-token + attestations: write |

### SBOM-informed corrections to the original taxonomy

The first draft of this doc predated the SBOM milestone. Three corrections it taught us:

1. **SBOM is not a `prepare` artifact.** It must be generated **and signed in `ship`**, bound to the
   *exact published artifact* (attest-before-publish), as Milestone 1 built it. `prepare` produces
   notes/pr_list only.
2. **`ship` has an `attest` step** (`build → attest → publish → release → announce`). `attest` is the
   one verb that produces + signs the SBOM and, where needed, build-provenance.
3. **Custom-build actions are `build-and-ship` (turnkey) + `ship-package` (custom, prebuilt), with
   `pack` + `validate-package` on the build side** — superseding the earlier `pack`/`publish-artifact`/
   `validate-artifact` sketch.

### The facts-vs-artifacts cut (`configure` vs `prepare`)

`configure` derives **facts** (scalars from `package.json`/version file + git — all local reads).
`prepare` produces **content** (notes now; a draft release / reserved version later). That cut
coincides with **read-only vs privileged**: content generation tends to need a token
(`generate-notes`). Splitting this way keeps `configure` **unconditionally read-only** and dissolves
the "does `generate-notes` need read or write?" question — `prepare` owns the token, `configure` never
touches it. It also fixes `prepare`'s v1 sin (running *after* validate): here it sits between configure
and validate as the extensible bucket for any privileged pre-release prep.

### `configure` and versioning — version is *read*, not owned

`configure` **reads** the base version (already committed at the released SHA by the consumer's bump PR
or changesets) and **derives** the release metadata around it (channel, tag, rc-suffix `${base}-rc.${n}`,
github_release) from `release_type` + explicit overrides. It **never decides the version bump** — that
belongs to consumer tooling (changesets / `version.py` / bump PR). This absorbs the duplicated
`compute-metadata` glue while keeping `configure` read-only. Changeset repos, which compute the full
version themselves, just have `configure` read it. Default model: stable→`latest`+release,
prerelease→`rc`+no-release; a repo wanting `beta`/`next` overrides via explicit inputs. For custom
builds the version is already committed at the released SHA, so the build job builds the correct
version — no runtime patching (except the `bt-publishing-test` run-number test quirk).

### `ship` inner vocabulary

| step | does | lang/agnostic |
|---|---|---|
| `build` | produce the artifact | lang — skippable via `build: false` |
| `attest` | generate + sign the SBOM (and build-provenance where needed), bound to the artifact | lang wraps agnostic |
| `publish` | **push** the artifact to the registry (OIDC + provenance + dist-tag) | lang — pushing only |
| `release` | git tag + GitHub Release (gated by `github_release`; tag ⊆ release) | agnostic |
| `announce` | **declare** the release (Slack / PR comments) | agnostic |

**`attest` payload by context.** SBOM always. **build-provenance** is added wherever (a) the registry
mints no native provenance (**Ruby**, always), or (b) a cross-job handoff must be verified before publish
(**every custom build**, all languages — `ship-package` verifies the build-provenance against the
downloaded artifact). So: turnkey JS/Py = SBOM only (npm `--provenance` / PyPI PEP 740 native); turnkey
Ruby = SBOM + build-provenance; **custom js/py/ruby = SBOM + build-provenance**. Native registry
provenance (npm `--provenance`, PEP 740) is *also* still emitted at publish in the custom path — confirmed
for npm in the spike.

### `notify` vs `announce`

The shared primitive is `slack/send`. Two semantic wrappers sit on it: **`notify`** (used by
`request-approval`) is a *request for input/approval*; **`announce`** (used by `ship`, including the
failure path) is a *declaration that the release happened*. Reuse the primitive, not the verb.

### Why `request-approval` (not `review`)

The job succeeds the moment the request is *issued*, not when approval is *granted* (the actual gate is
the `environment:` on `ship`). A green `request-approval ✓` is truthful, and the next job is visibly
parked at the gate; `review ✓` would falsely read as "approved." The name presumes the gated default;
an ungated consumer simply omits the job.

### Toggleable validate checks (opinionated default-on)

Every guard is a boolean input, **default `true`**, with an escape hatch:

| input | default | check |
|---|---|---|
| `check_tag_unused` | `true` | the release tag doesn't already exist |
| `check_version_unpublished` | `true` | the version isn't already on the registry |
| `check_channel_allowed` | `true` | channel ∈ `allowed_channels` |
| `check_notes_not_blank` | `true` | notes are non-empty (warn on a genuine first/no-PR release) |
| `build` | `true` | the package builds (already shipped in v1) |
| `enforce_release_branch` | `false` | hard-fail off the release branch (otherwise a non-blocking ⚠️) |

The *parameters* those checks use (`allowed_channels`, `tag_format`, `release_branch`) stay plain
inputs. `on_release_branch` is a non-blocking **warn** by default, hard-failing only when
`enforce_release_branch: true`.

---

## One pipeline, two cuts

The release pipeline is **artifact-centric and identical across languages and shapes**:

```
build → pack → attest → publish(the EXACT packed artifact) → release → announce
```

- **`pack`** = produce the exact publishable artifact file(s). It already exists in every turnkey path:
  JS `pnpm pack` → `.tgz`, Python `uv build` → `dist/*`, Ruby `gem build` → `*.gem`.
- **`attest`** = SBOM (+ build-provenance) bound to *that* artifact.
- **`publish`** = push the artifact that was attested, so published==attested holds:
  - **Turnkey JS** keeps `pnpm publish` (from the tree) — the spike proved `pnpm pack` == `pnpm
    publish`-from-dir byte-for-byte, so the attested pack equals the upload, *and* staying on pnpm avoids
    the `EBADDEVENGINES` a direct `npm publish` trips on pnpm-strict consumers.
  - **Custom JS** (`ship-package`) has no source tree — it must publish the exact file: `npm publish
    ./x.tgz` (note the `./` — a bare `dl/x.tgz` is read as a GitHub shorthand).
  - **py/ruby** upload the exact files natively in both shapes (`uv publish dist/*` / `gem push x.gem`),
    no re-pack, so published==attested is automatic.

**Turnkey and custom are the same pipeline cut at different job boundaries** — turnkey is custom
un-split. Every language wears this shape, so adding a language's custom path is *drawing the cut*, not
a new design.

These are the two workflow shapes a consumer builds. **The gate is a job-level `environment: publish`;
"where's the gate" = which job carries it.**

### Turnkey (default) — the whole pipeline in one gated job

The **gate is `environment: publish` on `build-and-ship`**, so every pipeline step runs *after* approval.
(`validate` runs a throwaway build pre-gate, so you never approve an obviously-broken build — the "build
runs twice" trade-off.) The simplest default: py/ruby SDKs, autoevals, pi-extension. `build: false`
skips the build step for a consumer who supplies a prebuilt tree.

```
[configure] ─► [prepare] ─► [validate] ─► [request-approval] ═══ GATE ═══► [build-and-ship]
 read facts     notes/PRs    checks +      posts "pending"      approval     build→pack→attest→
 read-only      token        builds-to-    no creds             required     publish→release→announce
                             check                                           env: publish
```

### Custom build ("build-ownership") — the consumer owns a non-standard build

For a consumer whose build our turnkey `build` step can't produce (js-sdk turbo/tsup/`workspace:`
monorepo, opencode Bun, lingua npm, or any bespoke build). The pipeline is **cut after `attest`**: the
**gate is `environment: publish` on `ship-package`**, so `build+pack+attest` happen *before* the gate in
a job that holds attestation creds but **no publish creds**; only `verify+publish+release+announce` run
after approval.

```
[configure]─►[prepare]─►[validate]─►[pack]────────────►[request-approval]═══GATE═══►[ship-package]
 read facts   notes/PRs   checks      build+pack+         posts "pending"   approval   download→verify→
                                      attest+upload       no creds          required   publish→release→
                                      id-token+attest:                                 announce
                                      write, NO publish                                env: publish
                                      creds
```

**The only difference is gate position:** turnkey gates *before* build (all steps post-approval); custom
gates *after* attest (build+attest pre-approval in a creds-less job, publish post-approval).

**What the `lang/<lang>/` actions resolve to** (same DAG for js/py/ruby — only these differ):

| step | **js** | **py** | **ruby** |
|---|---|---|---|
| `configure`/`validate` read version from | `package.json` | `version.py` / `pyproject` | `version.rb` |
| `pack` produces | `pnpm pack` → `.tgz` | `uv build` → `dist/*` | `gem build` → `*.gem` |
| `attest` | SBOM + build-prov. | SBOM + build-prov. | SBOM + build-prov. |
| `publish` (the exact file) | `npm publish ./x.tgz` | `uv publish dist/*` | `gem push x.gem` |
| native registry provenance | npm `--provenance` | PyPI PEP 740 | (none → our build-prov.) |

**Tamper-evidence:** attest-*before*-upload (build job), verify-*after*-download (ship job). Any
tampering in transit changes the digest → `gh attestation verify` fails → publish rejected. The
consumer's untrusted build code never runs in the job holding publish credentials.

**Retry semantics — the two-job split is deliberate.** On the common failure (publish flakes),
**re-run the failed `ship-package` job only**: it re-downloads the same artifact, re-verifies the
existing attestation, and re-publishes — **no re-attestation**. Guidance: *on failure, re-run failed
jobs; don't re-dispatch* (a fresh dispatch re-builds + re-attests). Turnkey is actually worse here — one
job means a publish flake reruns build+attest too.

**Pre-gate attestation is accepted as benign.** Attestation must live in the trusted build job (moving
it to the publish job is a security downgrade), and the build job is pre-gate → a rejected release
leaves a "dangling" attestation. It is a *true* statement about a built-but-unpublished artifact,
permanent in the Rekor transparency log, rare (only rejected releases), and harmless — not multiplied
by publish retries (see retry semantics).

### Custom-build scope & ownership

- **All three ecosystems.** `pack` / `validate-package` / `ship-package` exist under
  `release/lang/{js,py,ruby}/`. The shape is uniform (above); per-ecosystem it differs only in the
  pack/publish mechanics — and py/ruby are *simpler* than JS, because `twine`/`uv publish`/`gem push`
  upload the exact files (no re-pack) and Ruby's turnkey Path C is already this shape un-split. The
  in-scope builds that *need* custom today are all JS (js-sdk turbo/tsup/`workspace:` monorepo, opencode
  Bun, lingua npm); py/ruby targets build with standard tooling, but we ship their custom path anyway so
  turnkey and custom are structurally identical and a consumer with a bespoke build (e.g. maturin wheels)
  can adopt it with **no new machinery**.
- **We own the custom SBOM.** Don't push SBOM responsibility onto consumers — provide an SBOM generator
  for every toolchain we roll out: **pnpm** (js-sdk/autoevals), **Bun** (opencode); py/ruby custom reuse
  the turnkey generators (`cyclonedx-py`, the Bundler-lockfile generator).
- **Publish-only OIDC per registry.** Proven for **npm** (spike). **PyPI** trusted publishing and
  **RubyGems** (already OIDC via Path C) must be confirmed e2e the same cheap way before rollout — very
  low risk (OIDC claims don't depend on building), but verified, not assumed.

### Monorepo publishing — per-package, independent workflows

A monorepo is **N independent single-package workflows** (one per publishable package), dispatched
separately — identical to separate repos. **No monorepo-special machinery**, no baked-in matrix.
Simultaneous multi-publish is a rare consumer opt-in (their own `matrix`). `workspace:*` deps still
resolve — `pnpm pack` rewrites them to the currently-published sibling version; a lockstep breaking
change is publish-in-order, not a batch. workflow-generation will emit one workflow per package.

---

## Cost / trade-offs

- **5 jobs → ~4 checkouts + 2 builds per release** (configure/prepare/validate/ship each check out;
  request-approval doesn't; validate + ship each build). Acceptable for a manual, infrequent release —
  the price of clean separation.
- **Build runs twice** (validate pre-approval, ship post-approval) on purpose: no point seeking
  approval for a build likely to break. The two aren't identical (validate builds the committed tree;
  ship builds the patched/rc tree) — validate only proves "nothing obviously broken."
- **`request-approval` presumes the gate;** ungated consumers omit it.

---

## Action / step tree — deltas from v1

Current v1 (`templates/actions/release/`): `prepare` (agnostic), `notify-pending` (agnostic), per-language
`lang/<lang>/{validate,publish}`.

**Rename / split (turnkey core):**
- `lang/<lang>/validate` **splits** into **`configure`** (derive facts — new; absorbs read-version + the
  `release_type`→channel/tag mapping) + **`validate`** (judge only — the `check_*` toggles; keeps its
  pre-gate build).
- `prepare` stays the content bucket (notes/pr_list); repositioned **between configure and validate**.
- `notify-pending` → **`request-approval`** (agnostic; behavior unchanged, name change).
- `lang/<lang>/publish` → **`lang/<lang>/build-and-ship`** (turnkey umbrella; inner steps
  `build → attest → publish → release → announce`). The Milestone-1 SBOM/attest steps slot into `attest`.

**New (custom-build, all three ecosystems):**
- `lang/<lang>/pack` — produce the exact publishable artifact + generate SBOM + attest SBOM +
  attest-build-provenance (upload handled by the workflow). Maps to `pnpm pack` (js) / `uv build` (py) /
  `gem build` (ruby).
- `lang/<lang>/validate-package` — sanity-check the packed artifact (name/version/contents).
- `lang/<lang>/ship-package` — download + `gh attestation verify` + publish the exact file + release +
  announce (publish-only; no build, no attest).

**New steps:** `steps/release/lang/js/sbom-bun.yml.erb` (Bun SBOM generator, for opencode). Reuse the
per-language `sbom` steps and the agnostic `attest-sbom` / `attest-provenance`. **Turnkey and custom share
the `pack` / `attest` / `publish` steps** — turnkey composes them in one job; custom splits them across the
build and ship jobs. That shared composition is what keeps the two shapes identical.

All actions are generated via `scripts/generate.rb` (`render_step`/`with_if`/`indent_lines`);
`rake generate` regenerates and `rake ci:actions` guards drift. Never hand-edit `actions/`.

---

## Sequencing

0. **Spike (blocking) — ✅ DONE, all confirmed** (against `@braintrust/bt-publishing-test`, 2026-07-06):
   (a) digest match — `pnpm pack` is deterministic, its bytes == `pnpm publish` upload, and `workspace:*`
   is rewritten to the concrete version inside the tarball (proven locally); (b) attestation (SBOM +
   build-provenance) survives upload→download and verifies in a separate job; (c) publish-only OIDC —
   a job that never built the artifact authenticates tokenlessly and publishes; the published digest
   == the attested digest exactly; (d) re-running only the `ship` job reuses build/artifact/attestation
   with fresh OIDC and **no re-attestation** (build does not re-run); (e) tampering the tarball makes
   `gh attestation verify` 404 on the new digest → fails closed → publish skipped.
   **Findings folded into the design:**
   - `npm publish <prebuilt.tgz> --provenance` **works** — so custom JS carries npm-native provenance
     *and* our SBOM + build-provenance attestation (resolves the `--provenance` question in "attest").
   - `ship-package` must publish via a **path npm won't read as a GitHub shorthand** — prefix `./`
     (bare `dl/x.tgz` is parsed as `owner/repo` and npm tries `git ls-remote`).
   - `pack` must write to a **clean destination** (`--pack-destination` outside the package) — a stray
     `.tgz` in the package dir gets packed into the next tarball.
1. **Turnkey taxonomy reshape** — `configure` split, `validate` slim + `check_*` toggles, `prepare`
   reposition, `notify-pending`→`request-approval`, `publish`→`build-and-ship`. Migrate the reference
   workflows; keep v1 actions alongside.
2. **Custom-build (all three)** — `pack` + `validate-package` + `ship-package` under
   `release/lang/{js,py,ruby}/`, sharing the turnkey `pack`/`attest`/`publish` steps + the Bun SBOM
   generator + a build-ownership reference workflow per ecosystem. Order: JS (proven) → py → ruby, each
   with one confirming e2e run (chiefly publish-only OIDC on PyPI / RubyGems).
3. **Docs + migration** — this doc; the v1→v2 name-delta migration note.

---

## Verification

1. **Regen/drift:** `rake generate` → `rake ci:actions` (`git diff --exit-code actions/` clean).
2. **Schema:** `rake validate` (YAML + `check-jsonschema`).
3. **Turnkey e2e:** PR dry-runs + one real `workflow_dispatch` per language on `bt-publishing-test`;
   `gh attestation verify` confirms a signed SBOM (+ provenance where applicable) bound to the published
   artifact — parity with Milestone 1.
4. **Custom-build e2e (per ecosystem):** real dispatch through build job → gate → `ship-package` for
   **js, then py, then ruby**; confirm the published digest == the attested digest, `gh attestation
   verify` passes post-download, and re-running the failed `ship-package` job re-publishes without
   re-attesting. JS is proven (spike); py/ruby each need one confirming run — chiefly to verify
   **publish-only OIDC** against PyPI / RubyGems (very low risk; OIDC claims don't depend on building).
5. **Tamper test:** corrupt the uploaded artifact → `ship-package`'s verify must fail closed (proven on JS).

---

## Migration

- v1 actions (`validate`/`prepare`/`notify-pending`/`publish`) stay until consumers migrate.
- Build v2 actions alongside; migrate autoevals + pi-extension via a SHA bump + rewire.
- **Name deltas:** `validate` splits into **`configure`** + **`validate`**; `prepare` becomes the
  **content** bucket; `notify-pending` → **`request-approval`**; `publish` → **`build-and-ship`** (with
  `publish` demoted to the inner registry-push step); custom builds add **`pack`** / **`validate-package`**
  / **`ship-package`**.
- **pi-extension** is SHA-pinned to v1, so it keeps working untouched; migrate later, no rush.
- **Dual-registry parity** (autoevals) is consumer-owned: run two independent per-package workflows
  (npm + PyPI); the JS↔Py parity check stays the consumer's gate (`check_version_sync.py`).
- The `build: false` toggle and the `check_*` toggles are forward-compatible.

## Out of scope (follow-ons)

- **workflow-generation** — the next milestone, on settled v2 names.
- **Python-native custom builds** (e.g. maturin wheels) — the `pack`/`ship-package` *machinery* ships for
  all three ecosystems, so a maturin consumer wires in with no new actions; a maturin-specific SBOM
  generator (if the reused `cyclonedx-py` proves insufficient for compiled wheels) is the only possible
  additive follow-on.
- **Action version bumps** — a separate focused PR (setup-uv, pnpm/action-setup, checkout,
  ruby/setup-ruby majors + the automation-workflow checkout upgrades); consider enabling Dependabot for
  github-actions.

See also `docs/design/js-build-ownership-provenance.md` for the build-ownership background.
