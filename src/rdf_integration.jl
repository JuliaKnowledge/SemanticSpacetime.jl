#=
RDF integration for Semantic Spacetime.

Provides bidirectional conversion between SST graphs and RDF triples
using simple string-based triples (no hard dependency on RDFLib.jl).
=#

# ──────────────────────────────────────────────────────────────────
# RDF Triple type
# ──────────────────────────────────────────────────────────────────

"""
    RDFTriple

A simple RDF triple as three URI/literal strings.
"""
struct RDFTriple
    subject::String
    predicate::String
    object::String
end

Base.:(==)(a::RDFTriple, b::RDFTriple) = a.subject == b.subject && a.predicate == b.predicate && a.object == b.object
Base.hash(a::RDFTriple, h::UInt) = hash(a.object, hash(a.predicate, hash(a.subject, h)))

function Base.show(io::IO, t::RDFTriple)
    print(io, "<$(t.subject)> <$(t.predicate)> <$(t.object)>")
end

# ──────────────────────────────────────────────────────────────────
# SST namespace
# ──────────────────────────────────────────────────────────────────

const _DEFAULT_SST_NAMESPACE = "http://sst.example.org/"

"""
    SSTNamespace

Configurable namespace for SST RDF serialization.
"""
struct SSTNamespace
    base::String       # Base URI for nodes, e.g. "http://sst.example.org/"
    vocab::String      # Vocabulary URI for predicates/classes
end

"""
    SSTNamespace(base::AbstractString)

Create an SST namespace from a base URI. The vocabulary namespace
is derived as `{base}vocab#`.
"""
function SSTNamespace(base::AbstractString)
    b = endswith(base, "/") ? String(base) : String(base) * "/"
    SSTNamespace(b, b * "vocab#")
end

"""
    sst_namespace(base::AbstractString="$(_DEFAULT_SST_NAMESPACE)") -> SSTNamespace

Return an SST RDF namespace configuration.
"""
sst_namespace(base::AbstractString=_DEFAULT_SST_NAMESPACE) = SSTNamespace(base)

# ──────────────────────────────────────────────────────────────────
# URI helpers
# ──────────────────────────────────────────────────────────────────

"""Encode a node name as a URI-safe fragment."""
function _uri_encode(s::AbstractString)
    # Replace spaces and special chars with underscores, percent-encode the rest
    buf = IOBuffer()
    for c in s
        if c == ' '
            write(buf, '_')
        elseif isletter(c) || isdigit(c) || c in ('-', '_', '.', '~')
            write(buf, c)
        else
            for b in codeunits(string(c))
                write(buf, '%')
                write(buf, uppercase(string(b; base=16, pad=2)))
            end
        end
    end
    return String(take!(buf))
end

"""Build a node URI from namespace and node name."""
_node_uri(ns::SSTNamespace, name::AbstractString) = ns.base * "node/" * _uri_encode(name)

"""Build an arrow predicate URI."""
_arrow_uri(ns::SSTNamespace, arrow_name::AbstractString) = ns.vocab * _uri_encode(arrow_name)

"""Build an STType class URI."""
_sttype_uri(ns::SSTNamespace, sttype::AbstractString) = ns.vocab * sttype

"""Build a context URI."""
_context_uri(ns::SSTNamespace, ctx::AbstractString) = ns.base * "context/" * _uri_encode(ctx)

"""Build a chapter URI."""
_chapter_uri(ns::SSTNamespace, chap::AbstractString) = ns.base * "chapter/" * _uri_encode(chap)

# Standard RDF/RDFS URIs
const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
const RDFS_LABEL = "http://www.w3.org/2000/01/rdf-schema#label"

# ──────────────────────────────────────────────────────────────────
# SST → RDF conversion
# ──────────────────────────────────────────────────────────────────

