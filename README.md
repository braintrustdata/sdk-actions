# sdk-actions

Shared GitHub actions and workflows for Braintrust SDK repositories.

## Releases

The release actions provide building blocks for implementing release workflows in your own repository. They contain features for security (e.g. trusted publishing, gating, provenance, SBOM, etc) and convenience (e.g. Slack notifications, summaries, automated GitHub release, etc)

These actions can be used in combination to bootstrap quickly or individually to build out a customized release workflow.

### Pre-requisites

- **JS**: needs `packageManager` (or `pnpm_version`) **≥ pnpm 11.8** (for `pnpm sbom`). Bun (custom builds) needs a `bun build … --metafile` build.
- **Python**: a `uv`-buildable project; Python pinned via `.python-version` / `.tool-versions`.
- **Ruby**: needs a `rake build` that emits exactly one `pkg/*.gem`, and `rake lint`.

### Generate a release workflow

Generate one with `bin/workflow`: run it from an sdk-actions checkout and it renders a clean, ready-to-commit release workflow into your repo, then keeps it in sync with upstream.

1. **Pick a template.** *Turnkey* means we build and publish in one gated job; *custom* means you build the artifact yourself and a gated, publish-only job verifies its attestation and ships it (same trusted-publishing + provenance guarantees).

   | Template | When to use |
   |---|---|
   | `release/js/turnkey` | JavaScript, standard build — we build and publish. |
   | `release/js/custom` | JavaScript, you own the build (monorepo, bundler, custom pipeline). |
   | `release/py/turnkey` | Python, standard build — we build and publish. |
   | `release/py/custom` | Python, you own the build. |
   | `release/ruby/turnkey` | Ruby, standard build — we build and publish. |
   | `release/ruby/custom` | Ruby, you own the build. |

2. **Generate it,** writing into your repo:
   ```
   bin/workflow generate release/ruby/turnkey --gem-name braintrust --version-module Braintrust --dest ../braintrust-ruby/.github/workflows/release.yml
   ```
   Each template declares its own parameters; `bin/workflow generate <id> --help` lists them (JS exposes `--channel`/`--access`, Ruby `--version-module`, and so on). The generated workflow pins the actions to `--ref` (defaults to `origin/main`) and carries a provenance header for updates. Run `bin/workflow validate <file>` to schema-check a workflow before committing it.

3. **Follow post-generation instructions** After writing the file, `bin/workflow` prints a checklist: typically creating environments, setting up OIDC trusted publishing on your registry, and some env vars (e.g. for Slack).

### Updating a release workflow

The generated file's provenance header records the template, ref, and params, so pulling in upstream improvements is mechanical:

```
bin/workflow compare release.yml    # preview the diff against a freshly-rendered baseline
bin/workflow update  release.yml    # 3-way merge upstream changes in, keeping your edits
```

`update` re-renders the old and new baselines and applies only the delta, so your customizations survive and only genuine conflicts are flagged. It bumps the pinned sdk-actions ref as part of the merge; whether a bump is breaking is signalled by the soft-semver stamped in each `action.yml` header (a major jump means breaking changes):
```
# sdk-actions: {"family":"release","version":"1.0.0"}
#   machine-readable:  sed -n 's/^# sdk-actions: //p' action.yml | jq -r .version
```

### Available release actions

The workflow is composed from these actions — `bin/workflow generate` wires them for you, but they're listed here for reference. Each is **self-contained** (calls no other action in this repo), so a single SHA pin pulls in everything it needs.

| Action | Purpose |
|---|---|
| `release/lang/<lang>/configure` | Derive release facts (tag, channel, rc suffix, `github_release`) from the version + `release_type` — read-only |
| `release/prepare` | Fetch the PR list and release notes |
| `release/lang/<lang>/validate` | Validate the release (tag / channel / branch / metadata, registry availability) and run a pre-gate build + SBOM generation |
| `release/request-approval` | Post the pre-approval job summary and Slack notification |
| `release/lang/<lang>/build-and-ship` | **Turnkey**: build → sign a CycloneDX SBOM (+ build provenance for Ruby) → publish (OIDC trusted publishing) → create the GitHub release (SBOM attached) → notify |
| `release/lang/js/pack-pnpm` · `pack-bun`, `release/lang/{py,ruby}/pack` | **Custom build**: build + pack + sign SBOM + build provenance in an unprivileged job (no publish credentials) |
| `release/lang/<lang>/ship-package` | **Custom build**: verify the attestation against the downloaded artifact → publish that exact artifact → create the GitHub release → notify |

Inputs and outputs are documented in each `action.yml`. Reference an action by commit SHA:

```yaml
- uses: braintrustdata/sdk-actions/actions/release/prepare@<sha>
```

## Developing

`actions/` is **generated** from `templates/actions/`: never edit it by hand. See [CONTRIBUTING.md](CONTRIBUTING.md) for the template system and tooling.
