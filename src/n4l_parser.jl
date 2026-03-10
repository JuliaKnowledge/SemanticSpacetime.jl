#=
N4L (Notes for Learning) parser and compiler for Semantic Spacetime.

Ported from SSTorytime/src/N4L.go.
=#

# ──────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────

const ALPHATEXT = 'x'
const NON_ASCII_LQUOTE = '\u201c'  # "
const NON_ASCII_RQUOTE = '\u201d'  # "

const HAVE_PLUS  = 11
const HAVE_MINUS = 22

"""N4L line role: an event or item declaration."""
const ROLE_EVENT            = 1
"""N4L line role: a relation (arrow) between items."""
const ROLE_RELATION         = 2
"""N4L line role: a section/chapter declaration."""
const ROLE_SECTION          = 3
"""N4L line role: a context assignment."""
const ROLE_CONTEXT          = 4
"""N4L line role: add to the current context."""
const ROLE_CONTEXT_ADD      = 5
"""N4L line role: subtract from the current context."""
const ROLE_CONTEXT_SUBTRACT = 6
"""N4L line role: a blank line (separator)."""
const ROLE_BLANK_LINE       = 7
"""N4L line role: a line alias definition (`@label`)."""
const ROLE_LINE_ALIAS       = 8
"""N4L line role: a lookup/back-reference (`\$label.n`)."""
const ROLE_LOOKUP           = 9
"""N4L line role: a composition (multi-part relation)."""
const ROLE_COMPOSITION      = 11
"""N4L line role: a result/output declaration."""
const ROLE_RESULT           = 12

const WORD_MISTAKE_LEN = 2

const SEQUENCE_RELN          = "then"
const SEQUENCE_RELN_INV      = "from"
const SEQUENCE_RELN_LONG     = "then followed by"
const SEQUENCE_RELN_INV_LONG = "follows on from"

# Error/warning messages
const WARN_NOTE_TO_SELF = "WARNING: Found a possible note to self in the text"
const WARN_INADVISABLE_CONTEXT_EXPRESSION = "WARNING: Inadvisably complex/parenthetic context expression - simplify?"
const WARN_CHAPTER_CLASS_MIXUP = "WARNING: possible space between class cancellation -:: <class> :: ambiguous chapter name, in: "
const ERR_CHAPTER_COMMA = "You shouldn't use commas in the chapter title (ambiguous separator): "
const ERR_NO_SUCH_FILE_FOUND = "No file found in the name "
const ERR_MISSING_EVENT = "Missing item? Dangling section, relation, or context"
const ERR_MISSING_SECTION = "Declarations outside a section or chapter"
const ERR_NO_SUCH_ALIAS = "No such alias or \" reference exists to fill in - aborting"
const ERR_MISSING_ITEM_SOMEWHERE = "Missing item, empty string, perhaps a missing ditto or variable reference"
const ERR_MISSING_ITEM_RELN = "Missing item or double relation"
const ERR_MISMATCH_QUOTE = "Apparent missing or mismatch in ', \" or ( )"
const ERR_ILLEGAL_CONFIGURATION = "Error in configuration, no such section"
const ERR_BAD_LABEL_OR_REF = "Badly formed label or reference (@label becomes \$label.n) in "
const ERR_ILLEGAL_QUOTED_STRING_OR_REF = "WARNING: Something wrong, bad quoted string or mistaken back reference. Double-quoted strings should not have a space after leading quote, as it can be confused with \" ditto symbol"
const ERR_ANNOTATION_BAD = "Annotation marker should be short mark of non-space, non-alphanumeric character "
const ERR_BAD_ABBRV = "abbreviation out of place"
const ERR_BAD_ALIAS_REFERENCE = "Alias references start from \$name.1"
const ERR_ANNOTATION_MISSING = "Missing non-alphnumeric annotation marker or stray relation"
const ERR_ANNOTATION_REDEFINE = "Redefinition of annotation character"
const ERR_SIMILAR_NO_SIGN = "Arrows for similarity do not have signs, they are directionless"
const ERR_ARROW_SELFLOOP = "Arrow's origin points to itself"
const ERR_ARR_REDEFINITION = "Warning: Redefinition of arrow "
const ERR_NEGATIVE_WEIGHT = "Arrow relation has a negative weight, which is disallowed. Use a NOT relation if you want to signify inhibition: "
const ERR_TOO_MANY_WEIGHTS = "More than one weight value in the arrow relation "
const ERR_STRAY_PAREN = "Stray ) in an event/item - illegal character"
const ERR_MISSING_LINE_LABEL_IN_REFERENCE = "Missing a line label in reference, should be in the form \$label.n"
const ERR_NON_WORD_WHITE = "Non word (whitespace) character after an annotation: "
const ERR_SHORT_WORD = "Short word, possible mistake or mistaken annotation (try spaces around symbol): "
const ERR_ILLEGAL_ANNOT_CHAR = "Cannot use +/- reserved tokens for annotation"
const ERR_NO_SUCH_ARROW = "No such arrow "

# ──────────────────────────────────────────────────────────────────
# N4LState — mutable parser state
# ──────────────────────────────────────────────────────────────────

"""
    N4LState

Mutable state for the N4L parser/compiler. Each parse session
gets its own state object to avoid global mutable state.
"""
mutable struct N4LState
    line_num::Int
    line_item_cache::Dict{String, Vector{String}}
    line_reln_cache::Dict{String, Vector{Link}}
    line_item_refs::Vector{NodePtr}
    line_item_state::Int
    line_alias::String
    line_item_counter::Int
    line_reln_counter::Int
    line_path::Vector{Link}

    fwd_arrow::String
    bwd_arrow::String
    fwd_index::ArrowPtr
    bwd_index::ArrowPtr
    annotation::Dict{String, String}

    context_state::Dict{String, Bool}
    section_state::String

    sequence_mode::Bool
    sequence_start::Bool
    last_in_sequence::String

    verbose::Bool
    configuring::Bool
    current_file::String

    errors::Vector{String}
    warnings::Vector{String}
    
    nd::NodeDirectory
end

function N4LState(; verbose::Bool=false)
    N4LState(
        1,                                  # line_num
        Dict{String, Vector{String}}(),     # line_item_cache
        Dict{String, Vector{Link}}(),       # line_reln_cache
        NodePtr[],                          # line_item_refs
        ROLE_BLANK_LINE,                    # line_item_state
        "",                                 # line_alias
        1,                                  # line_item_counter
        0,                                  # line_reln_counter
        Link[],                             # line_path

        "",                                 # fwd_arrow
        "",                                 # bwd_arrow
        0,                                  # fwd_index
        0,                                  # bwd_index
        Dict{String, String}(),             # annotation

        Dict{String, Bool}(),               # context_state
        "",                                 # section_state

        false,                              # sequence_mode
        false,                              # sequence_start
        "",                                 # last_in_sequence

        verbose,                            # verbose
        false,                              # configuring
        "",                                 # current_file

        String[],                           # errors
        String[],                           # warnings
        new_node_directory(),               # nd
    )
