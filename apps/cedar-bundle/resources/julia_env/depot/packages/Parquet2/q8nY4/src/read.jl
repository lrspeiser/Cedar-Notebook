
# element type of byte arrays in parquet columns
const ByteArrayView = SubArray{UInt8,1,Vector{UInt8},Tuple{UnitRange{Int64}},true}

"""
    convertvalue(pt::ParquetType, x)

Provided the parquet encoded value `x` convert it to the Julia object appropriate for the parquet type `pt`.
"""
convertvalue(::ParquetType, ::Missing) = missing
convertvalue(pt::ParquetType, x) = convert(juliatype(pt), x)
# this is a work-around of a bizarre issue caused by the fact that parquet declares its fundamental
# types to be signed ints.  If you don't use reinterpret on e.g. typemax(UInt64), it will error
# this is obviously not an ideal solution, I think the only real alternative is to change it so that
# within Parquet2 the bitstypes are UInt by default.  This is not a trivial change
function convertvalue(pt::ParquetBitsType, x) 
    jt = juliatype(pt)
    if sizeof(jt) == sizeof(x)
        reinterpret(jt, x)
    else
        convert(jt, x)
    end
end
convertvalue(::ParqString, x::AbstractVector{UInt8}) = String(x)
# one needs to be careful here because String steals data
convertvalue(::ParqString, x::Vector{UInt8}) = String(x)
convertvalue(pt::ParqDateTime, x) = DateTime(pt, x)
convertvalue(pt::ParqDate, x) = Date(pt, x)
convertvalue(pt::ParqTime, x) = Time(pt, x)
# fixed-length strings will have trailing 0x00 bytes that should be omitted
convertvalue(pt::ParqString, x::SVector{N,UInt8}) where {N} = rstrip(String(x), Char(0x00))
convertvalue(pt::ParqDecimal, x::Integer) = Dec64(pt, x)
convertvalue(pt::ParqDecimal, x::StaticArray)  = Dec64(pt, x)
convertvalue(pt::ParqUUID, x::StaticArray) = UUID(staticarray2int(UInt128, x))
convertvalue(pt::ParqByteArray, x::AbstractVector{UInt8}) = x

# WARN! this returns a WeakRefString for performance
convertvalue(::ParqString, x::SubArray{UInt8,1}) = WeakRefString(pointer(parent(x))+x.offset1, length(x))

# ensure this doesn't try to do something crazy
convertvalue(::ParqFixedByteArray, v::StaticArray) = v

convertvalue(::ParqJSON, x::AbstractVector{UInt8}) = JSON3.read(x, Union{Dict{String,Any},Vector{Any}})
convertvalue(pt::ParqJSON, x::AbstractString) = convertvalue(pt, codeunits(x))

# unfortunately LightBSON requires us to make this into a regular Vector
convertvalue(::ParqBSON, x::AbstractVector{UInt8}) = bson_read(Vector(x))

# the following are to resolve method ambiguities
for PT ∈ (:ParqDateTime, :ParqDate, :ParqTime)
    @eval convertvalue(::$PT, ::Missing) = missing
end

"""
    VectorWithStatistics{𝒯,𝒮,𝒱<:AbstractVector{𝒯}} <: AbstractVector{𝒯}

A wrapper for an `AbstractVector` object which can store the following statistics:
- minimum value, accessible with `minimum(v)`
- maximum value, accessible with `maximum(v)`
- number of missings, accessible with `count(ismissing, v)`
- number of distinct elements, accessible with `ndistinct(v)`.

Methods are provided so that the stored values are returned rather than re-computing the values when
these functions are called.  Note that a method is also provided for `count(!ismissing, v)` so this should
also be efficient.

The `use_statistics` option for [`Dataset`](@ref) controls whether columns are loaded with statistics.
"""
struct VectorWithStatistics{𝒯,𝒮,𝒱<:AbstractVector{𝒯}} <: AbstractVector{𝒯}
    statistics::ColumnStatistics{𝒮}  # carry extra parameter in case of missings
    data::𝒱

    function VectorWithStatistics(stats::ColumnStatistics, v::AbstractVector)
        et = eltype(v)
        new{et,nonmissingtype(et),typeof(v)}(stats, v)
    end
