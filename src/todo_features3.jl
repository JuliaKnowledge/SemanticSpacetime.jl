#=
ToDo features batch 3:
  1. Log Data Analysis Pipeline  – parse structured logs into SST graphs
  2. Text Breakdown Assistant    – heuristic entity/relationship extraction
=#

# ══════════════════════════════════════════════════════════════════
# 1. Log Data Analysis Pipeline
# ══════════════════════════════════════════════════════════════════

"""
    LogFormat

Enum for supported log formats.
"""
@enum LogFormat LOG_SYSLOG LOG_JSON LOG_CSV LOG_TSV LOG_CUSTOM

"""
    LogParseConfig

Configuration for log parsing into SST.
"""
struct LogParseConfig
    format::LogFormat
    timestamp_field::String
    message_field::String
    level_field::String
    source_field::String
    chapter::String
    link_sequential::Bool
    extract_patterns::Vector{Regex}
end

"""
    default_log_config() -> LogParseConfig

Return default configuration for log parsing (syslog format).
"""
function default_log_config()
    LogParseConfig(
        LOG_SYSLOG,
        "timestamp",
        "message",
        "level",
        "source",
        "logs",
        true,
        Regex[],
    )
end

# ── Individual line parsers ──────────────────────────────────────

const _SYSLOG_RE = r"^(\w{3}\s+\d+\s+[\d:]+)\s+(\S+)\s+(\S+?)(?:\[(\d+)\])?:\s+(.*)$"

"""
    parse_syslog_line(line::String) -> NamedTuple

Parse a syslog-format line:
`"Jan 15 10:30:45 hostname service[pid]: message"`
"""
function parse_syslog_line(line::String)
    m = match(_SYSLOG_RE, line)
    if m === nothing
        return (timestamp="", source="", service="", pid="", message=strip(line), level="INFO")
    end
    (
        timestamp = String(m.captures[1]),
        source    = String(m.captures[2]),
        service   = String(m.captures[3]),
        pid       = m.captures[4] === nothing ? "" : String(m.captures[4]),
        message   = String(m.captures[5]),
        level     = "INFO",
    )
end

"""
    parse_json_log_line(line::String; config::LogParseConfig=default_log_config()) -> NamedTuple

Parse a JSON log line.
"""
function parse_json_log_line(line::String; config::LogParseConfig=default_log_config())
    stripped = strip(line)
    isempty(stripped) && return (timestamp="", source="", message="", level="")
    obj = JSON3.read(stripped)
    ts_sym  = Symbol(config.timestamp_field)
    msg_sym = Symbol(config.message_field)
    lvl_sym = Symbol(config.level_field)
    src_sym = Symbol(config.source_field)
    (
        timestamp = haskey(obj, ts_sym)  ? string(obj[ts_sym])  : "",
        source    = haskey(obj, src_sym) ? string(obj[src_sym]) : "",
        message   = haskey(obj, msg_sym) ? string(obj[msg_sym]) : "",
        level     = haskey(obj, lvl_sym) ? string(obj[lvl_sym]) : "INFO",
    )
end

"""
    parse_csv_log(text::String; delimiter::Char=',', header::Bool=true) -> Vector{NamedTuple}

Parse CSV/TSV log data. First row is treated as header when `header=true`.
"""
function parse_csv_log(text::String; delimiter::Char=',', header::Bool=true)
    lines = filter(!isempty, map(strip, split(text, '\n')))
    isempty(lines) && return NamedTuple[]

    results = NamedTuple{(:timestamp, :source, :message, :level), NTuple{4,String}}[]

    if header && length(lines) >= 2
        cols = map(strip, split(lines[1], delimiter))
        col_lower = map(lowercase, cols)
        ts_idx  = findfirst(c -> c in ("timestamp", "time", "date", "@timestamp"), col_lower)
        msg_idx = findfirst(c -> c in ("message", "msg", "text", "body"), col_lower)
        lvl_idx = findfirst(c -> c in ("level", "severity", "loglevel"), col_lower)
        src_idx = findfirst(c -> c in ("source", "host", "hostname", "origin"), col_lower)
        for i in 2:length(lines)
            fields = map(strip, split(lines[i], delimiter))
            push!(results, (
                timestamp = ts_idx  !== nothing && ts_idx  <= length(fields) ? fields[ts_idx]  : "",
                source    = src_idx !== nothing && src_idx <= length(fields) ? fields[src_idx] : "",
                message   = msg_idx !== nothing && msg_idx <= length(fields) ? fields[msg_idx] : "",
                level     = lvl_idx !== nothing && lvl_idx <= length(fields) ? fields[lvl_idx] : "INFO",
            ))
        end
    else
        for line in lines
            fields = map(strip, split(line, delimiter))
            push!(results, (
                timestamp = length(fields) >= 1 ? fields[1] : "",
                source    = "",
                message   = length(fields) >= 2 ? join(fields[2:end], string(delimiter)) : "",
                level     = "INFO",
            ))
        end
    end
    return results
