# sdk-actions

Shared GitHub actions and workflows for Braintrust SDK repositories.

## Releases

**Copy the canonical release workflow template** from `.github/workflows/release-<LANG>.yml` and adapt it for your repository. Using it as an upstream source will enable the implemented release process to receive improvements in the future.

### Pre-requisites

- **JS**: needs `packageManager` (or `pnpm_version`) **≥ pnpm 11.8** (for `pnpm sbom`)
- **Ruby**: needs a `rake build` that emits exactly one `pkg/*.gem`.

### Adopting the release workflow

1. **Copy the canonical template** for your language into your repo's
   `.github/workflows/`:
      - [`release-js.yml`](.github/workflows/release-js.yml)
      - [`release-py.yml`](.github/workflows/release-py.yml)
      - [`release-ruby.yml`](.github/workflows/release-ruby.yml)
2. **Configure an OIDC trusted publisher** on your registry (npm / PyPI / RubyGems) for this repo + workflow (and environment, if gated) — publishing and attestation use it, no long-lived tokens. (Adapting an existing workflow rather than copying? Also grant the publish job `attestations: write`.)
3. **Adapt the marked sections** — version source, package/gem name, working directory, and so on; the template's comments flag exactly what changes.
4. **Record the upstream version you based it on** — the sdk-actions ref (commit SHA or tag) your copy was adapted from, e.g. in a header comment. Tracking it lets you (or an agent) diff your copy against a newer upstream template and sync changes deliberately as this repo evolves.
5. **Bump the pinned SHA** to pick up action changes. Because each action is self-contained, one SHA bump pulls in the whole updated chain.

### Available release actions

The release workflow is composed from these actions. You normally get them via
the template, but they're listed here as a reference for customizing it — each is
**self-contained** (calls no other action in this repo), so a single SHA pin
pulls in everything it needs.

| Action | Purpose |
|---|---|
| `release/lang/ruby/publish` | Build the gem, generate + sign a CycloneDX SBOM and SLSA build provenance, push to RubyGems (OIDC trusted publishing), create the GitHub release (SBOM attached), and notify |
| `release/lang/ruby/validate` | Check out the SHA, set up Ruby, read the version, validate the release (tag/branch/metadata), lint + build + generate SBOM (pre-gate check) |
| `release/lang/js/publish` | Build, generate + sign a CycloneDX SBOM, publish to npm (OIDC trusted publishing + provenance), create the GitHub release (SBOM attached), and notify |
| `release/lang/js/validate` | Check out the SHA, set up Node + package manager, read the version, validate the release (channel/tag/branch/metadata), build + generate SBOM (pre-gate check) |
| `release/lang/py/publish` | Build, generate + sign a CycloneDX SBOM, publish to PyPI (OIDC trusted publishing + PEP 740 attestations), create the GitHub release (SBOM attached), and notify |
| `release/lang/py/validate` | Check out the SHA, set up uv + Python, read the version, validate the release (tag/branch/metadata, PyPI availability), build + generate SBOM (pre-gate check) |
| `release/notify-pending` | Post the pre-approval job summary and Slack notification |
| `release/prepare` | Fetch the PR list and release notes |

Inputs and outputs are documented in each `action.yml`. Reference an action by
commit SHA:

```yaml
- uses: braintrustdata/sdk-actions/actions/release/prepare@<sha>
```

## Developing

`actions/` is **generated** from `templates/` — never edit it by hand. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the template system and workflow.