end

Base.size(v::VectorWithStatistics) = size(v.data)

Base.getindex(v::VectorWithStatistics, i::Int) = v.data[i]::eltype(v)

Base.IndexStyle(::Type{<:VectorWithStatistics}) = IndexLinear()

Base.minimum(v::VectorWithStatistics) = v.statistics.min ≡ nothing ? minimum(v.data) : v.statistics.min
Base.maximum(v::VectorWithStatistics) = v.statistics.max ≡ nothing ? maximum(v.data) : v.statistics.max

"""
    ndistinct(v::AbstractVector)

Get the number of distinct elements in `v`.  If `v` is a `VectorWithStatistics`, as returned from parquet columns
when metadata is available, computation will be elided and the stored value will be used instead.
"""
ndistinct(v::VectorWithStatistics) = v.statistics.n_distinct ≡ nothing ? length(unique(v)) : v.statistics.n_distinct
ndistinct(v::AbstractVector) = length(unique(v))

function Base.count(::typeof(ismissing), v::VectorWithStatistics)
    v.statistics.n_null ≡ nothing ? count(ismissing, v) : v.statistics.n_null
end
Base.count(::typeof(!ismissing), v::VectorWithStatistics) = length(v) - count(ismissing, v)


"""
    AbstractColumnLoader{𝒞<:Column,P}

A wrapper of a parquet `Column` to hold outputs and any possible intermediate state
for deserialization of the column.  Different subtypes are defined for different
methods of loading the column.  The parameter `P::Bool` indicates whether page
loading should be parallel.
"""
abstract type AbstractColumnLoader{𝒞<:Column,P} end

pageloaders(co::AbstractColumnLoader) = pageloaders(co.column)

Base.values(co::AbstractColumnLoader) = co.values

parqtype(co::AbstractColumnLoader, pl::PageLoader) = parqtype(pl)

"""
    ColumnAllocLoader <: AbstractColumnLoader

A `Column` wrapper for loading the column by fully allocating the output array and writing
values into it as they are read.  Can load pages in parallel or not.

Note that this type is *not* for strings which require their own special loader types.
"""
struct ColumnAllocLoader{𝒞<:Column,P,𝒯,ℳ} <: AbstractColumnLoader{𝒞,P}
    column::𝒞
    values::Vector{𝒯}
    pool::Vector{ℳ}
end

function ColumnAllocLoader(c::Column)
    vals = outputvector(c)
    pool = poolvector(c)
    P = c.parallel_page_loading
    ColumnAllocLoader{typeof(c),P,eltype(vals),eltype(pool)}(c, vals, pool)
end


"""
    ColumnStringLoader <: AbstractColumnLoader

A `Column` wrapper for deserializing arrays of strings from a parquet file.  The buffer
allocated at the start of the serializatin will have the same size as the number of
uncompressed bytes in the column, i.e. it will greatly overestimate the required size.

Note that this laoder can only load page sequentially due to memory and garbage collection
limitations (i.e. the complexity of doing this in parallel vastly outweighs the typically
small performance benefits).
"""
struct ColumnStringLoader{𝒞<:Column,P,𝒯} <: AbstractColumnLoader{𝒞,P}
    column::𝒞
    values::StringVector{𝒯}
    pool::StringVector{String}
end

parqtype(co::ColumnStringLoader, pl::PageLoader) = ParqString()

function _check_column_string_type(pt)
    if pt ∉ (ParqString(), ParqJSON(), ParqBSON())
        throw(ArgumentError("parquet data type $pt cannot be interpreted as strings"))
    end