end

# ──────────────────────────────────────────────────────────────────
# Error handling
# ──────────────────────────────────────────────────────────────────

function parse_error!(st::N4LState, message::AbstractString)
    msg = "$(st.line_num): N4L $(st.current_file) $message at line $(st.line_num)"
    push!(st.errors, msg)
    if st.verbose
        printstyled(stderr, msg, "\n"; color=:red)
    end
    nothing
end

function parse_warning!(st::N4LState, message::AbstractString)
    msg = "$(st.line_num): N4L $(st.current_file) $message at line $(st.line_num)"
    push!(st.warnings, msg)
    if st.verbose
        printstyled(stderr, msg, "\n"; color=:yellow)
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Character classification helpers
# ──────────────────────────────────────────────────────────────────

function is_whitespace(r::Char, rn::Char)
    return isspace(r) || r == '#' || (r == '/' && rn == '/')
end

function is_quote(r::Char)
    return r == '"' || r == '\'' || r == NON_ASCII_LQUOTE || r == NON_ASCII_RQUOTE
end

function is_back_reference(src::Vector{Char}, pos::Int)
    p = pos + 1
    while p <= length(src)
        if src[p] == '(' || src[p] == '\n' || src[p] == '#'
            return true
        elseif !isspace(src[p])
            return false
        end
        p += 1
    end
    return false
end

function is_general_string(st::N4LState, src::Vector{Char}, pos::Int)
    c = src[pos]
    if c == ')'
        before = max(1, pos - 20)
        after = min(length(src), pos + 20)
        msg = "$ERR_STRAY_PAREN at position $pos near '...$(String(src[before:after]))...'"
        parse_error!(st, msg)
        throw(N4LParseError(msg))
    elseif c == '('
        return false
    elseif c == '#'
        return false
    elseif c == '\n'
        return false
    elseif c == '/' && pos + 1 <= length(src) && src[pos + 1] == '/'
        return false
    end
    return true
end

# ──────────────────────────────────────────────────────────────────
# Parse error exception
# ──────────────────────────────────────────────────────────────────

"""
    N4LParseError <: Exception

Exception thrown when the N4L parser encounters an unrecoverable error.

# Fields
- `message::String`: description of the parse error
"""
struct N4LParseError <: Exception
    message::String
end

Base.showerror(io::IO, e::N4LParseError) = print(io, "N4LParseError: ", e.message)

# ──────────────────────────────────────────────────────────────────
# Tokenizer: reading tokens from rune array
# ──────────────────────────────────────────────────────────────────

function last_special_char(src::Vector{Char}, pos::Int, stop::Char)
    if src[pos] == '\n' && stop != '"'
        return true
    end
    if src[pos] == '@'
        return false
    end
    if pos > 1 && src[pos - 1] == stop && src[pos] != stop
        return true
    end
    return false
end

function collect_char(st::N4LState, src::Vector{Char}, pos::Int, stop::Char, cpy::Vector{Char})
    if is_quote(stop)
        if pos + 1 > length(src)
            is_end = true
        else
            is_end = is_whitespace(src[pos], pos + 1 <= length(src) ? src[pos + 1] : ' ')
        end
        if pos > 1 && src[pos - 1] == stop && is_end
            return false
        else
            return true
        end
    end

    if pos > length(src) || src[pos] == '\n'
        return false
    end

    if stop == ALPHATEXT
        return is_general_string(st, src, pos)
    else
        if stop != ':' && !is_quote(stop)
            return !last_special_char(src, pos, stop)
        else
            groups = 0
            for r in 2:(length(cpy) - 1)
                if cpy[r] != ':' && cpy[r - 1] == ':'
                    groups += 1
                end
                if cpy[r] != '"' && cpy[r - 1] == '"'
                    groups += 1
                end
            end
            if groups > 1
                return !last_special_char(src, pos, stop)
            end
        end
    end
    return true
end

function read_to_last(st::N4LState, src::Vector{Char}, pos::Int, stop::Char)
    cpy = Char[]
    starting_at = st.line_num

    while pos <= length(src) && collect_char(st, src, pos, stop, cpy)
        push!(cpy, src[pos])

        # Handle embedded quotes
        if pos + 1 <= length(src) && src[pos] == '"'
            for p in (pos + 1):length(src)
                push!(cpy, src[p])
                if src[p] == '"'
                    pos = p
                    break
                end
            end
        end

        pos += 1
    end

    if is_quote(stop)
        # Check for mismatched quotes
        last_c = if !isempty(cpy)
            cpy[end]
        elseif pos > 1 && pos - 1 <= length(src)
            src[pos - 1]
        else
            ' '
        end
        if last_c != stop
            e = "$ERR_MISMATCH_QUOTE starting at line $starting_at (found token $(String(cpy)))"
            parse_error!(st, e)
            throw(N4LParseError(e))
        end
    end

    token = String(strip(String(cpy)))
    count_nl = count(==('\n'), token)
    st.line_num += count_nl
    return token, pos
end

# ──────────────────────────────────────────────────────────────────
# Skip whitespace and comments
# ──────────────────────────────────────────────────────────────────

function skip_whitespace!(st::N4LState, src::Vector{Char}, pos::Int)
    while pos <= length(src)
        c = src[pos]
        cn = pos + 1 <= length(src) ? src[pos + 1] : ' '
        if !is_whitespace(c, cn)
            break
        end
        if c == '\n'
            update_last_line_cache!(st)
        else
            if c == '#' || (c == '/' && cn == '/')
                while pos <= length(src) && src[pos] != '\n'
                    pos += 1
                end
                update_last_line_cache!(st)
                continue  # re-check at new pos
            end
        end
        pos += 1
    end
    return pos
end

# ──────────────────────────────────────────────────────────────────
# Get token (N4L language)
# ──────────────────────────────────────────────────────────────────

