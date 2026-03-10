#=
Search operations for Semantic Spacetime.

Provides structured search parameter parsing and node search
against the PostgreSQL database.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go
(SearchParameters, DecodeSearchField, GetDBNodePtrMatchingNCCS).
=#

# ──────────────────────────────────────────────────────────────────
# Search command constants
# ──────────────────────────────────────────────────────────────────

# Backslash-prefixed commands (primary form)
const CMD_ON       = "\\on"
const CMD_FOR      = "\\for"
const CMD_ABOUT    = "\\about"
const CMD_NOTES    = "\\notes"
const CMD_BROWSE   = "\\browse"
const CMD_PAGE     = "\\page"
const CMD_PATH     = "\\path"
const CMD_PATH2    = "\\paths"
const CMD_SEQ1     = "\\sequence"
const CMD_SEQ2     = "\\seq"
const CMD_STORY    = "\\story"
const CMD_STORIES  = "\\stories"
const CMD_FROM     = "\\from"
const CMD_TO       = "\\to"
const CMD_CTX      = "\\ctx"
const CMD_CONTEXT  = "\\context"
const CMD_AS       = "\\as"
const CMD_CHAPTER  = "\\chapter"
const CMD_CONTENTS = "\\contents"
const CMD_TOC      = "\\toc"
const CMD_MAP      = "\\map"
const CMD_SECTION  = "\\section"
const CMD_IN       = "\\in"
const CMD_ARROW    = "\\arrow"
const CMD_ARROWS   = "\\arrows"
const CMD_LIMIT    = "\\limit"
const CMD_DEPTH    = "\\depth"
const CMD_RANGE    = "\\range"
const CMD_DISTANCE = "\\distance"
const CMD_STATS    = "\\stats"
const CMD_REMIND   = "\\remind"
const CMD_HELP     = "\\help"
const CMD_FINDS    = "\\finds"
const CMD_FINDING  = "\\finding"
const CMD_GT       = "\\gt"
const CMD_LT       = "\\lt"
const CMD_MIN      = "\\min"
const CMD_MAX      = "\\max"
const CMD_ATLEAST  = "\\atleast"
const CMD_ATMOST   = "\\atmost"
const CMD_NEVER    = "\\never"
const CMD_NEW      = "\\new"

# Bare-word aliases
const CMD_ON_2     = "on"
const CMD_FOR_2    = "for"
const CMD_TO_2     = "to"
const CMD_AS_2     = "as"
const CMD_IN_2     = "in"
const CMD_TOC_2    = "toc"
const CMD_STATS_2  = "stats"
const CMD_HELP_2   = "help"

# Orientation (kept as bare words)
const CMD_FORWARD  = "forward"
const CMD_BACKWARD = "backward"

const RECENT = 4
const NEVER_HORIZON = -1

const SEARCH_KEYWORDS = [
    CMD_ON, CMD_ON_2, CMD_FOR, CMD_FOR_2, CMD_ABOUT,
    CMD_NOTES, CMD_BROWSE,
    CMD_PATH, CMD_PATH2, CMD_FROM, CMD_TO, CMD_TO_2,
    CMD_SEQ1, CMD_SEQ2, CMD_STORY, CMD_STORIES,
    CMD_CONTEXT, CMD_CTX, CMD_AS, CMD_AS_2,
    CMD_CHAPTER, CMD_IN, CMD_IN_2, CMD_SECTION, CMD_CONTENTS, CMD_TOC, CMD_TOC_2, CMD_MAP,
    CMD_ARROW, CMD_ARROWS,
    CMD_LIMIT, CMD_DEPTH, CMD_RANGE, CMD_DISTANCE,
    CMD_STATS, CMD_STATS_2,
    CMD_REMIND,
    CMD_HELP, CMD_HELP_2,
    CMD_PAGE,
    CMD_FINDS, CMD_FINDING,
    CMD_GT, CMD_LT, CMD_MIN, CMD_MAX, CMD_ATLEAST, CMD_ATMOST,
    CMD_NEVER, CMD_NEW,
    CMD_FORWARD, CMD_BACKWARD,
]

# ──────────────────────────────────────────────────────────────────
# SearchParameters
# ──────────────────────────────────────────────────────────────────

"""
    SearchParameters

Structured representation of a search query, parsed from a natural
language command string. Mirrors the Go SearchParameters struct.
"""
mutable struct SearchParameters
    names::Vector{String}
    chapter::String
    context::Vector{String}
    arrows::Vector{ArrowPtr}
    seq_only::Bool
    limit::Int
    from_node::NodePtr
    to_node::NodePtr
    orientation::String
    depth::Int
    from_names::Vector{String}
    to_names::Vector{String}
    stats::Bool
    horizon::Int
    min_limits::Vector{Int}
    max_limits::Vector{Int}
    page_nr::Int
    range_val::Int
    finds::Vector{String}
