
BitIntegers.@define_integers 96


"""
    decompose(x::UInt96)

Decompose the `UInt96` into a `UInt64` (the first 8 bytes) and a
`UInt32` (the last 4 bytes).  This is needed because of the way
the legacy 96-bit timestamps are stored.
"""
function decompose(x::UInt96)
    r = Ref(x)
    GC.@preserve x begin
        ϖ = pointer_from_objref(r)
        a = unsafe_load(convert(Ptr{UInt64}, ϖ))
        b = unsafe_load(convert(Ptr{UInt32}, ϖ)+8)
    end
    a, b
end


"""
    ParquetType

Describes a type specified by the parquet standard metadata.
"""
abstract type ParquetType end

# for non-leaf nodes
struct ParqTree <: ParquetType end
juliatype(::ParqTree) = NamedTuple

abstract type ParquetBitsType <: ParquetType end

struct ParqBool <: ParquetBitsType end
juliatype(::ParqBool)::Type{Bool} = Bool

struct ParqUInt8 <: ParquetBitsType end
juliatype(::ParqUInt8)::Type{UInt8} = UInt8

struct ParqInt8 <: ParquetBitsType end
juliatype(::ParqInt8)::Type{Int8} = Int8

struct ParqUInt16 <: ParquetBitsType end
juliatype(::ParqUInt16)::Type{UInt16} = UInt16

struct ParqInt16 <: ParquetBitsType end
juliatype(::ParqInt16)::Type{Int16} = Int16

struct ParqUInt32 <: ParquetBitsType end
juliatype(::ParqUInt32)::Type{UInt32} = UInt32

struct ParqInt32 <: ParquetBitsType end
juliatype(::ParqInt32)::Type{Int32} = Int32

struct ParqUInt64 <: ParquetBitsType end
juliatype(::ParqUInt64)::Type{UInt64} = UInt64

struct ParqInt64 <: ParquetBitsType end
juliatype(::ParqInt64)::Type{Int64} = Int64

struct ParqInt96 <: ParquetBitsType end
juliatype(::ParqInt96) = UInt96

# for inferring type from Meta.LogicalType
function ParqInt(t::Meta.IntType)
    if t.isSigned
        if t.bitWidth == 8
            ParqInt8()
        elseif t.bitWidth == 16
            ParqInt16()
        elseif t.bitWidth == 32
            ParqInt32()
        elseif t.bitWidth == 64
            ParqInt64()
        elseif t.bitWidth == 96
            ParqInt96()
        else
            throw(ArgumentError("got metadata describing integers with invalid bit width: $(t.bitWidth)"))
        end
    else
        if t.bitWidth == 8
            ParqUInt8()
        elseif t.bitWidth == 16
            ParqUInt16()
        elseif t.bitWidth == 32
            ParqUInt32()
        elseif t.bitWidth == 64
            ParqUInt64()
        elseif t.bitWidth == 96
            ParqUInt96()
        else
            throw(ArgumentError("got metadata describing integers with invalid bit width: $(t.bitWidth)"))
        end
    end
end

struct ParqFloat32 <: ParquetBitsType end
juliatype(::ParqFloat32)::Type{Float32} = Float32

struct ParqFloat64 <: ParquetBitsType end
juliatype(::ParqFloat64)::Type{Float64} = Float64

struct ParqByteArray <: ParquetBitsType end
juliatype(::ParqByteArray)::Type{Vector{UInt8}} = Vector{UInt8}

struct ParqFixedByteArray{N} <: ParquetBitsType end
juliatype(::ParqFixedByteArray{N}) where {N} = SVector{N,UInt8}

valuesize(::ParqFixedByteArray{N}) where {N} = N

abstract type ParquetLogicalType <: ParquetType end

struct ParqDecimal <: ParquetLogicalType
    scale::Int  # this is negative from theirs because their convention is dumb
    precision::Int
end
juliatype(::ParqDecimal)::Type{Dec64} = Dec64

ParqDecimal(t::Meta.DecimalType) = ParqDecimal(-t.scale, t.precision)
ParqDecimal(s::Meta.SchemaElement) = ParqDecimal(-s.scale, s.precision)

# we don't yet support arbitrary precision decimals
DecFP.Dec64(pd::ParqDecimal, x::Real) = Dec64(sign(x), x, pd.scale)
DecFP.Dec64(pd::ParqDecimal, x::SVector) = Dec64(pd, concat_integer(x))

struct ParqString <: ParquetLogicalType end
juliatype(::ParqString)::Type{String} = String

struct ParqEnum{ℐ} <: ParquetLogicalType end
juliatype(::ParqEnum{ℐ}) where {ℐ} = ℐ

struct ParqDate <: ParquetLogicalType end
juliatype(::ParqDate)::Type{Date} = Date

struct ParqJSON <: ParquetLogicalType end
juliatype(::ParqJSON) = Union{AbstractDict{String,Any},Vector{Any}}

struct ParqBSON <: ParquetLogicalType end
juliatype(::ParqBSON) = Union{AbstractDict{String,Any},Vector{Any}}

Dates.Date(pd::ParqDate, x) = Date(1970,1,1) + Day(x)

function _parq_timetype_exponent(t)
    u = t.unit
    u′ = if !isnothing(thriftget(u, :MILLIS, nothing))
        -3
    elseif !isnothing(thriftget(u, :MICROS, nothing))
        -6
    elseif !isnothing(thriftget(u, :NANOS, nothing))
        -9
    else
        nothing
    end
end

struct ParqTime <: ParquetLogicalType
    exponent::Union{Int,Nothing}  # cannot error in cases where this is unknown
end
juliatype(::ParqTime)::Type{Time} = Time

ParqTime(t::Meta.TimeType) = ParqTime(_parq_timetype_exponent(t))

function Dates.Time(pt::ParqTime, x)
    𝒯 = if pt.exponent == -3
        Millisecond
    elseif pt.exponent == -6
        Microsecond
    elseif pt.exponent == -9
        Nanosecond
    else
        throw(ArgumentError("unsupported Time type with exponent $(pt.exponent)"))
    end
    Time(0) + 𝒯(x)
end

struct ParqDateTime <: ParquetLogicalType
    exponent::Union{Int,Nothing}  # cannot error in cases where this is unknown
end
juliatype(::ParqDateTime)::Type{DateTime} = DateTime

