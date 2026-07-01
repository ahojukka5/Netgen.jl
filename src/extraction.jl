# --- mesh extraction --------------------------------------------------------
"""points(mesh) -> 3×nnodes Matrix{Float64} of node coordinates."""
function points(m)
    np = Internals.GetNP(m)
    P = Matrix{Float64}(undef, 3, np)
    for i in 1:np
        p = Internals.Point(m, i)
        P[1, i] = p(0); P[2, i] = p(1); P[3, i] = p(2)
    end
    return P
end

"""tetrahedra(mesh) -> 4×ne Matrix{Int32}, 1-based node ids."""
function tetrahedra(m)
    ne = Internals.GetNE(m)
    T = Matrix{Int32}(undef, 4, ne)
    for i in 1:ne
        e = Internals.VolumeElement(m, i)
        for j in 1:4
            T[j, i] = Internals.PNum(e, j)
        end
    end
    return T
end

"""surface_triangles(mesh) -> 3×nse Matrix{Int32}, 1-based node ids."""
function surface_triangles(m)
    nse = Internals.GetNSE(m)
    S = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = Internals.SurfaceElement(m, i)
        for j in 1:3
            S[j, i] = Internals.PNum(e, j)
        end
    end
    return S
end
