"""Repository rules: one repo per Lean release archive, plus a hub of toolchains.

The hub only declares `toolchain()` targets. A release archive (about 600 MB)
is downloaded only when toolchain resolution picks its platform, which happens
only when a Lean target is actually built.
"""

load(":versions.bzl", "PLATFORMS", "URL_TEMPLATES")

_RELEASE_BUILD = """\
load("@rules_lean//lean:toolchain.bzl", "lean_toolchain")

package(default_visibility = ["//visibility:public"])

# Everything `lean` needs to elaborate a file: the executable, its DLLs on
# Windows, and the prebuilt core library (Init, Std, Lean, Lake).
filegroup(
    name = "compile_files",
    srcs = glob(
        ["{p}bin/**", "{p}lib/lean/**"],
        exclude = [
            "{p}lib/lean/**/*.a",
            "{p}lib/lean/**/*.lib",
        ],
    ),
)

# Everything `leanc` needs to compile generated C and link a native binary:
# the bundled clang and linker, headers, runtime and static libraries.
filegroup(
    name = "cc_files",
    srcs = glob(
        ["{p}bin/**", "{p}include/**", "{p}lib/**"],
        exclude = [
            "{p}lib/lean/**/*.olean",
            "{p}lib/lean/**/*.olean.*",
            "{p}lib/lean/**/*.ilean",
            "{p}lib/lean/**/*.ir",
            "{p}lib/lean/**/*.ir.*",
        ],
    ),
)

lean_toolchain(
    name = "toolchain_impl",
    lean = "{p}bin/lean{ext}",
    leanc = "{p}bin/leanc{ext}",
    lean_files = ":compile_files",
    cc_files = ":cc_files",
    version = "{version}",
)

exports_files(glob(["{p}LICENSE*"]))
"""

def _lean_release_impl(rctx):
    urls = [t.format(version = rctx.attr.version, asset = rctx.attr.asset) for t in URL_TEMPLATES]
    rctx.download_and_extract(url = urls, sha256 = rctx.attr.sha256)

    # The archive has a single top-level directory whose name is not part of
    # Lean's documented interface; find it instead of hard-coding it.
    prefix = ""
    if not rctx.path("bin").exists:
        roots = [d for d in rctx.path(".").readdir() if d.get_child("bin").exists]
        if len(roots) != 1:
            fail("rules_lean: could not find the Lean installation inside {}".format(rctx.attr.asset))
        prefix = roots[0].basename + "/"

    rctx.file("BUILD.bazel", _RELEASE_BUILD.format(
        p = prefix,
        ext = ".exe" if rctx.attr.platform.startswith("windows") else "",
        version = rctx.attr.version,
    ))

lean_release = repository_rule(
    implementation = _lean_release_impl,
    attrs = {
        "asset": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
        "sha256": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
    },
    doc = "Downloads and verifies one Lean 4 release archive.",
)

def _lean_toolchains_hub_impl(rctx):
    lines = ['package(default_visibility = ["//visibility:public"])', ""]
    for platform, repo in rctx.attr.repos.items():
        lines.append("""toolchain(
    name = "{platform}",
    exec_compatible_with = {constraints},
    toolchain = "@{repo}//:toolchain_impl",
    toolchain_type = "@rules_lean//lean:toolchain_type",
)
""".format(platform = platform, repo = repo, constraints = repr(PLATFORMS[platform])))
    rctx.file("BUILD.bazel", "\n".join(lines))

lean_toolchains_hub = repository_rule(
    implementation = _lean_toolchains_hub_impl,
    attrs = {
        "repos": attr.string_dict(doc = "platform -> name of its lean_release repo"),
    },
    doc = "Declares one toolchain() per platform without fetching any archive.",
)