ParqDateTime(t::Meta.TimestampType) = ParqDateTime(_parq_timetype_exponent(t))

Dates.DateTime(pdt::ParqDateTime, x) = unix2datetime(x*10.0^pdt.exponent)

function Dates.DateTime(pdt::ParqDateTime, x::UInt96)
    a, b = decompose(x)
    d = Date(1970,1,1) - Day(2440588) + Day(b)  # who the fuck knows
    t = Time(0) + Millisecond(round(Int, a*10.0^(-6)))
    DateTime(d, t)
end

# note that these have a normal base type but it doesn't matter which
struct ParqMissing <: ParquetLogicalType end
juliatype(::ParqMissing)::Type{Missing} = Missing

struct ParqUUID <: ParquetLogicalType end
juliatype(::ParqUUID)::Type{UUID} = UUID

"""
    ParqUnknown{𝒯}

Represents a parquet type that could not be identified.  This stores information obtained from the metadata
so that objects of the type can be handled elsewhere.  The type parameter is the parquet type of the base type.
"""
struct ParqUnknown{𝒯<:ParquetBitsType} <: ParquetLogicalType
    basetype::𝒯
    legacy_type_code::Union{Int,Nothing}
end
juliatype(u::ParqUnknown) = juliatype(u.basetype)

ParqUnknown(t::ParquetType, c::Union{Integer,Nothing}=nothing) = ParqUnknown{typeof(t)}(t, c)

struct ParqList <: ParquetLogicalType end
juliatype(::ParqList) = Vector

struct ParqMap <: ParquetLogicalType end
juliatype(::ParqMap) = Dict

"""
    parqtype(t::Type; kw...)

Return the parquet type object corresponding to the provided Julia type.

The following keyword arguments should be provided for context only where appropriate
- `decimal_scale=0`: base 10 scale of a decimal number
- `decimal_precision=3`: precision of a decimal number.
- `bson=false`: whether serialization of dictionaries should prefer BSON to JSON.

Only one method with the signature `::Type` is defined so to avoid excessive run-time dispatch.
"""
function parqtype(t::Type;
                  decimal_scale::Integer=0, decimal_precision::Integer=3,
                  bson::Bool=false,
                 )
    # without this, if somehow a Union{} gets through we wind up with a Bool
    t ≡ Union{} && throw(ArgumentError("provided type is Union{}, cannot determine parquet type"))
    t ≡ Missing && return ParqMissing()
    t = nonmissingtype(t)
    if t <: Bool
        ParqBool()
    elseif t <: Unsigned
        if t <: UInt8
            ParqUInt8()
        elseif t <: UInt16
            ParqUInt16()
        elseif t <: UInt32
            ParqUInt32()
        elseif t <: UInt64
            ParqUInt64()
        end
    elseif t <: Signed
        if t <: Int8
            ParqInt8()
        elseif t <: Int16
            ParqInt16()
        elseif t <: Int32
            ParqInt32()
        elseif t <: Int64
            ParqInt64()
        elseif t <: Int96
            ParqInt96()
        end
    elseif t <: DecFP.DecimalFloatingPoint
        ParqDecimal(decimal_scale, decimal_precision)
    elseif t <: Real
        if t <: Float32
            ParqFloat32()
        elseif t <: Float64
            ParqFloat64()
        end
    elseif t <: StaticVector{N,UInt8} where {N}
        ParqFixedByteArray{length(t)}()
    elseif t <: AbstractVector{UInt8}
        ParqByteArray()
    elseif t <: AbstractString
        ParqString()
    elseif t <: Time
        ParqTime(-9)
    elseif t <: Date
        ParqDate()
    elseif t <: Dates.AbstractDateTime
        ParqDateTime(-3)
    elseif t <: UUID
        ParqUUID()
    elseif t <: Union{AbstractVector,AbstractDict} && bson  # start falling back to JSON/BSON vectors only at end
        ParqBSON()
    elseif t <: Union{AbstractVector,AbstractDict}
        ParqJSON()
    else
        throw(ArgumentError("type $t does not have a corresponding parquet type"))
    end
end

function _thrift_extract_from_union(u)
    for j ∈ 1:nfields(u)
        ϕ = getfield(u, j)
        isnothing(ϕ) || return ϕ
    end
end

"""
    parqbasetype(s)

Gets the parquet type of the underlying bit representation of an object when it is stored in a parquet file.
The possible types are described in the parquet specification
[here](https://github.com/apache/parquet-format/blob/master/Encodings.md#plain-plain--0).
"""
function parqbasetype(s::Meta.SchemaElement)
    isnothing(s.type) && return ParqTree()
    parqbasetype(s.type, thriftget(s, :type_length, 0))
end
parqbasetype(t::Meta.BitsType, pt::ParquetType) = parqbasetype(t, valuesize(pt))
function parqbasetype(t::Meta.BitsType, ℓ::Integer=0)
    if t == Meta.BOOLEAN
        ParqBool()
    elseif t == Meta.INT32
        ParqInt32()
    elseif t == Meta.INT64
        ParqInt64()
    elseif t == Meta.INT96
        ParqInt96()
    elseif t == Meta.FLOAT
        ParqFloat32()
    elseif t == Meta.DOUBLE
        ParqFloat64()
    elseif t == Meta.BYTE_ARRAY
        ParqByteArray()
    elseif t == Meta.FIXED_LEN_BYTE_ARRAY
        ParqFixedByteArray{ℓ}()
    else
        error("schema has invalid bits type $t, this may indicate a corrupt schema")
    end
end