"""
    sst_to_rdf(store::AbstractSSTStore; namespace=sst_namespace()) -> Vector{RDFTriple}

Convert all nodes and edges in an SST store to RDF triples.

Nodes are mapped to URIs under the namespace base, with `rdf:type`,
`rdfs:label`, and chapter membership triples. Edges become triples
with the arrow short name as the predicate URI.

# Keyword Arguments
- `namespace::SSTNamespace`: The namespace configuration (default: `sst_namespace()`)
"""
function sst_to_rdf(store::MemoryStore; namespace::SSTNamespace=sst_namespace())
    triples = RDFTriple[]
    ns = namespace

    # Emit node triples
    for (nptr, node) in store.nodes
        subj = _node_uri(ns, node.s)

        # rdf:type sst:Node
        push!(triples, RDFTriple(subj, RDF_TYPE, _sttype_uri(ns, "Node")))

        # rdfs:label
        push!(triples, RDFTriple(subj, RDFS_LABEL, node.s))

        # Chapter membership
        if !isempty(node.chap)
            push!(triples, RDFTriple(subj, _sttype_uri(ns, "chapter"), _chapter_uri(ns, node.chap)))
        end
    end

    # Emit edge triples
    for (nptr, node) in store.nodes
        subj = _node_uri(ns, node.s)
        for stidx in 1:ST_TOP
            for link in node.incidence[stidx]
                dst_node = mem_get_node(store, link.dst)
                isnothing(dst_node) && continue

                # Look up arrow name
                arrow_entry = get_arrow_by_ptr(link.arr)
                pred = _arrow_uri(ns, arrow_entry.short)
                obj = _node_uri(ns, dst_node.s)

                push!(triples, RDFTriple(subj, pred, obj))

                # STType classification of the predicate
                sttype_name = print_stindex(arrow_entry.stindex)
                push!(triples, RDFTriple(pred, RDF_TYPE, _sttype_uri(ns, "STType")))
                push!(triples, RDFTriple(pred, RDFS_LABEL, sttype_name))

                # Context annotation (reification-lite: context as a property of the edge subject)
                ctx_str = get_context(link.ctx)
                if !isempty(ctx_str)
                    push!(triples, RDFTriple(subj, _sttype_uri(ns, "context"), _context_uri(ns, ctx_str)))
                end
            end
        end
    end

    return triples
end

# ──────────────────────────────────────────────────────────────────
# RDF → SST conversion
# ──────────────────────────────────────────────────────────────────

"""
    PredicateMapping

Maps an RDF predicate URI to an SST arrow name and STType.
"""
struct PredicateMapping
    predicate::String
    arrow_name::String
    sttype::String    # "NEAR", "LEADSTO", "CONTAINS", "EXPRESS"
    sign::String      # "+" or "-"
end

"""
    default_predicate_mappings(namespace::SSTNamespace) -> Dict{String, PredicateMapping}

Return default mappings from common RDF predicates to SST arrow types.
"""
function default_predicate_mappings(namespace::SSTNamespace=sst_namespace())
    mappings = Dict{String, PredicateMapping}()
    # Skip metadata predicates that don't map to SST edges
    return mappings
end

"""
    rdf_to_sst!(store::MemoryStore, triples::Vector{RDFTriple};
                namespace=sst_namespace(),
                chapter="imported",
                predicate_map=Dict{String,PredicateMapping}()) -> store

Import RDF triples into an SST store. Subjects and objects become nodes;
predicates become edges.

Metadata predicates (`rdf:type`, `rdfs:label`, chapter) are used to set
node properties rather than creating edges.

Unknown predicates are auto-registered as NEAR arrows unless a custom
`predicate_map` provides a mapping.

# Keyword Arguments
- `namespace::SSTNamespace`: Namespace for URI parsing
- `chapter::AbstractString`: Default chapter for imported nodes
- `predicate_map::Dict{String,PredicateMapping}`: Custom predicate→arrow mappings
"""
function rdf_to_sst!(store::MemoryStore, triples::Vector{RDFTriple};
                     namespace::SSTNamespace=sst_namespace(),
                     chapter::AbstractString="imported",
                     predicate_map::Dict{String,PredicateMapping}=Dict{String,PredicateMapping}())
    ns = namespace

    # Metadata predicates to skip as edges
    skip_predicates = Set([RDF_TYPE, RDFS_LABEL, _sttype_uri(ns, "chapter"), _sttype_uri(ns, "context")])

    # First pass: collect node labels from rdfs:label triples
    labels = Dict{String, String}()  # subject URI → label
    for t in triples
        if t.predicate == RDFS_LABEL
            labels[t.subject] = t.object
        end
    end

    # Collect chapters from chapter triples
    chapters = Dict{String, String}()  # subject URI → chapter name
    for t in triples
        if t.predicate == _sttype_uri(ns, "chapter")
            # Extract chapter name from URI
            prefix = ns.base * "chapter/"
            chap_name = if startswith(t.object, prefix)
                _uri_decode(t.object[length(prefix)+1:end])
            else
                t.object
            end
            chapters[t.subject] = chap_name
        end
    end

    # Helper: get a display name for a URI
    function _name_for_uri(uri::String)
        get(labels, uri, _extract_local_name(uri))
    end

    # Second pass: create edges from non-metadata triples
    for t in triples
        t.predicate in skip_predicates && continue
        # Skip STType metadata triples
        t.object == _sttype_uri(ns, "STType") && continue

        subj_name = _name_for_uri(t.subject)
        obj_name = _name_for_uri(t.object)
        subj_chap = get(chapters, t.subject, chapter)
        obj_chap = get(chapters, t.object, chapter)

        from = mem_vertex!(store, subj_name, subj_chap)
        to = mem_vertex!(store, obj_name, obj_chap)

        # Determine arrow name from predicate
        arrow_name, sttype_name, sign = _resolve_predicate(t.predicate, ns, predicate_map)

        # Ensure the arrow is registered
        if isnothing(get_arrow_by_name(arrow_name))
            insert_arrow!(sttype_name, arrow_name, arrow_name, sign)
        end

        mem_edge!(store, from, arrow_name, to)
    end

    return store
