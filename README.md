# sdk-actions

Shared GitHub actions and workflows for Braintrust SDK repositories.

## Releases

The release actions provide building blocks for implementing release workflows in your own repository. They contain features for security (e.g. trusted publishing, gating, provenance, SBOM, etc) and convenience (e.g. Slack notifications, summaries, automated GitHub release, etc)

These actions can be used in combination to bootstrap quickly or individually to build out a customized release workflow.

### Pre-requisites

- **JS**: needs `packageManager` (or `pnpm_version`) **≥ pnpm 11.8** (for `pnpm sbom`). Bun (custom builds) needs a `bun build … --metafile` build.
- **Python**: a `uv`-buildable project; Python pinned via `.python-version` / `.tool-versions`.
- **Ruby**: needs a `rake build` that emits exactly one `pkg/*.gem`, and `rake lint`.

### Adopting the release workflow

1. **Pick a shape**:
   - **Turnkey** builds and publishes for you in one gated job. Recommended for most applications.
   - **Custom build** lets you build your own artifact and hands it to a publish-only job that verifies and ships it, keeping the same security guarantees.

2. **Copy the canonical template** for your language + shape into your repo's
   `.github/workflows/`:

   | Language   | Turnkey                                                  | Custom build                                                           |
   | ---------- | -------------------------------------------------------- | ---------------------------------------------------------------------- |
   | JavaScript | [`release-js.yml`](.github/workflows/release-js.yml)     | [`release-js-custom.yml`](.github/workflows/release-js-custom.yml)     |
   | Python     | [`release-py.yml`](.github/workflows/release-py.yml)     | [`release-py-custom.yml`](.github/workflows/release-py-custom.yml)     |
   | Ruby       | [`release-ruby.yml`](.github/workflows/release-ruby.yml) | [`release-ruby-custom.yml`](.github/workflows/release-ruby-custom.yml) |

3. **Configure an OIDC trusted publisher** on your registry (npm / PyPI / RubyGems) for this repo + workflow filename (and environment, if gated) — publishing and attestation use it, no long-lived tokens.
4. **Adapt the template to your package.** The template demonstrates an actual package deploy and includes glue to make that function: other applications will want to remove that glue, so review the whole file before adapting. The comments flag what typically changes (version source, package/gem name, working directory), but they aren't exhaustive.
5. **Record the upstream SHA you based it on** Copy the sdk-actions commit your copy of the workflow was adapted from, e.g. in a header comment. Tracking it lets you (or an agent) diff your copy against a newer upstream template and sync changes deliberately as this repo evolves.

### Updating a release workflow

Actions are pinned by commit SHA. Bump the SHA to pick up changes. To judge whether a bump is safe, compare the version stamped into each `action.yml` header between the old and new SHA:

```yaml
# sdk-actions: {"family":"release","version":"1.0.0"}

# Tip: this is machine-readable:
#   sed -n 's/^# sdk-actions: //p' action.yml | jq -r .version   # → 1.0.0
```

These actions follow semantic versioning: expect breaking changes when the major version updates.

### Manifest-driven JavaScript tarball releases

For monorepos that own their own build and package selection, create a manifest
plus prebuilt npm tarballs and SBOMs in the source repository, attest those
artifacts before upload, then call `release/lang/js/publish-tarballs` from the
gated publish job. The action verifies the downloaded tarball attestations,
then publishes the exact tarballs to npmjs in manifest order. After the source
repository pushes its package tags, call `release/create-package-releases` with
`sboms` to attach the per-package SBOM assets.

The manifest passed between build and publish jobs is JSON in this shape:

```json
{
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "packages": [
    {
      "name": "@scope/package",
      "version": "1.2.3",
      "dir": "packages/package",
      "tag": "@scope/package@1.2.3",
      "tarball_asset": "scope-package-1.2.3.tgz",
      "sbom_asset": "scope-package-1.2.3.sbom.json",
      "release_title": "@scope/package@1.2.3",
      "release_body": "Markdown release notes",
      "channel": "latest",
      "provenance": true
    }
  ]
}
```

`name` and `version` are required. `packages` must already be in publish order.
`dir` and `commit` are source-repository metadata, useful while building and
tagging. `tarball_asset` and `sbom_asset` identify the downloaded artifact
basenames; when omitted, actions derive them from `name` and `version`. `tag`
defaults to `name@version`; `release_title` defaults to `tag`; and
`release_body` defaults to a short publish message. `channel` and `provenance`
may override the `publish-tarballs` defaults per package. JavaScript SBOM
generation commonly uses `pnpm sbom`, which requires pnpm `>= 11.8`.

### Available release actions

The release workflow is composed from these actions. You normally get them via
the template, but they're listed here as a reference for customizing it — each is
**self-contained** (calls no other action in this repo), so a single SHA pin
pulls in everything it needs.

| Action                                                                  | Purpose                                                                                                                                                           |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `release/lang/<lang>/configure`                                         | Derive release facts (tag, channel, rc suffix, `github_release`) from the version + `release_type` — read-only                                                    |
| `release/prepare`                                                       | Fetch the PR list and release notes                                                                                                                               |
| `release/lang/<lang>/validate`                                          | Validate the release (tag / channel / branch / metadata, registry availability) and run a pre-gate build + SBOM generation                                        |
| `release/request-approval`                                              | Post the pre-approval job summary and Slack notification                                                                                                          |
| `release/lang/<lang>/build-and-ship`                                    | **Turnkey**: build → sign a CycloneDX SBOM (+ build provenance for Ruby) → publish (OIDC trusted publishing) → create the GitHub release (SBOM attached) → notify |
| `release/lang/js/pack-pnpm` · `pack-bun`, `release/lang/{py,ruby}/pack` | **Custom build**: build + pack + sign SBOM + build provenance in an unprivileged job (no publish credentials)                                                     |
| `release/lang/<lang>/ship-package`                                      | **Custom build**: verify the attestation against the downloaded artifact → publish that exact artifact → create the GitHub release → notify                       |
| `release/lang/js/publish-tarballs`                                      | Verify prebuilt npm tarballs by glob and publish the exact bytes to npmjs in manifest order                                                                       |
| `release/create-package-releases`                                       | Create per-package GitHub releases from existing manifest tags, titles, and bodies, with optional per-package SBOM assets                                         |
| `release/verify-package`                                                | Verify downloaded artifact attestations without using a language-specific ship action                                                                             |

Inputs and outputs are documented in each `action.yml`. Reference an action by
commit SHA:

```yaml
- uses: braintrustdata/sdk-actions/actions/release/prepare@<sha>
```

## Developing

`actions/` is **generated** from `templates/` — never edit it by hand. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the template system and workflow.
