#=
CairoMakie-based graph visualization for Semantic Spacetime.

All functions check for CairoMakie availability and return nothing
with a warning if it is not loaded.
=#

# Color scheme for ST types (-3..+3)
const ST_COLORS = Dict(
    -3 => :purple,    # -EXPRESS
    -2 => :blue,      # -CONTAINS
    -1 => :cyan,      # -LEADSTO
     0 => :green,     # NEAR
     1 => :yellow,    # +LEADSTO
     2 => :orange,    # +CONTAINS
     3 => :red,       # +EXPRESS
)

# Check if CairoMakie is available
function _has_cairomakie()
    try
        @eval import CairoMakie
        return true
    catch
        return false
    end
end

const _CAIROMAKIE_AVAILABLE = Ref{Union{Bool,Nothing}}(nothing)

function _check_cairomakie()
    if isnothing(_CAIROMAKIE_AVAILABLE[])
        _CAIROMAKIE_AVAILABLE[] = _has_cairomakie()
    end
    if !_CAIROMAKIE_AVAILABLE[]
        @warn "CairoMakie not available. Install with: using Pkg; Pkg.add(\"CairoMakie\")"
        return false
    end
    return true
end

"""
    plot_cone(store::AbstractSSTStore, cone::Vector{Vector{Link}};
              title::String="Causal Cone", kwargs...)

Create a figure showing cone paths as a directed graph.
Uses `assign_cone_coordinates` for layout.
Nodes are shown as scatter points, links as arrows, colored by ST type.

Returns a CairoMakie Figure, or `nothing` if CairoMakie is unavailable.
"""
function plot_cone(store::AbstractSSTStore, cone::Vector{Vector{Link}};
                   title::String="Causal Cone", swimlanes::Int=1, kwargs...)
    _check_cairomakie() || return nothing

    coords = assign_cone_coordinates(cone, 1, swimlanes)
    isempty(coords) && return nothing

    CairoMakie = @eval Main.CairoMakie

    fig = CairoMakie.Figure(; size=(800, 600))
    ax = CairoMakie.Axis(fig[1, 1]; title=title, xlabel="Lane", ylabel="Depth")

    # Collect node positions
    xs = Float64[]
    ys = Float64[]
    labels = String[]

    for (nptr, c) in coords
        push!(xs, c.x)
        push!(ys, c.z)
        node = mem_get_node(store, nptr)
        push!(labels, isnothing(node) ? string(nptr) : node.s)
    end

    # Draw links
    for path in cone
        for (i, lnk) in enumerate(path)
            if haskey(coords, lnk.dst) && i > 1
                # Find source node from previous link's destination
                src_nptr = path[i - 1].dst
                if haskey(coords, src_nptr)
                    entry = get_arrow_by_ptr(lnk.arr)
                    st = isnothing(entry) ? 0 : index_to_sttype(entry.stindex)
                    color = get(ST_COLORS, st, :gray)
                    sc = coords[src_nptr]
                    dc = coords[lnk.dst]
                    CairoMakie.lines!(ax, [sc.x, dc.x], [sc.z, dc.z];
                                      color=color, linewidth=1.5)
                end
            end
        end
    end

    CairoMakie.scatter!(ax, xs, ys; markersize=10, color=:steelblue)

    for (i, lbl) in enumerate(labels)
        short = length(lbl) > 20 ? lbl[1:20] * "…" : lbl
        CairoMakie.text!(ax, xs[i], ys[i]; text=short, fontsize=8, align=(:left, :bottom))
    end

    return fig
end

"""
    plot_orbit(store::AbstractSSTStore, nptr::NodePtr, orbits::Vector{Vector{Orbit}};
               title::String="Node Orbit", kwargs...)

Show a central node with orbiting satellites colored by ST type.

Returns a CairoMakie Figure, or `nothing` if CairoMakie is unavailable.
"""
function plot_orbit(store::AbstractSSTStore, nptr::NodePtr, orbits::Vector{Vector{Orbit}};
                    title::String="Node Orbit", kwargs...)
    _check_cairomakie() || return nothing

    CairoMakie = @eval Main.CairoMakie

    fig = CairoMakie.Figure(; size=(600, 600))
    ax = CairoMakie.Axis(fig[1, 1]; title=title, aspect=CairoMakie.DataAspect())

    # Central node
    node = mem_get_node(store, nptr)
    center_label = isnothing(node) ? string(nptr) : node.s

    CairoMakie.scatter!(ax, [0.0], [0.0]; markersize=15, color=:black)
    CairoMakie.text!(ax, 0.0, 0.0; text=center_label, fontsize=10, align=(:center, :bottom))

    for sti in 1:length(orbits)
        st = index_to_sttype(sti)
        color = get(ST_COLORS, st, :gray)
        for orb in orbits[sti]
            CairoMakie.scatter!(ax, [orb.xyz.x], [orb.xyz.y]; markersize=8, color=color)
            CairoMakie.lines!(ax, [orb.ooo.x, orb.xyz.x], [orb.ooo.y, orb.xyz.y];
                              color=color, linewidth=0.5)
            short = length(orb.text) > 15 ? orb.text[1:15] * "…" : orb.text
            CairoMakie.text!(ax, orb.xyz.x, orb.xyz.y; text=short, fontsize=7,
                             align=(:left, :bottom))
        end
    end

    return fig
