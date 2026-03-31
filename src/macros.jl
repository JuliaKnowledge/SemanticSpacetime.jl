#=
Syntactic sugar: string macros, convenience macros, and do-block patterns
for idiomatic Julia usage of SemanticSpacetime.
=#

# ──────────────────────────────────────────────────────────────────
# String macros
# ──────────────────────────────────────────────────────────────────

"""
    n4l"..."

Parse an N4L string literal at runtime, returning an `N4LResult`.
Uses the default SSTconfig if available, otherwise parses without config.

# Examples
```julia
result = n4l"-section\\n\\n apple (contains) fruit\\n"

result = n4l\"\"\"
-vocabulary

 apple (contains) fruit
 banana (contains) fruit
\"\"\"
```
"""
macro n4l_str(text::String)
    quote
        parse_n4l($(esc(text)))
    end
end

"""
    n4l"..."config_dir

Parse an N4L string literal with a specific config directory.

# Example
```julia
result = n4l\"\"\"
-section

 apple (contains) fruit
\"\"\""/path/to/SSTconfig"
```
"""
macro n4l_str(text::String, config_dir::String)
    quote
        parse_n4l($(esc(text)); config_dir=$(esc(config_dir)))
    end
end

# ──────────────────────────────────────────────────────────────────
# @sst — scoped store with do-block
# ──────────────────────────────────────────────────────────────────

"""
    @sst [store] begin ... end

Create a `MemoryStore` and execute a block of operations on it,
returning the store. If a variable name is given, it is bound within
the block; otherwise the store is accessible as `s`.

# Examples
```julia
# Implicit variable `s`
store = @sst begin
    v1 = vertex!(s, "apple", "fruits")
    v2 = vertex!(s, "banana", "fruits")
    edge!(s, v1, "contains", v2)
end

# Explicit variable name
store = @sst g begin
    a = vertex!(g, "hello", "greetings")
    b = vertex!(g, "world", "greetings")
    edge!(g, a, "note", b)
end
```
"""
macro sst(body::Expr)
    _sst_impl(:s, body)
end

macro sst(name::Symbol, body::Expr)
    _sst_impl(name, body)
end

function _sst_impl(name::Symbol, body::Expr)
    quote
        let $(esc(name)) = MemoryStore()
            $(esc(body))
            $(esc(name))
        end
    end
end

# ──────────────────────────────────────────────────────────────────
# @compile — compile N4L text into a new or existing store
# ──────────────────────────────────────────────────────────────────

"""
    @compile text
    @compile store text
    @compile text config_dir=path

Compile an N4L string into a `MemoryStore`. If no store is provided,
a new one is created. Returns `(store, compile_result)`.

# Examples
```julia
# New store
store, result = @compile \"\"\"
-section

 apple (contains) fruit
\"\"\"

# Into existing store
store = MemoryStore()
_, result = @compile store \"\"\"
-section

 banana (contains) fruit
\"\"\"
```
"""
macro compile(text)
    quote
        _store = MemoryStore()
        _cr = compile_n4l_string!(_store, $(esc(text)))
        (_store, _cr)
    end
end

macro compile(store, text)
    quote
        _cr = compile_n4l_string!($(esc(store)), $(esc(text)))
        ($(esc(store)), _cr)
    end
end

# ──────────────────────────────────────────────────────────────────
# Infix-style edge creation: node1 → arrow → node2
# ──────────────────────────────────────────────────────────────────

"""
    EdgeBuilder

Intermediate object for infix-style edge construction.
Created by `-->` or `|>` operators on `(store, node, arrow)` tuples.

# Example
```julia
store = MemoryStore()
a = mem_vertex!(store, "apple", "test")
b = mem_vertex!(store, "banana", "test")
# Using the connect! function:
connect!(store, a, "contains", b)
connect!(store, a, "contains", b; context=["food"], weight=2.0f0)
```
"""
struct EdgeBuilder
    store::MemoryStore
    from::Node
    arrow::String
end

