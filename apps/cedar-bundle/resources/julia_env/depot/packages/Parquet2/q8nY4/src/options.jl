
"""
    OptionSet

Abstract type for storing options for reading or writing parquet data.

See [`ReadOptions`](@ref) and [`WriteOptions`](@ref).
"""
abstract type OptionSet end

Base.getindex(o::OptionSet, ϕ) = getfield(o, ϕ)

Base.pairs(o::OptionSet) = (ϕ=>getfield(o, ϕ) for ϕ in fieldnames(ϕ))

function filterkw(::Type{𝒪}, kw) where {𝒪<:OptionSet}
    kw = NamedTuple(kw)
    kw = NamedTuple(ϕ=>getproperty(kw, ϕ) for ϕ ∈ (keys(kw) ∩ fieldnames(𝒪)))
    𝒪(;kw...)
end

function Base.iterate(opts::OptionSet, s=1)
    s > nfields(opts) && return nothing
    (fieldname(typeof(opts), s) => getfield(opts, s)), s+1
end

Base.length(opts::OptionSet) = nfields(opts)

function validatekeywords(::Type{𝒪}, kw) where {𝒪}
    valid = Set(fieldnames(𝒪))
    for k ∈ keys(kw)
        (k ∈ valid) && continue
        throw(ArgumentError("\"$k\" is an invalid keyword argument for $𝒪"))
    end
end

function evaloption(opts::OptionSet, name::Symbol, a...)
    opt = getfield(opts, name)
    opt isa AbstractOption ? evaloption(opt, a...) : opt
end


abstract type AbstractOption{𝒯} end

"""
    ColumnOption{𝒯}

A container for a column-specific read or write option with value type `𝒯`.  Contains
sets of names and types for determining what option to apply to a column.  Column-specific
keyword arguments passed to [`Dataset`] and [`FileWriter`] will be converted to
`ColumnOption`s.

The provide arguments must be one of the following:
- A single value of the appropriate type, in which case this option will be applied to all columns.
- A `NamedTuple` the keys of which are column names and the values of which are the value to be applied
    to the corresponding column.  Columns not listed will use the default option for that keyword
    argument.
- An `AbstractDict` the keys of which are the column names as strings.  This works analogously to
    `NamedTuple`.
- An `AbstractDict` the keys of which are types and the values of which are options to be applied to all
    columns with element types which are subtypes of the provided type.
- A `Pair` will be treated as a dictionary with a single entry.

## Constructors
```julia
ColumnOption(dict_value_or_namedtuple, default)
```
Users may wish to construct a `ColumnOption` and pass it as an argument to set their own default.

## Examples
```julia
# enable parallel page loading for *all* columns
Dataset(filename; parallel_page_loading=true)

# enable parallel page loading for column `col1`
Dataset(filename; parallel_page_loading=(col1=true,))

# columns `col1` and `col2` will be written with 2 and 3 pages respectively, else 1 page
writefile(filename; npages=Dict("col1"=>2, "col2"=>3))

# `col1` will use snappy compression, all other columns will use zstd
writefile(filename; compression_codec=Parquet2.ColumnOption((col1=:snappy), :zstd))

# All dictionary columns will be encoded as BSON
writefile(filename; bson_columns=Dict(AbstractDict=>true))
```
"""
struct ColumnOption{𝒯} <: AbstractOption{𝒯}
    names::Dict{Set{String},𝒯}
    types::Dict{Set{Type},𝒯}
    default::𝒯
end

function ColumnOption(val, default::𝒯) where {𝒯}
    val = convert(𝒯, val)
    ColumnOption{𝒯}(Dict{Set{String},𝒯}(), Dict{Set{Type},𝒯}(), val)
end
function ColumnOption(nt::NamedTuple, default::𝒯) where {𝒯}  # in this case keys are column names
    names = Dict{Set{String},𝒯}(Set([string(k)])=>convert(𝒯, v) for (k,v) ∈ nt)
    ColumnOption{𝒯}(names, Dict{Set{Type},𝒯}(), default)