end

"""Extract a local name from a URI (after last / or #)."""
function _extract_local_name(uri::AbstractString)
    i = findlast(c -> c == '/' || c == '#', uri)
    isnothing(i) && return uri
    name = uri[nextind(uri, i):end]
    return _uri_decode(name)
end

"""Decode URI-encoded characters (%XX and underscores)."""
function _uri_decode(s::AbstractString)
    result = replace(s, '_' => ' ')
    # Decode percent-encoded characters
    while (m = match(r"%([0-9A-Fa-f]{2})", result)) !== nothing
        byte = parse(UInt8, m.captures[1]; base=16)
        result = replace(result, m.match => String([byte]); count=1)
    end
    return result
end

"""Resolve a predicate URI to (arrow_name, sttype_name, sign)."""
function _resolve_predicate(predicate::String, ns::SSTNamespace,
                            predicate_map::Dict{String,PredicateMapping})
    # Check custom mapping first
    if haskey(predicate_map, predicate)
        pm = predicate_map[predicate]
        return (pm.arrow_name, pm.sttype, pm.sign)
    end

    # If it's in our SST vocab namespace, extract the arrow name
    if startswith(predicate, ns.vocab)
        arrow_name = _uri_decode(predicate[length(ns.vocab)+1:end])
        # Try to find it in the arrow directory
        entry = get_arrow_by_name(arrow_name)
        if !isnothing(entry)
            sttype_name = print_stindex(entry.stindex)
            sign = index_to_sttype(entry.stindex) < 0 ? "-" : "+"
            # Clean STType name (remove sign prefix)
            sttype_name = replace(sttype_name, r"^[+-]" => "")
            return (arrow_name, sttype_name, sign)
        end
        return (arrow_name, "NEAR", "+")
    end

    # For unknown predicates, use local name as arrow name, default to NEAR
    arrow_name = _extract_local_name(predicate)
    return (arrow_name, "NEAR", "+")
end

# ──────────────────────────────────────────────────────────────────
# Turtle serialization
# ──────────────────────────────────────────────────────────────────

"""
    export_turtle(store::AbstractSSTStore; namespace=sst_namespace()) -> String

Export an SST store as an RDF Turtle format string.
"""
function export_turtle(store::MemoryStore; namespace::SSTNamespace=sst_namespace())
    triples = sst_to_rdf(store; namespace=namespace)
    return triples_to_turtle(triples; namespace=namespace)
end

"""
    triples_to_turtle(triples::Vector{RDFTriple}; namespace=sst_namespace()) -> String

Serialize a vector of RDFTriples as Turtle format.
"""
function triples_to_turtle(triples::Vector{RDFTriple}; namespace::SSTNamespace=sst_namespace())
    io = IOBuffer()
    ns = namespace

    # Prefixes
    println(io, "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")
    println(io, "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .")
    println(io, "@prefix sst: <$(ns.base)> .")
    println(io, "@prefix sst-vocab: <$(ns.vocab)> .")
    println(io)

    for t in triples
        s = _turtle_term(t.subject)
        p = _turtle_term(t.predicate)
        o = _turtle_term(t.object)
        println(io, "$s $p $o .")
    end

    return String(take!(io))