end

"""
    plot_graph_summary(store::AbstractSSTStore; chapter::String="", kwargs...)

Overview: node count by type, degree distribution as a bar plot.

Returns a CairoMakie Figure, or `nothing` if CairoMakie is unavailable.
"""
function plot_graph_summary(store::AbstractSSTStore; chapter::String="", kwargs...)
    _check_cairomakie() || return nothing

    CairoMakie = @eval Main.CairoMakie

    # Count nodes by text size class
    class_counts = Dict{Int,Int}()
    for (nptr, _) in store.nodes
        c = nptr.class
        class_counts[c] = get(class_counts, c, 0) + 1
    end

    classes = sort(collect(keys(class_counts)))
    counts = [class_counts[c] for c in classes]
    class_labels = [get(Dict(N1GRAM=>"1gram", N2GRAM=>"2gram", N3GRAM=>"3gram",
                             LT128=>"<128", LT1024=>"<1024", GT1024=>">1024"), c, "?")
                    for c in classes]

    fig = CairoMakie.Figure(; size=(600, 400))
    ax = CairoMakie.Axis(fig[1, 1]; title="Node Distribution by Class",
                         xticks=(1:length(classes), class_labels), ylabel="Count")
    CairoMakie.barplot!(ax, 1:length(classes), counts; color=:steelblue)

    return fig
end

"""
    plot_adjacency_heatmap(adj::Matrix{Float32}; labels::Vector{String}=String[], kwargs...)

Heatmap of an adjacency matrix.

Returns a CairoMakie Figure, or `nothing` if CairoMakie is unavailable.
"""
function plot_adjacency_heatmap(adj::Matrix{Float32}; labels::Vector{String}=String[], kwargs...)
    _check_cairomakie() || return nothing

    CairoMakie = @eval Main.CairoMakie

    fig = CairoMakie.Figure(; size=(600, 600))
    ax = CairoMakie.Axis(fig[1, 1]; title="Adjacency Heatmap")

    if !isempty(labels)
        ax.xticks = (1:length(labels), labels)
        ax.yticks = (1:length(labels), labels)
        ax.xticklabelrotation = π / 4
    end

    CairoMakie.heatmap!(ax, adj; colormap=:viridis)

    return fig
end

"""
    save_plot(fig, filename::AbstractString)

Save a CairoMakie figure to file (PNG, SVG, PDF based on extension).
"""
function save_plot(fig, filename::AbstractString)
    _check_cairomakie() || return nothing
    CairoMakie = @eval Main.CairoMakie
    CairoMakie.save(filename, fig)
    nothing
end

"""
    to_dot(store::AbstractSSTStore; chapter::String="", title::String="SST") -> String

Export the graph (or a single chapter) as a GraphViz DOT string.
Nodes become DOT nodes and links become directed edges labeled with the arrow name
and colored by ST type.
"""
function to_dot(store::AbstractSSTStore; chapter::String="", title::String="SST")
    io = IOBuffer()
    println(io, "digraph \"", _dot_escape(title), "\" {")
    println(io, "  rankdir=LR;")
    println(io, "  node [shape=box, style=filled, fillcolor=lightgrey, fontsize=10];")

    dot_colors = Dict(
        -3 => "purple", -2 => "blue", -1 => "cyan",
         0 => "green",   1 => "gold",  2 => "orange", 3 => "red",
    )

    for (nptr, node) in store.nodes
        if !isempty(chapter) && node.chapter != chapter
            continue
        end
        id = _dot_node_id(nptr)
        label = _dot_escape(node.s)
        println(io, "  ", id, " [label=\"", label, "\"];")
        for lnk in node.li_fwd
            entry = get_arrow_by_ptr(lnk.arr)
            arrow_label = isnothing(entry) ? "" : entry.long
            st = isnothing(entry) ? 0 : index_to_sttype(entry.stindex)
            color = get(dot_colors, st, "gray")
            dst_id = _dot_node_id(lnk.dst)
            println(io, "  ", id, " -> ", dst_id,
                    " [label=\"", _dot_escape(arrow_label),
                    "\", color=\"", color,
                    "\", fontcolor=\"", color,
                    "\", fontsize=8];")
        end
    end

    println(io, "}")
    return String(take!(io))
end

"""
    save_dot(store::AbstractSSTStore, filename::AbstractString; kwargs...)

Write the graph as a GraphViz DOT file.
"""
function save_dot(store::AbstractSSTStore, filename::AbstractString; kwargs...)
    open(filename, "w") do f
        write(f, to_dot(store; kwargs...))
    end
    nothing
end

function _dot_node_id(nptr::NodePtr)
    return "n$(nptr.class)_$(nptr.cptr)"
end

function _dot_escape(s::AbstractString)
    return replace(replace(s, "\\" => "\\\\"), "\"" => "\\\"")
end