end

function SearchParameters()
    SearchParameters(
        String[], "", String[], ArrowPtr[],
        false, CAUSAL_CONE_MAXLIMIT,
        NO_NODE_PTR, NO_NODE_PTR,
        "", 0,
        String[], String[],
        false, 0,
        Int[], Int[],
        0, 0,
        String[],
    )
end

# ──────────────────────────────────────────────────────────────────
# Query parsing
# ──────────────────────────────────────────────────────────────────

"""
    matches_cmd(w::AbstractString, cmds::AbstractString...) -> Bool

Match a word against command constants, ignoring leading backslash.
"""
function matches_cmd(w::AbstractString, cmds::AbstractString...)::Bool
    w_bare = startswith(w, "\\") ? SubString(w, 2) : w
    for cmd in cmds
        cmd_bare = startswith(cmd, "\\") ? SubString(cmd, 2) : cmd
        w_bare == cmd_bare && return true
    end
    return false
end

"""
    is_search_keyword(word::AbstractString) -> Bool

Check if a word is a recognized search keyword.
"""
function is_search_keyword(word::AbstractString)
    w = lowercase(strip(word))
    w in SEARCH_KEYWORDS && return true
    w_bare = startswith(w, "\\") ? SubString(w, 2) : w
    for kw in SEARCH_KEYWORDS
        kw_bare = startswith(kw, "\\") ? SubString(kw, 2) : kw
        w_bare == kw_bare && return true
    end
    return false
end

"""
    decode_search_field(query::String) -> SearchParameters

Parse a natural language search query into structured SearchParameters.

Handles patterns like:
- "in chapter X" or "chapter X"
- "context Y" or "ctx Y"
- "arrows Z" or "arrow Z"
- "from X to Y"
- "range N" or "limit N" or "depth N"
- "forward" or "backward" (orientation/cone)
- "sequence about X" or "seq X"
- "notes on X"
- "about X" or "on X" or "for X"
- bare words are treated as search names
"""
function decode_search_field(query::String)
    params = SearchParameters()

    # Normalize whitespace and lowercase
    cmd = lowercase(strip(replace(query, r"[ \t]+" => " ")))
    isempty(cmd) && return params

    words = split(cmd, ' ')
    i = 1

    while i <= length(words)
        w = String(words[i])

        if matches_cmd(w, CMD_CHAPTER, CMD_SECTION, CMD_IN)
            if i < length(words)
                i += 1
                chap = String(words[i])
                chap = strip(chap, ['"', '\''])
                params.chapter = chap == "any" ? "%%" : chap
            end

        elseif matches_cmd(w, CMD_CONTEXT, CMD_CTX, CMD_AS)
            while i < length(words) && !is_search_keyword(words[i+1])
                i += 1
                ctx_parts = split(String(words[i]), ',')
                for c in ctx_parts
                    c = strip(c, ['"', '\'', ' '])
                    !isempty(c) && push!(params.context, c)
                end
            end

        elseif matches_cmd(w, CMD_ARROW, CMD_ARROWS)
            while i < length(words) && !is_search_keyword(words[i+1])
                i += 1
                arrow_str = strip(String(words[i]), ['"', '\''])
                entry = get_arrow_by_name(arrow_str)
                if !isnothing(entry)
                    push!(params.arrows, entry.ptr)
                end
            end

        elseif matches_cmd(w, CMD_FROM)
            if i < length(words)
                i += 1
                from_str = String(words[i])
                from_str = strip(from_str, ['"', '\''])
                # Try parsing as NodePtr literal "(class,cptr)"
                if startswith(from_str, "(") && endswith(from_str, ")")
                    try
                        params.from_node = parse_nodeptr(from_str)
                    catch
                        push!(params.names, from_str)
                    end
                else
                    push!(params.names, from_str)
                end
            end

        elseif matches_cmd(w, CMD_TO)
            if i < length(words)
                i += 1
                to_str = String(words[i])
                to_str = strip(to_str, ['"', '\''])
                if startswith(to_str, "(") && endswith(to_str, ")")
                    try
                        params.to_node = parse_nodeptr(to_str)
                    catch
                        push!(params.names, to_str)
                    end
                else
                    push!(params.names, to_str)
                end
            end

        elseif matches_cmd(w, CMD_RANGE, CMD_LIMIT, CMD_DISTANCE)
            if i < length(words)
                i += 1
                no = tryparse(Int, String(words[i]))
                if !isnothing(no) && no > 0
                    params.limit = no
                end
            end

        elseif matches_cmd(w, CMD_DEPTH)
            if i < length(words)
                i += 1
                no = tryparse(Int, String(words[i]))
                if !isnothing(no) && no > 0
                    params.depth = no
                end
            end

        elseif matches_cmd(w, CMD_PAGE)
            if i < length(words)
                i += 1
                no = tryparse(Int, String(words[i]))
                if !isnothing(no) && no > 0
                    params.limit = no  # page mapped to limit
                end
            end

        elseif matches_cmd(w, CMD_SEQ1, CMD_SEQ2, CMD_STORY, CMD_STORIES)
            params.seq_only = true

        elseif matches_cmd(w, CMD_FORWARD)
            params.orientation = "forward"

        elseif matches_cmd(w, CMD_BACKWARD)
            params.orientation = "backward"

        elseif matches_cmd(w, CMD_NOTES, CMD_BROWSE)
            if i < length(words)
                i += 1
                next = String(words[i])
                next = strip(next, ['"', '\''])
                params.chapter = next == "any" ? "%%" : next
            end

        elseif matches_cmd(w, CMD_ABOUT, CMD_ON, CMD_FOR)
            while i < length(words) && !is_search_keyword(words[i+1])
                i += 1
                nm = String(words[i])
                nm = strip(nm, ['"', '\''])
                push!(params.names, nm == "any" ? "%%" : nm)
            end

        elseif matches_cmd(w, CMD_FINDS, CMD_FINDING)
            while i < length(words) && !is_search_keyword(words[i+1])
                i += 1
                push!(params.names, String(words[i]))
            end

        else
            # Bare word — treat as a search name
            if !is_search_keyword(w)
                push!(params.names, w == "any" ? "%%" : w)
            end
        end

        i += 1
    end

    return params
