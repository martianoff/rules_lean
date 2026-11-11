"""The Lean toolchain rule and the toolchain type label.

rules_lean declares these toolchains itself (see the `lean` module extension);
use `lean_toolchain` directly only to register a Lean installation of your own.
"""

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
        "cc_files": attr.label(
            mandatory = True,
            doc = "Everything `leanc` needs to compile C and link: its bundled clang " +
                  "and linker, headers, runtime and static libraries.",
        ),
        "lean": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_single_file = True,
            doc = "The `lean` executable.",
        ),
        "lean_files": attr.label(
            mandatory = True,
            doc = "Everything `lean` needs to elaborate a module: the executable, its " +
                  "shared libraries and the prebuilt `Init`, `Std` and `Lean` libraries.",
        ),
        "leanc": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_single_file = True,
            doc = "The `leanc` executable (Lean's C compiler and linker driver).",
        ),
        "version": attr.string(mandatory = True, doc = "The Lean version, e.g. \"4.35.0\"."),
    },
    doc = "A Lean 4 installation: `lean`, `leanc` and the files each needs. " +
          "Provides `ToolchainInfo` with fields `lean`, `leanc`, `lean_files`, " +
          "`cc_files` and `version`.",
)