end

function ColumnStringLoader(c::Column)
    pt = parqtype(c)
    _check_column_string_type(pt)
    et = juliamissingtype(c) >: Missing ? Union{Missing,String} : String
    vals = StringVector{et}(undef, nvalues(c))
    # try to make space for data in column; this is a significant *over* estimate
    sizehint!(vals.buffer, nbytesuncompressed(c))
    pool = StringVector{String}()
    P = c.parallel_page_loading
    # we disable parallel page loading in this case because scariness
    ColumnStringLoader{typeof(c),false,eltype(vals)}(c, vals, pool)
end

Base.values(co::ColumnStringLoader) = co.values


"""
    ColumnStringViewLoader <: AbstractColumnLoader

A `Column` wrapper for deserializing strings without copying.  The resulting output needs
to maintain a reference to the original parquet buffer to keep it from being garbage collected,
therefore using this loader requires keeping the entire parquet `RowGroup` in memory.
"""
struct ColumnStringViewLoader{𝒞<:Column,P,𝒯} <: AbstractColumnLoader{𝒞,P}
    column::𝒞
    values::Vector{𝒯}
    refs::Set{Ref}  # should not need explicit typing since we don't access it
end

parqtype(co::ColumnStringViewLoader, pl::PageLoader) = ParqString()

function ColumnStringViewLoader(c::Column)
    et = juliamissingtype(c) >: Missing ? Union{Missing,WeakRefString} : WeakRefString
    vals = Vector{et}(undef, nvalues(c))
    ColumnStringViewLoader{typeof(c),false,eltype(vals)}(c, vals, Set{Ref}())
end

function Base.values(co::ColumnStringViewLoader)
    StringRefVector{juliamissingtype(co.column),eltype(co.values)}(co.refs, co.values)
end


"""
    ColumnDictLoader <: AbstractColumnLoader

A `Column` wrapper for loading a parquet dictionary encoded column into a Julia object with analogous structure,
see [`PooledVector`](@ref).  That is, an array of integer references is allocated, but the values are only
allocated once per distinct value.  Can load pages in parallel or not.
"""
struct ColumnDictLoader{𝒞<:Column,P,𝒯,𝒫} <: AbstractColumnLoader{𝒞,P}
    column::𝒞
    values::Vector{𝒯}  # 𝒯 must be either UInt32 or Union{Missing,UInt32}
    pool::Vector{𝒫}
end

function ColumnDictLoader(c::Column)
    jt = juliamissingtype(c)
    rt = jt >: Missing ? Union{Missing,UInt32} : UInt32
    vals = if jt >: Missing
        zeros(Union{Missing,UInt32}, nvalues(c))
    else
        Vector{UInt32}(undef, nvalues(c))
    end
    pool = Vector{juliatype(c)}()
    P = c.parallel_page_loading
    ColumnDictLoader{typeof(c),P,eltype(vals),eltype(pool)}(c, vals, pool)
end

Base.values(co::ColumnDictLoader) = PooledVector(co.pool, co.values)


function _loadplain_bits!(o::AbstractVector, k::Integer, v::AbstractVector, n::Integer, pt::ParquetType)
    i = 1
    for j ∈ k:(k+n-1)
        o[j] = convertvalue(pt, v[i])
        i += 1
    end
    nothing
end
function _loadplain_bits!(o::AbstractVector{Union{Missing,𝒯}}, k::Integer, v::AbstractVector, n::Integer,
                          pt::ParquetType,
                         ) where {𝒯}
    i = 1
    for j ∈ k:(k+n-1)
        isassigned(o, j) && ismissing(o[j]) && continue
        o[j] = convertvalue(pt, v[i])
        i += 1
    end
    nothing
end

