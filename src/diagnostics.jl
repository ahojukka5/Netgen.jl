# --- shared diagnostic message types ----------------------------------------
# DiagnosticMessage is owned by OodiCore (see AGENTS.md / ../OodiCore.jl); this
# file only adds the small `_diagnostic`/`_append!` convenience wrappers used
# throughout the local reports, mapping this package's category vocabulary
# (:error, :warning, :info, :suggestion) onto OodiCore's three severities.
# `:suggestion` maps to severity `:info` — the distinction from a plain info
# message is carried by which report field it lives in (a `suggestions` vector).

function _diagnostic(category::Symbol, code::Symbol, message::AbstractString)
    category === :error && return error_diagnostic(code, message)
    category === :warning && return warning(code, message)
    (category === :info || category === :suggestion) && return info(code, message)
    throw(ArgumentError("unknown diagnostic category :$category"))
end

function _append!(msgs::Vector{DiagnosticMessage}, category::Symbol, code::Symbol, message::AbstractString)
    push!(msgs, _diagnostic(category, code, message))
    return msgs
end
