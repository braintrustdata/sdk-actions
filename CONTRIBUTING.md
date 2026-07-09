# Contributing

## Setup

This repo uses [mise](https://mise.jdx.dev) to manage its toolchain. `mise.toml` is the single source of truth for tool versions (Ruby, Python, and `check-jsonschema`) — CI reads it too. With mise installed:

```sh
git clone https://github.com/braintrustdata/sdk-actions && cd sdk-actions
mise install      # ruby, python, check-jsonschema — versions from mise.toml
rake ci           # regenerate + validate everything (actions + the workflow fixtures)
```

## Adding or changing actions

`actions/` is generated output. **Do not edit it by hand** — edit `templates/` and regenerate:

- **A new step:** add `templates/steps/<scope>/<name>.yml.erb` (one or more steps; document its params in a leading `<%# … %>` comment), then compose it with `render_step` where needed.
- **A new action:** add `templates/actions/<path>.yml(.erb)` and run `rake actions:generate`. It appears at `actions/<path>/action.yml`.

After any change, run `rake actions:generate` and commit `templates/` and the regenerated `actions/` **together**. CI (`rake ci`) fails if they drift.

### Versioning

Each action family (the top directory under `templates/actions/`, e.g. `release`) carries a soft-semver in `templates/actions/<family>/VERSION`. `rake actions:generate` stamps it into every generated action's header as a machine-readable comment:

```
# sdk-actions: {"family":"release","version":"1.0.0"}
```

Consumers pin by SHA and diff this stamp across SHAs to judge upgrade risk, so bump `VERSION` when a family's public interface changes and regenerate:

- **major** — breaking (an input removed/renamed, a behavior contract changed)
- **minor** — additive (new action, new optional input)
- **patch** — fix

We publish **no git tags** — SHA pinning is the contract. The version is a comment, not a YAML key (`action.yml` has no native version field), so it never affects schema validation.

### Commands

| command | what it does |
|---|---|
| `rake ci` | what CI runs — regenerate + validate **both** actions and workflow fixtures, fail on drift |
| `rake actions:generate` | render `templates/actions/` → `actions/` |
| `rake actions:validate` | validate generated actions (YAML + GitHub Action schema) |
| `rake actions:ci` | regenerate + validate, then fail if committed `actions/` drifted |
| `rake workflows:generate` | render the golden workflow fixtures under `test/release/*/.github/workflows/` |
| `rake workflows:validate` | validate the fixtures (delegates to `bin/workflow validate`) |
| `rake workflows:ci` | regenerate + validate, then fail if committed fixtures drifted |

## Design

### Why generated, and why flat

GitHub resolves a `./actions/...` path relative to the **calling workflow's** workspace, not the repo the action was fetched from. So a composite action that another repo pins by SHA **cannot** call a sibling action in this repo via `./` — it just won't be found. (And GitHub has no mechanism to guard a *group* of steps, so you can't nest your way around it either.)

The template system sidesteps this by **inlining everything at generation time**: each shipped action is one self-contained `action.yml` with no intra-repo `uses:` — only `run:` steps and external (marketplace) actions. That makes every action safely referenceable by SHA from any repo.

### Layout

```
bin/
  workflow                     # public CLI: generate | validate | compare | update workflows
templates/
  actions/                     # The actions a workflow calls (→ actions/<path>/action.yml)
    release/                   # Language-agnostic actions for releases
    release/lang/<LANG>/       # Language-specific actions for releases go here
  steps/                       # Reusable steps composed INTO actions (never shipped standalone)
    slack/                     # Slack functions
    release/                   # Release functions
    lang/<LANG>/               # Language functions
    release/lang/<LANG>/       # Language-specific release functions
  workflows/                   # Workflow sources (flat, parameterized; rendered by bin/workflow)
    release/<LANG>/{turnkey,custom}.yml.erb
scripts/
  generate.rb                  # Renders templates/actions/ → actions/
  lib/template.rb              # Shared ERB engine (used by generate.rb AND bin/workflow)
  sbom_verify.rb               # Checks a generated SBOM's contents against the package-SBOM spec
  github-action.schema.json    # Vendored SchemaStore schema (used by `rake actions:validate`)
actions/                       # GENERATED — do not edit
test/release/<LANG>/           # bt-publishing-test packages + generated workflow fixtures (.github/workflows/)
Rakefile
```

#### workflows vs. actions vs. steps

- **`templates/workflows/`** — whole workflows, rendered by `bin/workflow` into the target repo. Unlike actions, these are **flat** (no `render_step` composition) so each reads top-to-bottom like the workflow it produces — the canonical reference they're generated from. Each declares its parameters in a leading `<%# params: … -%>` frontmatter block.
- **`templates/actions/`** — entrypoints a workflow `uses:`. Generated flat, with no intra-repo `uses:`; the public, SHA-referenceable surface.
- **`templates/steps/`** — reusable fragments (one or more steps) composed into actions with `<%= render_step('<name>', ...) %>`. A step may compose other steps; steps are never referenced by a workflow directly. Grouped by scope: `release/` (language-agnostic release logic), `lang/<lang>/` (language-specific, release-neutral), and `release/lang/<lang>/` (both).

### How templates work

A `.yml.erb` template is plain YAML plus `render_step` calls; a `.yml` template is copied verbatim. `render_step(name, indent: 4, **locals)`:

- inlines `templates/steps/<name>.yml.erb`;
- exposes keyword args to the step as a `locals` hash, read with `locals.fetch(:x) { default }`;
- **`if:`** is the composing action's one control-flow knob — it's stamped onto *every* top-level step in the fragment (GitHub has no group-level `if:`), so a terminal `on-failure`'s `if: failure()` lands on each of its steps;
- nested calls (a step composing another step) pass `indent: 0`.

#### Conventions

- **Control flow lives in the action.** Compose pure "do" steps, then a terminal failure handler: `… → render_step('on-failure', if: "${{ failure() }}")`.
- **A toggle that enables/disables a whole step uses `if:` at the call site.** e.g. `render_step('lang/js/build', if: "${{ inputs.build == 'true' }}")` and `render_step('release/lang/ruby/sbom', if: "${{ inputs.sbom == 'true' }}")`. Attestation steps (which must not run pre-approval or on dry runs) are gated the same way: `if: "${{ inputs.sbom == 'true' && inputs.dry_run != 'true' }}"`.
- **A condition that changes behavior *within* a step is a shell self-guard, not `if:`.** "Slack configured?", "dry run → skip the push but still preview", "create a GitHub release?" are handled with an early `exit 0` (or a branch) inside the step's own `run:` — keeping the step self-contained and the call site readable.

### How generation works

Two generators share one ERB engine (`scripts/lib/template.rb`, `Templating::Template`):

- **Actions** — `scripts/generate.rb` renders every `templates/actions/**` into `actions/<path>/action.yml`, inlining steps via `render_step`. Invoked by `rake actions:generate`.
- **Workflows** — `bin/workflow` renders a `templates/workflows/` template into the target repo. It reads the template's frontmatter to build `--<param>` flags dynamically (so it stays template-agnostic), stamps a provenance header, and prints the template's `checklist:`. The header — `# sdk-actions: {"template":…,"ref":…,"params":…}` — lets `bin/workflow compare`/`update` re-render the recorded baseline and 3-way-merge upstream changes in (via `git merge-file`) with no re-supplied args.

Both stamp the same `# sdk-actions: {…}` comment via `Templating.metadata_comment` — one machine-readable metadata convention across actions and workflows.

### Validating

`rake ci` is what CI runs: it regenerates and validates both generated surfaces and fails on drift.

#### Actions

`rake actions:ci` regenerates `actions/`, validates each against the vendored GitHub Action schema (`scripts/github-action.schema.json`), and fails if the committed `actions/` drifted from `templates/`.

#### Golden workflow fixtures

`rake workflows:ci` renders each workflow template with bt-publishing-test's params into `test/release/<lang>/.github/workflows/` (a mirror of a real target repo), validates them (delegating to `bin/workflow validate`, which uses `check-jsonschema`'s built-in `vendor.github-workflows` schema), and fails on drift — so a template edit can't land without its rendered output updating, the same discipline as `actions/`. These fixtures never run; only the repo-root `.github/workflows/` does.

#### SBOM contents

`scripts/sbom_verify.rb` checks a generated CycloneDX SBOM against the package-SBOM spec: a `metadata.component` subject with a `version` and an ecosystem-correct `purl`, the attestation triple (`bomFormat` / `specVersion` / `serialNumber`), a `dependencies` graph rooted at the subject, plus caller-supplied `--require` / `--forbid` component names. The turnkey release harnesses run it on the `sbom.json` their PR dry-run already generates, guarding the SBOM generators (`templates/steps/**/sbom*.yml.erb`) against silent content regressions (dev tooling leaking in, a runtime dep dropping, a missing subject/purl). It runs in CI, not something a publisher installs — a plain script, not a `bin/` tool.