end

# ──────────────────────────────────────────────────────────────────
# Database search
# ──────────────────────────────────────────────────────────────────

"""
    node_where_string(name::String, chap::String, context::Vector{String},
                      arrows::Vector{ArrowPtr}, seq::Bool) -> String

Build a SQL WHERE clause for node search matching name, chapter,
context, arrows, and sequence constraints.
"""
function node_where_string(name::String, chap::String, context::Vector{String},
                           arrows::Vector{ArrowPtr}, seq::Bool)
    clauses = String[]

    # Chapter constraint
    if !isempty(chap) && chap != "any"
        ec = sql_escape(chap)
        push!(clauses, "lower(Chap) LIKE lower('%$(ec)%')")
    end

    # Name constraint using TSVECTOR search
    if !isempty(name) && name != "any" && name != "%%"
        en = sql_escape(name)
        if occursin('%', en) || occursin('_', en)
            push!(clauses, "lower(S) LIKE '$(en)'")
        else
            push!(clauses, "Search @@ to_tsquery('english', '$(en)')")
        end
    end

    # Sequence constraint
    if seq
        push!(clauses, "Seq = true")
    end

    isempty(clauses) && return "true"
    return join(clauses, " AND ")
end

"""
    get_db_node_ptr_matching_nccs(sst::SSTConnection, name::String, chap::String,
                                  context::Vector{String}, arrows::Vector{ArrowPtr},
                                  seq::Bool, limit::Int) -> Vector{NodePtr}

Retrieve node pointers matching name/chapter/context/sequence constraints,
ordered by text length (favouring exact matches) and cardinality.
"""
function get_db_node_ptr_matching_nccs(sst::SSTConnection, name::String, chap::String,
                                       context::Vector{String}, arrows::Vector{ArrowPtr},
                                       seq::Bool, limit::Int)
    where_clause = node_where_string(name, chap, context, arrows, seq)
    qstr = "SELECT NPtr FROM Node WHERE $(where_clause) ORDER BY L ASC LIMIT $(limit)"

    ptrs = NodePtr[]
    try
        result = execute_sql_strict(sst.conn, qstr)
        for row in LibPQ.Columns(result)
            push!(ptrs, parse_nodeptr(string(row[1])))
        end
    catch e
        @warn "NCCS search failed" query=qstr exception=e
    end
    return ptrs
end

