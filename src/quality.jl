# --- mesh quality metrics (Julia-side, no FEM assembly) ---------------------

_norm(v) = sqrt(sum(abs2, v))
_det3(v1, v2, v3) =
    v1[1] * (v2[2] * v3[3] - v2[3] * v3[2]) -
    v1[2] * (v2[1] * v3[3] - v2[3] * v3[1]) +
    v1[3] * (v2[1] * v3[2] - v2[2] * v3[1])

"""
    MeshQualityReport

Shape-quality summary computed from mesh coordinates and connectivity.
"""
struct MeshQualityReport
    min_quality::Float64
    max_quality::Float64
    mean_quality::Float64
    quantiles::NamedTuple{(:p05, :p25, :p50, :p75, :p95), NTuple{5,Float64}}
    bad_element_count::Int
    inverted_element_count::Int
    zero_volume_element_count::Int
    min_edge_length::Float64
    max_edge_length::Float64
    aspect_ratio_summary::NamedTuple{(:min, :mean, :max), NTuple{3,Float64}}
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::MeshQualityReport)
    print(io, "MeshQualityReport(",
          "min_quality=", round(r.min_quality; digits=4),
          ", mean=", round(r.mean_quality; digits=4),
          ", bad=", r.bad_element_count,
          ", inverted=", r.inverted_element_count, ")")
end

const _QUALITY_BAD_THRESHOLD = 0.05
const _VOLUME_ZERO_TOL = 1e-30

function _edge_lengths(P, conn, nverts)
    edges = Tuple{Int,Int}[]
    for j in 1:nverts
        for k in (j + 1):nverts
            push!(edges, (conn[j], conn[k]))
        end
    end
    return [_norm(P[:, b] - P[:, a]) for (a, b) in edges]
end

function _triangle_quality(P, a, b, c)
    p1, p2, p3 = P[:, a], P[:, b], P[:, c]
    area2 = abs((p2[1] - p1[1]) * (p3[2] - p1[2]) - (p3[1] - p1[1]) * (p2[2] - p1[2]))
    area = area2 / 2
    area <= _VOLUME_ZERO_TOL && return 0.0, area, true
    lens = [_norm(p2 - p1), _norm(p3 - p2), _norm(p1 - p3)]
    hmax = maximum(lens)
    # normalized quality: 4*sqrt(3)*area / sum(l^2) in [0,1] for equilateral=1
    q = 4 * sqrt(3) * area / sum(lens .^ 2)
    return q, area, false
end

function _tet_quality(P, a, b, c, d)
    p1, p2, p3, p4 = P[:, a], P[:, b], P[:, c], P[:, d]
    vol = abs(_det3(p2 - p1, p3 - p1, p4 - p1)) / 6
    vol <= _VOLUME_ZERO_TOL && return 0.0, vol, true
    lens = _edge_lengths(P, (a, b, c, d), 4)
    # radius-ratio proxy: scaled volume vs longest edge
    hmax = maximum(lens)
    q = vol <= 0 ? 0.0 : clamp(6 * sqrt(6) * vol / (hmax^3), 0.0, 1.0)
    return q, vol, vol <= 0
end

function _quantiles(v::Vector{Float64})
    isempty(v) && return (p05=NaN, p25=NaN, p50=NaN, p75=NaN, p95=NaN)
    s = sort(v)
    n = length(s)
    q(p) = s[max(1, min(n, ceil(Int, p * n)))]
    return (p05=q(0.05), p25=q(0.25), p50=q(0.50), p75=q(0.75), p95=q(0.95))
end

"""
    quality(mesh) -> MeshQualityReport

Compute simplex quality metrics from node coordinates and connectivity.
"""
function quality(m)
    warnings = DiagnosticMessage[]
    P = points(m)
    d = mesh_dimension(m)
    qualities = Float64[]
    edge_lens = Float64[]
    bad = 0
    inverted = 0
    zero_vol = 0

    if d == 3
        T = tetrahedra(m)
        ne = size(T, 2)
        for e in 1:ne
            q, vol, is_zero = _tet_quality(P, T[1, e], T[2, e], T[3, e], T[4, e])
            push!(qualities, q)
            append!(edge_lens, _edge_lengths(P, T[:, e], 4))
            is_zero && (zero_vol += 1)
            vol <= 0 && (inverted += 1)
            q < _QUALITY_BAD_THRESHOLD && (bad += 1)
        end
    elseif d == 2
        Tr = triangles2d(m)
        ne = size(Tr, 2)
        for e in 1:ne
            q, area, is_zero = _triangle_quality(P, Tr[1, e], Tr[2, e], Tr[3, e])
            push!(qualities, q)
            append!(edge_lens, _edge_lengths(P, Tr[:, e], 3))
            is_zero && (zero_vol += 1)
            area <= 0 && (inverted += 1)
            q < _QUALITY_BAD_THRESHOLD && (bad += 1)
        end
    else
        _append!(warnings, :warning, :unsupported_dimension,
            "quality metrics not computed for dimension $d")
        return MeshQualityReport(0, 0, 0, _quantiles(Float64[]), 0, 0, 0,
            0, 0, (min=0.0, mean=0.0, max=0.0), warnings)
    end

    isempty(qualities) && _append!(warnings, :warning, :empty_mesh, "no elements to measure")
    min_e = isempty(edge_lens) ? 0.0 : minimum(edge_lens)
    max_e = isempty(edge_lens) ? 0.0 : maximum(edge_lens)
    ar = isempty(edge_lens) ? (min=0.0, mean=0.0, max=0.0) :
        (min=min_e / max_e, mean=(sum(edge_lens) / length(edge_lens)) / max_e, max=1.0)

    return MeshQualityReport(
        isempty(qualities) ? 0.0 : minimum(qualities),
        isempty(qualities) ? 0.0 : maximum(qualities),
        isempty(qualities) ? 0.0 : sum(qualities) / length(qualities),
        _quantiles(qualities),
        bad, inverted, zero_vol,
        min_e, max_e, ar, warnings)
end

"""
    mesh_quality(mesh) -> MeshQualityReport

Alias for [`quality`](@ref).
"""
mesh_quality(m) = quality(m)