function get_token(st::N4LState, src::Vector{Char}, pos::Int)
    if pos > length(src)
        update_last_line_cache!(st)
        return "", pos
    end

    token = ""
    c = src[pos]

    if c == '+'
        cn = pos + 1 <= length(src) ? src[pos + 1] : ' '
        if cn == ':'
            token, pos = read_to_last(st, src, pos, ':')
        else
            token, pos = read_to_last(st, src, pos, ALPHATEXT)
        end
    elseif c == '-'
        cn = pos + 1 <= length(src) ? src[pos + 1] : ' '
        if cn == ':'
            token, pos = read_to_last(st, src, pos, ':')
        else
            token, pos = read_to_last(st, src, pos, ALPHATEXT)
        end
    elseif c == ':'
        token, pos = read_to_last(st, src, pos, ':')
    elseif c == '('
        token, pos = read_to_last(st, src, pos, ')')
    elseif c == '"' || c == '\'' || c == NON_ASCII_LQUOTE || c == NON_ASCII_RQUOTE
        qchar = c
        if is_quote(qchar) && is_back_reference(src, pos)
            token = "\""
            pos += 1
        else
            if qchar == '"' && pos + 2 <= length(src) && is_whitespace(src[pos + 1], src[pos + 2])
                parse_error!(st, ERR_ILLEGAL_QUOTED_STRING_OR_REF)
                throw(N4LParseError(ERR_ILLEGAL_QUOTED_STRING_OR_REF))
            end
            token, pos = read_to_last(st, src, pos, qchar)
            parts = split(token, string(qchar))
            if length(parts) >= 2
                token = String(parts[2])
            end
        end
    elseif c == '#'
        return "", pos
    elseif c == '/'
        if pos + 1 <= length(src) && src[pos + 1] == '/'
            return "", pos
        end
        token, pos = read_to_last(st, src, pos, ALPHATEXT)
    elseif c == '@'
        token, pos = read_to_last(st, src, pos, ' ')
    else
        token, pos = read_to_last(st, src, pos, ALPHATEXT)
    end

    return token, pos
end

# ──────────────────────────────────────────────────────────────────
# Get config token
# ──────────────────────────────────────────────────────────────────

function get_config_token(st::N4LState, src::Vector{Char}, pos::Int)
    if pos > length(src)
        return "", pos
    end

    token = ""
    c = src[pos]

    if c == '+' || c == '-'
        token, pos = read_to_last(st, src, pos, ALPHATEXT)
    elseif c == '('
        token, pos = read_to_last(st, src, pos, ')')
    elseif c == '#'
        return "", pos
    elseif c == '/'
        if pos + 1 <= length(src) && src[pos + 1] == '/'
            return "", pos
        end
        token, pos = read_to_last(st, src, pos, ALPHATEXT)
    elseif c == ':'
        token, pos = read_to_last(st, src, pos, ':')
    else
        token, pos = read_to_last(st, src, pos, ALPHATEXT)
    end

    return token, pos
end

# ──────────────────────────────────────────────────────────────────
# Line cache management
# ──────────────────────────────────────────────────────────────────

function dangler(st::N4LState)
    s = st.line_item_state
    s in (ROLE_EVENT, ROLE_LOOKUP, ROLE_BLANK_LINE, ROLE_SECTION,
          ROLE_CONTEXT, ROLE_CONTEXT_ADD, ROLE_CONTEXT_SUBTRACT,
          HAVE_MINUS, ROLE_RESULT) && return false
    return true
end

function update_last_line_cache!(st::N4LState)
    if dangler(st)
        parse_error!(st, ERR_MISSING_EVENT)
    end

    st.line_num += 1

    if st.line_item_state != ROLE_BLANK_LINE
        if haskey(st.line_item_cache, "THIS") && !isempty(st.line_item_cache["THIS"])
            st.line_item_cache["PREV"] = copy(st.line_item_cache["THIS"])
        end
        if haskey(st.line_reln_cache, "THIS") && !isempty(st.line_reln_cache["THIS"])
            st.line_reln_cache["PREV"] = copy(st.line_reln_cache["THIS"])
        end
    end

    st.line_item_cache["THIS"] = String[]
    st.line_reln_cache["THIS"] = Link[]
    st.line_item_refs = NodePtr[]
    st.line_item_counter = 1
    st.line_reln_counter = 0
    st.line_alias = ""
    st.line_path = Link[]
    st.line_item_state = ROLE_BLANK_LINE
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Context management
# ──────────────────────────────────────────────────────────────────

function reset_context_state!(st::N4LState)
    empty!(st.context_state)
    nothing
end

function clean_expression(s::AbstractString)
    s = String(strip(s))
    # Trim outer parens if balanced
    s = trim_paren(s)
    # Normalize separators
    s = replace(s, r"[|,]+" => "|")
    s = replace(s, r"[&]+" => ".")
    s = replace(s, r"[.]+" => ".")
    return s
end

function trim_paren(s::AbstractString)
    isempty(s) && return s
    s = strip(s)
    s[1] != '(' && return s

    level = 0
    trim = true
    chars = collect(s)
    for (i, c) in enumerate(chars)
        if c == '('
            level += 1
        elseif c == ')'
            level -= 1
            if level == 0 && i == length(chars)
                return trim ? String(chars[2:end-1]) : s
            end
        end
        if level == 0 && i < length(chars)
            trim = false
        end
    end
    return s
end

function split_with_parens_intact(expr::String, split_ch::Char)
    token = ""
    result = String[]
    chars = collect(expr)
    i = 1
    while i <= length(chars)
        if chars[i] == split_ch
            push!(result, token)
            token = ""
        elseif chars[i] == '('
            # Read the paren block
            level = 0
            start = i
            while i <= length(chars)
                if chars[i] == '('
                    level += 1
                elseif chars[i] == ')'
                    level -= 1
                    if level == 0
                        break
                    end
                end
                i += 1
            end
            token *= String(chars[start:i])
        else
            token *= string(chars[i])
        end
        i += 1
    end
    if !isempty(token)
        push!(result, token)
    end
    return result
end

function mod_context!(st::N4LState, list::Vector{String}, op::AbstractString)
    for frag_raw in list
        frag = strip(frag_raw)
        isempty(frag) && continue
        if op == "+"
            st.context_state[frag] = true
        elseif op == "-"
            to_delete = String[]
            for cand in keys(st.context_state)
                and_parts = split_with_parens_intact(cand, '.')
                for part in and_parts
                    if occursin(frag, part)
                        push!(to_delete, cand)
                    end
                end
            end
            for d in to_delete
                delete!(st.context_state, d)
            end
        end
    end
    nothing
end

function context_eval!(st::N4LState, s::AbstractString, op::AbstractString)
    expr = clean_expression(s)
    or_parts = split_with_parens_intact(expr, '|')

    if occursin("(", s)
        parse_warning!(st, WARN_INADVISABLE_CONTEXT_EXPRESSION)
    end

    if op == "="
        reset_context_state!(st)
        mod_context!(st, or_parts, "+")
    else
        mod_context!(st, or_parts, op)
    end
    nothing
end

function extract_context_expression(token::AbstractString)
    parts = split(token, ":")
    for i in 2:length(parts)
        p = String(strip(String(parts[i])))
        if length(p) > 0
            return p
        end
    end
    return ""
end