end
function ColumnOption(dct::AbstractDict, default::𝒯) where {𝒯}
    names = Dict{Set{String},𝒯}()
    types = Dict{Set{Type},𝒯}()
    for (k, v) ∈ dct
        v = convert(𝒯, v)
        if k isa AbstractString
            names[Set([k])] = v
        elseif k isa Symbol
            names[Set([string(k)])] = v
        elseif k isa Type
            types[Set([k])] = v
        elseif eltype(k) <: AbstractString
            names[Set(k)] = v
        elseif eltype(k) <: Symbol
            names[Set(string(κ) for κ ∈ k)] = v
        elseif eltype(k) <: Type
            types[Set(k)] = v
        else
            throw(ArgumentError("invalid column option key $k"))
        end
    end
    ColumnOption{𝒯}(names, types, default)
end
function ColumnOption(cols::AbstractVector{<:AbstractString}, default::Bool)
    ColumnOption(Dict(cols=>!default), default)
end
ColumnOption(cols::AbstractVector{Symbol}, default::Bool) = ColumnOption(string.(cols), default)
ColumnOption(opt::ColumnOption, default) = opt

function fromkw(::Type{𝒪}, kw, optname, default) where {𝒪<:AbstractOption}
    o = get(kw, optname, missing)
    if ismissing(o)
        𝒪(default, default)
    else
        𝒪(o, default)
    end
end

function evaloption(opt::ColumnOption, name::AbstractString, type=nothing)
    for (t, v) ∈ opt.types
        for τ ∈ t
            type <: t && return v
        end
    end
    if !isnothing(type)
        for (n, v) ∈ opt.names
            name ∈ n && return v
        end
    end
    opt.default
end
evaloption(opt::ColumnOption, name::Symbol, type=nothing) = evaloption(opt, string(name), type)
function evaloption(opt::ColumnOption, type::Type)
    for (t, v) ∈ opt.types
        type ∈ t && return v
    end
    opt.default
end


"""
    ReadOptions <: OptionSet

A struct containing all options relevant for reading parquet files.  Specific
options are documented in [`Dataset`](@ref).
"""
struct ReadOptions <: OptionSet
    # file options
    support_legacy::Bool
    use_mmap::Bool
    mmap_shared::Bool
    load_initial::Union{Nothing,Bool}
    parallel_column_loading::Union{Nothing,Bool}

    # column options
    allow_string_copying::ColumnOption{Bool}
    lazy_dictionary::ColumnOption{Bool}
    parallel_page_loading::ColumnOption{Bool}
    use_statistics::ColumnOption{Bool}
    eager_page_scanning::ColumnOption{Bool}
end

function ReadOptions(;kw...)
    validatekeywords(ReadOptions, kw)
    ReadOptions(get(kw, :support_legacy, true),
                get(kw, :use_mmap, true),
                get(kw, :mmap_shared, true),
                get(kw, :load_initial, nothing),
                get(kw, :parallel_column_loading, nothing),
                fromkw(ColumnOption, kw, :allow_string_copying, false),
                fromkw(ColumnOption, kw, :lazy_dictionary, true),
                fromkw(ColumnOption, kw, :parallel_page_loading, false),
                fromkw(ColumnOption, kw, :use_statistics, false),
                fromkw(ColumnOption, kw, :eager_page_scanning, true),
               )
end


"""
    WriteOptions <: OptionSet

A struct containing all options relevant for writing parquet files.  Specific
options are documented in [`FileWriter`](@ref)
"""
struct WriteOptions <: OptionSet
    # file options
    metadata::Dict{String,Any}
    propagate_table_metadata::Bool

    # column options
    npages::ColumnOption{Int}
    compression_codec::ColumnOption{Symbol}
    column_metadata::ColumnOption{Dict{String,Any}}
    compute_statistics::ColumnOption{Bool}
    json_columns::ColumnOption{Bool}
    bson_columns::ColumnOption{Bool}
    propagate_col_metadata::ColumnOption{Bool}
end

function WriteOptions(;kw...)
    validatekeywords(WriteOptions, kw)
    WriteOptions(get(kw, :metadata, Dict()),
                 get(kw, :propagate_table_metadata, true),
                 fromkw(ColumnOption, kw, :npages, 1),
                 fromkw(ColumnOption, kw, :compression_codec, :snappy),
                 fromkw(ColumnOption, kw, :column_metadata, Dict{String,Any}()),
                 fromkw(ColumnOption, kw, :compute_statistics, false),
                 fromkw(ColumnOption, kw, :json_columns, false),
                 fromkw(ColumnOption, kw, :bson_columns, false),
                 fromkw(ColumnOption, kw, :propagate_col_metadata, true),
                )
end
