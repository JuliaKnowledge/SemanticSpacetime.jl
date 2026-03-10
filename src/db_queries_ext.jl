#=
Extended database query functions for Semantic Spacetime.
These complement the existing db_queries.jl with specialized lookups.
=#

"""Get all arrows matching a name (exact or fuzzy via lowercase comparison)."""
function get_arrows_matching_name(s::AbstractString)::Vector{ArrowPtr}
    list = ArrowPtr[]
    trimmed = strip(s, ['!'])
    isempty(trimmed) && return list

    is_exact = trimmed != s

    for (i, entry) in enumerate(_ARROW_DIRECTORY)
        entry.ptr == 0 && continue
        if is_exact
            if entry.long == trimmed || entry.short == trimmed
                push!(list, ArrowPtr(i))
            end
        else
            if lowercase(entry.long) == lowercase(s) || lowercase(entry.short) == lowercase(s)
                push!(list, ArrowPtr(i))
            end
        end
    end
    return list
end

"""Get all arrows of a specific STtype."""
function get_arrows_by_sttype(sttype::Int)::Vector{Pair{ArrowPtr,ArrowEntry}}
    result = Pair{ArrowPtr,ArrowEntry}[]
    for (i, entry) in enumerate(_ARROW_DIRECTORY)
        entry.ptr == 0 && continue
        if index_to_sttype(entry.stindex) == sttype
            push!(result, ArrowPtr(i) => entry)
        end
    end
    return result
end

"""Get arrow with its name and STtype."""
function get_arrow_with_name(s::AbstractString)::Tuple{ArrowPtr,Int}
    name = strip(s, ['!'])
    isempty(name) && return (ArrowPtr(0), 0)

    for (i, entry) in enumerate(_ARROW_DIRECTORY)
        entry.ptr == 0 && continue
        if name == entry.long || name == entry.short
            return (ArrowPtr(i), index_to_sttype(entry.stindex))
        end
    end
    return (ArrowPtr(0), 0)
end

"""Find next link arrow in a path matching given arrow constraints."""
function next_link_arrow(store::AbstractSSTStore, path::Vector{Link}, arrows::Vector{ArrowPtr})::String
    for link in path
        if link.arr in arrows
            if link.arr >= 1 && link.arr <= length(_ARROW_DIRECTORY)
                return get_arrow_by_ptr(link.arr).long
            end
        end
    end
    return ""
end

"""Get all links from all incidence channels of a node."""
function _all_node_links(node::Node)::Vector{Link}
    result = Link[]
    for stidx in 1:ST_TOP
        append!(result, node.incidence[stidx])
    end
    return result
end

"""Incrementally expand constrained cone links."""
function inc_constraint_cone_links(store::AbstractSSTStore, cone::Vector{Vector{Link}};
                                    chapter::String="", context::Vector{String}=String[],
                                    arrows::Vector{ArrowPtr}=ArrowPtr[],
                                    sttypes::Vector{Int}=Int[], maxdepth::Int=10)::Vector{Vector{Link}}
    result = Vector{Link}[]

    for path in cone
        isempty(path) && continue
        last_node_ptr = path[end].dst

        node = mem_get_node(store, last_node_ptr)
        isnothing(node) && continue

        links = _all_node_links(node)

        for link in links
            # Filter by arrow constraints
            if !isempty(arrows) && !(link.arr in arrows)
                continue
            end

            # Filter by sttype constraints
            if !isempty(sttypes)
                if link.arr >= 1 && link.arr <= length(_ARROW_DIRECTORY)
                    entry = get_arrow_by_ptr(link.arr)
                    st = index_to_sttype(entry.stindex)
                    st ∉ sttypes && continue
                end
            end

            # Filter by chapter
            if !isempty(chapter) && chapter != "any" && chapter != "%%"
                dst_node = mem_get_node(store, link.dst)
                if !isnothing(dst_node) && lowercase(dst_node.chap) != lowercase(chapter)
                    continue
                end
            end

            # Extend path
            new_path = vcat(path, [link])
            length(new_path) <= maxdepth && push!(result, new_path)
        end
    end

    return result
end

"""Get singleton nodes by STtype (sources have outgoing but no incoming, sinks vice versa)."""
function get_singleton_by_sttype(store::MemoryStore, sttypes::Vector{Int};
                                  chapter::String="", context::Vector{String}=String[])::Tuple{Vector{NodePtr},Vector{NodePtr}}
    sources = NodePtr[]
    sinks = NodePtr[]

    # Build set of stindices for forward and backward
    fwd_indices = Set{Int}()
    bwd_indices = Set{Int}()
    for st in sttypes
        push!(fwd_indices, sttype_to_index(st))
        push!(bwd_indices, sttype_to_index(-st))
    end

    for (nptr, node) in store.nodes
        # Filter by chapter
        if !isempty(chapter) && chapter != "any" && chapter != "%%"
            lowercase(node.chap) != lowercase(chapter) && continue
        end

        has_fwd = false
        has_bwd = false

        for stidx in fwd_indices
            if stidx >= 1 && stidx <= ST_TOP && !isempty(node.incidence[stidx])
                has_fwd = true
                break
            end
        end

        for stidx in bwd_indices
            if stidx >= 1 && stidx <= ST_TOP && !isempty(node.incidence[stidx])
                has_bwd = true
                break
            end
        end

        # Source: has forward links but no backward
        if has_fwd && !has_bwd
            push!(sources, nptr)
        end
        # Sink: has backward links but no forward
        if has_bwd && !has_fwd
            push!(sinks, nptr)
        end
    end

    return (sources, sinks)
end

"""Get sequence containers (stories) from node pointers."""
function get_sequence_containers(store::AbstractSSTStore, nodeptrs::Vector{NodePtr},
                                  arrowptrs::Vector{ArrowPtr};
                                  sttypes::Vector{Int}=Int[], limit::Int=100)::Vector{Story}
    stories = Story[]
    isempty(arrowptrs) && return stories

    count = 0
    already = Dict{NodePtr,Bool}()

    for (nth, nptr) in enumerate(nodeptrs)
        node = mem_get_node(store, nptr)
        isnothing(node) && continue

        axis = get_longest_axial_path(store, nptr, arrowptrs[1]; limit=limit)
        isempty(axis) && continue

        directory = assign_story_coordinates(axis, nth, length(nodeptrs); limit=limit, already=already)

        events = NodeEvent[]
        for (lnk_idx, link) in enumerate(axis)
            nd = mem_get_node(store, link.dst)
            isnothing(nd) && continue

            ne = NodeEvent(
                nd.s,
                nd.l,
                nd.chap,
                link.ctx > 0 ? get_context(link.ctx) : "",
                link.dst,
                get(directory, link.dst, Coords()),
                get_node_orbit(store, link.dst; limit=limit)
            )

            push!(events, ne)
            lnk_idx > limit && break
        end

        if !isempty(events)
            push!(stories, Story(node.chap, events))
        end
        count += 1
        count > limit && break
    end

    return stories
end

"""Check if a string was already seen in a cone structure."""
function already_seen(s::AbstractString, cone::Dict{Int,Vector{String}})::Bool
    for (_, strs) in cone
        s in strs && return true
    end
    return false
end