# ──────────────────────────────────────────────────────────────────
# Sequence mode
# ──────────────────────────────────────────────────────────────────

function check_sequence_mode!(st::N4LState, context::String, mode::Char)
    if occursin("_sequence_", context)
        if mode == '+'
            st.sequence_mode = true
            st.sequence_start = true
            st.last_in_sequence = ""
        elseif mode == '-'
            st.sequence_mode = false
            st.sequence_start = false
        end
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Arrow lookup and link construction
# ──────────────────────────────────────────────────────────────────

function get_link_arrow_by_name(st::N4LState, token::AbstractString)
    name = if !isempty(token) && token[1] == '('
        token[2:end-1]
    else
        token
    end
    name = strip(name)

    weight = Float32(1.0)
    weightcount = 0
    ctx = String[]

    if occursin(",", name)
        reln = split(name, ",")
        name = strip(String(reln[1]))
        for i in 2:length(reln)
            part = strip(String(reln[i]))
            v = tryparse(Float64, part)
            if v !== nothing
                if v < 0
                    parse_error!(st, ERR_NEGATIVE_WEIGHT * token)
                    throw(N4LParseError(ERR_NEGATIVE_WEIGHT * token))
                end
                weightcount += 1
                if weightcount > 1
                    parse_error!(st, ERR_TOO_MANY_WEIGHTS * token)
                    throw(N4LParseError(ERR_TOO_MANY_WEIGHTS * token))
                end
                weight = Float32(v)
            else
                push!(ctx, part)
            end
        end
    end

    entry = get_arrow_by_name(name)
    if entry === nothing
        msg = "$ERR_NO_SUCH_ARROW($name)"
        parse_error!(st, msg)
        throw(N4LParseError(msg))
    end

    ctx_ptr = register_context!(vcat(collect(keys(filter(kv -> kv.second, st.context_state))), ctx))
    return Link(entry.ptr, weight, ctx_ptr, NO_NODE_PTR)
end

# ──────────────────────────────────────────────────────────────────
# Alias management
# ──────────────────────────────────────────────────────────────────

function lookup_alias(st::N4LState, alias::AbstractString, counter::Int)
    if !haskey(st.line_item_cache, alias) || counter > length(st.line_item_cache[alias])
        parse_error!(st, ERR_NO_SUCH_ALIAS)
        throw(N4LParseError(ERR_NO_SUCH_ALIAS))
    end
    return st.line_item_cache[alias][counter]
end

function resolve_aliased_item(st::N4LState, token::AbstractString)
    !occursin(".", token) && return token

    # Check if it's just a dollar amount or $$
    contig = split(token)[1]
    length(contig) == 1 && return token
    contig == "\$\$" && return token

    parts = split(token[2:end], ".")
    if length(parts) < 2
        parse_error!(st, ERR_MISSING_LINE_LABEL_IN_REFERENCE)
        throw(N4LParseError(ERR_MISSING_LINE_LABEL_IN_REFERENCE))
    end

    name = strip(String(parts[1]))
    number = tryparse(Int, strip(String(parts[2])))
    if number === nothing || number < 1
        parse_error!(st, ERR_BAD_ALIAS_REFERENCE)
        throw(N4LParseError(ERR_BAD_ALIAS_REFERENCE))
    end

    return lookup_alias(st, name, number)
end

function store_alias!(st::N4LState, name::AbstractString)
    if !isempty(st.line_alias)
        if !haskey(st.line_item_cache, st.line_alias)
            st.line_item_cache[st.line_alias] = String[]
        end
        push!(st.line_item_cache[st.line_alias], name)
    end
    nothing
end

function check_line_alias!(st::N4LState, token::AbstractString)
    contig = split(strip(token))[1]
    if token[1] == '@' && length(contig) == 1
        parse_error!(st, ERR_BAD_LABEL_OR_REF * token)
        throw(N4LParseError(ERR_BAD_LABEL_OR_REF * token))
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Annotation support
# ──────────────────────────────────────────────────────────────────

function strip_annotations(st::N4LState, fulltext::AbstractString)
    protected = false
    deloused = Char[]
    chars = collect(fulltext)
    r = 1
    while r <= length(chars)
        if chars[r] == '"'
            protected = !protected
        end
        if !protected
            skip, _ = embedded_symbol(st, chars, r)
            if skip > 0
                r += skip
                if r <= length(chars) && isspace(chars[r])
                    parse_warning!(st, ERR_NON_WORD_WHITE)
                end
                continue
            end
        end
        push!(deloused, chars[r])
        r += 1
    end
    return String(deloused)
end

function embedded_symbol(st::N4LState, runetext::Vector{Char}, offset::Int)
    offset > length(runetext) && return (0, "end of string")

    found_len = 0
    found = ""

    for (an, _) in st.annotation
        uni = collect(an)
        length(uni) == 0 && continue
        match = runetext[offset] == uni[1]

        for r in 1:length(uni)
            idx = offset + r - 1
            idx > length(runetext) && (match = false; break)
            if uni[r] != runetext[idx]
                match = false
                break
            end
            if idx >= length(runetext)
                match = false
                break
            end
            if idx + 1 <= length(runetext) && isspace(runetext[idx + 1])
                match = false
                break
            end
        end

        if match && length(an) > found_len
            found = an
            found_len = length(an)
        end
    end

    if found_len > 0
        return (found_len, found)
    end
    return (0, "UNKNOWN SYMBOL")
end

# ──────────────────────────────────────────────────────────────────
# Node handling
# ──────────────────────────────────────────────────────────────────

function idemp_add_node!(st::N4LState, s::AbstractString, intended_sequence::Bool)
    clean_version = strip_annotations(st, s)
    
    new_node = Node(clean_version, st.section_state)
    new_node.seq = new_node.seq || intended_sequence

    iptr = append_text_to_directory!(st.nd, new_node)

    # Set chapter/sequence on existing node
    idemp_add_chapter_seq_to_node!(st.nd, iptr.class, iptr.cptr, st.section_state, intended_sequence)

    if isempty(st.line_path)
        leg = Link(0, Float32(0.0), 0, iptr)
        push!(st.line_path, leg)
    end

    return iptr, clean_version
end

function idemp_add_context_to_node!(st::N4LState, nptr::NodePtr)
    nowhere = NO_NODE_PTR
    ctx_ptr = register_context!(collect(keys(filter(kv -> kv.second, st.context_state))))
    empty_link = Link(0, Float32(1.0), ctx_ptr, nowhere)
    append_link_to_node!(st.nd, nptr, empty_link, nowhere)
    nothing
end

