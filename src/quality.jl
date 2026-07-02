# --- mesh quality metrics (Julia-side, no FEM assembly) ---------------------

_norm(v) = sqrt(sum(abs2, v))
_det3(v1, v2, v3) =
    v1[1] * (v2[2] * v3[3] - v2[3] * v3[2]) -
    v1[2] * (v2[1] * v3[3] - v2[3] * v3[1]) +
    v1[3] * (v2[1] * v3[2] - v2[2] * v3[1])

"""
    MeshQualityReport

Shape-quality summary computed from mesh coordinates and connectivity.

Two distinct provenances are embedded here — don't confuse them:

- Fields named plainly (`min_quality`, `max_edge_length`, ...) are
  **Julia-side proxy metrics**: simplex radius-ratio-style scores computed
  from node coordinates and connectivity alone (see the module comment at
  the top of `quality.jl`). No FEM assembly, no Netgen quality kernel.
- Fields prefixed `netgen_...` are **native Netgen diagnostics**, calling
  straight into Netgen's own C++ quality/topology kernel (`Mesh::CalcTotalBad`,
  `Mesh::ElementError`, `Mesh::CheckVolumeMesh`, `Mesh::CheckOverlappingBoundary`
  via `Netgen`). They use Netgen's own tet-badness functional (normalized
  so a perfect/equilateral tet scores `1.0`; larger is worse — this is the
  *opposite* sense from the Julia `*_quality` fields above, where `1.0` is
  best and `0.0` is worst — do not compare the two scales directly).
  Volume-mesh-only (3D); left at their neutral defaults (`NaN`/`0`/`false`)
  with a warning for 2D meshes.
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
    # --- native Netgen diagnostics (see docstring above) --------------------
    netgen_total_bad::Float64
    netgen_min_element_badness::Float64
    netgen_max_element_badness::Float64
    netgen_mean_element_badness::Float64
    netgen_volume_mesh_ok::Bool
    netgen_boundary_ok::Bool
    netgen_overlapping_boundary::Bool
    netgen_open_element_count::Int
    netgen_open_segment_count::Int
end

function Base.show(io::IO, r::MeshQualityReport)
    print(io, "MeshQualityReport(",
          "min_quality=", round(r.min_quality; digits=4),
          ", mean=", round(r.mean_quality; digits=4),
          ", bad=", r.bad_element_count,
          ", inverted=", r.inverted_element_count,
          ", netgen_total_bad=", round(r.netgen_total_bad; digits=2),
          ", netgen_volume_mesh_ok=", r.netgen_volume_mesh_ok, ")")
end

function Base.summary(io::IO, r::MeshQualityReport)
    print(io, "MeshQualityReport(min_quality=", round(r.min_quality; digits=4),
          ", bad=", r.bad_element_count, ")")
end

function Base.show(io::IO, ::MIME"text/html", r::MeshQualityReport)
    print(io, "<table><caption>MeshQualityReport</caption>",
          "<tr><th>min_quality</th><td>", round(r.min_quality; digits=4), "</td></tr>",
          "<tr><th>mean_quality</th><td>", round(r.mean_quality; digits=4), "</td></tr>",
          "<tr><th>max_quality</th><td>", round(r.max_quality; digits=4), "</td></tr>",
          "<tr><th>bad_element_count</th><td>", r.bad_element_count, "</td></tr>",
          "<tr><th>inverted_element_count</th><td>", r.inverted_element_count, "</td></tr>",
          "<tr><th>zero_volume_element_count</th><td>", r.zero_volume_element_count, "</td></tr>",
          "<tr><th>netgen_total_bad</th><td>", round(r.netgen_total_bad; digits=2), "</td></tr>",
          "<tr><th>netgen_volume_mesh_ok</th><td>", r.netgen_volume_mesh_ok, "</td></tr>",
          "<tr><th>netgen_open_element_count</th><td>", r.netgen_open_element_count, "</td></tr></table>")
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
    NativeQualityReport

Native Netgen quality/topology diagnostics for a volume (3D) mesh, computed
entirely by calls into Netgen's own C++ kernel via `Netgen` — no Julia-side
geometry recomputation. See [`native_quality`](@ref).

Netgen's tet-badness functional (`CalcTetBadness`, exposed here via
`Mesh::CalcTotalBad` / `Mesh::ElementError`) is normalized so a perfect
(equilateral) tet scores `1.0`; larger values are worse and unbounded above.
This is the *opposite* orientation from the Julia radius-ratio proxy used by
[`MeshQualityReport`](@ref) (`1.0` = best, `0.0` = worst) — the two scales
are not directly comparable.

# Fields
- `total_bad`: `Mesh::CalcTotalBad` — Netgen's own summed quality functional
  across all volume elements (lower is better; `0` only for an empty mesh).
- `min_element_badness`, `max_element_badness`, `mean_element_badness`:
  per-element `Mesh::ElementError` (`CalcTetBadness`) summary statistics.
- `volume_mesh_ok`: `Mesh::CheckVolumeMesh() == 0` (also drives
  [`check_mesh`](@ref)`.volume_ok`). Note: as implemented in the Netgen build
  this binds against, `CheckVolumeMesh` unconditionally returns `0` — a
  nonzero-orientation element is only ever surfaced by Netgen printing
  `ERROR: Element <i> has wrong orientation` to its own C-level stdout
  stream, not via this boolean or any other Julia-visible signal. Treat
  `volume_mesh_ok=true` as "no crash", not as "provably orientation-clean".
- `boundary_ok`: `Mesh::CheckConsistentBoundary() == 0`.
- `overlapping_boundary`: `Mesh::CheckOverlappingBoundary() != 0` — `true`
  means Netgen detected self-intersecting/overlapping boundary elements.

# Open elements / open segments (watertightness)

`Mesh::GetNOpenElements`/`OpenElement`/`GetNOpenSegments`/`GetOpenSegment`
(populated by the already-used `FindOpenElements`/`FindOpenSegments`) are now
wrapped (`NetgenCxxWrap_jll` commit `b551a88`). `open_element_count` is
well-verified: `0` on a normally generated mesh, exactly `4` on a hand-built
single tet with no surface elements added (its 4 unpaired faces) — treat it
as the authoritative "is the boundary watertight" signal.

`open_segment_count`, by contrast, was **not** confirmed to mean what its
name suggests: on the same normally-generated, fully-consistent `frame.step`
mesh (`open_element_count == 0`, `CheckConsistentBoundary == 0`),
`open_segment_count` read `7187` — nonzero on a mesh with no other sign of a
problem, and larger than `GetNSeg` (the total 1D edge-segment count, `5053`
on that mesh). `FindOpenSegments`/`GetNOpenSegments` almost certainly track
something more specific than "the boundary has a hole" (plausibly open edges
of the *surface triangulation* rather than unpaired boundary facets) that
was not pinned down here. Exposed for completeness with this caveat
attached; do **not** treat a nonzero `open_segment_count` as evidence of a
problem the way a nonzero `open_element_count` is.
"""
struct NativeQualityReport
    total_bad::Float64
    min_element_badness::Float64
    max_element_badness::Float64
    mean_element_badness::Float64
    volume_mesh_ok::Bool
    boundary_ok::Bool
    overlapping_boundary::Bool
    open_element_count::Int
    open_segment_count::Int
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::NativeQualityReport)
    print(io, "NativeQualityReport(",
          "total_bad=", round(r.total_bad; digits=2),
          ", mean_element_badness=", round(r.mean_element_badness; digits=4),
          ", volume_mesh_ok=", r.volume_mesh_ok,
          ", boundary_ok=", r.boundary_ok,
          ", overlapping_boundary=", r.overlapping_boundary,
          ", open_element_count=", r.open_element_count, ")")
