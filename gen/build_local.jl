#!/usr/bin/env julia
# Local development build of libnetgen_cxxwrap, for iterating without the
# registry. Compiles NetgenCxxWrap_jll/bundled (the CxxWrap module) against the
# locally-bound NGSolveNetgen artifact, OCCT_jll and the JlCxx/libcxxwrap_julia
# shipped with CxxWrap.jl, then binds the result into Delone.jl/Artifacts.toml as
# the "libnetgen_cxxwrap" artifact (this platform only; cross-platform binaries
# come from NetgenCxxWrap_jll/build_tarballs.jl once NGSolveNetgen_jll is
# registered).
#
# Run:  julia --project=Delone.jl Delone.jl/gen/build_local.jl
using Pkg
using Pkg.Artifacts
using TOML
using CxxWrap

const PKG = normpath(joinpath(@__DIR__, ".."))                       # Delone.jl
const BUNDLED = normpath(joinpath(PKG, "..", "NetgenCxxWrap_jll", "bundled"))
const ARTIFACTS_TOML = joinpath(PKG, "Artifacts.toml")

# Netgen install root from the bound NGSolveNetgen artifact.
ng_sha = TOML.parsefile(ARTIFACTS_TOML)["NGSolveNetgen"]["git-tree-sha1"]
netgen_root = artifact_path(Base.SHA1(ng_sha))
isdir(netgen_root) || error("NGSolveNetgen artifact not found at $netgen_root")

import OCCT_jll
occ_root = OCCT_jll.artifact_dir
jlcxx_prefix = CxxWrap.prefix_path()

builddir = mktempdir()
@info "Building libnetgen_cxxwrap" netgen_root occ_root jlcxx_prefix builddir
# CMAKE_PREFIX_PATH is a ';'-separated list — build it as one string so the ';'
# is data, not a command-literal special character.
prefix_path = string(occ_root, ";", jlcxx_prefix)
jlcxx_dir = joinpath(jlcxx_prefix, "lib", "cmake", "JlCxx")
run(`cmake -S $BUNDLED -B $builddir -DCMAKE_BUILD_TYPE=Release
         -DNETGEN_ROOT=$netgen_root
         -DJlCxx_DIR=$jlcxx_dir
         -DCMAKE_PREFIX_PATH=$prefix_path`)
run(`cmake --build $builddir -j$(Sys.CPU_THREADS)`)

dlext = Base.Libc.Libdl.dlext
libfile = joinpath(builddir, "libnetgen_cxxwrap.$dlext")
isfile(libfile) || error("build did not produce $libfile")

staging = mktempdir()
mkpath(joinpath(staging, "lib"))
cp(libfile, joinpath(staging, "lib", "libnetgen_cxxwrap.$dlext"); force=true)
h = create_artifact() do dir
    cp(joinpath(staging, "lib"), joinpath(dir, "lib"))
end
bind_artifact!(ARTIFACTS_TOML, "libnetgen_cxxwrap", h; force=true)
@info "Bound libnetgen_cxxwrap artifact" hash=h
