# --- mesh surgery (topology splitting, merging, sub-meshing) ----------------
#
# Thin Julian wrappers over a handful of Netgen mesh-surgery primitives
# (`Mesh::Split2Tets`, `SplitIntoParts`, `Merge`, `GetSubMesh`, `PureTetMesh`,
# `PureTrigMesh`, `SurfaceMeshOrientation`). Each docstring below records what
# was empirically verified in this build (mesh generated from
# `test/fixtures/frame.step`, see `test/mesh_surgery.jl`) -- some of these
# mutate more, or less, than their name alone suggests; read the notes before
# relying on them for anything beyond the verified behavior.

"""
    split_to_tets!(mesh) -> mesh

Convert any PRISM elements in `mesh` into tetrahedra, in place
(`Netgen.Split2Tets`).

Netgen's OCC volume mesher used by [`generate_mesh`](@ref) in this package
only ever produces pure tetrahedral meshes (no prisms/pyramids) in this build,
so on a `generate_mesh`-built mesh this was verified to be a safe no-op:
element count, per-element type (`Netgen.GetType`), and
[`pure_tet_mesh`](@ref) were all unchanged after calling it on the
`frame.step` fixture. It exists here for meshes that do contain prism
elements (e.g. hand-built or imported with extrusion); that actual
PRISM-to-TET conversion path was not exercised end-to-end in this
verification since this build has no supported way to *produce* a prism in
the first place.
"""
function split_to_tets!(m)
    Netgen.Split2Tets(m)
    return m
end

"""
    split_into_parts!(mesh) -> mesh

Renumber `mesh`'s volume and surface elements by connected component
(`Netgen.SplitIntoParts`): elements transitively reachable from one
another via shared mesh points get the same new 1-based region id, replacing
whatever region ids were assigned before.

!!! warning "Destructive to existing boundary/material names"
    Verified on the `frame.step` fixture (a single connected solid): calling
    this collapsed the mesh's 375 distinct named boundary face descriptors
    down to just 2 generic entries (`Netgen.GetNFD` 375 -> 2, and every
    surviving entry in [`boundary_names`](@ref)/[`material_names`](@ref)
    read back as the generic `"default"`) -- **any boundary-condition or
    material names set before calling this are lost.** Only the volume
    elements' new component id ([`cell_regions`](@ref)) reflects real new
    topological information; on `frame.step` all volume tets stayed a single
    connected part (`cell_regions` unique value `[1]`, unchanged) even though
    Netgen detected 2 separate point-connected components at the *surface*
    level (`Netgen.GetNFD` went to 2) -- yet after the call
    [`boundary_regions`](@ref) (which face descriptor each boundary triangle
    actually points at) was *still* uniformly `[1]`, i.e. the second
    face-descriptor slot Netgen allocated was not referenced by any surface
    element. Treat the exact face-descriptor bookkeeping this produces as a
    Netgen-internal implementation detail, not a stable "one region per part"
    contract -- re-derive names/tags with [`tag_report`](@ref) afterward if
    you depend on them.
"""
function split_into_parts!(m)
    Netgen.SplitIntoParts(m)
    return m
end

"""
    merge_mesh_file!(mesh, path::AbstractString) -> mesh

Append another Netgen-format mesh **file** at `path` into `mesh`, in place
(`Netgen.Merge`). This is *not* an in-memory merge of two `Delone` mesh
handles -- `path` must be a file on disk, typically one previously written
with [`save_mesh`](@ref). Point ids and domain/material indices read from the
file are offset by `mesh`'s current point/domain counts before appending, so
they do not collide with `mesh`'s existing content.

Verified on the `frame.step` fixture (save a generated mesh to a `.vol` file,
then merge that same file into a freshly-loaded copy of itself): `num_nodes`
and the volume-element count (`Netgen.GetNE`) both **exactly doubled**, as
expected for appending a full copy. Surprisingly, in this build,
`Netgen.GetNSE` (boundary triangles) and `Netgen.GetNSeg` (edge
segments) did **not** change, even though the saved `.vol` file does contain
non-empty `"surfaceelements"`/`"edgesegmentsgi3"` sections and the reviewed
Netgen source (`Mesh::Merge`, `meshclass.cpp`) reads and appends them; calling
`update_topology!`/[`compress!`](@ref) afterward did not recover them either.
This looks like a real gap between the reviewed Netgen source and this
build's linked runtime (the bundled native library is not guaranteed to
exactly match the sibling source checkout used to read these semantics) --
flagged explicitly rather than silently assumed to work. Bottom line: rely on
`merge_mesh_file!` for combining volume topology (points + tets); verify
[`num_boundary_facets`](@ref) yourself before depending on it also merging
boundary/surface meshes in this build.

A pure in-memory `merge_mesh!(mesh, other_mesh)` convenience (internally
`save_mesh`-ing `other_mesh` to a temp file and calling this) was considered
but not shipped: given the boundary/segment gap just described, such a
convenience would silently under-merge surface tags for a "merge two mesh
objects" call that reads as complete. Left as a documented follow-up rather
than a wrapper that quietly does less than its name implies.
"""
function merge_mesh_file!(m, path::AbstractString)
    isfile(path) || throw(ArgumentError("merge_mesh_file!: file not found: $path"))
    Netgen.Merge(m, String(path))
    return m