"""
    search_nodes(sst::SSTConnection, params::SearchParameters) -> Vector{Node}

Execute a structured search against the database, returning matching nodes.
"""
function search_nodes(sst::SSTConnection, params::SearchParameters)
    nodes = Node[]

    if isempty(params.names)
        # Search with empty name but chapter/context constraints
        ptrs = get_db_node_ptr_matching_nccs(
            sst, "%%", params.chapter, params.context,
            params.arrows, params.seq_only, params.limit)
        for nptr in ptrs
            node = get_db_node_by_nodeptr(sst, nptr)
            !isempty(node.s) && push!(nodes, node)
        end
    else
        for name in params.names
            ptrs = get_db_node_ptr_matching_nccs(
                sst, name, params.chapter, params.context,
                params.arrows, params.seq_only, params.limit)
            for nptr in ptrs
                node = get_db_node_by_nodeptr(sst, nptr)
                !isempty(node.s) && push!(nodes, node)
            end
        end
    end

    return nodes
end

"""
    search_text(sst::SSTConnection, text::String) -> Vector{Node}

Simple text search using TSVECTOR full-text search.
"""
function search_text(sst::SSTConnection, text::String)
    et = sql_escape(text)
    qstr = "SELECT NPtr FROM Node WHERE Search @@ to_tsquery('english', '$(et)') ORDER BY L ASC LIMIT $(CAUSAL_CONE_MAXLIMIT)"

    nodes = Node[]
    try
        result = execute_sql_strict(sst.conn, qstr)
        for row in LibPQ.Columns(result)
            nptr = parse_nodeptr(string(row[1]))
            node = get_db_node_by_nodeptr(sst, nptr)
            !isempty(node.s) && push!(nodes, node)
        end
    catch e
        @warn "Text search failed" text=text exception=e
    end
    return nodes
end

# ──────────────────────────────────────────────────────────────────
# Search query preprocessing
# ──────────────────────────────────────────────────────────────────

"""
    is_quote_char(c::Char) -> Bool

Return true if `c` is an ASCII or Unicode quote character.
"""
function is_quote_char(c::Char)::Bool
    c in ('"', '\'', '\u201c', '\u201d')
end

"""
    read_to_next(array::Vector{Char}, pos::Int, target::Char) -> (String, Int)

Read from `pos` in `array` until `target` is found (after pos).
Returns the collected string and its length.
"""
function read_to_next(array::Vector{Char}, pos::Int, target::Char)::Tuple{String,Int}
    buf = Char[]
    for i in pos:length(array)
        push!(buf, array[i])
        if i > pos && array[i] == target
            return String(buf), length(buf)
        end
    end
    return String(buf), length(buf)
end

"""
    split_quotes(s::AbstractString) -> Vector{String}

Split a string respecting quoted sections and parenthesized groups.
Quoted sections (single, double, or Unicode quotes) and parenthesized
groups are returned as single tokens.
"""
function split_quotes(s::AbstractString)::Vector{String}
    items = String[]
    runes = collect(s)
    upto = Char[]
    r = 1
    while r <= length(runes)
        ch = runes[r]
        if is_quote_char(ch)
            if !isempty(upto)
                push!(items, String(upto))
                empty!(upto)
            end
            qstr, offset = read_to_next(runes, r, ch)
            if !isempty(qstr)
                push!(items, qstr)
                r += offset
            end
            r += 1
            continue
        elseif ch == '('
            if !isempty(upto)
                push!(items, String(upto))
                empty!(upto)
            end
            qstr, offset = read_to_next(runes, r, ')')
            if !isempty(qstr)
                push!(items, qstr)
                r += offset
            end
            r += 1
            continue
        elseif ch == ' '
            if !isempty(upto)
                push!(items, String(upto))
                empty!(upto)
            end
            r += 1
            continue
        else
            push!(upto, ch)
        end
        r += 1
    end
    if !isempty(upto)
        push!(items, String(upto))
    end
    return items
end

"""
    deq(s::AbstractString) -> String

Strip leading/trailing double-quote characters from a string.
"""
function deq(s::AbstractString)::String
    strip(s, ['"'])
end

"""
    is_command(s::AbstractString, keywords::Vector{String}) -> Bool

Check if `s` matches a keyword exactly or as a prefix (for keywords longer than 5 chars).
"""
function is_command(s::AbstractString, keywords::Vector{String})::Bool
    min_sense = 5
    for kw in keywords
        s == kw && return true
        if length(kw) > min_sense && startswith(s, kw)
            return true
        end
    end
    return false
end

"""
    something_like(s::AbstractString, keywords::Vector{String}) -> String

Return the keyword that `s` matches (exact or prefix), or `s` itself if no match.
"""
function something_like(s::AbstractString, keywords::Vector{String})::String
    min_sense = 4
    for kw in keywords
        s == kw && return kw
        if length(s) > min_sense && length(kw) > min_sense && startswith(s, kw)
            return kw
        end
    end
    return s