function _legacy_parqtype(s::Meta.SchemaElement)
    # if it doesn't have the field, the type is considered known but we default to the base type
    isnothing(s.converted_type) && return parqbasetype(s)
    t = s.converted_type
    if t == Meta.UTF8
        ParqString()
    elseif t == Meta.MAP
        ParqMap()  # not implemented
    elseif t == Meta.MAP_KEY_VALUE
        ParqMap()  # not implemented
    elseif t == Meta.LIST
        ParqList()  # not implemented
    elseif t == Meta.ENUM
        # enum type is read as a string
        ParqString()
    elseif t == Meta.DECIMAL
        ParqDecimal(s)
    elseif t == Meta.DATE
        ParqDate()
    elseif t == Meta.TIME_MILLIS
        ParqTime(-3)
    elseif t == Meta.TIME_MICROS
        ParqTime(-6)
    elseif t == Meta.TIMESTAMP_MILLIS
        ParqDateTime(-3)
    elseif t == Meta.TIMESTAMP_MICROS
        ParqDateTime(-6)
    elseif t == Meta.UINT_8
        ParqUInt8()
    elseif t == Meta.UINT_16
        ParqUInt16()
    elseif t == Meta.UINT_32
        ParqUInt32()
    elseif t == Meta.UINT_64
        ParqUInt64()
    elseif t == Meta.INT_8
        ParqInt8()
    elseif t == Meta.INT_16
        ParqInt16()
    elseif t == Meta.INT_32
        ParqInt32()
    elseif t == Meta.INT_64
        ParqInt64()
    elseif t == Meta.JSON
        ParqJSON()
    elseif t == Meta.BSON
        ParqBSON()
    else
        # some types such as float don't have a logical or converted type (can be nothing)
        parqbasetype(s)
    end
end

"""
    parqtype(s)

Gets the [`ParquetType`](@ref) for elements of the object `s`, e.g. a [`Column`](@ref) or [`SchemaNode`](@ref).
See
[this section](https://github.com/apache/parquet-format/blob/master/Encodings.md)
of the parquet specification.
"""
function parqtype(s::Meta.SchemaElement;
                  support_legacy::Bool=true)
    if support_legacy && thriftget(s, :type, nothing) == Meta.INT96
        return ParqDateTime(nothing)
    end
    isnothing(s.logicalType) && return _legacy_parqtype(s)
    t = _thrift_extract_from_union(s.logicalType)
    if t isa Meta.IntType
        ParqInt(t)
    elseif t isa Meta.DecimalType
        ParqDecimal(t)
    elseif t isa Meta.StringType
        ParqString()
    elseif t isa Meta.DateType
        ParqDate()
    elseif t isa Meta.TimeType
        ParqTime(t)
    elseif t isa Meta.TimestampType
        ParqDateTime(t)
    elseif t isa Meta.NullType
        ParqMissing()
    elseif t isa Meta.UUIDType
        ParqUUID()
    elseif t isa Meta.ListType
        ParqList()  # not implemented
    elseif t isa Meta.MapType
        ParqMap()
    elseif t isa Meta.JsonType
        ParqJSON()
    elseif t isa Meta.BsonType
        ParqBSON()
    else
        # some types such as floats don't have a logicalType
        parqbasetype(s)
    end
end

"""
    SchemaNode

Represents a single node in a parquet schema tree.  Statisfies the
[`AbstractTrees`](https://github.com/JuliaCollections/AbstractTrees.jl) interface.
"""
struct SchemaNode{𝒯<:ParquetType}
    name::String
    type::𝒯
    children::OrderedDict{String,SchemaNode}
    name_lookup::Dict{String,Int}  # for child names
    field_id::Union{Nothing,Int}
    elsize::Int  # really shouldn't be here, but the format absolutely *insists*.  dumb.
    hasnulls::Bool
    isrepeated::Bool
end

AbstractTrees.children(s::SchemaNode) = values(s.children)

getchild(s::SchemaNode, name::AbstractString, default) = get(s.children, name, default)
getchild(s::SchemaNode, name::AbstractString) = s.children[name]

name(s::SchemaNode) = s.name

function Base.getindex(s::SchemaNode, p::AbstractVector{<:AbstractString})
    n = s
    for ϖ ∈ p
        n = getchild(n, ϖ)
    end
    n
end

SchemaNode(t::ParquetTable, n::Integer) = column_schema_nodes(t)[n]
SchemaNode(t::ParquetTable, name::AbstractString) = root_schema_node(t)[[name]]

function SchemaNode(s::Meta.SchemaElement, children::OrderedDict=OrderedDict{<:AbstractString,<:SchemaNode}();
                    support_legacy::Bool=true)
    fid = thriftget(s, :field_id, nothing)
    rtype = s.repetition_type
    isnothing(rtype) && (rtype = Meta.REQUIRED)
    elsize = thriftget(s, :type_length, 0)
    hasnulls = rtype ≠ Meta.REQUIRED
    isrepeated = rtype == Meta.REPEATED
    t = parqtype(s; support_legacy)
    lkp = Dict{String,Int}(n=>i for (i, n) ∈ enumerate(keys(children)))
    SchemaNode{typeof(t)}(s.name, t, children, lkp, fid, elsize, hasnulls, isrepeated)
end

parqtype(s::SchemaNode) = s.type

juliatype(s::SchemaNode) = juliatype(parqtype(s))

juliamissingtype(s::SchemaNode) = s.hasnulls ? Union{Missing,juliatype(s)} : juliatype(s)

function SchemaNode(ss::AbstractVector{<:Meta.SchemaElement}, i::Integer=1;
                    support_legacy::Bool=true)
    s = ss[i]
    cidx = isnothing(s.num_children) ? Int[] : Int[i+j for j ∈ 1:s.num_children]
    SchemaNode(s, OrderedDict(ss[j].name=>SchemaNode(ss, j; support_legacy) for j ∈ cidx);
               support_legacy)
end

namelookup(s::SchemaNode, n::AbstractString) = s.name_lookup[n]
namelookup(s::SchemaNode, n::Integer) = n  # easier to write generic functions

"""
    maxreplevel(r::SchemaNode, p)

Compute the maximum repetition level for the node at path `p` from the root node `r`.
"""
function maxreplevel(r::SchemaNode, p::AbstractVector{<:AbstractString})
    n = r[p]
    l = n.isrepeated ? 1 : 0
    length(p) ≤ 1 ? l : (l + maxreplevel(r, p[1:(end-1)]))
end

"""
    maxdeflevel(r::SchemaNode, p)

Compute the maximum definition level for the node at path `p` from the root node `r`.
"""
function maxdeflevel(r::SchemaNode, p::AbstractVector{<:AbstractString})
    n = r[p]
    l = n.hasnulls ? 1 : 0
    length(p) ≤ 1 ? l : (l + maxdeflevel(r, p[1:(end-1)]))
end

maxdeflevel(v::AbstractVector{Union{𝒯,Missing}}) where {𝒯} = 1
maxdeflevel(v::AbstractVector) = 0


