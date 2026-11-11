# Bazel Central Registry templates

Used by [publish-to-bcr](https://github.com/bazel-contrib/publish-to-bcr) to open the
registry pull request for each release (see `.github/workflows/publish.yml`).

- `metadata.template.json`: homepage, maintainers and repository of the module.
- `source.template.json`: where the release archive and its API docs are downloaded.
- `presubmit.yml`: what the registry's CI runs: `e2e/smoke` on every platform.