function _loadplain_bytearrays!(o::AbstractVector, k::Integer, v::AbstractVector, n::Integer, pt::ParquetType)
    m = 1
    for j ∈ k:(k+n-1)
        ℓ = reinterpret(UInt32, view(v, m:(m+3)))[1]
        m += 4
        o[j] = convertvalue(pt, view(v, m:(m + ℓ - 1)))
        m += ℓ
    end
    nothing
end
function _loadplain_bytearrays!(o::AbstractVector{𝒯}, k::Integer, v::AbstractVector, n::Integer,
                                pt::ParquetType) where {𝒯>:Missing}
    m = 1
    for j ∈ k:(k+n-1)
        isassigned(o, j) && ismissing(o[j]) && continue
        ℓ = reinterpret(UInt32, view(v, m:(m+3)))[1]
        m += 4
        o[j] = convertvalue(pt, view(v, m:(m + ℓ - 1)))
        m += ℓ
    end
    nothing
end

function _loadbits_hybrid!(o::AbstractVector{>:Missing}, k::Integer, n::Integer, hi::HybridIterator)
    for r ∈ hi
        for x ∈ r
            while isassigned(o, k) && ismissing(o[k])
                k += 1
            end
            o[k] = x
            k += 1
        end
    end
    k
end
function _loadbits_hybrid!(o::AbstractVector{<:Integer}, k::Integer, n::Integer, hi::HybridIterator)
    for r ∈ hi
        view(o, k:(k+length(r)-1)) .= r
        k += length(r)
    end
    k
end

function _loadbits_refs!(o::AbstractVector{Union{𝒯,Missing}}, k::Integer, n::Integer, p::AbstractVector,
                         hi::HybridIterator) where {𝒯}
    for r ∈ hi
        for x ∈ r
            while isassigned(o, k) && ismissing(o[k])
                k += 1
            end
            o[k] = p[x + 1]
            k += 1
        end
    end
    k
end
function _loadbits_refs!(o::AbstractVector, k::Integer, n::Integer, p::AbstractVector, hi::HybridIterator)
    for r ∈ hi
        view(o, k:(k+length(r)-1)) .= getindex.((p,), r .+ 1)
        k += length(r)
    end
    k
end

function _loadbits_refs!(co::AbstractColumnLoader, k::Integer, n::Integer, hi::HybridIterator)
    _loadbits_refs!(co.values, k, n, co.pool, hi)
end
function _loadbits_refs!(co::ColumnDictLoader, k::Integer, n::Integer, hi::HybridIterator)
    _loadbits_hybrid!(co.values, k, n, hi)
end

function _fillmissings!(o::AbstractVector, k::Integer, r::AbstractVector)
    n = 0  # count missing
    for (j, x) ∈ enumerate(r)
        if iszero(x)
            o[k+j-1] = missing
            n += 1
        end
    end
    n
end

function _loaddeflevels!(o::AbstractVector, k::Integer, hi::HybridIterator)
    n = 0  # count missing
    for r ∈ hi
        isempty(r) && continue
        if r isa Fill
            # only need to do anything at all if these are zeros
            if r[1] == 0
                view(o, k:(k+length(r)-1)) .= missing
                n += length(r)
            end
            k += length(r)
        else
            n += _fillmissings!(o, k, r)
            k += length(r)
        end
    end
    k, n
end

function _loadplain!(o::AbstractVector, k::Integer, v::AbstractVector, n::Integer,
                     pt::ParquetType,
                     bt::ParquetBitsType,  # parquet base type
                     ::Type{ℬ};  # julia base type
                     n_non_null::Integer=n,
                    ) where {ℬ}
    if bt isa ParqBool
        w = BitUnpackVector{Bool}(v, 1, n)
        _loadplain_bits!(o, k, w, n, pt)
    elseif isbitstype(nonmissingtype(eltype(o))) || bt isa ParqFixedByteArray
        w = reinterpret(ℬ, view(v, 1:(n_non_null*sizeof(ℬ))))
        _loadplain_bits!(o, k, w, n, pt)
    else
        _loadplain_bytearrays!(o, k, v, n, pt)
    end
