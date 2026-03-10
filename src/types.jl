#=
Core types and constants for Semantic Spacetime.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Semantic Spacetime type spectrum
# ──────────────────────────────────────────────────────────────────

"""
    STType

The Semantic Spacetime link type spectrum. Links are classified along
a signed integer axis from -EXPRESS to +EXPRESS:

- `NEAR` (0): proximity / similarity
- `LEADSTO` (±1): causal / temporal ordering
- `CONTAINS` (±2): containment / membership
- `EXPRESS` (±3): expressive properties / attributes
"""
@enum STType begin
    NEAR     = 0
    LEADSTO  = 1
    CONTAINS = 2
    EXPRESS  = 3
end

"""
    ST_ZERO

Offset constant equal to `Int(EXPRESS)` (3), used to map signed ST type
values (-3..+3) to 1-based array indices (1..7).
"""
const ST_ZERO = Int(EXPRESS)

"""
    ST_TOP

Total number of ST channels (7). Equal to `ST_ZERO + Int(EXPRESS) + 1`.
Used to size incidence lists on nodes.
"""
const ST_TOP  = ST_ZERO + Int(EXPRESS) + 1

"""Map signed STtype (-3..+3) to a 1-based array index (1..7)."""
sttype_to_index(st::Int) = st + ST_ZERO + 1

"""Map a 1-based array index (1..7) back to signed STtype (-3..+3)."""
index_to_sttype(idx::Int) = idx - ST_ZERO - 1

# ST channel DB column names (matching Go I_MEXPR..I_PEXPR)
const ST_COLUMN_NAMES = ["Im3", "Im2", "Im1", "In0", "Il1", "Ic2", "Ie3"]

# ──────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────

"""
    CREDENTIALS_FILE

Filename for database credentials, looked up in the user's home directory (`~/.SSTorytime`).
"""
const CREDENTIALS_FILE = ".SSTorytime"

"""
    SCREENWIDTH

Default terminal screen width (120 characters) for text rendering.
"""
const SCREENWIDTH = 120

"""
    RIGHTMARGIN

Right margin (5 characters) for terminal text rendering.
"""
const RIGHTMARGIN = 5

"""
    LEFTMARGIN

Left margin (5 characters) for terminal text rendering.
"""
const LEFTMARGIN  = 5

"""
    CAUSAL_CONE_MAXLIMIT

Default maximum number of results for causal cone search operations (100).
"""
const CAUSAL_CONE_MAXLIMIT = 100

"""
    N1GRAM

Text size class constant for single-word n-grams (value 1).
"""
const N1GRAM = 1

"""
    N2GRAM

Text size class constant for two-word n-grams (value 2).
"""
const N2GRAM = 2

"""
    N3GRAM

Text size class constant for three-word n-grams (value 3).
"""
const N3GRAM = 3

"""
    LT128

Text size class constant for strings shorter than 128 characters (value 4).
"""
const LT128  = 4

"""
    LT1024

Text size class constant for strings shorter than 1024 characters (value 5).
"""
const LT1024 = 5

"""
    GT1024

Text size class constant for strings of 1024 characters or longer (value 6).
"""
const GT1024 = 6

const CLASS_CHANNEL_DESCRIPTION = [
    "",
    "single word ngram",
    "two word ngram",
    "three word ngram",
    "string less than 128 chars",
    "string less than 1024 chars",
    "string greater than 1024 chars",
]

# ──────────────────────────────────────────────────────────────────
# Mandatory relation names (used in text processing)
# ──────────────────────────────────────────────────────────────────

const EXPR_INTENT_L       = "has contextual theme"
const EXPR_INTENT_S       = "has_theme"
const INV_EXPR_INTENT_L   = "is a context theme in"
const INV_EXPR_INTENT_S   = "theme_of"

const EXPR_AMBIENT_L      = "has contextual highlight"
const EXPR_AMBIENT_S      = "has_highlight"
const INV_EXPR_AMBIENT_L  = "is contextual highlight of"
const INV_EXPR_AMBIENT_S  = "highlight_of"