"""
    connect!(store, from, arrow, to; context=String[], weight=1.0f0)

Convenience alias for `mem_edge!` with keyword arguments.

# Example
```julia
connect!(store, apple, "contains", fruit)
connect!(store, apple, "note", description; context=["botany"])
```
"""
function connect!(store::MemoryStore, from::Node, arrow::AbstractString, to::Node;
                  context::Vector{String}=String[], weight::Float32=1.0f0)
    mem_edge!(store, from, arrow, to, context, weight)
end

function connect!(store::AbstractSSTStore, from::Node, arrow::AbstractString, to::Node;
                  context::Vector{String}=String[], weight::Float32=1.0f0)
    mem_edge!(store, from, arrow, to, context, weight)
end

# ──────────────────────────────────────────────────────────────────
# Piping: store |> @graph ... end
# ──────────────────────────────────────────────────────────────────

"""
    @graph store begin
        "node1" -arrow-> "node2"
        ...
    end

Build a graph declaratively. Each line in the block should be a
call to `vertex!` or `edge!`, or use the DSL helpers.

# Example
```julia
store = MemoryStore()
@graph store begin
    a = vertex!("apple", "fruits")
    b = vertex!("banana", "fruits")
    c = vertex!("fruit", "fruits")
    edge!(a, "contains", c)
    edge!(b, "contains", c)
end
```

Inside `@graph`, `vertex!` and `edge!` calls automatically use the store.
"""
macro graph(store, body::Expr)
    store_var = gensym("graphstore")
    new_body = _rewrite_graph_calls(store_var, body)
    quote
        let $(esc(store_var)) = $(esc(store))
            $(esc(new_body))
            $(esc(store_var))
        end
    end
end

function _rewrite_graph_calls(store_sym::Symbol, expr::Expr)
    if expr.head == :call
        fname = expr.args[1]
        if fname == :vertex!
            new_args = [:(mem_vertex!), store_sym, expr.args[2:end]...]
            return Expr(:call, new_args...)
        elseif fname == :edge!
            new_args = [:(mem_edge!), store_sym, expr.args[2:end]...]
            return Expr(:call, new_args...)
        elseif fname == :connect!
            new_args = [:(connect!), store_sym, expr.args[2:end]...]
            return Expr(:call, new_args...)
        end
    end
    # Recursively rewrite child expressions
    new_expr = copy(expr)
    for (i, arg) in enumerate(new_expr.args)
        if arg isa Expr
            new_expr.args[i] = _rewrite_graph_calls(store_sym, arg)
        end
    end
    return new_expr
end

# ──────────────────────────────────────────────────────────────────
# Property access: node.links, node.text, etc.
# ──────────────────────────────────────────────────────────────────

"""
    links(node::Node) -> Vector{Link}

Get all links from a node, flattened across all ST types.
"""
function links(node::Node)::Vector{Link}
    result = Link[]
    for bucket in node.incidence
        append!(result, bucket)
    end
    return result
end

"""
    links(node::Node, sttype::STType) -> Vector{Link}

Get links from a node for a specific ST type.

# Example
```julia
fwd_links = links(node, LEADSTO)      # Forward causal links
contains = links(node, CONTAINS)      # Containment links
similar = links(node, NEAR)           # Similarity links
```
"""
function links(node::Node, sttype::STType)::Vector{Link}
    idx = sttype_to_index(Int(sttype))
    return node.incidence[idx]
end

"""
    neighbors(store::MemoryStore, node::Node) -> Vector{Node}

Get all nodes directly connected to this node.
"""
function neighbors(store::MemoryStore, node::Node)::Vector{Node}
    result = Node[]
    seen = Set{NodePtr}()
    for bucket in node.incidence
        for lnk in bucket
            if lnk.dst ∉ seen
                push!(seen, lnk.dst)
                n = mem_get_node(store, lnk.dst)
                n !== nothing && push!(result, n)
            end
        end
    end
    return result
end