"""
    ColumnStatistics

A data structure for storing the statistics for a parquet column.  The following functions are available
for accessing statistics.  In all cases, will return `nothing` if the statistic was not included in the
parquet metadata.
- `minimum(stats)`: The minimum value.
- `maximum(stats)`: The maximum value.
- `count(ismissing, stats)`: The number of missing values.
- `ndistinct(stats)`: The number of distinct values.

Can be obtained from a `Column` object with `ColumnStatistics(col)`.
"""
struct ColumnStatistics{𝒯}
    min::Union{𝒯,Nothing}
    max::Union{𝒯,Nothing}
    n_null::Union{Int,Nothing}
    n_distinct::Union{Int,Nothing}
end

Base.minimum(s::ColumnStatistics) = s.min
Base.maximum(s::ColumnStatistics) = s.max

Base.count(::typeof(ismissing), s::ColumnStatistics) = s.n_null

"""
    ndistinct(s::ColumnStatistics)

Returns the number of distinct elements in the column.  `nothing` if not available.
"""
ndistinct(s::ColumnStatistics) = s.n_distinct

has_any_statistics(cs::ColumnStatistics) = !all(isnothing, (cs.min, cs.max, cs.n_null, cs.n_distinct))

function _thrift_unpack_value(t::ParquetType, ::Type{𝒯}, v::AbstractVector{UInt8}) where {𝒯}
    convertvalue(t, reinterpret(𝒯, v)[1])
end
_thrift_unpack_value(t::ParqByteArray, ::Type{<:AbstractVector{UInt8}}, v::AbstractVector{UInt8}) = convertvalue(t, v)
_thrift_unpack_value(t::ParqString, ::Type, s::AbstractVector{UInt8}) = convertvalue(t, s)

function ColumnStatistics(t::ParquetType, ::Type{𝒯}, c::Meta.Column) where {𝒯}
    st = thriftget(c.meta_data, :statistics, nothing)
    if isnothing(st) || 𝒯 <: StaticArray  # static arrays are too rare and annoying an edge case
        return ColumnStatistics{juliatype(t)}(nothing, nothing, nothing, nothing)
    end
    mn = thriftget(st, :min_value, nothing)
    isnothing(mn) && (mn = thriftget(st, :min, nothing))
    isnothing(mn) || (mn = _thrift_unpack_value(t, 𝒯, mn))
    mx = thriftget(st, :max_value, nothing)
    isnothing(mx) && (mx = thriftget(st, :max, nothing))
    isnothing(mx) || (mx = _thrift_unpack_value(t, 𝒯, mx))
    ColumnStatistics{juliatype(t)}(mn, mx, thriftget(st, :null_count, nothing), thriftget(st, :distinct_count, nothing))
end
ColumnStatistics(t::ParquetType, ::Nothing) = ColumnStatistics{juliatype(t)}(nothing, nothing, nothing, nothing)
ColumnStatistics(t::ParquetType, ::Type, ::Nothing) = ColumnStatistics(t, nothing)


"""
    PageHeader

Abstract type for parquet format page headers.

See the description of pages in the specification
[`here`](https://github.com/apache/parquet-format#data-pages).
"""
abstract type PageHeader end

"""
    DataPageHeader <: PageHeader

Header for a page of data.  This type stores metadata for either the newer `DataHeaderV2` or
legacy `DataHeader`.
"""
struct DataPageHeader <: PageHeader
    n::Int  # number of values
    nmissing::Union{Nothing,Int}
    startidx::Int  # index of first value in this page in the column
    nrows::Int
    encoding::Meta.Encoding
    iscompressed::Bool
    nbytesdef::Int  # < 0 if not provided
    nbytesrep::Int  # < 0 if not provided
end

function DataPageHeader(h::Meta.DataPageHeader, k::Integer=1)
    DataPageHeader(h.num_values, nothing, k, h.num_values, h.encoding, false, -1, -1)
end

function DataPageHeader(h::Meta.DataPageHeaderV2, k::Integer=1)
    DataPageHeader(h.num_values, h.num_nulls, k, h.num_rows, h.encoding,
                   thriftget(h, :is_compressed, true), h.definition_levels_byte_length,
                   h.repetition_levels_byte_length,
                  )
end

"""
    DictionaryPageHeader <: PageHeader

Header for pages storing dictionary reference values.
"""
struct DictionaryPageHeader <: PageHeader
    n::Int
    encoding::Meta.Encoding
    issorted::Bool
end

function DictionaryPageHeader(h::Meta.DictionaryPageHeader)
    DictionaryPageHeader(h.num_values, h.encoding, thriftget(h, :is_sorted, false))
end

function pageheader(h::Meta.PageHeader, k::Integer=1)
    t = h.type
    if t == Meta.DATA_PAGE
        DataPageHeader(h.data_page_header, k)
    elseif t == Meta.INDEX_PAGE
        IndexPageHeader(h.index_page_header)
    elseif t == Meta.DICTIONARY_PAGE
        DictionaryPageHeader(h.dictionary_page_header)
    elseif t == Meta.DATA_PAGE_V2
        DataPageHeader(h.data_page_header_v2, k)
    else
        error("unknown page type $t")
    end
end

encoding(h::PageHeader) = h.encoding


"""
    Page

Object containing metadata for parquet pages.  These are esesentially subsets of the data of a column.
The raw data contained in the page can be accessed with `view(page)`.
"""
struct Page{ℰ,ℋ<:PageHeader}
    header::ℋ
    ℓ::Int
    compressed_ℓ::Int
    crc::Union{Nothing,Int}
    buffer::PageBuffer
end

iscompressed(p::Page) = p.ℓ ≠ p.compressed_ℓ

pagelength(ph::Meta.PageHeader) = ph.compressed_page_size

# this always gives the length of the (decompressed) page view
nbytes(p::Page) = p.ℓ

nvalues(p::Page)::Int = Int(p.header.n)

encoding(p::Page) = encoding(p.header)

isdictpool(p::Page) = p.header isa DictionaryPageHeader

isdictencoded(p::Page) = encoding(p) ∈ (Meta.PLAIN_DICTIONARY, Meta.RLE_DICTIONARY)

isdictrefs(p::Page) = !isdictpool(p) && isdictencoded(p)

colstartindex(p::Page{ℰ,<:DataPageHeader}) where {ℰ} = p.header.startidx