end

"""Format a term for Turtle output: URIs in <>, plain strings as literals."""
function _turtle_term(term::AbstractString)
    # If it looks like a URI (starts with http:// or similar scheme)
    if _is_uri(term)
        return "<$term>"
    else
        # Escape for Turtle literal
        escaped = replace(term, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")
        return "\"$escaped\""
    end
end

"""Check whether a string looks like a URI."""
_is_uri(s::AbstractString) = occursin(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", s)

# ──────────────────────────────────────────────────────────────────
# Turtle parsing (minimal)
# ──────────────────────────────────────────────────────────────────

"""
    import_turtle!(store::MemoryStore, text::AbstractString;
                   namespace=sst_namespace(), chapter="imported") -> store

Parse a minimal Turtle string and import triples into the SST store.

Supports `<uri>` terms and `"literal"` terms. Handles `@prefix` declarations.
"""
function import_turtle!(store::MemoryStore, text::AbstractString;
                        namespace::SSTNamespace=sst_namespace(),
                        chapter::AbstractString="imported")
    triples = parse_turtle(text)
    rdf_to_sst!(store, triples; namespace=namespace, chapter=chapter)
    return store
end

"""
    parse_turtle(text::AbstractString) -> Vector{RDFTriple}

Parse a minimal Turtle string into RDFTriples.

Handles `<URI>` and `"literal"` terms, and `@prefix` declarations.
Does not handle blank nodes, collections, or shorthand predicates.
"""
function parse_turtle(text::AbstractString)
    triples = RDFTriple[]
    prefixes = Dict{String, String}()

    for line in eachline(IOBuffer(text))
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, '#') && continue

        # @prefix declaration
        m = match(r"^@prefix\s+(\S+)\s+<([^>]+)>\s*\.\s*$", stripped)
        if m !== nothing
            prefixes[m.captures[1]] = m.captures[2]
            continue
        end

        # Triple line: extract three terms followed by '.'
        terms = String[]
        pos = 1
        sline = stripped
        while length(terms) < 3 && pos <= length(sline)
            # Skip whitespace
            while pos <= length(sline) && isspace(sline[pos])
                pos += 1
            end
            pos > length(sline) && break

            if sline[pos] == '<'
                # URI
                close = findnext('>', sline, pos + 1)
                isnothing(close) && break
                push!(terms, String(sline[pos+1:close-1]))
                pos = close + 1
            elseif sline[pos] == '"'
                # Literal — find closing quote (handle escapes)
                pos += 1
                buf = IOBuffer()
                while pos <= length(sline)
                    c = sline[pos]
                    if c == '\\' && pos < length(sline)
                        pos += 1
                        nc = sline[pos]
                        if nc == 'n'
                            write(buf, '\n')
                        elseif nc == '"'
                            write(buf, '"')
                        elseif nc == '\\'
                            write(buf, '\\')
                        else
                            write(buf, '\\')
                            write(buf, nc)
                        end
                    elseif c == '"'
                        break
                    else
                        write(buf, c)
                    end
                    pos += 1
                end
                push!(terms, String(take!(buf)))
                pos += 1  # skip closing quote
                # Skip optional language tag or datatype
                while pos <= length(sline) && !isspace(sline[pos]) && sline[pos] != '.'
                    pos += 1
                end
            else
                # Prefixed name or other token
                start = pos
                while pos <= length(sline) && !isspace(sline[pos]) && sline[pos] != '.'
                    pos += 1
                end
                token = String(sline[start:pos-1])
                # Expand prefixed name
                expanded = _expand_prefix(token, prefixes)
                push!(terms, expanded)
            end
        end

        if length(terms) == 3
            push!(triples, RDFTriple(terms[1], terms[2], terms[3]))
        end
    end

    return triples
end

"""Expand a prefixed name using a prefix map."""
function _expand_prefix(token::AbstractString, prefixes::Dict{String, String})
    i = findfirst(':', token)
    isnothing(i) && return String(token)
    prefix = token[1:i]  # includes the colon
    local_name = token[i+1:end]
    if haskey(prefixes, prefix)
        return prefixes[prefix] * local_name
    end
    return String(token)
end