"""
    neighbors(store::MemoryStore, node::Node, sttype::STType) -> Vector{Node}

Get nodes connected via a specific ST type.
"""
function neighbors(store::MemoryStore, node::Node, sttype::STType)::Vector{Node}
    idx = sttype_to_index(Int(sttype))
    result = Node[]
    for lnk in node.incidence[idx]
        n = mem_get_node(store, lnk.dst)
        n !== nothing && push!(result, n)
    end
    return result
end

# ──────────────────────────────────────────────────────────────────
# Iteration and collection protocols
# ──────────────────────────────────────────────────────────────────

"""
    nodes(store::AbstractSSTStore; chapter::String="") -> Vector{Node}

Get all nodes in the store as a vector.
"""
function nodes(store::MemoryStore; chapter::String="")::Vector{Node}
    all_nodes = collect(values(store.nodes))
    isempty(chapter) && return all_nodes
    return [node for node in all_nodes if node.chap == chapter]
end

function nodes(store::DBStore; chapter::String="")::Vector{Node}
    sql = "SELECT class, cptr FROM sst_nodes"
    params = Any[]
    if !isempty(chapter)
        sql *= " WHERE chapter = ?"
        push!(params, chapter)
    end
    sql *= " ORDER BY class, cptr"
    rows = _collect_rows(DBInterface.execute(store.conn, sql, params))
    return [db_get_node(store, NodePtr(Int(row[1]), Int(row[2]))) for row in rows]
end

"""
    eachnode(store::AbstractSSTStore; chapter::String="")

Iterate over all nodes in the store.

# Example
```julia
for node in eachnode(store)
    println(node.s)
end
```
"""
function eachnode(store::AbstractSSTStore; chapter::String="")
    return nodes(store; chapter=chapter)
end

"""
    eachlink(node::Node)

Iterate over all links from a node (across all ST types).

# Example
```julia
for link in eachlink(node)
    println("Arrow: \$(link.arr), Dst: \$(link.dst)")
end
```
"""
function eachlink(node::Node)
    return Iterators.flatten(node.incidence)
end

"""
    eachlink(node::Node, sttype::STType)

Iterate over links of a specific ST type.
"""
function eachlink(node::Node, sttype::STType)
    idx = sttype_to_index(Int(sttype))
    return node.incidence[idx]
end

# ──────────────────────────────────────────────────────────────────
# Functional combinators for graph queries
# ──────────────────────────────────────────────────────────────────

"""
    find_nodes(store::AbstractSSTStore, predicate::Function) -> Vector{Node}

Find all nodes matching a predicate.

# Examples
```julia
# Find long text nodes
long_nodes = find_nodes(store, n -> n.l > 100)

# Find nodes in a chapter
ch_nodes = find_nodes(store, n -> n.chap == "vocabulary")
```
"""
function find_nodes(store::AbstractSSTStore, predicate::Function)::Vector{Node}
    return filter(predicate, nodes(store))
end

"""
    find_nodes(store::AbstractSSTStore, pattern::Regex) -> Vector{Node}

Find all nodes whose text matches a regex pattern.

# Example
```julia
fruit_nodes = find_nodes(store, r"fruit|apple|banana"i)
```
"""
function find_nodes(store::AbstractSSTStore, pattern::Regex)::Vector{Node}
    return filter(n -> occursin(pattern, n.s), nodes(store))
end

"""
    map_nodes(f::Function, store::AbstractSSTStore) -> Vector

Apply a function to each node and collect results.

# Example
```julia
names = map_nodes(n -> n.s, store)
```
"""
function map_nodes(f::Function, store::AbstractSSTStore)
    return map(f, nodes(store))
end

# ──────────────────────────────────────────────────────────────────
# do-block compile pattern
# ──────────────────────────────────────────────────────────────────

"""
    with_store(f::Function) -> MemoryStore
    with_store(f::Function, store::MemoryStore) -> MemoryStore

Execute a function with a MemoryStore, using do-block syntax.

# Example
```julia
store = with_store() do s
    a = mem_vertex!(s, "apple", "fruits")
    b = mem_vertex!(s, "banana", "fruits")
    mem_edge!(s, a, "contains", b)
end
```
"""
function with_store(f::Function)
    store = MemoryStore()
    f(store)
    return store