const CONT_FINDS_L        = "contains extract/quote"
const CONT_FINDS_S        = "has-extract"
const INV_CONT_FOUND_IN_L = "extract/quote from"
const INV_CONT_FOUND_IN_S = "extract-fr"

const CONT_FRAG_L         = "contains intented characteristic"
const CONT_FRAG_S         = "has-frag"
const INV_CONT_FRAG_IN_L  = "characteristic of"
const INV_CONT_FRAG_IN_S  = "charct-in"

# ──────────────────────────────────────────────────────────────────
# Pointer types
# ──────────────────────────────────────────────────────────────────

"""Integer index within a text-size class lane."""
const ClassedNodePtr = Int

"""Integer index into the arrow directory."""
const ArrowPtr = Int

"""Integer index into the context directory."""
const ContextPtr = Int

"""
    NodePtr

Two-part pointer identifying a node by its text-size class and
position within that class.
"""
struct NodePtr
    class::Int           # Text size class (N1GRAM..GT1024)
    cptr::ClassedNodePtr # Index within the class lane
end

NodePtr() = NodePtr(0, 0)

Base.:(==)(a::NodePtr, b::NodePtr) = a.class == b.class && a.cptr == b.cptr
Base.hash(a::NodePtr, h::UInt) = hash(a.cptr, hash(a.class, h))
Base.show(io::IO, np::NodePtr) = print(io, "($(np.class),$(np.cptr))")
Base.isless(a::NodePtr, b::NodePtr) = (a.class, a.cptr) < (b.class, b.cptr)

"""
    NO_NODE_PTR

Sentinel `NodePtr(0, 0)` representing the absence of a node pointer.
"""
const NO_NODE_PTR = NodePtr(0, 0)

# ──────────────────────────────────────────────────────────────────
# Event/Thing/Concept classification
# ──────────────────────────────────────────────────────────────────

"""
    Etc

Classification of a node as Event, Thing, and/or Concept.
These are not mutually exclusive.
"""
mutable struct Etc
    e::Bool  # event
    t::Bool  # thing
    c::Bool  # concept
end

Etc() = Etc(false, false, false)

function Base.show(io::IO, etc::Etc)
    parts = String[]
    etc.e && push!(parts, "E")
    etc.t && push!(parts, "T")
    etc.c && push!(parts, "C")
    print(io, isempty(parts) ? "-" : join(parts))
end

# ──────────────────────────────────────────────────────────────────
# Link type
# ──────────────────────────────────────────────────────────────────

"""
    Link

A typed, weighted, contextual edge to a destination node.
"""
struct Link
    arr::ArrowPtr    # Arrow type from the arrow directory
    wgt::Float32     # Numerical weight
    ctx::ContextPtr  # Context for this pathway
    dst::NodePtr     # Adjacent node
end

Link() = Link(0, 0.0f0, 0, NO_NODE_PTR)

Base.:(==)(a::Link, b::Link) = a.arr == b.arr && a.wgt == b.wgt && a.ctx == b.ctx && a.dst == b.dst
Base.hash(a::Link, h::UInt) = hash(a.dst, hash(a.ctx, hash(a.wgt, hash(a.arr, h))))

# ──────────────────────────────────────────────────────────────────
# Node type
# ──────────────────────────────────────────────────────────────────

"""
    Node

A node in the Semantic Spacetime graph. Stores text content,
chapter membership, sequence status, ETC classification,
self-pointer, and incidence lists for each ST channel.
"""
mutable struct Node
    l::Int                           # Length of text string
    s::String                        # Text string
    seq::Bool                        # Begins an intended sequence?
    chap::String                     # Section/chapter name
    nptr::NodePtr                    # Self-pointer
    psi::Etc                         # Induced node type
    incidence::Vector{Vector{Link}}  # ST_TOP vectors of links (indexed 1..7)
end