end

"""
    parse_log_to_sst!(store::MemoryStore, text::String;
                      config::LogParseConfig=default_log_config()) -> Dict{String,Int}

Parse log text and create SST nodes for each log entry.
- Each entry becomes a node in the configured chapter
- Sequential entries are linked via LEADSTO (`then`) if `link_sequential=true`
- Log level, source, and extracted patterns become EXPRESS (`note`) annotations
- Timestamp becomes a timeline annotation

Returns statistics: `entries_parsed`, `nodes_created`, `links_created`.
"""
function parse_log_to_sst!(store::MemoryStore, text::String;
                           config::LogParseConfig=default_log_config())
    stats = Dict{String,Int}("entries_parsed" => 0, "nodes_created" => 0, "links_created" => 0)

    # Parse entries depending on format
    entries = if config.format == LOG_JSON
        lines = filter(l -> !isempty(strip(l)), split(text, '\n'))
        [parse_json_log_line(String(l); config=config) for l in lines]
    elseif config.format == LOG_CSV
        parse_csv_log(text; delimiter=',', header=true)
    elseif config.format == LOG_TSV
        parse_csv_log(text; delimiter='\t', header=true)
    else  # LOG_SYSLOG or LOG_CUSTOM
        lines = filter(l -> !isempty(strip(l)), split(text, '\n'))
        [parse_syslog_line(String(l)) for l in lines]
    end

    stats["entries_parsed"] = length(entries)

    prev_node = nothing
    note_arrow  = get_arrow_by_name("note")
    then_arrow  = get_arrow_by_name("then")

    for entry in entries
        msg = entry.message
        isempty(msg) && continue

        node = mem_vertex!(store, msg, config.chapter)
        stats["nodes_created"] += 1

        # Annotate with level
        if note_arrow !== nothing && !isempty(entry.level)
            lvl_node = mem_vertex!(store, entry.level, config.chapter)
            mem_edge!(store, node, "note", lvl_node)
            stats["links_created"] += 1
        end

        # Annotate with source
        if note_arrow !== nothing && !isempty(entry.source)
            src_node = mem_vertex!(store, entry.source, config.chapter)
            mem_edge!(store, node, "note", src_node)
            stats["links_created"] += 1
        end

        # Annotate with timestamp
        if note_arrow !== nothing && !isempty(entry.timestamp)
            ts_node = mem_vertex!(store, entry.timestamp, config.chapter)
            mem_edge!(store, node, "note", ts_node)
            stats["links_created"] += 1
        end

        # Extract patterns
        for pat in config.extract_patterns
            for m in eachmatch(pat, msg)
                if note_arrow !== nothing
                    pat_node = mem_vertex!(store, m.match, config.chapter)
                    mem_edge!(store, node, "note", pat_node)
                    stats["links_created"] += 1
                end
            end
        end

        # Sequential LEADSTO chain
        if config.link_sequential && prev_node !== nothing && then_arrow !== nothing
            mem_edge!(store, prev_node, "then", node)
            stats["links_created"] += 1
        end

        prev_node = node
    end

    return stats
end

# ══════════════════════════════════════════════════════════════════
# 2. Text Breakdown Assistant
# ══════════════════════════════════════════════════════════════════

