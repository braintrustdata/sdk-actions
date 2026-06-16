# sdk-actions

Shared GitHub actions and workflows for Braintrust SDK repositories.

## Releases

**Copy the canonical release workflow template** from `.github/workflows/release-<LANG>.yml` and adapt it for your repository. Using it as an upstream source will enable the implemented release process to receive improvements in the future.

### Adopting the release workflow

1. **Copy the canonical template** for your language into your repo's
   `.github/workflows/`. For Ruby that's
   [`release-ruby.yml`](.github/workflows/release-ruby.yml) — it doubles as this
   repo's end-to-end test and the reference implementation.
2. **Adapt the marked sections** — version source, gem name, working directory,
   and so on. The template's comments flag exactly what changes per repo;
   everything else is provided by the pinned actions.
3. **Record the upstream version you based it on** — the sdk-actions ref (commit
   SHA or tag) your copy was adapted from, e.g. in a header comment. Tracking it
   lets you (or an agent) diff your copy against a newer upstream template and
   sync changes deliberately as this repo evolves.
4. **Bump the pinned SHA** to pick up action changes. Because each action is
   self-contained, one SHA bump pulls in the whole updated chain.

### Available release actions

The release workflow is composed from these actions. You normally get them via
the template, but they're listed here as a reference for customizing it — each is
**self-contained** (calls no other action in this repo), so a single SHA pin
pulls in everything it needs.

| Action | Purpose |
|---|---|
| `release/lang/ruby/publish` | Push the gem to RubyGems, create the GitHub release, and notify |
| `release/lang/ruby/validate` | Check out the SHA, set up Ruby, read the version, validate the release (tag/branch/metadata), lint + build |
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
