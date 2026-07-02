# --- strict 1:1 CxxWrap bindings (not exported from Delone) -------------------
# All Netgen/NGSolve C++ API names live here. The public Delone module composes them
# into Julian helpers; advanced callers may use `Delone.Netgen` directly.

module Netgen

using CxxWrap
using Libdl
using Artifacts
import OCCT_jll  # must load before libnetgen_cxxwrap (BREP bridge)
import Zlib_jll

const _netgen_dir = artifact"NGSolveNetgen"
const _wrap_dir = artifact"libnetgen_cxxwrap"
const libnetgen_cxxwrap =
    joinpath(_wrap_dir, "lib", "libnetgen_cxxwrap.$(Libdl.dlext)")

@wrapmodule(() -> libnetgen_cxxwrap)

function __init__()
    flags = Libdl.RTLD_LAZY | Libdl.RTLD_GLOBAL
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libngcore.$(Libdl.dlext)"), flags)
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libnglib.$(Libdl.dlext)"), flags)
    @initcxx
end

end # module Netgen
