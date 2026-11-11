"""The `lean` module extension: picks a Lean version and sets up its toolchains.

    lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")
    lean.toolchain(version = "4.35.0")

Exactly one Lean version is used per build:

1. the root module's `lean.toolchain` version, if it has one;
2. otherwise the newest version requested by any other module;
3. otherwise the default version of this rules_lean release.
"""

load("//lean/private:repositories.bzl", "lean_release", "lean_toolchains_hub")
load("//lean/private:versions.bzl", "DEFAULT_LEAN_VERSION", "LEAN_VERSIONS")

_toolchain_tag = tag_class(
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Lean 4 release, without the leading 'v' (e.g. \"4.35.0\"). " +
                  "Must be one of the versions this rules_lean release knows; " +
                  "see `lean/private/versions.bzl`.",
        ),
    },
    doc = "Requests a Lean version. The root module's request wins.",
)

def _version_key(version):
    """Sort key for "4.35.0" or "4.36.0-rc1": releases sort after their rcs."""
    core, _, pre = version.partition("-")
    parts = []
    for p in core.split("."):
        parts.append(int(p) if p.isdigit() else -1)
    return (parts, 1 if not pre else 0, pre)

def _known_versions():
    return ", ".join(sorted(LEAN_VERSIONS.keys(), key = _version_key))

def _check_known(version, requested_by):
    if version in LEAN_VERSIONS:
        return
    hint = ""
    if version.startswith("v") and version[1:] in LEAN_VERSIONS:
        hint = ' Drop the leading "v": use "{}".'.format(version[1:])
    fail(("rules_lean: Lean version \"{}\" (requested by module {}) is not known to this " +
          "release of rules_lean. Known versions: {}.{} To use another version, upgrade " +
          "rules_lean or add the version to lean/private/versions.bzl (see CONTRIBUTING.md).").format(
        version,
        requested_by,
        _known_versions(),
        hint,
    ))

def select_version(modules, default):
    """Picks the Lean version for a build.

    Args:
      modules: list of structs with `name`, `is_root` and `versions` (the
        versions that module's `lean.toolchain` tags request).
      default: version used when no module requests one.

    Returns:
      (version, requesting module name).
    """
    best = None
    for mod in modules:
        if len(mod.versions) > 1:
            fail("rules_lean: module {} calls lean.toolchain {} times; call it once.".format(
                mod.name,
                len(mod.versions),
            ))
        if not mod.versions:
            continue
        version = mod.versions[0]
        if mod.is_root:
            return (version, mod.name)
        if best == None or _version_key(version) > _version_key(best[0]):
            best = (version, mod.name)
    return best or (default, "rules_lean (default)")

def _lean_impl(mctx):
    version, requested_by = select_version(
        [
            struct(
                name = mod.name,
                is_root = mod.is_root,
                versions = [t.version for t in mod.tags.toolchain],
            )
            for mod in mctx.modules
        ],
        DEFAULT_LEAN_VERSION,
    )
    _check_known(version, requested_by)

    repos = {}
    for platform, (asset, sha256) in LEAN_VERSIONS[version].items():
        name = "lean_{}_{}".format(version.replace(".", "_").replace("-", "_"), platform)
        lean_release(
            name = name,
            asset = asset,
            platform = platform,
            sha256 = sha256,
            version = version,
        )
        repos[platform] = name

    lean_toolchains_hub(name = "lean_toolchains", repos = repos)

    return mctx.extension_metadata(reproducible = True)

lean = module_extension(
    implementation = _lean_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Downloads a pinned Lean 4 release for each supported platform and registers " +
          "its toolchains. Archives are fetched lazily: only the execution platform's.",
)