"""
    EntitySuggestion

A suggested entity extracted from text.
"""
struct EntitySuggestion
    text::String
    entity_type::Symbol       # :person, :place, :organization, :concept, :event, :thing
    confidence::Float64       # 0.0 to 1.0
    span::UnitRange{Int}      # position in original text
end

"""
    LinkSuggestion

A suggested relationship between two entities.
"""
struct LinkSuggestion
    source::String
    target::String
    arrow_name::String
    sttype::STType
    confidence::Float64
end

"""
    TextBreakdown

Complete analysis of a text passage.
"""
struct TextBreakdown
    original::String
    sentences::Vector{String}
    entities::Vector{EntitySuggestion}
    links::Vector{LinkSuggestion}
    n4l_suggestion::String
end

# ── Heuristic entity extraction ─────────────────────────────────

const _MONTH_NAMES = Set([
    "january","february","march","april","may","june",
    "july","august","september","october","november","december",
    "jan","feb","mar","apr","jun","jul","aug","sep","oct","nov","dec",
])

const _DAY_NAMES = Set([
    "monday","tuesday","wednesday","thursday","friday","saturday","sunday",
    "mon","tue","wed","thu","fri","sat","sun",
])

const _DATE_RE = r"\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b"

"""
    identify_entities(text::String) -> Vector{EntitySuggestion}

Extract named entities and concepts from text using heuristic NLP patterns.
"""
function identify_entities(text::String)
    entities = EntitySuggestion[]
    seen = Set{String}()

    # Dates  (YYYY-MM-DD etc.)
    for m in eachmatch(_DATE_RE, text)
        key = m.match
        key in seen && continue
        push!(seen, key)
        push!(entities, EntitySuggestion(key, :event, 0.9, m.offset:m.offset+length(key)-1))
    end

    # Quoted strings → concepts
    for m in eachmatch(r"\"([^\"]+)\"", text)
        key = m.captures[1]
        key in seen && continue
        push!(seen, key)
        push!(entities, EntitySuggestion(key, :concept, 0.8, m.offset:m.offset+length(m.match)-1))
    end

    # Month / day names → temporal events
    for m in eachmatch(r"\b([A-Za-z]+)\b", text)
        w = m.captures[1]
        if lowercase(w) in _MONTH_NAMES || lowercase(w) in _DAY_NAMES
            w in seen && continue
            push!(seen, w)
            push!(entities, EntitySuggestion(w, :event, 0.7, m.offset:m.offset+length(w)-1))
        end
    end

    # Capitalized words not at sentence start → proper nouns
    sentences_ranges = _sentence_start_offsets(text)
    for m in eachmatch(r"\b([A-Z][a-z]{2,})\b", text)
        w = m.captures[1]
        w in seen && continue
        lowercase(w) in _MONTH_NAMES && continue
        lowercase(w) in _DAY_NAMES && continue
        # Skip if at sentence start
        _is_sentence_start(m.offset, sentences_ranges) && continue
        push!(seen, w)
        push!(entities, EntitySuggestion(w, :person, 0.6, m.offset:m.offset+length(w)-1))
    end

    # Abstract concept suffixes: -tion, -ment, -ness
    for m in eachmatch(r"\b([a-z]+(?:tion|ment|ness))\b"i, text)
        w = m.captures[1]
        lowercase(w) in seen && continue
        push!(seen, lowercase(w))
        push!(entities, EntitySuggestion(lowercase(w), :concept, 0.5, m.offset:m.offset+length(w)-1))
    end

    # Words after "the" / "a" / "an" in subject position → things
    for m in eachmatch(r"\b(?:the|a|an)\s+([a-z]\w+)\b"i, text)
        w = lowercase(m.captures[1])
        w in seen && continue
        push!(seen, w)
        push!(entities, EntitySuggestion(w, :thing, 0.4, m.offset:m.offset+length(m.match)-1))
    end

    return entities
end

# Helpers for sentence-start detection
function _sentence_start_offsets(text::String)
    offsets = Int[1]
    for m in eachmatch(r"[.!?]\s+", text)
        push!(offsets, m.offset + length(m.match))
    end
    return offsets
end

function _is_sentence_start(offset::Int, starts::Vector{Int})
    for s in starts
        if abs(offset - s) <= 1
            return true
        end
    end
    return false