end

"""
    is_literal_nptr(s::AbstractString) -> Bool

Check if a string is a literal NodePtr like "(1,2)".
"""
function is_literal_nptr(s::AbstractString)::Bool
    s = strip(s)
    m = match(r"^\((\d+),(\d+)\)$", s)
    return !isnothing(m)
end

"""
    is_nptr_str(s::AbstractString) -> Bool

Check if string looks like a NodePtr string "(class,cptr)".
"""
function is_nptr_str(s::AbstractString)::Bool
    s = strip(s)
    isempty(s) && return false
    (s[1] == '(' && s[end] == ')') || return false
    m = match(r"^\((\d+),(\d+)\)$", s)
    return !isnothing(m)
end

"""
    is_bracketed_search_term(src::AbstractString) -> (Bool, String)

Check if string is a parenthesized search term.
Returns (true, sql-escaped inner text) or (false, original).
"""
function is_bracketed_search_term(src::AbstractString)::Tuple{Bool,String}
    s = strip(src)
    isempty(s) && return (false, "")
    if s[1] == '(' && s[end] == ')'
        stripped = strip(s[2:end-1])
        return (true, sql_escape(stripped))
    end
    return (false, s)
end

"""
    is_bracketed_search_list(list::Vector{String}) -> (Bool, Vector{String})

Process a list of search terms, wrapping bracketed ones with pipe delimiters.
"""
function is_bracketed_search_list(list::Vector{String})::Tuple{Bool,Vector{String}}
    stripped_list = String[]
    retval = false
    for item in list
        isbrack, stripped = is_bracketed_search_term(item)
        if isbrack
            retval = true
            push!(stripped_list, "|$(stripped)|")
        else
            push!(stripped_list, item)
        end
    end
    return (retval, stripped_list)
end

"""
    is_exact_match(org::AbstractString) -> (Bool, String)

Check if string is an exact match pattern delimited by ! or |.
Returns (true, lowercased inner text) or (false, original).
"""
function is_exact_match(org::AbstractString)::Tuple{Bool,String}
    org = strip(org)
    isempty(org) && return (false, org)
    if (org[1] == '!' && org[end] == '!') || (org[1] == '|' && org[end] == '|')
        tr = strip(org, ['!', '|'])
        return (true, lowercase(tr))
    end
    return (false, org)
end

"""
    is_string_fragment(s::AbstractString) -> Bool

Check if string is a text fragment (vs a ts_vector pattern).
"""
function is_string_fragment(s::AbstractString)::Bool
    tsvec_patterns = ["|", "&", "!", "<->", "<1>", "<2>", "<3>", "<4>"]
    for p in tsvec_patterns
        occursin(p, s) && return false
    end
    str_patterns = [" ", "-", "_", "'", "\""]
    for p in str_patterns
        occursin(p, s) && return true
    end
    return length(s) > 12
end

"""
    add_orphan(params::SearchParameters, orphan::AbstractString)

Add a keyword that isn't followed by the right param as a search term.
"""
function add_orphan(params::SearchParameters, orphan::AbstractString)
    if !isempty(params.to_names)
        push!(params.to_names, orphan)
    elseif !isempty(params.from_names)
        push!(params.from_names, orphan)
    else
        push!(params.names, orphan)
    end
    return params
end

"""
    check_help_query(name::AbstractString) -> String

Transform help command into a browseable search query.
"""
function check_help_query(name::AbstractString)::String
    name == "\\help" && return "\\notes \\chapter \"help and search\" \\limit 40"
    return name
end

"""
    check_nptr_query(name, nclass, ncptr) -> String

If name is empty but nclass and ncptr are valid integers,
construct a NodePtr string.
"""
function check_nptr_query(name::AbstractString, nclass::AbstractString, ncptr::AbstractString)::String
    if isempty(name) && !isempty(nclass) && !isempty(ncptr)
        a = tryparse(Int, nclass)
        b = tryparse(Int, ncptr)
        if !isnothing(a) && !isnothing(b)
            return "($a,$b)"
        end
    end
    return name
end

"""
    check_remind_query(name::AbstractString) -> String

Transform remind command into a reminder search query.
"""
function check_remind_query(name::AbstractString)::String
    if isempty(name) || name == "\\remind"
        ctx, key, _ = get_time_context()
        return "any \\chapter reminders \\context any, $(key) $(ctx) \\limit 20"
    end
    return name