function handle_node!(st::N4LState, annotated::AbstractString)
    clean_ptr, clean_version = idemp_add_node!(st, annotated, false)
    push!(st.line_item_refs, clean_ptr)

    if length(clean_version) != length(annotated)
        add_back_annotations!(st, clean_version, clean_ptr, annotated)
    end

    idemp_add_context_to_node!(st, clean_ptr)
    return clean_ptr
end

function append_link_to_node!(nd::NodeDirectory, from::NodePtr, link::Link, to::NodePtr)
    from_node = get_memory_node_from_ptr(nd, from)
    from_node.s == "" && return  # node not found
    
    new_link = Link(link.arr, link.wgt, link.ctx, to)
    entry = get_arrow_by_ptr(max(1, link.arr))
    stindex = entry.stindex
    
    if !(new_link in from_node.incidence[stindex])
        push!(from_node.incidence[stindex], new_link)
    end
    nothing
end

function idemp_add_link!(st::N4LState, from::AbstractString, frptr::NodePtr, link::Link, to::AbstractString, toptr::NodePtr; is_annotation::Bool=false)
    if from == to && !is_annotation
        parse_error!(st, ERR_ARROW_SELFLOOP)
        throw(N4LParseError(ERR_ARROW_SELFLOOP))
    end

    new_link = Link(link.arr, link.wgt, link.ctx, toptr)
    if !is_annotation
        push!(st.line_path, new_link)
    end

    if isempty(from) || isempty(to)
        parse_error!(st, ERR_MISSING_ITEM_SOMEWHERE * " (adding link)")
        throw(N4LParseError(ERR_MISSING_ITEM_SOMEWHERE))
    end

    append_link_to_node!(st.nd, frptr, new_link, toptr)

    # Add inverse link
    inv_ptr = get_inverse_arrow(link.arr)
    if inv_ptr !== nothing
        inv_entry = get_arrow_by_ptr(inv_ptr)
        inv_link = Link(inv_ptr, link.wgt, link.ctx, frptr)
        append_link_to_node!(st.nd, toptr, inv_link, frptr)
    end
    nothing
end

function add_back_annotations!(st::N4LState, cleantext::AbstractString, cleanptr::NodePtr, annotated::AbstractString)
    protected = false
    chars = collect(annotated)
    r = 1
    while r <= length(chars)
        if chars[r] == '"'
            protected = !protected
        elseif !protected
            skip, symb = embedded_symbol(st, chars, r)
            if skip > 0
                if haskey(st.annotation, symb)
                    link = get_link_arrow_by_name(st, st.annotation[symb])
                    this_item = extract_word(annotated, r + skip)
                    this_iptr, _ = idemp_add_node!(st, this_item, false)
                    idemp_add_link!(st, cleantext, cleanptr, link, this_item, this_iptr; is_annotation=true)
                end
                r += skip
                continue
            end
        end
        r += 1
    end
    nothing
end

function extract_word(fulltext::String, offset::Int)
    runetext = collect(fulltext)
    if isempty(runetext) || offset > length(runetext)
        return ""
    end
    word = Char[]
    protected = false
    pair_quote = ""

    for r in offset:length(runetext)
        if runetext[r] == '"' || runetext[r] == '\''
            protected = !protected
            pair_quote = string(runetext[r]) * " "
            continue
        end
        if !protected && !isletter(runetext[r])
            sword = strip(String(word))
            if !isempty(pair_quote)
                sword = strip(sword, [pair_quote[1]])
            end
            return sword
        end
        push!(word, runetext[r])
    end
    sword = strip(String(word))
    if !isempty(pair_quote)
        sword = strip(sword, [pair_quote[1]])
    end
    return sword
end

# ──────────────────────────────────────────────────────────────────
# Sequence linking
# ──────────────────────────────────────────────────────────────────

function link_up_story_sequence!(st::N4LState, this::AbstractString)
    if st.sequence_mode && this != st.last_in_sequence
        if st.line_item_counter == 1 && !isempty(st.last_in_sequence)
            if st.sequence_start
                last_iptr, _ = idemp_add_node!(st, st.last_in_sequence, true)
                st.sequence_start = false
            else
                last_iptr, _ = idemp_add_node!(st, st.last_in_sequence, false)
            end
            this_iptr, _ = idemp_add_node!(st, this, false)
            link = get_link_arrow_by_name(st, "(then)")
            append_link_to_node!(st.nd, last_iptr, link, this_iptr)

            inv_ptr = get_inverse_arrow(link.arr)
            if inv_ptr !== nothing
                inv_link = Link(inv_ptr, link.wgt, link.ctx, last_iptr)
                append_link_to_node!(st.nd, this_iptr, inv_link, last_iptr)
            end
        end
        st.last_in_sequence = this
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Section/chapter checks
# ──────────────────────────────────────────────────────────────────

function check_section!(st::N4LState, item::AbstractString)
    if isempty(st.section_state)
        parse_error!(st, ERR_MISSING_SECTION)
        throw(N4LParseError(ERR_MISSING_SECTION))
    end
    nothing
end

function check_chapter!(st::N4LState, name::AbstractString)
    if !isempty(name) && name[1] == ':'
        parse_error!(st, WARN_CHAPTER_CLASS_MIXUP * name)
        throw(N4LParseError(WARN_CHAPTER_CLASS_MIXUP * name))
    end
    if occursin(",", name)
        parse_error!(st, ERR_CHAPTER_COMMA * name)
        throw(N4LParseError(ERR_CHAPTER_COMMA * name))
    end
    st.sequence_mode = false
    st.sequence_start = false
    nothing
end

function note_to_self(st::N4LState, s::AbstractString)
    length(s) <= 2 * WORD_MISTAKE_LEN && return false
    if length(s) > 50 && endswith(s, ".")
        return false
    end
    for r in s
        if !isuppercase(r) && (isletter(r) || isnumeric(r))
            return false
        end
    end
    return true
end

# ──────────────────────────────────────────────────────────────────
# Classify token roles (N4L language)
# ──────────────────────────────────────────────────────────────────