function Page(h::Meta.PageHeader, buf::PageBuffer, k::Integer=1)
    η = pageheader(h, k)
    Page{η.encoding,typeof(η)}(η, h.uncompressed_page_size, h.compressed_page_size,
                               thriftget(h, :crc, nothing), buf)
end

Base.view(p::Page, δ::Integer=0) = view(p.buffer, δ)

"""
    unsupported_encodings()

A list of binary encodings according to their names in the thrift schema that Parquet2.jl does not yet support.
"""
unsupported_encodings() = (Meta.DELTA_BINARY_PACKED, Meta.DELTA_LENGTH_BYTE_ARRAY, Meta.DELTA_BYTE_ARRAY,
                           Meta.BYTE_STREAM_SPLIT
                          )

"""
    decompressedpageview

Creates the view of page data handling decompression appropriately.  If
`DataPageHeaderV2` this must be handled carefully since the levels bytes
are not compressed.  For the old data page format, this simply decompresses
the entire buffer.
"""
function decompressedpageview(𝒻, p::Page, v::AbstractVector=view(p))
    dst = Vector{UInt8}(undef, nbytes(p))
    if p.header isa DataPageHeader && p.header.nbytesdef ≥ 0
        # This is a `DataPageHeaderV2`
        # WARN: apparently at some point I thought this block was needed,
        # but it was causing problems and removing it seems to work...
        # this would imply that these pages just don't get compressed which also makes no sense
        # am going to try removing it but will restore if it breaks everything
        #if encoding(p) == Meta.RLE_DICTIONARY
        #    return p.header.iscompressed ? 𝒻(v) : v
        #end
        # This check is required to be compatible with pyarrow v20
        # Ref: https://github.com/apache/arrow/pull/45367
        if !p.header.iscompressed
            𝒻 = NoopCodec()
        end
        p.header.nbytesrep ≥ 0 || throw(ArgumentError("unexpected negative repetition_levels_byte_length"))
        k = p.header.nbytesrep + p.header.nbytesdef
        # copyto! will safely error if the previous addition overflows
        # or is out of bounds.
        if !iszero(k)
            copyto!(dst, 1, v, 1, k)
        end
        v = view(v, (k+1):lastindex(v))
        decode!(𝒻, view(dst, (k+1):lastindex(dst)), v)
    else
        decode!(𝒻, dst, v)
    end
    dst
end


struct ColumnData{𝒮<:ParquetBitsType}
    basetype::𝒮
    data::Buffer
    startindex::Int
    ℓ::Int  # size in bytes
    compressed_ℓ::Int
    data_page_offset::Int
    index_page_offset::Union{Int,Nothing}
    dict_page_offset::Union{Int,Nothing}
    encodings::Vector{Meta.Encoding}
    pages::Vector{Page}
    compression_codec::Meta.CompressionCodec
    decompressor::Any # implements `ChunkCodecCore.try_decode!`
    compressor::Function
end

parqbasetype(cdat::ColumnData) = cdat.basetype

iscompressed(cdat::ColumnData) = cdat.compression_codec ≠ Meta.UNCOMPRESSED

"""
    Column

Data structure for organizing metadata and loading data of a parquet column object.  These columns are the segments
of columns referred to by individual row groups, not necessarily the entire columns of the master table schema.
As such, these will have the same type of the columns in the full table but not necessarily the same number of
values.

## Usage
```julia
c = rg[n]  # returns nth `Column` from row group
c = rg["column_name"]  # retrieve by name

Parquet2.pages!(c)  # infer page schema of columns

Parquet2.name(c)  # get the name of c

Parquet2.filepath(c)  # get the path of the file containing c

v = Parquet2.load(c)  # load column values as a lazy AbstractVector

v[:]  # fully load values into memory
```
"""
struct Column{𝒯<:ParquetType,𝒮<:Union{ParquetBitsType,ParqTree}}
    type::𝒯
    file_path::AbstractPath
    schema_path::Vector{String}
    schema::SchemaNode  # *must* be able to infer level in tree
    node::SchemaNode{𝒯}
    n::Int  # number of values
    data::Union{Nothing,ColumnData}
    children::OrderedDict{String,Column}
    metadata::Dict{String,Any}
    statistics::ColumnStatistics

    #options
    allow_string_copying::Bool
    lazy_dictionary::Bool
    parallel_page_loading::Bool
    use_statistics::Bool
    eager_page_scanning::Bool
end

AbstractTrees.children(col::Column) = values(col.children)

Base.Pair(kv::Meta.KeyValue) = kv.key=>thriftget(kv, :value, "")
Base.Dict(kv::AbstractVector{<:Meta.KeyValue}) = Dict{String,String}(Pair.(kv))

name(col::Column) = col.node.name

"""
    filepath(col::Column)

Returns the (relative) path of the file in which the column resides.  Typically this file contains the entire
`RowGroup` but this is not required by the specification.
"""
filepath(col::Column) = col.file_path

# pretty sure this is always true, but it makes me a bit nervous
nbytes(col::Column) = isnothing(col.data) ? nothing : col.data.compressed_ℓ

nbytesuncompressed(col::Column) = isnothing(col.data) ? nothing : col.data.ℓ

startindex(col::Column) = col.data.startindex
endindex(col::Column) = startindex(col) + nbytes(col) - 1

parqtype(col::Column) = col.type
parqbasetype(col::Column) = col.data.basetype

evaloption(opt::ColumnOption, col::Column) = evaloption(opt, name(col), juliamissingtype(col))

"""
    juliatype(col::Column)

Get the element type of the `AbstractVector` the column is loaded into *ignoring missings*.
For example, if the eltype is `Union{Int,Missing}` this will return `Int`.

See [`juliamissingtype`](@ref) for the exact type.
"""
juliatype(col::Column) = juliatype(parqtype(col))

"""
    juliabasetype(col::Column)

Get the Julia type of the underlying binary representation of the elements of the `Column`.  For example, this
is `Vector{UInt8}` for strings.
"""
juliabasetype(col::Column) = juliatype(parqbasetype(col))

_juliamissingtype(::Type{𝒯}, col::Column) where {𝒯} = col.node.hasnulls ? Union{Missing,𝒯} : 𝒯

