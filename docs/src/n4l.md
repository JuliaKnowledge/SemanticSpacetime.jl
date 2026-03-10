# N4L — Notes For Learning

N4L is a lightweight markup language for entering knowledge as semi-structured notes. You write natural notes and N4L compiles them into a typed knowledge graph.

## Parsing N4L

```julia
using SemanticSpacetime
add_mandatory_arrows!()

result = parse_n4l("""
-chapter nursery rhymes

Mary had a little lamb
(then)
Its fleece was white as snow
""")

println(has_errors(result))   # false
```

The parser returns an [`N4LResult`](@ref) containing the parsed [`NodeDirectory`](@ref), any errors or warnings, and the final parser state.

## Compiling to a Store

Once parsed, compile the result into a store:

```julia
store = MemoryStore()
cr = compile_n4l!(store, result)
println(cr.nodes_created)
println(cr.edges_created)
```

Or use the convenience functions to parse and compile in one step:

```julia
store = MemoryStore()
compile_n4l_string!(store, "...")
compile_n4l_file!(store, "notes.n4l")
```

## Validation

Validate N4L text without compiling:

```julia
vr = validate_n4l("-chapter test\nhello\n(then)\nworld")
println(vr.valid)
println(vr.node_count)
```

Get a human-readable summary:

```julia
n4l_summary(result)
```

## N4L Syntax

| Syntax | Meaning |
|:-------|:--------|
| `-section name` | Start a new chapter/section |
| `text` | Create a node with this text |
| `(arrow)` | Link previous node to next node via arrow |
| `:: ctx ::` | Set context |
| `+:: ctx ::` | Add to context |
| `-:: ctx ::` | Remove from context |
| `@alias` | Create a line alias |
| `$alias` | Reference a previous alias |
| `"` | Ditto — reference the previous item |
| `#` or `//` | Comment |

See the [N4L vignette](https://github.com/JuliaKnowledge/SemanticSpacetime.jl/blob/main/vignettes/04-n4l-language/04-n4l-language.md) for detailed examples and the [SSTorytime N4L documentation](https://github.com/markburgess/SSTorytime/blob/main/docs/N4L.md) for the full language specification.

## Configuration Files

N4L supports configuration files for custom arrows, contexts, and closures. Use [`find_config_dir`](@ref) to locate the configuration directory and [`read_config_files`](@ref) to load them:

```julia
config_dir = find_config_dir()
read_config_files(config_dir)
```