function classify_token_role!(st::N4LState, token::AbstractString)
    isempty(token) && return

    c = token[1]

    if c == ':'
        expression = extract_context_expression(token)
        check_sequence_mode!(st, expression, '+')
        st.line_item_state = ROLE_CONTEXT
        assess_grammar_completions!(st, expression, st.line_item_state)

    elseif c == '+'
        expression = extract_context_expression(token)
        check_sequence_mode!(st, expression, '+')
        st.line_item_state = ROLE_CONTEXT_ADD
        assess_grammar_completions!(st, expression, st.line_item_state)

    elseif c == '-'
        if endswith(token, ":")
            expression = extract_context_expression(token)
            check_sequence_mode!(st, expression, '-')
            st.line_item_state = ROLE_CONTEXT_SUBTRACT
            assess_grammar_completions!(st, expression, st.line_item_state)
        elseif isempty(st.section_state)
            section = strip(token[2:end])
            st.line_item_state = ROLE_SECTION
            assess_grammar_completions!(st, section, st.line_item_state)
        else
            if !haskey(st.line_item_cache, "THIS")
                st.line_item_cache["THIS"] = String[]
            end
            push!(st.line_item_cache["THIS"], token)
            store_alias!(st, token)
            assess_grammar_completions!(st, token, st.line_item_state)
            st.line_item_state = ROLE_EVENT
            st.line_item_counter += 1
        end

    elseif c == '('
        if st.line_item_state == ROLE_RELATION
            parse_error!(st, ERR_MISSING_ITEM_RELN)
            throw(N4LParseError(ERR_MISSING_ITEM_RELN))
        end
        link = get_link_arrow_by_name(st, token)
        st.line_item_state = ROLE_RELATION
        if !haskey(st.line_reln_cache, "THIS")
            st.line_reln_cache["THIS"] = Link[]
        end
        push!(st.line_reln_cache["THIS"], link)
        st.line_reln_counter += 1

    elseif c == '"'
        result = lookup_alias(st, "PREV", st.line_item_counter)
        if !haskey(st.line_item_cache, "THIS")
            st.line_item_cache["THIS"] = String[]
        end
        push!(st.line_item_cache["THIS"], result)
        store_alias!(st, result)
        assess_grammar_completions!(st, result, st.line_item_state)
        st.line_item_state = ROLE_EVENT
        st.line_item_counter += 1

    elseif c == '@'
        st.line_item_state = ROLE_LINE_ALIAS
        token = strip(token)
        st.line_alias = token[2:end]
        check_line_alias!(st, token)

    elseif c == '$'
        check_line_alias!(st, token)
        actual = resolve_aliased_item(st, token)
        if !haskey(st.line_item_cache, "THIS")
            st.line_item_cache["THIS"] = String[]
        end
        push!(st.line_item_cache["THIS"], actual)
        assess_grammar_completions!(st, actual, st.line_item_state)
        st.line_item_state = ROLE_LOOKUP
        st.line_item_counter += 1

    else
        if !haskey(st.line_item_cache, "THIS")
            st.line_item_cache["THIS"] = String[]
        end
        push!(st.line_item_cache["THIS"], token)
        store_alias!(st, token)
        assess_grammar_completions!(st, token, st.line_item_state)
        st.line_item_state = ROLE_EVENT
        st.line_item_counter += 1
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Assess grammar completions (compile step)
# ──────────────────────────────────────────────────────────────────

function assess_grammar_completions!(st::N4LState, token::AbstractString, prior_state::Int)
    isempty(token) && return

    this_item = token
    BOM_UTF8 = "\xef\xbb\xbf"
    this_item == BOM_UTF8 && return

    if prior_state == ROLE_RELATION
        idx = st.line_item_counter - 1  # 1-based: last stored item
        if idx < 1
            parse_error!(st, ERR_MISSING_ITEM_SOMEWHERE)
            throw(N4LParseError(ERR_MISSING_ITEM_SOMEWHERE))
        end
        last_item = st.line_item_cache["THIS"][idx]
        last_reln = st.line_reln_cache["THIS"][st.line_reln_counter]
        last_iptr = st.line_item_refs[idx]
        this_iptr = handle_node!(st, this_item)
        idemp_add_link!(st, last_item, last_iptr, last_reln, this_item, this_iptr)
        check_section!(st, this_item)

    elseif prior_state == ROLE_CONTEXT
        context_eval!(st, this_item, "=")
        check_section!(st, this_item)

    elseif prior_state == ROLE_CONTEXT_ADD
        context_eval!(st, this_item, "+")
        check_section!(st, this_item)

    elseif prior_state == ROLE_CONTEXT_SUBTRACT
        context_eval!(st, this_item, "-")
        check_section!(st, this_item)

    elseif prior_state == ROLE_SECTION
        check_chapter!(st, this_item)
        st.section_state = this_item

    else
        check_section!(st, this_item)
        if note_to_self(st, token)
            parse_warning!(st, WARN_NOTE_TO_SELF * " ($token)")
        end
        handle_node!(st, this_item)
        link_up_story_sequence!(st, this_item)
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Config classification
# ──────────────────────────────────────────────────────────────────

function classify_config_role!(st::N4LState, token::AbstractString)
    isempty(token) && return

    c = token[1]

    # Section definition
    if c == '-' && st.line_item_state == ROLE_BLANK_LINE
        st.section_state = strip(token[2:end])
        st.line_item_state = ROLE_SECTION
        return
    end

    # Handle context lines in config (e.g., :: context :: lines)
    if c == ':'
        # Just skip context lines in config - they annotate but don't affect arrows
        return
    end

    sect = st.section_state

    if sect in ("leadsto", "contains", "properties")
        if c == '+'
            st.fwd_arrow = strip(token[2:end])
            st.line_item_state = HAVE_PLUS
        elseif c == '-'
            st.bwd_arrow = strip(token[2:end])
            st.line_item_state = HAVE_MINUS
        elseif c == '('
            reln = strip(token[2:end-1])
            if st.line_item_state == HAVE_MINUS
                st.bwd_index = insert_arrow!(sect, reln, st.bwd_arrow, "-")
                insert_inverse_arrow!(st.fwd_index, st.bwd_index)
            elseif st.line_item_state == HAVE_PLUS
                st.fwd_index = insert_arrow!(sect, reln, st.fwd_arrow, "+")
            else
                parse_error!(st, ERR_BAD_ABBRV)
                throw(N4LParseError(ERR_BAD_ABBRV))
            end
        end

    elseif sect == "similarity"
        if c == '('
            reln = strip(token[2:end-1])
            if st.line_item_state == HAVE_MINUS
                idx = insert_arrow!(sect, reln, st.bwd_arrow, "both")
                insert_inverse_arrow!(idx, idx)
            end
        elseif c == '+' || c == '-'
            parse_error!(st, ERR_SIMILAR_NO_SIGN)
            throw(N4LParseError(ERR_SIMILAR_NO_SIGN))
        else
            similarity = strip(token)
            st.fwd_arrow = similarity
            st.bwd_arrow = similarity
            st.line_item_state = HAVE_MINUS
        end

    elseif sect == "annotations"
        if c == '('
            if st.line_item_state != HAVE_PLUS
                parse_error!(st, ERR_ANNOTATION_MISSING)
            end
            st.fwd_arrow = strip_config_paren(token)

            if haskey(st.annotation, st.last_in_sequence) && st.annotation[st.last_in_sequence] != st.fwd_arrow
                parse_error!(st, ERR_ANNOTATION_REDEFINE)
                throw(N4LParseError(ERR_ANNOTATION_REDEFINE))
            end
            st.annotation[st.last_in_sequence] = st.fwd_arrow
            st.line_item_state = ROLE_BLANK_LINE
        else
            for r in token
                if isletter(r)
                    parse_error!(st, ERR_ANNOTATION_BAD)
                    break
                end
            end
            if !isempty(token) && (token[1] == '+' || token[1] == '-')
                parse_error!(st, ERR_ILLEGAL_ANNOT_CHAR)
                throw(N4LParseError(ERR_ILLEGAL_ANNOT_CHAR))
            end
            st.line_item_state = HAVE_PLUS
            st.last_in_sequence = token
        end

    elseif sect == "closures"
        if c == '('
            if st.line_item_state == ROLE_RESULT
                # closure result - skip for now (closures not fully implemented)
                st.line_item_state = ROLE_BLANK_LINE
            else
                st.line_item_counter += 1
                if !haskey(st.line_item_cache, "THIS")
                    st.line_item_cache["THIS"] = String[]
                end
                push!(st.line_item_cache["THIS"], token)
                st.line_item_state = ROLE_COMPOSITION
            end
        elseif c == '+' || c == ','
            st.line_item_state = ROLE_COMPOSITION
        elseif c == '='
            st.line_item_state = ROLE_RESULT
        else
            parse_error!(st, ERR_ILLEGAL_CONFIGURATION * " " * sect)
            throw(N4LParseError(ERR_ILLEGAL_CONFIGURATION * " " * sect))
        end

    else
        if !isempty(sect)
            parse_error!(st, ERR_ILLEGAL_CONFIGURATION * " " * sect)
            throw(N4LParseError(ERR_ILLEGAL_CONFIGURATION * " " * sect))
        end
    end
    nothing