end

function Base.summary(io::IO, r::NativeQualityReport)
    print(io, "NativeQualityReport(total_bad=", round(r.total_bad; digits=2),
          ", volume_mesh_ok=", r.volume_mesh_ok, ")")
end

function Base.show(io::IO, ::MIME"text/html", r::NativeQualityReport)
    print(io, "<table><caption>NativeQualityReport</caption>",
          "<tr><th>total_bad</th><td>", round(r.total_bad; digits=2), "</td></tr>",
          "<tr><th>min_element_badness</th><td>", round(r.min_element_badness; digits=4), "</td></tr>",
          "<tr><th>max_element_badness</th><td>", round(r.max_element_badness; digits=4), "</td></tr>",
          "<tr><th>mean_element_badness</th><td>", round(r.mean_element_badness; digits=4), "</td></tr>",
          "<tr><th>volume_mesh_ok</th><td>", r.volume_mesh_ok, "</td></tr>",
          "<tr><th>boundary_ok</th><td>", r.boundary_ok, "</td></tr>",
          "<tr><th>overlapping_boundary</th><td>", r.overlapping_boundary, "</td></tr>",
          "<tr><th>open_element_count</th><td>", r.open_element_count, "</td></tr>",
          "<tr><th>open_segment_count</th><td>", r.open_segment_count, "</td></tr></table>")
end

const _NATIVE_QUALITY_EMPTY = NativeQualityReport(0.0, NaN, NaN, NaN, true, true, false, 0, 0, DiagnosticMessage[])

