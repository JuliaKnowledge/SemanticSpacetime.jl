# N4L API

## Parser

```@docs
N4LState
N4LResult
N4LParseError
parse_n4l
parse_n4l_file
parse_config_file
find_config_dir
read_config_files
has_errors
has_warnings
ROLE_EVENT
ROLE_RELATION
ROLE_SECTION
ROLE_CONTEXT
ROLE_CONTEXT_ADD
ROLE_CONTEXT_SUBTRACT
ROLE_BLANK_LINE
ROLE_LINE_ALIAS
ROLE_LOOKUP
ROLE_COMPOSITION
ROLE_RESULT
```

## Compiler

```@docs
N4LCompileResult
compile_n4l!
compile_n4l_file!
compile_n4l_string!
```

## Validation and Summary

```@docs
N4LValidationResult
validate_n4l
validate_n4l_file
n4l_summary
```

## Provenance

```@docs
Provenance
set_provenance!
get_provenance
compile_n4l_with_provenance!
```

## Macros

```@docs
@n4l_str
@sst
@compile
@graph
```
