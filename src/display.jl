#=
Terminal display functions for Semantic Spacetime.
Port of Go print/show functions for command-line output.
=#

"""Format text for terminal display with word-wrapping."""
function show_text(s::AbstractString; width::Int=SCREENWIDTH)
    width < 40 && (width = SCREENWIDTH)
    runes = collect(s)

    # Check if preformatted (lots of spaces)
    space_count = count(isspace, runes)
    if length(runes) > SCREENWIDTH - LEFTMARGIN - RIGHTMARGIN
        if space_count > length(runes) ÷ 3
            println()
            println(s)
            return
        end
    end

    indent_str = " "^LEFTMARGIN
    line_counter = 0
    for (i, r) in enumerate(runes)
        if isspace(r) && line_counter > width - RIGHTMARGIN
            if r != '\n'
                print("\n", indent_str)
                line_counter = 0
                continue
            else
                line_counter = 0
            end
        end
        if ispunct(r) && line_counter > width - RIGHTMARGIN
            print(r)
            if i + 1 <= length(runes) && runes[i+1] != '\n'
                print("\n", indent_str)
                line_counter = 0
                continue
            end
        end
        print(r)
        line_counter += 1
    end
end

"""Create indentation string of given width."""
function indent(n::Int)::String
    " "^n
end

"""Print a node orbit to terminal."""
function print_node_orbit(store::AbstractSSTStore, nptr::NodePtr; limit::Int=100)
    node = mem_get_node(store, nptr)
    isnothing(node) && return
    print("\"")
    show_text(node.s)
    print("\"")
    println("\tin chapter: ", node.chap)
    println()

    satellites = get_node_orbit(store, nptr; limit=limit)

    for sttype in [Int(EXPRESS), -Int(EXPRESS), -Int(CONTAINS), Int(LEADSTO), -Int(LEADSTO), Int(NEAR)]
        print_link_orbit(satellites, sttype)
    end
    println()
end

"""Print links of a specific STtype from orbit satellites."""
function print_link_orbit(satellites::Vector{Vector{Orbit}}, sttype::Int; indent_level::Int=0)
    t = sttype_to_index(sttype)
    (t < 1 || t > length(satellites)) && return

    for sat in satellites[t]
        r = sat.radius + indent_level
        ind = indent(LEFTMARGIN * r)
        if !isempty(sat.ctx)
            txt = " -    ($(sat.arrow)) - $(sat.text)  \t.. in the context of $(sat.ctx)"
            show_text(ind * txt)
            println()
        else
            txt = " -    ($(sat.arrow)) - $(sat.text)"
            show_text(ind * txt)
            println()
        end
    end
end

"""Print a link path from a cone."""
function print_link_path(store::AbstractSSTStore, cone::Vector{Vector{Link}}, p::Int;
                         prefix::String="", chapter::String="", context::Vector{String}=String[],
                         limit::Int=10000)
    (p < 1 || p > length(cone)) && return
    path = cone[p]
    length(path) <= 1 && return

    path_start = mem_get_node(store, path[1].dst)
    start_shown = false
    stpath = String[]
    count = 0

    for l in 2:length(path)
        count += 1
        count > limit && return

        if !start_shown
            if length(cone) > 1
                print("$prefix ($p) $(path_start.s)")
            else
                print("$prefix $(path_start.s)")
            end
            start_shown = true
        end

        nextnode = mem_get_node(store, path[l].dst)

        # Get arrow info
        arr_long = "?"
        arr_stindex = 0
        if path[l].arr >= 1 && path[l].arr <= length(_ARROW_DIRECTORY)
            entry = get_arrow_by_ptr(path[l].arr)
            arr_long = entry.long
            arr_stindex = entry.stindex
        end

        push!(stpath, print_stindex(arr_stindex))

        print("  -($(arr_long))->  ")
        print(nextnode.s)
    end

    print("\n     -  [ Link STTypes:")
    for s in stpath
        print(" -($(s))-> ")
    end
    println(". ]\n")
end

"""Show context summary."""
function show_context(ambient::AbstractString, intent::AbstractString, key::AbstractString)
    println()
    println("  .......................................................")
    println("  Context key:     ", key)
    println("  Ambient context: ", ambient)
    println("  Intent context:  ", intent)
    println("  .......................................................")
    println()
end

"""Print STtype index as human-readable string."""
function print_sta_index(stindex::Int)::String
    print_stindex(stindex)
end

"""Format human-readable time duration."""
function show_time(years::Int, days::Int, hours::Int, mins::Int)::String
    parts = String[]
    years > 0 && push!(parts, "$years Years")
    days > 0 && push!(parts, "$days Days")
    hours > 0 && push!(parts, "$hours Hours")
    mins > 0 && push!(parts, "$mins Minutes")
    isempty(parts) && return "0 Minutes"
    return join(parts, ", ")
end

"""Print a newline n times."""
function new_line(n::Int=1)
    for _ in 1:n
        println()
    end
end

"""Show a waiting/progress indicator."""
function waiting(output::Bool, total::Int)
    if output
        if total > 0
            print("\r  Processing... $(total)   ")
        else
            print("\r  Done.             ")
            println()
        end
    end
end

"""
    print_some_link_path(store::AbstractSSTStore, cone::Vector{Vector{Link}}, p::Int;
                         prefix::AbstractString="", chapter::AbstractString="any",
                         context::Vector{String}=String[], limit::Int=10000)

Print a formatted link path from a cone result, with context and chapter filtering.
Similar to `print_link_path` but adds context filtering and chapter boundary checks.
"""
function print_some_link_path(store::AbstractSSTStore, cone::Vector{Vector{Link}}, p::Int;
                              prefix::AbstractString="", chapter::AbstractString="any",
                              context::Vector{String}=String[], limit::Int=10000)
    (p < 1 || p > length(cone)) && return
    path = cone[p]
    length(path) <= 1 && return

    count = 0
    start_shown = false
    stpath = String[]

    for l in 2:length(path)
        if !isempty(context) && !match_contexts(context, path[l].ctx)
            return
        end
        count += 1
        count > limit && return

        if !start_shown
            start_node = mem_get_node(store, path[1].dst)
            if start_node !== nothing
                if length(cone) > 1
                    print("$(prefix) ($(p)) $(start_node.s)")
                else
                    print("$(prefix) $(start_node.s)")
                end
            end
            start_shown = true
        end

        nextnode = mem_get_node(store, path[l].dst)
        nextnode === nothing && continue

        if chapter != "any" && !isempty(chapter)
            if !similar_string(nextnode.chap, chapter)
                break
            end
        end

        arr_entry = nothing
        if path[l].arr >= 1 && path[l].arr <= length(_ARROW_DIRECTORY)
            arr_entry = get_arrow_by_ptr(path[l].arr)
        end

        if arr_entry !== nothing
            if arr_entry.short == "then"
                print("\n   >>> ")
            elseif arr_entry.short == "prior" || arr_entry.short == "prev"
                print("\n   <<< ")
            end
            push!(stpath, sttype_name(index_to_sttype(arr_entry.stindex)))
            print("  -($(arr_entry.long))->  ")
        end

        print(nextnode.s)
    end

    println("\n     -  [ Link STTypes:", join([" -($s)-> " for s in stpath]), ". ]\n")
end
