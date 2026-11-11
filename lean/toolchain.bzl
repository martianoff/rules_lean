"""The Lean toolchain rule and the toolchain type label."""

LEAN_TOOLCHAIN_TYPE = "@rules_lean//lean:toolchain_type"

def _lean_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        lean = ctx.executable.lean,
        leanc = ctx.executable.leanc,
        lean_files = ctx.attr.lean_files[DefaultInfo].files,
        cc_files = ctx.attr.cc_files[DefaultInfo].files,
        version = ctx.attr.version,
    )]

lean_toolchain = rule(
    implementation = _lean_toolchain_impl,
    attrs = {
        "cc_files": attr.label(mandatory = True, doc = "Files leanc needs to compile C and link."),
        "lean": attr.label(mandatory = True, executable = True, cfg = "exec", allow_single_file = True),
        "lean_files": attr.label(mandatory = True, doc = "Files lean needs to elaborate a module."),
        "leanc": attr.label(mandatory = True, executable = True, cfg = "exec", allow_single_file = True),
        "version": attr.string(mandatory = True),
    },
    doc = "A Lean 4 installation: `lean`, `leanc` and the files each needs.",
)