end

function _checkreplevels(pl::PageLoader)
    if hasreplevels(pl)
        error("tried to load repetition levels; this indicates an unsupported nested data format is"*
              "improperly trying to load")
    end
    nothing
end

function _loaddeflevels!(co::AbstractColumnLoader, pl::PageLoader, v::AbstractVector=view(pl))
    m = maxdeflevel(pl)
    n = nvalues(pl)
    if !hasdeflevels(pl, m)
        pl.n_non_null[] = n
        return nothing
    end
    # figure out whether nbytes is stored in the buffer
    (ν, δ) = if pl.page.header.nbytesdef > 0
        (pl.page.header.nbytesdef, 0)
    else
        (nothing, 4)  # in this case 4 is from reading nbytes
    end
    hi = HybridIterator{UInt32}(v, 1, bitwidth(m), n, ν)
    (_, n_null) = _loaddeflevels!(co.values, colstartindex(pl), hi)
    pl.δ[] += hi.nbytes + δ
    pl.n_non_null[] = n - n_null
    nothing
end

function _loadpool!(co::AbstractColumnLoader, pl::PageLoader)
    k = length(co.pool) + 1
    n = nvalues(pl)
    v = view(pl)
    resize!(co.pool, length(co.pool) + nvalues(pl))
    # this assumes the dict pool is always plain encoded
    _loadplain!(co.pool, k, v, n, parqtype(co, pl), parqbasetype(pl), juliabasetype(pl))
end


function _loadrefs!(co::AbstractColumnLoader, pl::PageLoader, v::AbstractVector=view(pl))
    n = pl.n_non_null[]
    (w, δ) = leb128decode(UInt32, v, 1)
    w = Int(w)
    if w > 32
        error("invalid bit width for dictionary encoding ($w); parquet buffer may be corrupted")
    end
    pl.δ[] += δ - 1
    hi = HybridIterator{UInt32}(v, δ, w, n, length(v)-δ)
    _loadbits_refs!(co, colstartindex(pl), nvalues(pl), hi)
    nothing
end

function _loadplain!(co::AbstractColumnLoader, pl::PageLoader)
    n = nvalues(pl)
    _loadplain!(co.values, colstartindex(pl), view(pl), n, parqtype(co, pl), parqbasetype(pl), juliabasetype(pl);
                n_non_null=pl.n_non_null[],
               )
end

"""
    init!(co::AbstractColumnLoader, pl::PageLoader)

Perform any initialization needed to accommodate loading from the page on the column loader.
"""
init!(::AbstractColumnLoader, ::PageLoader) = nothing
init!(co::ColumnStringViewLoader, pl::PageLoader) = push!(co.refs, Ref(view(pl)))

"""
    load!(co::AbstractColumnLoader, pl::PageLoader)

Deserialize a single page (wrapped by the page loader `pl`) into the
column loader output.
"""
function load!(co::AbstractColumnLoader, pl::PageLoader)
    reset!(pl)
    let enc = encoding(pl)
        enc ∈ unsupported_encodings() && error("Parquet2.jl does not yet support $enc binary encoding")
    end
    init!(co, pl)
    _checkreplevels(pl)
    _loaddeflevels!(co, pl)
    if isdictpool(pl)
        _loadpool!(co, pl)
    elseif isdictrefs(pl)
        _loadrefs!(co, pl)
    else
        _loadplain!(co, pl)
    end
end

"""
    _defaultvalue(c::Column)

Get the default value that will fill an output column constructed for `c`.  This is important because of the way
`missing`s are handled, it must be possible to determine which elements of an uninitialized array are null.
"""
function _defaultvalue(c::Column)
    jt = juliatype(c)
    if jt <: DecFP.DecimalFloatingPoint
        jt(0.0)
    else
        jt(zero(juliabasetype(c)))
    end