"""
    juliamissingtype(col::Column)

Returns the element type of the `AbstractVector` that is returned on `load(col)`.
"""
juliamissingtype(col::Column) = _juliamissingtype(juliatype(col), col)

"""
    juliamissingbasetype(col::Column)

Returns the encoded element type of the `AbstractVector` that is returned by calling `loadbits` on pages from
the column, with missings where appropriate.
"""
juliamissingbasetype(col::Column) = _juliamissingtype(juliabasetype(col), col)

"""
    nvalues(col::Column)

Returns the number of values in the column (i.e. number of rows).
"""
nvalues(col::Column)::Int = col.n

"""
    iscompressed(col::Column)

Whether the column is compressed.
"""
iscompressed(col::Column) = iscompressed(col.data)

"""
    encodings(col::Column)

Get a list of all encodings used in the column.
"""
encodings(col::Column) = isnothing(col.data) ? Meta.Encoding[] : col.data.encodings

"""
    hasdictencoding(col::Column)

Returns `true` if *any* of the pages in the column use dictionary encoding, else false.  This is used
to determine whether the column needs to allocate the dictionary pool.
"""
hasdictencoding(col::Column) = any(enc -> enc ∈ (Meta.RLE_DICTIONARY, Meta.PLAIN_DICTIONARY), encodings(col))

"""
    isdictencoded(col::Column)

Returns `true` if *all* data in the column is dictionary encoded.

This will force the scanning of pages.
"""
isdictencoded(col::Column) = all(p -> isdictpool(p) || isdictencoded(p), pages(col))

# this only works from the root node for now
SchemaNode(r::SchemaNode, col::Column) = r[col.schema_path]

maxreplevel(col::Column) = maxreplevel(col.schema, col.schema_path)
maxdeflevel(col::Column) = maxdeflevel(col.schema, col.schema_path)

function initial_page_offset(c::Meta.Column)
    m = c.meta_data
    o = m.data_page_offset
    isnothing(m.index_page_offset) || (o = min(o, m.index_page_offset))
    isnothing(m.dictionary_page_offset) || (o = min(o, m.dictionary_page_offset))
    o
end

DataAPI.metadatasupport(::Type{<:Column}) = (read=true, write=false)

"""
    metadata(col::Column; style=false)

Get the key-value metadata for the column.
"""
function DataAPI.metadata(col::Column; style::Bool=false)
    style ? Dict(k => (v, :default) for (k, v) in col.metadata) : col.metadata
end

"""
    metadata(col::Column, k::AbstractString[, default]; style=false)

Get the key `k` from the key-value metadata for column `col`.  If `default` is provided it will
be returned if `k` is not present.
"""
function DataAPI.metadata(col::Column, k::AbstractString; style::Bool=false)
    o = metadata(col)[k]
    style ? (o, :default) : o
end
function DataAPI.metadata(col::Column, k::AbstractString, default; style::Bool=false)
    o = get(metadata(col), k, default)
    style ? (o, :default) : o
end

DataAPI.metadatakeys(col::Column) = keys(metadata(col))

function columndata(v::Buffer, mc::Meta.Column, elsize::Integer; read_opts::ReadOptions=ReadOptions())
    m = mc.meta_data
    s = parqbasetype(m.type, elsize)
    cmp = getcompressor(m.codec)
    dcmp = getdecompressor(m.codec)
    ColumnData{typeof(s)}(s, v, initial_page_offset(mc)+1,
                          m.total_uncompressed_size,
                          m.total_compressed_size,
                          m.data_page_offset,
                          thriftget(m, :index_page_offset, nothing),
                          thriftget(m, :dictionary_page_offset, nothing),
                          m.encodings,
                          Page[],
                          m.codec, dcmp, cmp
                         )
end
columndata(::Buffer, ::Nothing, ::Integer; kw...) = nothing

function columnchildren(v::Buffer, r::SchemaNode, n::SchemaNode,
                        coldict::AbstractDict, p::AbstractPath,
                        schp::AbstractVector{<:AbstractString},
                        nvals::Integer
                       )
    o = OrderedDict{String,Column}()
    for n′ ∈ children(n)
        nm = n′.name
        schq = copy(schp)
        push!(schq, nm)
        o[nm] = Column(v, r, coldict, p, schq, nvals)
    end
    o
end

function Column(v::Buffer, r::SchemaNode, coldict::AbstractDict, p::AbstractPath,
                schp::AbstractVector{<:AbstractString}, nvals::Integer;
                read_opts::ReadOptions=ReadOptions(),
               )
    n = r[schp]
    mc = get(coldict, schp, nothing)
    mdat = columndata(v, mc, n.elsize; read_opts)  # constructor, but may return nothing
    meta = unpack_thrift_metadata(thriftget(mc, :meta_data, nothing))
    t = n.type
    s = isnothing(mdat) ? ParqTree() : parqbasetype(mdat)
    chldrn = columnchildren(v, r, n, coldict, p, schp, nvals)
    stats = ColumnStatistics(t, juliatype(s), mc)
    nvals = isnothing(mc) ? nvals : mc.meta_data.num_values
    Column{typeof(t),typeof(s)}(t, p, schp,
                                r, n, nvals, mdat,
                                chldrn, meta, stats,
                                evaloption(read_opts.allow_string_copying, name(n), juliamissingtype(n)),
                                evaloption(read_opts.lazy_dictionary, name(n), juliamissingtype(n)),
                                evaloption(read_opts.parallel_page_loading, name(n), juliamissingtype(n)),
                                evaloption(read_opts.use_statistics, name(n), juliamissingtype(n)),
                                evaloption(read_opts.eager_page_scanning, name(n), juliamissingtype(n)),
                               )
end

ColumnStatistics(c::Column) = c.statistics

Base.get!(col::Column) = get!(col.data.data, startindex(col):endindex(col))

PageBuffer(col::Column, a::Integer, b::Integer) = PageBuffer(col.data.data, a, b)


"""
    PageIterator

Object for iterating through pages of a column.  Executing the iteration is essentially binary schema discovery
and may invoke reading from the data source.  Normally once a full iteration has been performed `Page` objects
are stored by the `Column` making future access cheaper and this object can be discarded.
"""
struct PageIterator{𝒞<:Column}
    col::𝒞
end

filepath(piter::PageIterator) = filepath(piter.col)

