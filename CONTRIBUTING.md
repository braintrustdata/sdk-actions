# Contributing

## Setup

This repo uses [mise](https://mise.jdx.dev) to manage its toolchain. `mise.toml`
is the single source of truth for tool versions (Ruby, Python, and
`check-jsonschema`) — CI reads it too. With mise installed:

```sh
git clone https://github.com/braintrustdata/sdk-actions && cd sdk-actions
mise install      # ruby, python, check-jsonschema — versions from mise.toml
rake generate     # render templates/ → actions/, then validate
```

## Adding or changing actions

`actions/` is generated output. **Do not edit it by hand** — edit `templates/`
and regenerate:

- **A new step:** add `templates/steps/<scope>/<name>.yml.erb` (one or more
  steps; document its params in a leading `<%# … %>` comment), then compose it
  with `render_step` where needed.
- **A new action:** add `templates/actions/<path>.yml(.erb)` and run
  `rake generate`. It appears at `actions/<path>/action.yml`.

After any change, run `rake generate` and commit `templates/` and the regenerated
`actions/` **together**. CI fails if they drift.

### Commands

| command | what it does |
|---|---|
| `rake` / `rake generate` | render `templates/` → `actions/`, then validate (YAML + schema) |
| `rake render` | render only (no validation) |
| `rake validate` | `validate:yaml` + `validate:schema` |
| `rake validate:yaml` | every generated action parses as YAML (stdlib, no extra deps) |
| `rake validate:schema` | every generated action conforms to the GitHub Action schema |
| `rake ci:actions` | what CI runs: regenerate, validate, and fail if `actions/` is out of sync |

## Design

### Why generated, and why flat

GitHub resolves a `./actions/...` path relative to the **calling workflow's**
workspace, not the repo the action was fetched from. So a composite action that
another repo pins by SHA **cannot** call a sibling action in this repo via `./`
— it just won't be found. (And GitHub has no mechanism to guard a *group* of
steps, so you can't nest your way around it either.)

The template system sidesteps this by **inlining everything at generation time**:
each shipped action is one self-contained `action.yml` with no intra-repo
`uses:` — only `run:` steps and external (marketplace) actions. That makes every
action safely referenceable by SHA from any repo.

### Layout

```
templates/
  actions/                     # The actions a workflow calls (→ actions/<path>/action.yml)
    release/                   # Language-agnostic actions for releases
    release/lang/<LANG>/       # Language-specific actions for releases go here
  steps/                       # Reusable steps composed INTO actions (never shipped standalone)
    slack/                     # Slack functions
    release/                   # Release functions
    lang/<LANG>/               # Language functions
    release/lang/<LANG>/       # Language-specific release functions
scripts/
  generate.rb                  # Renders templates/ → actions/
  github-action.schema.json    # Vendored SchemaStore schema (used by `rake validate:schema`)
actions/                       # GENERATED — do not edit
Rakefile
```

#### actions vs. steps

- **`templates/actions/`** — entrypoints a workflow `uses:`. Generated flat, no
  intra-repo `uses:`. These are the public, SHA-referenceable surface.
- **`templates/steps/`** — reusable fragments (one or more steps) composed into
  actions with `<%= render_step('<name>', ...) %>`. A step may compose other
  steps. Steps are *not* referenced by a workflow directly. They're grouped by
  scope: `release/` (language-agnostic release logic), `lang/<lang>/`
  (language-specific, release-neutral), and `release/lang/<lang>/` (both).

### How templates work

A `.yml.erb` template is plain YAML plus `render_step` calls; a `.yml` template is
copied verbatim. `render_step(name, indent: 4, **locals)`:

- inlines `templates/steps/<name>.yml.erb`;
- exposes keyword args to the step as a `locals` hash, read with
  `locals.fetch(:x) { default }`;
- **`if:`** is the composing action's one control-flow knob — it's stamped onto
  *every* top-level step in the fragment (GitHub has no group-level `if:`), so a
  terminal `on-failure`'s `if: failure()` lands on each of its steps;
- nested calls (a step composing another step) pass `indent: 0`.

#### Conventions

- **Control flow lives in the action.** Compose pure "do" steps, then a terminal
  failure handler: `… → render_step('on-failure', if: "${{ failure() }}")`.
- **A toggle that enables/disables a whole step uses `if:` at the call site.**
  e.g. `render_step('lang/js/build', if: "${{ inputs.build == 'true' }}")` and
  `render_step('release/lang/ruby/sbom', if: "${{ inputs.sbom == 'true' }}")`.
  Attestation steps (which must not run pre-approval or on dry runs) are gated the
  same way: `if: "${{ inputs.sbom == 'true' && inputs.dry_run != 'true' }}"`.
- **A condition that changes behavior *within* a step is a shell self-guard, not
  `if:`.** "Slack configured?", "dry run → skip the push but still preview", "create
  a GitHub release?" are handled with an early `exit 0` (or a branch) inside the
  step's own `run:` — keeping the step self-contained and the call site readable.