end

function strip_config_paren(token::AbstractString)
    t = strip(token[2:end])
    if !isempty(t) && t[1] == '('
        t = strip(t[2:end])
    end
    if !isempty(t) && t[end] == ')'
        t = t[1:end-1]
    end
    return strip(t)
end

# ──────────────────────────────────────────────────────────────────
# Mandatory arrows
# ──────────────────────────────────────────────────────────────────

"""
    add_mandatory_arrows!()

Register the mandatory built-in arrow types required by the SST system.
This includes sequence arrows (`then`/`from`), extract arrows, fragment
arrows, intent/ambient property arrows, and URL/image arrows.
Called automatically by [`parse_n4l`](@ref).
"""
function add_mandatory_arrows!()
    register_context!(["any"])

    arr = insert_arrow!("leadsto", "empty", "debug", "+")
    inv = insert_arrow!("leadsto", "void", "unbug", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("contains", CONT_FINDS_S, CONT_FINDS_L, "+")
    inv = insert_arrow!("contains", INV_CONT_FOUND_IN_S, INV_CONT_FOUND_IN_L, "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("contains", CONT_FRAG_S, CONT_FRAG_L, "+")
    inv = insert_arrow!("contains", INV_CONT_FRAG_IN_S, INV_CONT_FRAG_IN_L, "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", EXPR_INTENT_S, EXPR_INTENT_L, "+")
    inv = insert_arrow!("properties", INV_EXPR_INTENT_S, INV_EXPR_INTENT_L, "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", EXPR_AMBIENT_S, EXPR_AMBIENT_L, "+")
    inv = insert_arrow!("properties", INV_EXPR_AMBIENT_S, INV_EXPR_AMBIENT_L, "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("leadsto", SEQUENCE_RELN, SEQUENCE_RELN_LONG, "+")
    inv = insert_arrow!("leadsto", SEQUENCE_RELN_INV, SEQUENCE_RELN_INV_LONG, "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "url", "has URL", "+")
    inv = insert_arrow!("properties", "isurl", "is a URL for", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "img", "has image", "+")
    inv = insert_arrow!("properties", "isimg", "is an image for", "-")
    insert_inverse_arrow!(arr, inv)

    # ── Extra arrows needed by SSTorytime/examples/ ──

    # ownership.n4l
    arr = insert_arrow!("properties", "rents", "rents from", "+")
    inv = insert_arrow!("properties", "rented-by", "is rented by", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "employs", "employs", "+")
    inv = insert_arrow!("properties", "employed-by", "is employed by", "-")
    insert_inverse_arrow!(arr, inv)

    # PromiseTheory.n4l
    arr = insert_arrow!("properties", "expresses", "expresses", "+")
    inv = insert_arrow!("properties", "expressed-by", "is expressed by", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "has intended promiser", "has intended promiser", "+")
    inv = insert_arrow!("properties", "is intended promiser of", "is intended promiser of", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "has intended promisee", "has intended promisee", "+")
    inv = insert_arrow!("properties", "is intended promisee of", "is intended promisee of", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("nearness", "may be influenced by", "may be influenced by", "+")
    inv = insert_arrow!("nearness", "may influence", "may influence", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("nearness", "has overlap", "has overlap with", "+")
    inv = insert_arrow!("nearness", "overlaps-with", "overlaps with", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "has promiser", "has promiser", "+")
    inv = insert_arrow!("properties", "is promiser of", "is promiser of", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("leadsto", "imposes", "imposes on", "+")
    inv = insert_arrow!("leadsto", "imposed-by", "is imposed on by", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "accepts", "accepts", "+")
    inv = insert_arrow!("properties", "accepted-by", "is accepted by", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "observes", "observes", "+")
    inv = insert_arrow!("properties", "observed-by", "is observed by", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "has accusee", "has accusee", "+")
    inv = insert_arrow!("properties", "is accusee of", "is accusee of", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("properties", "has promisee", "has promisee", "+")
    inv = insert_arrow!("properties", "is promisee of", "is promisee of", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("nearness", "observed by", "observed by", "+")
    inv = insert_arrow!("nearness", "observer-of", "is an observer of", "-")
    insert_inverse_arrow!(arr, inv)

    # inferences.n4l
    arr = insert_arrow!("nearness", "!eq", "is not equal to", "+")
    inv = insert_arrow!("nearness", "!eq-inv", "is not equal to (inverse)", "-")
    insert_inverse_arrow!(arr, inv)

    arr = insert_arrow!("nearness", "cf", "compare with", "+")
    inv = insert_arrow!("nearness", "cf-inv", "compared from", "-")
    insert_inverse_arrow!(arr, inv)

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Config file reading
# ──────────────────────────────────────────────────────────────────

"""
    find_config_dir(search_paths=nothing) -> Union{String, Nothing}

Search for the SSTconfig directory. Checks:
1. SST_CONFIG_PATH environment variable
2. ./SSTconfig, ../SSTconfig, ../../SSTconfig
3. Custom search_paths if provided
"""
function find_config_dir(search_paths::Union{Nothing, Vector{String}}=nothing)
    env_path = get(ENV, "SST_CONFIG_PATH", "")
    if !isempty(env_path) && isdir(env_path)
        return env_path
    end

    default_paths = ["./SSTconfig", "../SSTconfig", "../../SSTconfig"]
    paths = search_paths !== nothing ? vcat(search_paths, default_paths) : default_paths

    for p in paths
        if isdir(p)
            return p
        end
    end
    return nothing
end

"""
    read_config_files(config_dir::String) -> Vector{String}

Return the list of config file paths from an SSTconfig directory.
"""
function read_config_files(config_dir::String)
    files = ["arrows-LT-1.sst", "arrows-NR-0.sst", "arrows-CN-2.sst",
             "arrows-EP-3.sst", "annotations.sst", "closures.sst"]
    return [joinpath(config_dir, f) for f in files if isfile(joinpath(config_dir, f))]
end

"""
    read_file_as_chars(filename::String) -> Vector{Char}

Read a UTF-8 file and return as a vector of Chars, normalizing
non-ASCII quotes.
"""
function read_file_as_chars(filename::String)
    text = collect(read(filename, String))
    for i in eachindex(text)
        if text[i] == NON_ASCII_LQUOTE || text[i] == NON_ASCII_RQUOTE
            text[i] = '"'
        end
    end
    return text
end

"""
    parse_config!(st::N4LState, src::Vector{Char})

Parse an SSTconfig file, registering arrows.
"""
function parse_config!(st::N4LState, src::Vector{Char})
    pos = 1
    while pos <= length(src)
        pos = skip_whitespace!(st, src, pos)
        pos > length(src) && break
        token, pos = get_config_token(st, src, pos)
        classify_config_role!(st, token)
    end
    nothing
end

"""
    parse_config_file(filename::String; st::N4LState=N4LState()) -> N4LState

Parse a single config file and register its arrows.
"""
function parse_config_file(filename::String; st::N4LState=N4LState())
    !isfile(filename) && throw(N4LParseError(ERR_NO_SUCH_FILE_FOUND * filename))
    st.configuring = true
    st.current_file = filename
    st.line_item_state = ROLE_BLANK_LINE
    st.line_num = 1
    st.section_state = ""
    src = read_file_as_chars(filename)
    parse_config!(st, src)
    st.configuring = false
    return st
end

# ──────────────────────────────────────────────────────────────────
# New file state reset
# ──────────────────────────────────────────────────────────────────

function new_file!(st::N4LState, filename::AbstractString)
    st.current_file = filename
    st.line_item_state = ROLE_BLANK_LINE
    st.line_num = 1
    st.line_item_cache = Dict{String, Vector{String}}()
    st.line_reln_cache = Dict{String, Vector{Link}}()
    st.line_item_refs = NodePtr[]
    st.line_item_counter = 1
    st.line_reln_counter = 0
    st.line_alias = ""
    st.last_in_sequence = ""
    st.line_path = Link[]
    st.sequence_mode = false
    st.fwd_arrow = ""
    st.bwd_arrow = ""
    st.section_state = ""
    reset_context_state!(st)
    context_eval!(st, "any", "=")
    nothing
end

# ──────────────────────────────────────────────────────────────────
# N4L parsing
# ──────────────────────────────────────────────────────────────────

function parse_n4l_source!(st::N4LState, src::Vector{Char})
    pos = 1
    while pos <= length(src)
        try
            pos = skip_whitespace!(st, src, pos)
            pos > length(src) && break
            token, pos = get_token(st, src, pos)
            classify_token_role!(st, token)
        catch ex
            if ex isa N4LParseError
                # Error already recorded via parse_error!(); skip to next line
                while pos <= length(src) && src[pos] != '\n'
                    pos += 1
                end
                if pos <= length(src)
                    pos += 1  # skip the newline itself
                end
            else
                rethrow()
            end
        end
    end

    if dangler(st)
        parse_error!(st, ERR_MISSING_EVENT)
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────

"""
    N4LResult

Result of parsing N4L input.

# Fields
- `errors::Vector{String}`: parse errors encountered
- `warnings::Vector{String}`: parse warnings encountered
- `nd::NodeDirectory`: the node directory populated by the parser
- `state::N4LState`: the final parser state
"""
struct N4LResult
    errors::Vector{String}
    warnings::Vector{String}
    nd::NodeDirectory
    state::N4LState
end

"""
    has_errors(r::N4LResult) -> Bool

Return `true` if the parse result contains any errors.
"""
has_errors(r::N4LResult) = !isempty(r.errors)

"""
    has_warnings(r::N4LResult) -> Bool

Return `true` if the parse result contains any warnings.
"""
has_warnings(r::N4LResult) = !isempty(r.warnings)

"""
    parse_n4l(input::String; verbose=false, config_dir=nothing, load_config=true) -> N4LResult

Parse N4L text and return the result. This is the main entry point.

- `input`: N4L source text
- `verbose`: print diagnostic output
- `config_dir`: path to SSTconfig directory (auto-detected if not given)
- `load_config`: whether to load SSTconfig arrow definitions
"""
function parse_n4l(input::String; verbose::Bool=false, config_dir::Union{String, Nothing}=nothing, load_config::Bool=true)
    reset_arrows!()
    reset_contexts!()

    st = N4LState(verbose=verbose)
    add_mandatory_arrows!()

    if load_config
        cdir = config_dir !== nothing ? config_dir : find_config_dir()
        if cdir !== nothing
            config_files = read_config_files(cdir)
            for cf in config_files
                st.configuring = true
                st.current_file = cf
                st.line_item_state = ROLE_BLANK_LINE
                st.line_num = 1
                st.section_state = ""
                src = read_file_as_chars(cf)
                parse_config!(st, src)
            end
            st.configuring = false
        end
    end

    new_file!(st, "<string>")
    src = collect(input)
    # Normalize non-ASCII quotes
    for i in eachindex(src)
        if src[i] == NON_ASCII_LQUOTE || src[i] == NON_ASCII_RQUOTE
            src[i] = '"'
        end
    end
    parse_n4l_source!(st, src)

    return N4LResult(copy(st.errors), copy(st.warnings), st.nd, st)
end

"""
    parse_n4l_file(filename::String; verbose=false, config_dir=nothing, load_config=true) -> N4LResult

Parse an N4L file and return the result.
"""
function parse_n4l_file(filename::String; verbose::Bool=false, config_dir::Union{String, Nothing}=nothing, load_config::Bool=true)
    !isfile(filename) && throw(N4LParseError(ERR_NO_SUCH_FILE_FOUND * filename))
    input = read(filename, String)
    return parse_n4l(input; verbose=verbose, config_dir=config_dir, load_config=load_config)
end