"""
    native_quality(mesh) -> NativeQualityReport

Native Netgen quality/topology diagnostics (`CalcTotalBad`, `ElementError`,
`CheckVolumeMesh`, `CheckConsistentBoundary`, `CheckOverlappingBoundary`),
computed by Netgen's own C++ kernel rather than Julia-side proxies. See
[`NativeQualityReport`](@ref) for field provenance and caveats. Volume-mesh
only (3D); returns neutral defaults with a `:unsupported_dimension` warning
for other dimensions.
"""
function native_quality(m)
    warnings = DiagnosticMessage[]
    d = mesh_dimension(m)
    if d != 3
        _append!(warnings, :warning, :unsupported_dimension,
            "native quality diagnostics not computed for dimension $d (volume-mesh only)")
        return NativeQualityReport(_NATIVE_QUALITY_EMPTY.total_bad,
            _NATIVE_QUALITY_EMPTY.min_element_badness,
            _NATIVE_QUALITY_EMPTY.max_element_badness,
            _NATIVE_QUALITY_EMPTY.mean_element_badness,
            _NATIVE_QUALITY_EMPTY.volume_mesh_ok,
            _NATIVE_QUALITY_EMPTY.boundary_ok,
            _NATIVE_QUALITY_EMPTY.overlapping_boundary,
            _NATIVE_QUALITY_EMPTY.open_element_count,
            _NATIVE_QUALITY_EMPTY.open_segment_count,
            warnings)
    end

    ne = Netgen.GetNE(m)
    mp = Netgen.MeshingParameters()
    if ne == 0
        _append!(warnings, :warning, :empty_mesh, "no volume elements to measure")
        return NativeQualityReport(0.0, NaN, NaN, NaN, true, true, false, 0, 0, warnings)
    end

    total_bad = Netgen.CalcTotalBad(m, mp)
    errs = [Netgen.ElementError(m, i, mp) for i in 1:ne]
    vol_ok = Netgen.CheckVolumeMesh(m) == 0
    bnd_ok = Netgen.CheckConsistentBoundary(m) == 0
    overlap = Netgen.CheckOverlappingBoundary(m) != 0
    Netgen.FindOpenElements(m, 0)
    open_elements = Netgen.GetNOpenElements(m)
    Netgen.FindOpenSegments(m, 0)
    open_segments = Netgen.GetNOpenSegments(m)

    return NativeQualityReport(
        total_bad,
        minimum(errs), maximum(errs), sum(errs) / length(errs),
        vol_ok, bnd_ok, overlap, open_elements, open_segments, warnings)
end

"""
    quality(mesh) -> MeshQualityReport

Compute simplex quality metrics from node coordinates and connectivity, plus
native Netgen quality/topology diagnostics (see the `netgen_...` fields on
[`MeshQualityReport`](@ref) and [`native_quality`](@ref) for details).
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
        nq = _NATIVE_QUALITY_EMPTY
        return MeshQualityReport(0, 0, 0, _quantiles(Float64[]), 0, 0, 0,
            0, 0, (min=0.0, mean=0.0, max=0.0), warnings,
            nq.total_bad, nq.min_element_badness, nq.max_element_badness,
            nq.mean_element_badness, nq.volume_mesh_ok, nq.boundary_ok,
            nq.overlapping_boundary, nq.open_element_count, nq.open_segment_count)
    end

    isempty(qualities) && _append!(warnings, :warning, :empty_mesh, "no elements to measure")
    min_e = isempty(edge_lens) ? 0.0 : minimum(edge_lens)
    max_e = isempty(edge_lens) ? 0.0 : maximum(edge_lens)
    ar = isempty(edge_lens) ? (min=0.0, mean=0.0, max=0.0) :
        (min=min_e / max_e, mean=(sum(edge_lens) / length(edge_lens)) / max_e, max=1.0)

    nq = d == 3 ? native_quality(m) : _NATIVE_QUALITY_EMPTY
    append!(warnings, nq.warnings)

    return MeshQualityReport(
        isempty(qualities) ? 0.0 : minimum(qualities),
        isempty(qualities) ? 0.0 : maximum(qualities),
        isempty(qualities) ? 0.0 : sum(qualities) / length(qualities),
        _quantiles(qualities),
        bad, inverted, zero_vol,
        min_e, max_e, ar, warnings,
        nq.total_bad, nq.min_element_badness, nq.max_element_badness,
        nq.mean_element_badness, nq.volume_mesh_ok, nq.boundary_ok,
        nq.overlapping_boundary, nq.open_element_count, nq.open_segment_count)
end

Base.@deprecate mesh_quality(m) quality(m)