end

"""
    check_concept_query(name::AbstractString) -> String

Transform concept/dna/terms commands into arrow-based searches.
"""
function check_concept_query(name::AbstractString)::String
    for cmd in ["\\dna ", "\\concept ", "\\concepts ", "\\terms "]
        if occursin(cmd, name)
            repl = "any \\arrow contains \\limit 20 "
            return replace(name, cmd => repl)
        end
    end
    return name
end

"""
    parse_literal_node_ptrs(names::Vector{String}) -> (Vector{NodePtr}, Vector{String})

Extract literal NodePtr values from a list of name strings.
Returns parsed NodePtrs and remaining unparsed strings.
"""
function parse_literal_node_ptrs(names::Vector{String})::Tuple{Vector{NodePtr},Vector{String}}
    nodeptrs = NodePtr[]
    rest = String[]
    for name in names
        current = Char[]
        line = collect(name)
        i = 1
        while i <= length(line)
            if line[i] == '('
                rs = strip(String(current))
                if !isempty(rs)
                    push!(rest, rs)
                    empty!(current)
                end
                i += 1
                continue
            end
            if line[i] == ')'
                np = String(current)
                m = match(r"^(\d+),(\d+)$", strip(np))
                if !isnothing(m)
                    push!(nodeptrs, NodePtr(parse(Int, m[1]), parse(Int, m[2])))
                else
                    push!(rest, "($np)")
                end
                empty!(current)
                i += 1
                continue
            end
            push!(current, line[i])
            i += 1
        end
        rs = strip(String(current))
        !isempty(rs) && push!(rest, rs)
    end
    return (nodeptrs, rest)
end

"""Placeholder for context relevance scoring."""
function score_context(i::Int, j::Int)::Bool
    return true
end

"""
    search_term_len(names::Vector{String}) -> Int

Return the maximum length of non-NodePtr search terms.
"""
function search_term_len(names::Vector{String})::Int
    maxlen = 0
    for s in names
        if !is_nptr_str(s) && length(s) > maxlen
            maxlen = length(s)
        end
    end
    return maxlen
end

"""
    all_exact(list::Vector{String}) -> Bool

Check if any item in the list is an exact-match pattern.
"""
function all_exact(list::Vector{String})::Bool
    any_exact = false
    for s in list
        is, _ = is_exact_match(s)
        any_exact = any_exact || is
    end
    return any_exact
end

"""
    arrow_ptr_from_names(arrows::Vector{String}) -> (Vector{ArrowPtr}, Vector{Int})

Resolve arrow names/numbers to ArrowPtrs and STtype values.
"""
function arrow_ptr_from_names(arrows::Vector{String})::Tuple{Vector{ArrowPtr},Vector{Int}}
    arr = ArrowPtr[]
    stt = Int[]
    for a_name in arrows
        n = tryparse(Int, a_name)
        if isnothing(n)
            entry = get_arrow_by_name(strip(a_name, ['!']))
            if !isnothing(entry)
                push!(arr, entry.ptr)
                push!(stt, index_to_sttype(entry.stindex))
            end
        else
            if n >= -Int(EXPRESS) && n <= Int(EXPRESS)
                push!(stt, n)
            elseif n > Int(EXPRESS)
                try
                    entry = get_arrow_by_ptr(ArrowPtr(n))
                    push!(arr, entry.ptr)
                    push!(stt, index_to_sttype(entry.stindex))
                catch
                    # Arrow pointer out of bounds, skip
                end
            end
        end
    end
    return (arr, stt)
end

"""
    solve_node_ptrs(store::MemoryStore, nodenames::Vector{String}; ...) -> Vector{NodePtr}

Resolve node names to NodePtrs using the MemoryStore, with optional
chapter/context filtering.
"""
function solve_node_ptrs(store::MemoryStore, nodenames::Vector{String};
                         chapter::String="", context::Vector{String}=String[],
                         arrows::Vector{ArrowPtr}=ArrowPtr[], seq::Bool=false,
                         limit::Int=100)::Vector{NodePtr}
    nodeptrs, rest = parse_literal_node_ptrs(nodenames)
    seen = Set{NodePtr}(nodeptrs)
    for name in rest
        matches = mem_get_nodes_by_name(store, name)
        for node in matches
            nptr = node.nptr
            if nptr ∉ seen
                push!(seen, nptr)
                if !isempty(chapter) && chapter != "" && chapter != "%%"
                    if !similar_string(node.chap, chapter)
                        delete!(seen, nptr)
                        continue
                    end
                end
            end
            length(seen) >= limit && break
        end
    end
    return collect(seen)
