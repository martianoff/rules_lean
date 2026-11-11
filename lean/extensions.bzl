"""The `lean` module extension: picks a Lean version and sets up its toolchains.

    lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")
    lean.toolchain(version = "4.35.0")

The root module's version wins. Without any `lean.toolchain` tag the default
version of this rules_lean release is used.
"""

load("//lean/private:repositories.bzl", "lean_release", "lean_toolchains_hub")
load("//lean/private:versions.bzl", "DEFAULT_LEAN_VERSION", "LEAN_VERSIONS")

_toolchain_tag = tag_class(
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Lean 4 release, without the leading 'v' (e.g. \"4.35.0\").",
        ),
    },
)

def _lean_impl(mctx):
    version = None
    for mod in mctx.modules:
        if mod.tags.toolchain and (mod.is_root or version == None):
            version = mod.tags.toolchain[0].version
            if mod.is_root:
                break
    version = version or DEFAULT_LEAN_VERSION

    if version not in LEAN_VERSIONS:
        fail(("rules_lean: Lean {} is not known to this release of rules_lean (known: {}). " +
              "Add its checksums to lean/private/versions.bzl.").format(
            version,
            ", ".join(sorted(LEAN_VERSIONS.keys())),
        ))

    repos = {}
    for platform, (asset, sha256) in LEAN_VERSIONS[version].items():
        name = "lean_{}_{}".format(version.replace(".", "_"), platform)
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
)
