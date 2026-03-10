#=
Built-in dynamic function evaluation for Semantic Spacetime.
Supports {TimeUntil ...} and {TimeSince ...} expressions in text.
=#

"""Expand dynamic function expressions in text (e.g., Dynamic:{TimeUntil Day5})."""
function expand_dynamic_functions(s::AbstractString)::String
    !occursin("{", s) && return s
    !occursin("}", s) && return s

    # Strip "Dynamic:" prefix if present
    text = s
    if startswith(text, "Dynamic:")
        text = text[length("Dynamic:")+1:end]
    end

    chars = collect(text)
    result = Char[]
    pos = 1

    while pos <= length(chars)
        if chars[pos] != '{'
            push!(result, chars[pos])
            pos += 1
        else
            newpos, fn_result = evaluate_in_built(chars, pos)
            append!(result, collect(fn_result))
            pos = newpos + 1
        end
    end

    return String(result)
end

"""Evaluate a built-in function starting at pos (the '{' character)."""
function evaluate_in_built(chars::Vector{Char}, pos::Int)::Tuple{Int,String}
    fntext = Char[]
    endpos = pos

    for r in (pos+1):length(chars)
        chars[r] == '}' && (endpos = r; break)
        push!(fntext, chars[r])
        endpos = r
    end

    fn = split(strip(String(fntext)))
    result = do_in_built_function(fn)
    return (endpos, result)
end

"""Dispatch built-in function by name."""
function do_in_built_function(fn::Vector{<:AbstractString})::String
    isempty(fn) && return ""

    fname = fn[1]
    if fname == "TimeUntil"
        return in_built_time_until(fn)
    elseif fname == "TimeSince"
        return in_built_time_since(fn)
    end

    return ""
end

"""Calculate time until a semantic time specification."""
function in_built_time_until(fn::Vector{<:AbstractString})::String
    now = Dates.now()
    intended = get_time_from_semantics([String(f) for f in fn], now)
    duration = intended - now

    total_secs = round(Int, Dates.value(duration) / 1000)

    years = total_secs ÷ (365 * 24 * 3600)
    r1 = total_secs % (365 * 24 * 3600)
    days = r1 ÷ (24 * 3600)
    r2 = r1 % (24 * 3600)
    hours = r2 ÷ 3600
    r3 = r2 % 3600
    mins = r3 ÷ 60

    return show_time(years, days, hours, mins)
end

"""Calculate time since a semantic time specification."""
function in_built_time_since(fn::Vector{<:AbstractString})::String
    now = Dates.now()
    intended = get_time_from_semantics([String(f) for f in fn], now)
    duration = now - intended

    total_secs = round(Int, Dates.value(duration) / 1000)

    years = total_secs ÷ (365 * 24 * 3600)
    r1 = total_secs % (365 * 24 * 3600)
    days = r1 ÷ (24 * 3600)
    r2 = r1 % (24 * 3600)
    hours = r2 ÷ 3600
    r3 = r2 % 3600
    mins = r3 ÷ 60

    return show_time(years, days, hours, mins)
end