end

"""
    min_max_policy(params::SearchParameters) -> (Int, Int)

Determine min/max result limits from search parameters.
"""
function min_max_policy(params::SearchParameters)::Tuple{Int,Int}
    minlimit = 1
    maxlimit = 0

    has_from = !isempty(params.from_names) || params.from_node != NO_NODE_PTR
    has_to = !isempty(params.to_names) || params.to_node != NO_NODE_PTR

    if !isempty(params.min_limits) && !isempty(params.max_limits)
        if length(params.min_limits) == 1
            minlimit = params.min_limits[1]
        end
    end

    common_word = 5
    if params.range_val > 0
        maxlimit = params.range_val
    elseif !isempty(params.max_limits) && length(params.max_limits) == 1
        maxlimit = params.max_limits[1]
    else
        if has_from || has_to || params.seq_only
            maxlimit = 30
        else
            if search_term_len(params.names) < common_word
                maxlimit = 5
            else
                maxlimit = 10
            end
            if length(params.names) < 3 && all_exact(params.names)
                maxlimit = 30
            end
        end
    end

    return (minlimit, maxlimit)
end

# ──────────────────────────────────────────────────────────────────
# Segmented command parsing (fill_in_parameters / decode_search_command)
# ──────────────────────────────────────────────────────────────────

"""
    is_param(i::Int, lenp::Int, keys::Vector{<:AbstractString}, keywords::Vector{String}) -> Bool

Check if a token at position `i` is a parameter (not a keyword).
"""
function is_param(i::Int, lenp::Int, keys::Vector{<:AbstractString}, keywords::Vector{String})::Bool
    i > lenp && return false
    key = keys[i]
    is_command(key, keywords) && return false
    return true
end