function Node(text::String="", chap::String="")
    Node(
        length(text),
        text,
        false,
        chap,
        NO_NODE_PTR,
        Etc(),
        [Link[] for _ in 1:ST_TOP],
    )
end

Base.show(io::IO, n::Node) = print(io, "Node(\"$(n.s)\", $(n.nptr))")

# ──────────────────────────────────────────────────────────────────
# Arrow directory entry
# ──────────────────────────────────────────────────────────────────

"""
    ArrowEntry

An entry in the arrow directory, mapping a named relationship to
its Semantic Spacetime type and integer pointer.
"""
struct ArrowEntry
    stindex::Int     # ST array index (1..7)
    long::String     # Long descriptive name
    short::String    # Short alias
    ptr::ArrowPtr    # Integer pointer
end

# ──────────────────────────────────────────────────────────────────
# Context directory entry
# ──────────────────────────────────────────────────────────────────

"""
    ContextEntry

An entry in the context directory, mapping a context string to
its integer pointer.
"""
struct ContextEntry
    context::String
    ptr::ContextPtr
end

# ──────────────────────────────────────────────────────────────────
# Page map (layout tracking)
# ──────────────────────────────────────────────────────────────────

"""
    PageMap

Tracks the layout position of a node within a chapter for
page-view display.
"""
mutable struct PageMap
    chapter::String
    alias::String
    ctx::ContextPtr
    line::Int
    path::Vector{Link}
end

PageMap() = PageMap("", "", 0, 0, Link[])

# ──────────────────────────────────────────────────────────────────
# Appointment (hub join structure)
# ──────────────────────────────────────────────────────────────────

"""
    Appointment

An appointed "from" node points to a collection of "to" nodes
by the same arrow type.
"""
mutable struct Appointment
    arr::ArrowPtr
    sttype::Int
    chap::String
    ctx::Vector{String}
    nto::NodePtr
    nfrom::Vector{NodePtr}
end

Appointment() = Appointment(0, 0, "", String[], NO_NODE_PTR, NodePtr[])

# ──────────────────────────────────────────────────────────────────
# Web interface types (for JSON rendering)
# ──────────────────────────────────────────────────────────────────

struct Coords
    x::Float64
    y::Float64
    z::Float64
    r::Float64
    lat::Float64
    lon::Float64
end

Coords() = Coords(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

struct WebPath
    nptr::NodePtr
    arr::ArrowPtr
    stindex::Int
    line::Int
    name::String
    chp::String
    ctx::String
    xyz::Coords
end

struct Orbit
    radius::Int
    arrow::String
    stindex::Int
    dst::NodePtr
    ctx::String
    text::String
    xyz::Coords
    ooo::Coords  # origin
end

struct NodeEvent
    text::String
    l::Int
    chap::String
    context::String
    nptr::NodePtr
    xyz::Coords
    orbits::Vector{Vector{Orbit}}  # ST_TOP vectors
end

struct Story
    chapter::String
    axis::Vector{NodeEvent}
end

mutable struct LastSeen
    section::String
    first::Int64
    last::Int64
    pdelta::Float64
    ndelta::Float64
    freq::Int
    nptr::NodePtr
    xyz::Coords
end

# ──────────────────────────────────────────────────────────────────
# Utility: determine text size class
# ──────────────────────────────────────────────────────────────────

"""
    n_channel(s::AbstractString) -> Int

Determine the text size class (n-gram bucket) for a string,
based on the number of spaces (word count proxy) and length.
"""
function n_channel(s::AbstractString)
    spaces = count(==(' '), s)
    spaces == 0 && return N1GRAM
    spaces == 1 && return N2GRAM
    spaces == 2 && return N3GRAM
    l = length(s)
    l < 128  && return LT128
    l < 1024 && return LT1024
    return GT1024
end

"""
    sql_escape(s::AbstractString) -> String

Escape single quotes for SQL string literals.
"""
sql_escape(s::AbstractString) = replace(s, "'" => "''")