end

"""
    get_sub_mesh(mesh, domains::AbstractString, faces::AbstractString="") -> mesh

Extract a new mesh containing only the elements whose region matches
`domains`/`faces`, compressing away points no longer referenced by any kept
element (`Netgen.GetSubMesh`).

!!! note "`domains`/`faces` are regexes over *names*, not index ranges"
    Confirmed by reading the Netgen source (`Mesh::GetSubMesh`,
    `meshclass.cpp`) and reproduced empirically on `frame.step`: both
    arguments are `std::regex` patterns matched with `regex_match` (a
    full-string match) against, respectively, each domain's
    [`material_names`](@ref) entry and each face's [`boundary_names`](@ref)
    entry -- **not** an index/range syntax like `"1-3,5"`. Empirically, on a
    mesh whose only material is literally named `"default"`:
    `get_sub_mesh(m, "1")` returns an **empty** mesh (`"1"` does not
    `regex_match` `"default"`), while `get_sub_mesh(m, "default")` or
    `get_sub_mesh(m, ".*")` returns the full mesh unchanged (same
    `num_nodes`/`num_cells`/`num_boundary_facets`). In 3D, a boundary face is
    also kept automatically whenever `domains` matches the material on either
    side of it, regardless of `faces` -- so `get_sub_mesh(m, ".*")` (relying
    on the default `faces=""`) already returns the whole 3D mesh. This
    wrapper intentionally does **not** offer a `Vector{Int}`-of-ids
    convenience that stringifies to a numeric pattern: no numeric range
    syntax was confirmed to exist here, and inventing one silently would risk
    matching the wrong (or zero) elements. Build the regex from
    [`material_names`](@ref)/[`boundary_names`](@ref) yourself, e.g.
    `get_sub_mesh(m, "^" * material_names(m)[1] * "\$")` to select by exact
    name, or escape/compose a real regex for anything fancier.
"""
function get_sub_mesh(m, domains::AbstractString, faces::AbstractString="")
    return Netgen.GetSubMesh(m, String(domains), String(faces))
end

"""
    pure_tet_mesh(mesh) -> Bool

Whether every volume element in `mesh` is a tetrahedron (`Netgen.PureTetMesh`).
"""
pure_tet_mesh(m) = Netgen.PureTetMesh(m)

"""
    pure_trig_mesh(mesh, domain::Integer) -> Bool

Whether every surface element belonging to face index `domain` is a triangle
rather than a quad (`Netgen.PureTrigMesh`). Per the Netgen source, `domain
= 0` checks the *whole* surface mesh instead of a single face.
"""
pure_trig_mesh(m, domain::Integer) = Netgen.PureTrigMesh(m, Int(domain))

"""
    surface_mesh_orientation!(mesh) -> mesh

Re-orient `mesh`'s surface triangles to be mutually consistent
(`Netgen.SurfaceMeshOrientation`): treats surface element 1 as the
reference orientation and flips any other triangle whose shared-edge winding
with its already-visited neighbors implies the opposite orientation,
propagating across the whole surface mesh (a disconnected surface component
restarts from its own first unvisited triangle, so it converges to *a*
consistent orientation, not necessarily the same absolute one across
components).

Verified idempotent on an already consistently-oriented mesh: calling it on a
fresh `frame.step` mesh left [`surface_triangles`](@ref) bit-for-bit
unchanged. This build's `Netgen` bindings do not expose a way to
construct or reassign an `Element2d`'s point order from Julia (no `Element2d`
constructor or `PNum` setter is wrapped), so deliberately flipping a triangle
to exercise the actual repair path end-to-end was not possible here; the
"fixes an inconsistent mesh" behavior is confirmed by reading
`Mesh::SurfaceMeshOrientation` (`meshclass.cpp`) but not independently
reproduced by a passing/failing test in this verification.
"""
function surface_mesh_orientation!(m)
    Netgen.SurfaceMeshOrientation(m)
    return m
end