end

"""
    outputvector(c::Column)

Create an uninitialized output vector to which the values of column `c` can be written.  There is some subtlety in
the element type in cases where `missing` is present because of the different semantics for uninitialized arrays
for bits-types and non-bits-types.
"""
function outputvector(c::Column, n::Integer=nvalues(c))
    jt = juliamissingtype(c)
    if jt >: Missing
        t = nonmissingtype(jt)
        if isbitstype(t)
            o = Vector{jt}(undef, n)
            o .= _defaultvalue(c)
            o
        elseif t <: StaticVector
            # don't specify further than StaticVector to avoid conversion catastrophes
            Vector{Union{Missing,StaticVector}}(undef, n)
        else
            # in this case we can use isassigned to determine if null
            Vector{jt}(undef, n)
        end
    else
        Vector{jt}(undef, n)  # no need for annoying shit
    end
end

poolvector(c::Column) = Vector{juliatype(c)}()

# sequential
"""
    load!(co::AbstractColumnLoader)

Deserialize data from the column wrapped by the column loader object.

This will be sequential or parallel depending on how the loader was initialized.
"""
function load!(co::AbstractColumnLoader{𝒞,false}) where {𝒞}
    for pl ∈ pageloaders(co)
        load!(co, pl)
    end
    co
end

# parallel
function load!(co::AbstractColumnLoader{𝒞,true}) where {𝒞}
    pls = collect(pageloaders(co))
    if hasdictencoding(co.column)
        # we are guaranteed to only have one dict page
        dp_idx = findfirst(isdictpool, pls)
        isnothing(dp_idx) && error("failed to find required dictionary pool")
        dp = popat!(pls, dp_idx)
        load!(co, dp)  # have to load this first
    end
    pls |> Map(pl -> load!(co, pl)) |> foldxt(right)
    co
end

function AbstractColumnLoader(c::Column)
    pt = parqtype(c)
    c.eager_page_scanning && pages!(c)
    #TODO: ColumnStringViewDictLoader
    if c.eager_page_scanning && c.lazy_dictionary && isdictencoded(c)
        ColumnDictLoader(c)
    elseif pt isa ParqString && !hasdictencoding(c)
        if c.allow_string_copying
            ColumnStringLoader(c)
        else
            ColumnStringViewLoader(c)
        end
        #ColumnStringLoader(c)
    else
        ColumnAllocLoader(c)
    end
end

"""
    columnload(c::Column)

Deserialize the parquet column returning an `AbstractColumnLoader` object.  The column values can
be returned from this by calling `values(columnload(c))`.

See [`load`](@ref) which loads values from the column directly.
"""
function columnload(c::Column)
    # ignore unsupported nested column types
    if c.type isa Union{ParqTree,ParqMap,ParqList}
        @warn("column \"$(name(c))\" is nested and not supported by Parquet2.jl")
        return Fill(juliatype(c)(), nvalues(c))
    end
    try
        (juliamissingtype(c) ≡ Missing) && return Fill(missing, nvalues(c))
        co = AbstractColumnLoader(c)
        load!(co)
        co
    catch e
        @error("column \"$(name(c))\" hit an error when loading", exception=e, column=c)
        rethrow(e)
    end
end

"""
    load(c::Column)
    load(rg::RowGroup, column_name)
    load(ds::Dataset, column_name)

Deserialize values from a parquet column as an `AbstractVector` object.  Options for this
are defined when the file containing the column is first initialized.

Column name can be either a string column name or an integer column number.
"""
function load(c::Column)
    co = columnload(c)
    o = values(co)
    c.use_statistics && has_any_statistics(c.statistics) && (o = VectorWithStatistics(c.statistics, o))
    o
end
load(rg::RowGroup, n::Union{Integer,AbstractString}) = load(rg[n])

# this is makes columns that are just vectors compatible with the interface
load(v::AbstractVector) = v