startindex(piter::PageIterator) = startindex(piter.col)
endindex(piter::PageIterator) = endindex(piter.col)

Base.IteratorSize(::PageIterator) = Base.SizeUnknown()

function Base.iterate(piter::PageIterator, (idx, k)=(startindex(piter), 1))
    idx ≥ endindex(piter) && return nothing
    fio = IOBuffer(piter.col.data.data)
    seek(fio, idx-1)
    (ph, δ) = readthriftδ(fio, Meta.PageHeader)
    a = idx + δ
    b = a + pagelength(ph) - 1
    p = Page(ph, PageBuffer(piter.col, a, b), k)
    (p.header isa DataPageHeader) && (k += nvalues(p))
    p, (b+1, k)
end

"""
    pages!(col::Column)

Infer the binary schema of the column pages and store `Page` objects that store references to data page locations.
This function should typically be called only once as the objects discovered by this store all needed metadata.
Calling this may invoke calls to retrieve data from the source.  After calling this all data for the column is
guaranteed to be stored in memory.
"""
function pages!(col::Column)
    isnothing(col.data) && return Page[]
    pgs = col.data.pages
    empty!(pgs)
    for p ∈ PageIterator(col)
        push!(pgs, p)
    end
    pgs
end

"""
    pages(col::Column)

Accesses the pages of the column, loading them if they are not already loaded.  See [`pages!`](@ref) which is
called by this in cases where pages are not already discovered.
"""
function pages(col::Column)
    if isnothing(col.data)
        Page[]
    elseif isempty(col.data.pages)
        pages!(col)
    else
        col.data.pages
    end
end

"""
    npages(col::Column)

Get the number of pages of the column.
"""
npages(col::Column) = length(pages(col))


"""
    PageLoader

Object which wraps a [`Column`](@ref) and [`Page`](@ref) for loading data.  This is the object from which
all parquet data beneath the metadata is ultimately loaded.

## Development Notes
We badly want to get rid of this.  The main reason this is not possible is that in the original
`DataPageHeader` the length of the repetition and definition levels is not knowable a priori.
This has the consequence that reading from the page is stateful, i.e. one needs to know where the
data starts and this is only possible after reading the levels in the legacy format.
Since it will presumably never be possible to drop support for `DataPageHeader`, it will presumably
never be possible to eliminate this frustration.
"""
struct PageLoader{𝒯<:ParquetType,𝒮<:ParquetBitsType,
                  ℰ,ℋ<:PageHeader,𝒱<:AbstractVector{UInt8}}
    column::Column{𝒯,𝒮}
    page::Page{ℰ,ℋ}
    view::𝒱
    δ::RefValue{Int}
    n_non_null::RefValue{Int}

    function PageLoader(col::Column{𝒯,𝒮}, p::Page{ℰ,ℋ}) where {𝒯,𝒮,ℰ,ℋ}
        v = decompressedpageview(col.data.decompressor, p)
        new{𝒯,𝒮,ℰ,ℋ,typeof(v)}(col, p, v, Ref(0), Ref(nvalues(p)))
    end
end

function reset!(pl::PageLoader)
    pl.δ[] = 0
    pl.n_non_null[] = nvalues(pl.page)
    pl
end

PageLoader(col::Column, i::Integer=1) = PageLoader(col, pages(col)[i])

Base.getindex(col::Column, i::Integer) = PageLoader(col, i)

startindex(pl::PageLoader) = startindex(pl.page)
endindex(pl::PageLoader) = endindex(pl.page)

nbytes(pl::PageLoader) = nbytes(pl.page)

Base.view(pl::PageLoader)::AbstractVector{UInt8} = view(pl.view, (1+pl.δ[]):length(pl.view))

maxreplevel(pl::PageLoader) = maxreplevel(pl.column)
maxdeflevel(pl::PageLoader) = maxdeflevel(pl.column)

parqtype(pl::PageLoader) = parqtype(pl.column)
parqbasetype(pl::PageLoader) = parqbasetype(pl.column)

juliabasetype(pl::PageLoader) = juliabasetype(pl.column)

juliatype(pl::PageLoader) = juliatype(pl.column)

juliamissingtype(pl::PageLoader) = juliamissingtype(pl.column)

juliamissingbasetype(pl::PageLoader) = juliamissingbasetype(pl.column)

nvalues(pl::PageLoader)::Int = nvalues(pl.page)

encoding(pl::PageLoader) = encoding(pl.page)

isdictencoded(pl::PageLoader) = isdictencoded(pl.page)

isdictpool(pl::PageLoader) = isdictpool(pl.page)

isdictrefs(pl::PageLoader) = isdictrefs(pl.page)

hasdeflevels(pl::PageLoader, md::Integer=maxdeflevel(pl)) = md ≥ 1 && !isdictpool(pl)

# this might seem pedantic but seeing "hasdeflevels" just confuses the piss out of me
hasmissings(pl::PageLoader) = hasdeflevels(pl)

hasreplevels(pl::PageLoader, mr::Integer=maxreplevel(pl)) = mr ≥ 1 && !isdictpool(pl)

colstartindex(pl::PageLoader) = colstartindex(pl.page)

"""
    pageloaders(col)

Return an iterator over `PageLoader` objects for each page in `col`.  Pages are constructed on iteration calls.
"""
function pageloaders(col::Column)
    isnothing(col.data) && return Page[]
    Iterators.map(p -> PageLoader(col, p), pages(col))
end


"""
    RowGroup <: ParquetTable

A piece of a parquet table.  All parquet files are organized into 1 or more `RowGroup`s each of which is a table
in and of itself.  `RowGroup` satisfies the [Tables.jl](https://tables.juliadata.org/dev/) columnar interface.
Therefore, all row groups can be used as tables just like full [`Dataset`](@ref)s.  Typically different `RowGroup`s
are stored in different files and each file constitutes and entire `RowGroup`, though this is not enforced
by the specification or Parquet2.jl.  It is not expected for users to construct tables as their schema is
constructed from parquet metadata.

[`Dataset`](@ref)s are indexable collections of `RowGroup`s.

## Usage
```julia
ds = Dataset("/path/to/parquet")

length(ds)  # gives the number of row groups

rg = ds[1]  # get first row group

c = rg[1]  # get first column
c = rg["column_name"]  # or by name

for c ∈ rg  # RowGroups are indexable collections of columns
    println(name(c))
end

df = DataFrame(rg)  # RowGroups are bonified columnar tables themselves

# use TableOperations.jl to load only selected columns
df1 = rg |> TableOperations.select(:col1, :col2) |> DataFrame
```
"""
struct RowGroup{ℱ<:FileManager} <: ParquetTable
    file_manager::ℱ
    schema::SchemaNode
    columns::Vector{Column}
    ℓ::Int  # size in bytes
    nrows::Int
    startindex::Union{Nothing,Int}
    compressed_ℓ::Union{Nothing,Int}
    ordinal::Union{Nothing,Int}
    name_index::NameIndex
    partition_tree::PartitionNode
    partition_columns::OrderedDict{String,Fill{String,1}}

    # options
    parallel_column_loading::Union{Nothing,Bool}