end

function with_store(f::Function, store::MemoryStore)
    f(store)
    return store
end

function _snapshot_arrow_context_state()
    return (
        arrows = copy(_ARROW_DIRECTORY),
        arrow_short_dir = copy(_ARROW_SHORT_DIR),
        arrow_long_dir = copy(_ARROW_LONG_DIR),
        inverse_arrows = copy(_INVERSE_ARROWS),
        ignore_arrows = copy(_IGNORE_ARROWS),
        arrow_top = _ARROW_DIRECTORY_TOP[],
        contexts = copy(_CONTEXT_DIRECTORY),
        context_dir = copy(_CONTEXT_DIR),
        context_top = _CONTEXT_TOP[],
    )
end

function _restore_arrow_context_state!(state)
    reset_arrows!()
    append!(_ARROW_DIRECTORY, state.arrows)
    merge!(_ARROW_SHORT_DIR, state.arrow_short_dir)
    merge!(_ARROW_LONG_DIR, state.arrow_long_dir)
    merge!(_INVERSE_ARROWS, state.inverse_arrows)
    append!(_IGNORE_ARROWS, state.ignore_arrows)
    _ARROW_DIRECTORY_TOP[] = state.arrow_top

    reset_contexts!()
    append!(_CONTEXT_DIRECTORY, state.contexts)
    merge!(_CONTEXT_DIR, state.context_dir)
    _CONTEXT_TOP[] = state.context_top
    nothing
end

"""
    with_registry_state(f::Function; reset::Bool=false, config_dir::Union{Nothing,AbstractString}=nothing)

Execute a function with temporary arrow/context registry changes, restoring the
previous module-level state afterwards.

- Set `reset=true` to start from a clean registry inside the block.
- Set `config_dir` to load an SSTconfig directory inside the temporary scope.

# Example
```julia
with_registry_state(reset=true, config_dir="/path/to/SSTconfig") do
    @assert get_arrow_by_name("remark") !== nothing
end
```
"""
function with_registry_state(f::Function; reset::Bool=false,
                             config_dir::Union{Nothing,AbstractString}=nothing)
    state = _snapshot_arrow_context_state()
    try
        if reset
            reset_arrows!()
            reset_contexts!()
        end
        if !isnothing(config_dir)
            load_config!(String(config_dir); reset=false)
        end
        return f()
    finally
        _restore_arrow_context_state!(state)
    end
end

"""
    with_config(f::Function, config_dir::String)

Execute a function after loading SST arrow configuration.

# Example
```julia
with_config("/path/to/SSTconfig") do
    result = parse_n4l("-section\\n apple (contain) fruit\\n"; load_config=false)
    @show result
end
```
"""
function with_config(f::Function, config_dir::String)
    return with_registry_state(f; reset=true, config_dir=config_dir)
end

# ──────────────────────────────────────────────────────────────────
# Pretty printing extensions
# ──────────────────────────────────────────────────────────────────

"""
    summary(store::MemoryStore) -> String

Human-readable summary of a MemoryStore's contents.
"""
function Base.summary(store::MemoryStore)
    nc = node_count(store)
    lc = link_count(store)
    ch = mem_get_chapters(store)
    return "MemoryStore: $nc nodes, $lc links, $(length(ch)) chapters"
end

"""
    show(io::IO, ::MIME"text/plain", store::MemoryStore)

Multi-line display of a MemoryStore.
"""
function Base.show(io::IO, ::MIME"text/plain", store::MemoryStore)
    nc = node_count(store)
    lc = link_count(store)
    ch = mem_get_chapters(store)
    println(io, "MemoryStore")
    println(io, "  Nodes:    $nc")
    println(io, "  Links:    $lc")
    println(io, "  Chapters: $(join(ch, ", "))")
end

function Base.show(io::IO, ::MIME"text/plain", r::N4LResult)
    println(io, "N4LResult")
    println(io, "  Errors:   $(length(r.errors))")
    println(io, "  Warnings: $(length(r.warnings))")
end
