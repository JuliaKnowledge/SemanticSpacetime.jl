#=
Asset attachment helpers for Semantic Spacetime.

Ports the recent SSTorytime note-asset workflow into Julia using a
filesystem-backed cache keyed by note text, chapter, and context.
=#

import Downloads
import HTTP
using SHA

const _MAX_ASSET_BYTES = 25 * 1024 * 1024

_normalize_asset_context(context::AbstractString) = strip(String(context))
_normalize_asset_context(context::AbstractVector{<:AbstractString}) =
    join(filter(!isempty, strip.(String.(context))), ",")

function _sanitize_asset_component(s::AbstractString; empty::AbstractString="any")
    cleaned = replace(String(s), r"[^A-Za-z0-9]+" => "_")
    cleaned = replace(cleaned, r"^_+" => "")
    cleaned = replace(cleaned, r"_+$" => "")
    return isempty(cleaned) ? empty : cleaned
end

function _asset_key(name::AbstractString)::String
    _, cls = storage_class(name)
    if cls in (N1GRAM, N2GRAM, N3GRAM)
        return _sanitize_asset_component(name; empty="note")
    end

    words = filter(!isempty, split(strip(String(name))))
    prefix_words = isempty(words) ? ["note"] : words[1:min(3, length(words))]
    prefix = join([_sanitize_asset_component(word; empty="note") for word in prefix_words], "_")
    digest = bytes2hex(SHA.sha1(String(name)))
    return "$(prefix)_$(digest)"
end

function _normalize_asset_filename(source::AbstractString;
                                   filename::Union{Nothing,AbstractString}=nothing)::String
    candidate = something(filename, basename(first(split(String(source), '?'; limit=2))))
    stem, ext = splitext(candidate)
    safe_stem = _sanitize_asset_component(stem; empty="asset")
    safe_ext = replace(lowercase(ext), r"[^a-z0-9\.]" => "")
    return isempty(safe_ext) ? safe_stem : safe_stem * safe_ext
end

function _ensure_asset_size(size::Integer)
    size <= _MAX_ASSET_BYTES || error("Asset exceeds maximum size of $(_MAX_ASSET_BYTES) bytes")
    return size
end

function _check_asset_size(path::AbstractString)
    return _ensure_asset_size(filesize(path))
end

function _check_asset_size(data::AbstractVector{UInt8})
    return _ensure_asset_size(length(data))
end

function _asset_dir(name::AbstractString, chapter::AbstractString, context; root::AbstractString)
    ctx = _normalize_asset_context(context)
    return joinpath(root, "cacheroot",
        _sanitize_asset_component(chapter; empty="any"),
        _sanitize_asset_component(ctx; empty="any"),
        _asset_key(name))
end

function _asset_url(file::AbstractString, name::AbstractString, chapter::AbstractString, context;
                    base_url::AbstractString="/api/assets/file")
    ctx = _normalize_asset_context(context)
    return string(
        base_url,
        "?name=", HTTP.escapeuri(String(name)),
        "&chapter=", HTTP.escapeuri(String(chapter)),
        "&context=", HTTP.escapeuri(ctx),
        "&file=", HTTP.escapeuri(basename(String(file))),
    )
end

"""
    sanitize_asset_path(s::AbstractString) -> String

Normalize an arbitrary chapter/context/name fragment into a filesystem-safe path
component for the SST asset cache.
"""
sanitize_asset_path(s::AbstractString) = _sanitize_asset_component(s; empty="any")

"""
    asset_cache_location(name, chapter; context="", root=pwd()) -> String

Return the cache directory used for assets attached to a note identified by its
text, chapter, and context.
"""
function asset_cache_location(name::AbstractString, chapter::AbstractString;
                              context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                              root::AbstractString=pwd())::String
    return _asset_dir(name, chapter, context; root=root)
end

"""
    list_cached_assets(name, chapter; context="", root=pwd()) -> Vector{String}

List cached asset files attached to a note, returning absolute filesystem paths.
If no assets are present, returns an empty vector.
"""
function list_cached_assets(name::AbstractString, chapter::AbstractString;
                            context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                            root::AbstractString=pwd())::Vector{String}
    dir = _asset_dir(name, chapter, context; root=root)
    isdir(dir) || return String[]
    return sort(filter(isfile, readdir(dir; join=true)); by=basename)
end

"""
    attach_asset!(source_path, name, chapter; context="", root=pwd(), filename=nothing) -> String
    attach_asset!(data, source_name, name, chapter; context="", root=pwd(), filename=nothing) -> String

Copy a local file, or write in-memory uploaded bytes, into the SST asset cache
for a note identified by `(name, chapter, context)`. Returns the cached file
path.
"""
function attach_asset!(source_path::AbstractString, name::AbstractString, chapter::AbstractString;
                       context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                       root::AbstractString=pwd(),
                       filename::Union{Nothing,AbstractString}=nothing)::String
    isfile(source_path) || error("Asset source file does not exist: $source_path")
    _check_asset_size(source_path)

    dir = _asset_dir(name, chapter, context; root=root)
    mkpath(dir)

    target_name = _normalize_asset_filename(source_path; filename=filename)
    target_path = joinpath(dir, target_name)
    cp(source_path, target_path; force=true)
    return target_path
end

function attach_asset!(data::AbstractVector{UInt8}, source_name::AbstractString,
                       name::AbstractString, chapter::AbstractString;
                       context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                       root::AbstractString=pwd(),
                       filename::Union{Nothing,AbstractString}=nothing)::String
    _check_asset_size(data)

    dir = _asset_dir(name, chapter, context; root=root)
    mkpath(dir)

    target_name = _normalize_asset_filename(source_name; filename=filename)
    target_path = joinpath(dir, target_name)
    write(target_path, data)
    return target_path
end

"""
    attach_asset_from_uri!(uri, name, chapter; context="", root=pwd(), filename=nothing) -> String

Download a remote or `file://` URI into the SST asset cache for a note
identified by `(name, chapter, context)`. Returns the cached file path.
"""
function attach_asset_from_uri!(uri::AbstractString, name::AbstractString, chapter::AbstractString;
                                context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                                root::AbstractString=pwd(),
                                filename::Union{Nothing,AbstractString}=nothing)::String
    lower = lowercase(String(uri))
    startswith(lower, "http://") || startswith(lower, "https://") || startswith(lower, "file://") ||
        error("Asset URI must use http://, https://, or file://")

    downloaded = Downloads.download(String(uri))
    try
        guessed = something(filename, basename(first(split(String(uri), '?'; limit=2))))
        return attach_asset!(downloaded, name, chapter;
            context=context, root=root, filename=guessed)
    finally
        isfile(downloaded) && rm(downloaded; force=true)
    end
end

function cached_asset_path(name::AbstractString, chapter::AbstractString, file::AbstractString;
                           context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                           root::AbstractString=pwd())
    path = joinpath(_asset_dir(name, chapter, context; root=root), basename(String(file)))
    return isfile(path) ? path : nothing
end

function cached_asset_urls(name::AbstractString, chapter::AbstractString;
                           context::Union{AbstractString,AbstractVector{<:AbstractString}}="",
                           root::AbstractString=pwd(),
                           base_url::AbstractString="/api/assets/file")::Vector{String}
    return [_asset_url(path, name, chapter, context; base_url=base_url)
            for path in list_cached_assets(name, chapter; context=context, root=root)]
end