end

# ── Link suggestion ──────────────────────────────────────────────

const _LEADSTO_PATTERNS  = [r"\bcauses?\b"i, r"\bleads?\s+to\b"i, r"\bresults?\s+in\b"i,
                            r"\btriggers?\b"i, r"\bbefore\b"i, r"\bafter\b"i,
                            r"\bthen\b"i, r"\bfollowed\s+by\b"i]
const _CONTAINS_PATTERNS = [r"\bcontains?\b"i, r"\bincludes?\b"i, r"\bhas\b"i,
                            r"\bconsists?\s+of\b"i]
const _EXPRESS_PATTERNS  = [r"\bis\b"i, r"\bmeans?\b"i, r"\brepresents?\b"i,
                            r"\bdescribes?\b"i]
const _NEAR_PATTERNS     = [r"\blike\b"i, r"\bsimilar\s+to\b"i, r"\bnear\b"i,
                            r"\bresembles?\b"i]

"""
    suggest_links(text::String, entities::Vector{EntitySuggestion}) -> Vector{LinkSuggestion}

Given extracted entities, suggest SST relationships based on textual
proximity and verb/preposition patterns.
"""
function suggest_links(text::String, entities::Vector{EntitySuggestion})
    links = LinkSuggestion[]
    length(entities) < 2 && return links

    # Sort entities by span start
    sorted = sort(entities; by=e -> first(e.span))

    # For each consecutive pair, check the text between them for patterns
    for i in 1:length(sorted)-1
        e1 = sorted[i]
        e2 = sorted[i+1]
        gap_start = min(last(e1.span) + 1, length(text))
        gap_end   = min(first(e2.span) - 1, length(text))
        gap_start > gap_end && continue
        between = text[gap_start:gap_end]

        arrow_name, sttype, conf = _detect_relation(between)
        push!(links, LinkSuggestion(e1.text, e2.text, arrow_name, sttype, conf))
    end

    return links
end

function _detect_relation(text::String)
    for pat in _LEADSTO_PATTERNS
        if occursin(pat, text)
            return ("then", LEADSTO, 0.7)
        end
    end
    for pat in _CONTAINS_PATTERNS
        if occursin(pat, text)
            return ("contain", CONTAINS, 0.7)
        end
    end
    for pat in _EXPRESS_PATTERNS
        if occursin(pat, text)
            return ("note", EXPRESS, 0.6)
        end
    end
    for pat in _NEAR_PATTERNS
        if occursin(pat, text)
            return ("ll", NEAR, 0.6)
        end
    end
    # Default: NEAR with low confidence
    return ("ll", NEAR, 0.3)
end

# ── Full breakdown ───────────────────────────────────────────────

"""
    propose_structure(text::String; chapter::String="default") -> TextBreakdown

Full text analysis: extract entities, suggest links, generate N4L.
"""
function propose_structure(text::String; chapter::String="default")
    sents    = split_sentences(text)
    entities = identify_entities(text)
    links    = suggest_links(text, entities)

    tb = TextBreakdown(text, sents, entities, links, "")
    n4l = breakdown_to_n4l(tb; chapter=chapter)
    TextBreakdown(text, sents, entities, links, n4l)
end

"""
    breakdown_to_n4l(tb::TextBreakdown; chapter::String="default") -> String

Convert a TextBreakdown into N4L notation.
"""
function breakdown_to_n4l(tb::TextBreakdown; chapter::String="default")
    io = IOBuffer()
    println(io, " - $(chapter)")
    println(io)

    # Declare entities
    for (i, e) in enumerate(tb.entities)
        println(io, "@e$(i)   $(e.text)")
    end

    if !isempty(tb.entities)
        println(io)
    end

    # Declare links
    entity_labels = Dict{String,String}()
    for (i, e) in enumerate(tb.entities)
        entity_labels[e.text] = "@e$(i)"
    end

    for lnk in tb.links
        src_label = get(entity_labels, lnk.source, lnk.source)
        tgt_label = get(entity_labels, lnk.target, lnk.target)
        println(io, "$(src_label)  \" ($(lnk.arrow_name)) $(tgt_label)")
    end

    return String(take!(io))
end
