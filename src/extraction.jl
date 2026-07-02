# --- mesh extraction --------------------------------------------------------
"""points(mesh) -> 3×nnodes Matrix{Float64} of node coordinates."""
function points(m)
    np = Netgen.GetNP(m)
    P = Matrix{Float64}(undef, 3, np)
    for i in 1:np
        p = Netgen.Point(m, i)
        P[1, i] = p(0); P[2, i] = p(1); P[3, i] = p(2)
    end
    return P
end

"""
    tetrahedra(mesh) -> 4×ne Matrix{Int32}, 1-based node ids.

See also [`volume_tetrahedra`](@ref) for the same data with a dimension check
and a name unambiguous about which cells it returns.
"""
function tetrahedra(m)
    ne = Netgen.GetNE(m)
    T = Matrix{Int32}(undef, 4, ne)
    for i in 1:ne
        e = Netgen.VolumeElement(m, i)
        for j in 1:4
            T[j, i] = Netgen.PNum(e, j)
        end
    end
    return T
end

"""
    surface_triangles(mesh) -> 3×nse Matrix{Int32}, 1-based node ids.

3D boundary triangles. In a 2D mesh, Netgen's "surface elements" are actually
the domain triangles, not a boundary — use [`triangles2d`](@ref) there
instead for a dimension-checked, unambiguously-named accessor (and
[`segments2d`](@ref) for 2D boundary segments).
"""
function surface_triangles(m)
    nse = Netgen.GetNSE(m)
    S = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = Netgen.SurfaceElement(m, i)
        for j in 1:3
            S[j, i] = Netgen.PNum(e, j)
        end
    end
    return S
end