"""
    fill_in_parameters(cmd_parts::Vector{Vector{String}}, keywords::Vector{String}=SEARCH_KEYWORDS) -> SearchParameters

Parse segmented command parts into SearchParameters.
"""
function fill_in_parameters(cmd_parts::Vector{Vector{String}}, keywords::Vector{String}=SEARCH_KEYWORDS)::SearchParameters
    param = SearchParameters()

    for c in 1:length(cmd_parts)
        lenp = length(cmd_parts[c])
        p = 1
        while p <= lenp
            matched = something_like(cmd_parts[c][p], keywords)

            # Stats
            if matches_cmd(matched, CMD_STATS)
                param.stats = true
                p += 1; continue
            end

            # Help
            if matches_cmd(matched, CMD_HELP)
                param.chapter = "SSTorytime help"
                push!(param.names, "any")
                p += 1; continue
            end

            # Chapter/Section/In/Contents/TOC/Map
            if matches_cmd(matched, CMD_CHAPTER, CMD_SECTION, CMD_IN, CMD_CONTENTS, CMD_TOC, CMD_MAP)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    param.chapter = deq(cmd_parts[c][p])
                    if param.chapter == "any"
                        param.chapter = "%%"
                    end
                else
                    add_orphan(param, matched)
                end
                p += 1; continue
            end

            # Notes/Browse
            if matches_cmd(matched, CMD_NOTES, CMD_BROWSE)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    param.chapter = deq(cmd_parts[c][p])
                    if param.chapter == "any"
                        param.chapter = "%%"
                    end
                else
                    add_orphan(param, matched)
                end
                p += 1; continue
            end

            # Page
            if matches_cmd(matched, CMD_PAGE)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    no = tryparse(Int, cmd_parts[c][p])
                    if !isnothing(no) && no > 0
                        param.page_nr = no
                    end
                end
                p += 1; continue
            end

            # Range/Limit/Distance
            if matches_cmd(matched, CMD_RANGE, CMD_LIMIT, CMD_DISTANCE)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    no = tryparse(Int, cmd_parts[c][p])
                    if !isnothing(no) && no > 0
                        param.range_val = no
                    end
                end
                p += 1; continue
            end

            # Depth
            if matches_cmd(matched, CMD_DEPTH)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    no = tryparse(Int, cmd_parts[c][p])
                    if !isnothing(no) && no > 0
                        param.depth = no
                    end
                end
                p += 1; continue
            end

            # GT/Min/AtLeast
            if matches_cmd(matched, CMD_GT, CMD_MIN, CMD_ATLEAST)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    no = tryparse(Int, cmd_parts[c][p])
                    if !isnothing(no)
                        push!(param.min_limits, no)
                    end
                end
                p += 1; continue
            end

            # LT/Max/AtMost
            if matches_cmd(matched, CMD_LT, CMD_MAX, CMD_ATMOST)
                if is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    no = tryparse(Int, cmd_parts[c][p])
                    if !isnothing(no)
                        push!(param.max_limits, no)
                    end
                end
                p += 1; continue
            end

            # Arrow/Arrows
            if matches_cmd(matched, CMD_ARROW, CMD_ARROWS)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    arrow_str = deq(cmd_parts[c][p])
                    entry = get_arrow_by_name(arrow_str)
                    if !isnothing(entry)
                        push!(param.arrows, entry.ptr)
                    end
                end
                p += 1; continue
            end

            # Context/Ctx/As
            if matches_cmd(matched, CMD_CONTEXT, CMD_CTX, CMD_AS)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    ctx_str = deq(cmd_parts[c][p])
                    ctx_parts = split(ctx_str, ',')
                    for ct in ctx_parts
                        ct = strip(String(ct))
                        !isempty(ct) && push!(param.context, ct)
                    end
                end
                p += 1; continue
            end

            # Path/From
            if matches_cmd(matched, CMD_PATH, CMD_PATH2, CMD_FROM)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    push!(param.from_names, deq(cmd_parts[c][p]))
                end
                p += 1; continue
            end

            # To
            if matches_cmd(matched, CMD_TO)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    push!(param.to_names, deq(cmd_parts[c][p]))
                end
                p += 1; continue
            end

            # Seq/Story/Stories
            if matches_cmd(matched, CMD_SEQ1, CMD_SEQ2, CMD_STORY, CMD_STORIES)
                param.seq_only = true
                p += 1; continue
            end

            # New (horizon)
            if matches_cmd(matched, CMD_NEW)
                param.horizon = RECENT
                p += 1; continue
            end

            # Never (horizon)
            if matches_cmd(matched, CMD_NEVER)
                param.horizon = NEVER_HORIZON
                p += 1; continue
            end

            # Remind
            if matches_cmd(matched, CMD_REMIND)
                param.chapter = "reminders"
                p += 1; continue
            end

            # On/About/For (name)
            if matches_cmd(matched, CMD_ON, CMD_ABOUT, CMD_FOR)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    nm = deq(cmd_parts[c][p])
                    push!(param.names, nm == "any" ? "%%" : nm)
                end
                p += 1; continue
            end

            # Finds/Finding
            if matches_cmd(matched, CMD_FINDS, CMD_FINDING)
                while is_param(p+1, lenp, cmd_parts[c], keywords)
                    p += 1
                    push!(param.finds, deq(cmd_parts[c][p]))
                end
                p += 1; continue
            end

            # Default: treat as name
            nm = deq(cmd_parts[c][p])
            push!(param.names, nm == "any" ? "%%" : nm)
            p += 1
        end
    end

    # Remove redundant wildcards if other matches exist
    rnames = filter(t -> t != "%%" && t != "any", param.names)
    wildcards = any(t -> t == "%%" || t == "any", param.names)
    if wildcards && !isempty(rnames)
        param.names = rnames
    end

    return param
end

"""
    decode_search_command(cmd::AbstractString; keywords::Vector{String}=SEARCH_KEYWORDS) -> SearchParameters

Parse a search command string into SearchParameters using segmented command parsing.
"""
function decode_search_command(cmd::AbstractString; keywords::Vector{String}=SEARCH_KEYWORDS)::SearchParameters
    cmd = lowercase(string(cmd))
    cmd = replace(cmd, r"[ \t]+" => " ")
    cmd = strip(cmd)
    pts = split_quotes(cmd)

    parts = Vector{String}[]
    part = String[]

    for p in 1:length(pts)
        subparts = split_quotes(pts[p])
        for w in 1:length(subparts)
            if is_command(subparts[w], keywords)
                if p > 1 && subparts[w] == "to"
                    push!(part, subparts[w])
                    continue
                end
                if w > 1 && startswith(subparts[w], "to")
                    push!(part, subparts[w])
                else
                    !isempty(part) && push!(parts, part)
                    part = String[]
                    push!(part, subparts[w])
                end
            else
                push!(part, subparts[w])
            end
        end
    end
    !isempty(part) && push!(parts, part)

    param = fill_in_parameters(parts, keywords)

    # Check for Dirac notation
    for arg in param.names
        isdirac, beg, en, cnt = dirac_notation(arg)
        if isdirac
            param.names = String[]
            param.from_names = [beg]
            param.to_names = [en]
            !isempty(cnt) && (param.context = [cnt])
            break
        end
    end

    return param
end