end

# this is only for columns in the first generation
function _construct_column(nm::AbstractString, r::SchemaNode, coldict::AbstractDict, fm::FileManager, nvals::Integer,
                           current_file::AbstractPath; read_opts::ReadOptions=ReadOptions())
    c = get(coldict, [nm], nothing)
    p = isnothing(c) ? "" : thriftget(c, :file_path, "")
    if isempty(p)  # no path specified, must be in main
        if isempty(current_file)
            p = mainpath(fm)
            v = get(fm)
        else
            p = current_file
            v = get(fm, p)
        end
    elseif p ∈ auxpaths(fm)
        v = get(fm, p)
    else
        p = joinpath(fm, p)
        v = addpath!(fm, p)
    end
    Column(v, r, coldict, p, [nm], nvals; read_opts)
end

function _hive_partition_cols(fm::FileManager, ptree::PartitionNode, cols, nrows, current_file::AbstractPath)
    if isempty(children(ptree)) || !foldl(==, cols |> Map(c -> c.file_path))
        return OrderedDict{String,Fill{String,1}}()
    end
    p = if isempty(current_file)
        joinpath(dirname(fm), first(cols).file_path)
    else
        current_file
    end
    columns(ptree, p, nrows)
end

function RowGroup(fm::FileManager, r::SchemaNode, rg::Meta.RowGroup,
                  ptree::PartitionNode=PartitionNode(fm);
                  current_file::AbstractPath=Path(),
                  parallel_column_loading::Union{Nothing,Bool}=nothing,
                 )
    idx = isnothing(rg.file_offset) ? nothing : rg.file_offset+1
    coldict = Dict(c.meta_data.path_in_schema=>c for c ∈ rg.columns)
    nvals = rg.num_rows
    cols = children(r) |> Map(name) |> Map() do nm
        _construct_column(nm, r, coldict, fm, nvals, current_file; read_opts=fm.read_opts)
    end |> collect
    pcols = _hive_partition_cols(fm, ptree, cols, rg.num_rows, current_file)
    nidx = (keys(pcols), cols |> Map(name)) |> Cat() |> collect |> NameIndex
    RowGroup{typeof(fm)}(fm, r, cols, rg.total_byte_size, rg.num_rows,
                         idx,
                         convertnothing(Int, thriftget(rg, :total_compressed_size, nothing)),
                         convertnothing(Int, thriftget(rg, :ordinal, nothing)),
                         nidx, ptree, pcols,
                         parallel_column_loading,
                        )
end

is_hive_partitioned(rg::RowGroup) = !isempty(rg.partition_names)

DataAPI.nrow(rg::RowGroup) = rg.nrows

nbytes(rg::RowGroup) = rg.ℓ

# these only return real columns, not partition cols. This is deliberate
Column(rg::RowGroup, n::Integer) = rg.columns[n]
Column(rg::RowGroup, n::AbstractString) = Column(rg, namelookup(rg.schema, n))

PageLoader(rg::RowGroup, c::Column, p::Integer=1) = PageLoader(c, p)
PageLoader(rg::RowGroup, n::Union{Integer,AbstractString}, p::Integer=1) = PageLoader(Column(rg, n), p)

isnrowsknown(rg::RowGroup) = true

Base.length(rg::RowGroup) = length(rg.partition_columns) + length(rg.columns)

Base.names(rg::RowGroup) = (keys(rg.partition_columns), column_schema_nodes(rg) |> Map(n -> n.name)) |> Cat() |> collect

DataAPI.ncol(rg::RowGroup) = length(rg)

partition_column_names(rg::RowGroup) = OrderedSet(keys(rg.partition_columns))

function Base.getindex(rg::RowGroup, n::Integer)
    if check_partition_column(rg, n)
        rg.partition_columns[rg.partition_columns.keys[n]]
    else
        Column(rg, n - npartitioncols(rg))
    end
end
Base.getindex(rg::RowGroup, n::AbstractString) = rg[NameIndex(rg)[Int, n]]

Base.IteratorEltype() = HasEltype()
Base.eltype(rg::RowGroup) = Column

function Base.iterate(rg::RowGroup, n::Integer=1)
    n > length(rg) && return nothing
    (rg[n], n+1)
end

useparallel(rg::RowGroup) = _useparallel(rg.parallel_column_loading)

# there are extra methods here due to ambiguities

DataAPI.colmetadatasupport(::Type{<:RowGroup}) = (read=true, write=false)

DataAPI.colmetadata(rg::RowGroup, col::Int; style::Bool=false) = metadata(Column(rg, col); style)
function DataAPI.colmetadata(rg::RowGroup, col::Symbol; style::Bool=false) 
    colmetadata(rg, namelookup(rg.schema, string(col)); style)
end

function DataAPI.colmetadata(rg::RowGroup, col::Union{Int,Symbol}, k::AbstractString; style::Bool=false)
    colmetadata(rg, col; style)[k]
end

function DataAPI.colmetadata(rg::RowGroup, col::Union{Int,Symbol}, k::AbstractString, default; style::Bool=false)
    get(colmetadata(rg, col; style), k, default)
end

function DataAPI.colmetadatakeys(rg::RowGroup, col::Union{Integer,Symbol})
    metadatakeys(Column(rg, namelookup(rg.schema, col isa Symbol ? string(col) : col)))
end

function DataAPI.colmetadatakeys(rg::RowGroup)
    names(rg) |> Map(Symbol) |> Map(col -> col=>colmetadatakeys(rg, col)) |> OrderedDict
end
