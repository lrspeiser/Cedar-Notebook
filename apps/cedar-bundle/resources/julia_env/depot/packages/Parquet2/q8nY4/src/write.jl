
#====================================================================================================
       \begin{metadata}
====================================================================================================#
function thrift_base_type(::Type{T}) where {T}
    if T == Bool
        Meta.BOOLEAN
    elseif T == Float32
        Meta.FLOAT
    elseif T == Float64
        Meta.DOUBLE
    elseif T ∈ (UInt8, UInt16, UInt32, Int8, Int16, Int32)
        Meta.INT32
    elseif T ∈ (UInt64, Int64)
        Meta.INT64
    elseif T == Vector{UInt8}
        Meta.BYTE_ARRAY
    elseif T == (SVector{N,UInt8} where {N})
        Meta.FIXED_LEN_BYTE_ARRAY
    else
        throw(ArgumentError("there is not thrift base type for $T"))
    end
end
thrift_base_type(::Type{<:SVector{N,𝒯}}) where {N,𝒯} = thrift_base_type(SVector{N,UInt8} where {N})

_thrift_repetition_type(hasnulls::Bool) = hasnulls ? Meta.OPTIONAL : Meta.REQUIRED

function Meta.KeyValue(p::Pair)
    if isnothing(p[2]) || ismissing(p[2])
        Meta.KeyValue(key=p[1])
    else
        Meta.KeyValue(key=p[1], value=p[2])
    end
end

Meta.IntType(::Type{𝒯}) where {𝒯<:Signed} = Meta.IntType(bitWidth=8sizeof(𝒯), isSigned=true)
Meta.IntType(::Type{𝒯}) where {𝒯<:Unsigned} = Meta.IntType(bitWidth=8sizeof(𝒯), isSigned=false)

function Meta.LogicalType(t)
    n = if t isa Meta.StringType
        :STRING
    elseif t isa Meta.MapType
        :MAP
    elseif t isa Meta.ListType
        :LIST
    elseif t isa Meta.EnumType
        :ENUM
    elseif t isa Meta.DecimalType
        :DECIMAL
    elseif t isa Meta.DateType
        :DATE
    elseif t isa Meta.TimeType
        :TIME
    elseif t isa Meta.TimestampType
        :TIMESTAMP
    elseif t isa Meta.IntType
        :INTEGER
    elseif t isa Meta.NullType
        :UNKNOWN
    elseif t isa Meta.JsonType
        :JSON
    elseif t isa Meta.BsonType
        :BSON
    elseif t isa Meta.UUIDType
        :UUID
    else
        throw(ArgumentError("invalid parquet logical type $t"))
    end
    Meta.LogicalType(;n=>t)
end

# just can't be bothered to enumerate all types again
Base.convert(::Type{Meta.LogicalType}, x) = Meta.LogicalType(x)

thrift_root_schema_element(m::Integer) = Meta.SchemaElement(;name="schema", num_children=m)

"""
    encodedtype(t::ParquetType)

Return the bits type in which types in the parquet format of type `t` are encoded.  This returns a Julia type,
not the parquet format type.
"""
encodedtype(t::ParquetBitsType) = juliatype(t)
function encodedtype(t::ParquetLogicalType)
    if t isa ParqDecimal
        if t.precision ≤ 9
            Int32
        elseif t.precision ≤ 18
            Int64
        else
            throw(ArgumentError("maximum decimal precision currently supported is 18"))
        end
    elseif t isa ParqString
        Vector{UInt8}
    elseif t isa ParqEnum
        Int32
    elseif t isa ParqDate
        Int32
    elseif t isa ParqTime
        Int64
    elseif t isa ParqDateTime
        Int64
    elseif (t isa ParqJSON) || (t isa ParqBSON)
        Vector{UInt8}
    elseif t isa ParqUUID
        SVector{16,UInt8}
    elseif t isa ParqMissing
        Int64  # this is just a placeholder, no values will be serialized
    else
        throw(ArgumentError("parquet type $t does not have a known encoded and may not be implemented"))
    end
end

# this method is very convenient for simplifying the below
function Meta.SchemaElement(name::AbstractString, t::ParquetType, hasnulls::Bool=false; kw...)
    Meta.SchemaElement(;name, type=thrift_base_type(encodedtype(t)),
                       repetition_type=_thrift_repetition_type(hasnulls), kw...)
end

function Meta.SchemaElement(name::AbstractString, t::ParqBool, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=1)
end
function Meta.SchemaElement(name::AbstractString, t::ParqUInt8, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=8, logicalType=Meta.IntType(UInt8))
end
function Meta.SchemaElement(name::AbstractString, t::ParqUInt16, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=16, logicalType=Meta.IntType(UInt16))
end
function Meta.SchemaElement(name::AbstractString, t::ParqUInt32, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=32, logicalType=Meta.IntType(UInt32))
end
function Meta.SchemaElement(name::AbstractString, t::ParqUInt64, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=64, logicalType=Meta.IntType(UInt64))
end
function Meta.SchemaElement(name::AbstractString, t::ParqInt8, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=8, logicalType=Meta.IntType(Int8))
end
function Meta.SchemaElement(name::AbstractString, t::ParqInt16, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=16, logicalType=Meta.IntType(Int16))
end
function Meta.SchemaElement(name::AbstractString, t::ParqInt32, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=32, logicalType=Meta.IntType(Int32))
end
function Meta.SchemaElement(name::AbstractString, t::ParqInt64, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=64, logicalType=Meta.IntType(Int64))
end
function Meta.SchemaElement(name::AbstractString, t::ParqFloat32, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=32)
end
function Meta.SchemaElement(name::AbstractString, t::ParqFloat64, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=64)
end
# ParqByteArrays should fall back to method above
function Meta.SchemaElement(name::AbstractString, t::ParqFixedByteArray{N}, hasnulls::Bool=false) where {N}
    Meta.SchemaElement(name, t, hasnulls; type_length=N)
end

function Meta.SchemaElement(name::AbstractString, t::ParqDecimal, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; type_length=8sizeof(juliatype(t)),
                       logicalType=Meta.DecimalType(scale=-t.scale, precision=t.precision))
end

function Meta.SchemaElement(name::AbstractString, t::ParqString, hasnulls::Bool=false)
    # some readers ignore the logical type for some reason, so we set converted_type also
    # might be because we are writing old data page headers
    Meta.SchemaElement(name, t, hasnulls; logicalType=Meta.StringType(),
                       converted_type=Meta.UTF8)
end

function Meta.SchemaElement(name::AbstractString, t::ParqDate, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; logicalType=Meta.DateType())
end

function Meta.SchemaElement(name::AbstractString, t::ParqTime, hasnulls::Bool=false)
    # we follow Julia's Time type and only ever use nanoseconds
    u = Meta.TimeUnit(NANOS=Meta.NanoSeconds())
    Meta.SchemaElement(name, t, hasnulls;
                       logicalType=Meta.TimeType(isAdjustedToUTC=false, unit=u))
end

function Meta.SchemaElement(name::AbstractString, t::ParqDateTime, hasnulls::Bool=false)
    # we follow Julia's DateTime type and only ever use milliseconds
    u = Meta.TimeUnit(MILLIS=Meta.MilliSeconds())
    Meta.SchemaElement(name, t, hasnulls;
                       logicalType=Meta.TimestampType(isAdjustedToUTC=false, unit=u))
end

function Meta.SchemaElement(name::AbstractString, t::ParqJSON, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; logicalType=Meta.JsonType())
end

function Meta.SchemaElement(name::AbstractString, t::ParqBSON, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; logicalType=Meta.BsonType())
end

function Meta.SchemaElement(name::AbstractString, t::ParqUUID, hasnulls::Bool=false)
    # for static arrays type length is bytes not bits... yeah, gross
    Meta.SchemaElement(name, t, hasnulls; type_length=16, logicalType=Meta.UUIDType())
end

function Meta.SchemaElement(name::AbstractString, t::ParqMissing, hasnulls::Bool=false)
    Meta.SchemaElement(name, t, hasnulls; logicalType=Meta.NullType())
end

function Meta.Statistics(s::ColumnStatistics)
    Meta.Statistics(;min=s.min, max=s.max, null_count=s.n_null, distinct_count=s.n_distinct)
end

function Meta.ColumnMetaData(t::ParquetType, name::AbstractString, v::AbstractVector, enc::Meta.Encoding=Meta.PLAIN;
                             compute_stats::Bool=false,
                             data_page_offset::Integer, index_page_offset::Integer
                            )
    o = Meta.ColumnMetaData(;type=t,
                            encodings=[enc],
                            path_in_schema=[name],
                           )
end

function thrift_schema(types::AbstractDict, nulls::AbstractSet)
    m = length(types)
    o = Vector{Meta.SchemaElement}(undef, m+1)
    idx = 1
    o[idx] = thrift_root_schema_element(m)
    for (n, t) ∈ types
        idx += 1
        o[idx] = Meta.SchemaElement(n, t, n ∈ nulls)
    end
    o
end

_created_by_string() = "Parquet2.jl"

function Meta.FileMetaData(sch::AbstractVector{Meta.SchemaElement}, rgs::AbstractVector{Meta.RowGroup}, nrows::Integer;
                           metadata::AbstractDict=Dict())
    Meta.FileMetaData(version=2, schema=sch, num_rows=nrows, row_groups=rgs,
                      created_by=_created_by_string(),
                      key_value_metadata=(isempty(metadata) ? nothing : pack_thrift_metadata(metadata)),
                     )
end
function Meta.FileMetaData(types::AbstractDict, nulls::AbstractSet, nrows::Integer, rgs::AbstractVector{Meta.RowGroup};
                           metadata::AbstractDict=Dict())
    Meta.FileMetaData(thrift_schema(types, nulls), rgs, nrows; metadata)
end

_thrift_pack_value(t::ParquetType, s::ParquetBitsType, x) = reinterpret(UInt8, [encodevalue(t, s, x)])
_thrift_pack_value(t::ParquetType, s::ParqByteArray, x) = encodevalue(t, s, x)

function Meta.Statistics(t::ParquetType, s::ParquetBitsType, v::AbstractVector; n_nulls::Integer=count(ismissing, v))
    a, b = extrema(v)
    Meta.Statistics(null_count=n_nulls, distinct_count=length(unique(v)),
                    min_value=(ismissing(a) ? nothing : _thrift_pack_value(t, s, a)),
                    max_value=(ismissing(b) ? nothing : _thrift_pack_value(t, s, b)),
                   )
end

function Meta.DataPageHeaderV2(v::AbstractVector, enc::Meta.Encoding;
                               is_compressed::Bool=false,
                               nbytes_def_levels::Integer=0,
                               nbytes_rep_levels::Integer=0,
                              )
    n_nulls = count(ismissing, v)
    Meta.DataPageHeaderV2(;num_values=length(v),
                          num_nulls=n_nulls,
                          num_rows=length(v),  # is this right??
                          encoding=enc,
                          definition_levels_byte_length=nbytes_def_levels,
                          repetition_levels_byte_length=nbytes_rep_levels,
                          is_compressed,
                         )
end

function Meta.DataPageHeader(n::Integer, enc::Meta.Encoding;
                             statistics::Union{Nothing,Meta.Statistics}=nothing,
                             is_compressed::Bool=false,
                            )
    Meta.DataPageHeader(;num_values=n,
                        encoding=enc,
                        # pyarrow is very opinionated that the "hybrid" encoding we use is
                        # referred to as rle, *not* bitpacked
                        definition_level_encoding=Meta.RLE,
                        repetition_level_encoding=Meta.RLE,
                        statistics,
                       )
end

function Meta.DictionaryPageHeader(n::Integer, enc::Meta.Encoding; is_sorted::Bool=false)
    Meta.DictionaryPageHeader(;num_values=n, encoding=enc, is_sorted)
end
#====================================================================================================
\end{metadata}
====================================================================================================#

#====================================================================================================
\begin{PageWriter}
====================================================================================================#
mutable struct PageWriter{𝒯<:ParquetType,𝒮<:ParquetBitsType,𝒱<:AbstractVector,𝒞}
    type::𝒯
    basetype::𝒮
    data::𝒱
    buffer::IOBuffer
    compress::𝒞
    encoding::Meta.Encoding
    is_dict_pool::Bool
    has_null::Bool
    null_mask::Vector{Bool}
    nbytes_rep_levels::Int
    nbytes_def_levels::Int
    nbytes_compressed::Int
    nbytes_uncompressed::Int
    buffer_complete::Bool
end

function PageWriter(t::ParquetType, s::ParquetBitsType, v::AbstractVector, enc::Meta.Encoding=Meta.PLAIN,
                    nullmask::Union{Nothing,AbstractVector{Bool}}=nothing;
                    compress=identity,
                    is_dict_pool::Bool=false,
                   )
    if isnothing(nullmask)
        has_null = eltype(v) >: Missing
        nullmask = has_null ? .!ismissing.(v) : Vector{Bool}()
    else
        has_null = true  # we always try to write deflevels if this was specified
    end
    o = PageWriter{typeof(t),typeof(s),typeof(v),typeof(compress)}(t, s, v, IOBuffer(), compress, enc,
                                                                   is_dict_pool, has_null, nullmask,
                                                                   -1, -1, -1, -1, false)
    writebits!(o)
    o
end
function PageWriter(t::ParquetType, v::AbstractVector, enc::Meta.Encoding=Meta.PLAIN; kw...)
    s = encodedtype(t) |> parqtype
    PageWriter(t, s, v, enc; kw...)
end

nvalues(pw::PageWriter) = length(pw.has_null ? pw.null_mask : pw.data)

function Meta.DataPageHeaderV2(pw::PageWriter)
    Meta.DataPageHeaderV2(pw.data, encoding(pw);
                          is_compressed=(pw.compress ≠ identity),
                          nbytes_def_levels=pw.nbytes_def_levels,
                          nbytes_rep_levels=pw.nbytes_rep_levels,
                         )
end

#TODO: I give up using v2... for one, the fastparquet implementation of reading it looks broken
#(assuming I'm reading the spec right).  I can't manage to validate it right now, I don't think
#fastparquet is actually testing it
function Meta.DataPageHeader(pw::PageWriter)
    Meta.DataPageHeader(nvalues(pw), encoding(pw); is_compressed=(pw.compress ≠ identity))
end

Meta.DictionaryPageHeader(pw::PageWriter) = Meta.DictionaryPageHeader(nvalues(pw), pw.encoding)

function Meta.PageHeader(pw::PageWriter)
    t = pw.is_dict_pool ? Meta.DICTIONARY_PAGE : Meta.DATA_PAGE
    Meta.PageHeader(type=t,
                    uncompressed_page_size=pw.nbytes_uncompressed,
                    compressed_page_size=pw.nbytes_compressed,
                    dictionary_page_header=(pw.is_dict_pool ? Meta.DictionaryPageHeader(pw) : nothing),
                    data_page_header=(pw.is_dict_pool ? nothing : Meta.DataPageHeader(pw)),
                   )
end

encoding(pw::PageWriter) = pw.encoding
isdictpool(pw::PageWriter) = pw.is_dict_pool
maxdeflevel(pw::PageWriter) = pw.has_null ? 1 : 0

"""
    writereplevels!(pw::PageWriter)

Write repetition levels to the intermediate buffer.
"""
function writereplevels!(pw::PageWriter)
    pw.nbytes_rep_levels = 0
    pw
end

"""
    writedeflevels!(pw::PageWriter)

Write definition levesl to the intermediate buffer.
"""
function writedeflevels!(pw::PageWriter)
    pw.nbytes_def_levels = 0
    if pw.has_null
        m = maxdeflevel(pw)
        pw.nbytes_def_levels += encodehybrid_bitpacked(pw.buffer, pw.null_mask, bitwidth(m))
    else
        pw.nbytes_def_levels = 0
    end
    pw
end

function writebitshybrid_dictrefs!(pw::PageWriter)
    w = isempty(pw.data) ? 0 : bitwidth(maximum(pw.data))
    pw.nbytes_uncompressed = leb128encode(pw.buffer, UInt32(w))
    bw = isempty(pw.data) ? 1 : bitwidth(maximum(pw.data))
    pw.nbytes_uncompressed += encodehybrid_bitpacked(pw.buffer, pw.data, bw; write_preface=false)
    pw
end

"""
    encodevalue(t::ParquetType, s::ParquetBitsType, x)

Encode the value `x` as a `t` using encoding type `s` as dictated by the parquet standard.
"""
encodevalue(::ParquetType, ::ParquetBitsType, x) = x
encodevalue(::ParqString, ::ParqByteArray, x) = codeunits(x)
encodevalue(pdt::ParqDateTime, ::ParqInt64, x::DateTime) = floor(Int, datetime2unix(x) * 10^(-pdt.exponent))
encodevalue(pd::ParqDate, ::ParqInt32, x::Date) = Int32(Dates.value(x - Date(1970,1,1)))
encodevalue(pt::ParqTime, ::ParqInt64, x::Time) = Int64(Dates.value(x - Time(0)))
encodevalue(::ParqJSON, ::ParqByteArray, x) = JSON3.write(x)
encodevalue(::ParqBSON, ::ParqByteArray, x) = bson_write(UInt8[], x)
encodevalue(::ParqUUID, ::ParqFixedByteArray, id::UUID) = int2staticarray(id.value)
encodevalue(::ParquetType, ::ParqUInt8, x) = UInt32(x)
encodevalue(::ParquetType, ::ParqUInt16, x) = UInt32(x)
encodevalue(::ParquetType, ::ParqInt8, x) = Int32(x)
encodevalue(::ParquetType, ::ParqInt16, x) = Int32(x)

encodevalue(pt::ParqDecimal, bt::ParquetBitsType, x::DecFP.DecimalFloatingPoint) = round(Int64, ldexp10(x, -pt.scale))

"""
    writebitsplain(io, t::ParquetType, s::ParquetBitsType, x)

Write the value `x` to `io` according to the parquet plain serialization scheme.
"""
writebitsplain(io::IO, t::ParquetType, s::ParquetBitsType, x) = write(io, encodevalue(t, s, x))
function writebitsplain(io::IO, t::ParquetType, s::ParqByteArray, x)
    ξ = encodevalue(t, s, x)
    write(io, Int32(length(ξ))) + write(io, ξ)
end

function writebitsplain!(pw::PageWriter)
    pw.nbytes_uncompressed = 0
    data = skipmissing(pw.data)
    if pw.type == ParqBool()  # special handling for bools
        pw.nbytes_uncompressed += bitpack!(pw.buffer, collect(data), 1)
    else
        for x ∈ data
            pw.nbytes_uncompressed += writebitsplain(pw.buffer, pw.type, pw.basetype, x)
        end
    end
    pw
end

# for now we guess what this should look like by using `loadbits` as a template
function writebits!(pw::PageWriter)
    writereplevels!(pw)
    writedeflevels!(pw)
    enc = encoding(pw)
    if enc == Meta.PLAIN
        writebitsplain!(pw)
    elseif enc == Meta.RLE_DICTIONARY
        isdictpool(pw) ? writebitsplain!(pw) : writebitshybrid_dictrefs!(pw)
    else
        error("invalid encoding: $enc")
    end
    pw.buffer_complete = true
    pw
end

function Base.write(io::IO, pw::PageWriter)
    pw.buffer_complete || error("tried to write a page buffer that wasn't constructed yet")
    buf = take!(pw.buffer)
    pw.nbytes_uncompressed = length(buf)
    buf = pw.compress(buf)
    pw.nbytes_compressed = length(buf)
    h = Meta.PageHeader(pw)
    nw = write(CompactProtocol(io), h)
    nw += write(io, buf)
end

default_determine_type(v::AbstractVector) = parqtype(eltype(v))
default_determine_type(v::AbstractVector{Missing}) = parqtype(Missing)

_dec_exponent(v::AbstractVector)  = maximum(exponent10, skipmissing(v)) - precision(nonmissingtype(eltype(v)), base=10)
_dec_exponent(::AbstractVector{Missing}) = 0

function default_determine_type(v::AbstractVector{<:Union{Missing,DecFP.DecimalFloatingPoint}})
    parqtype(DecFP.DecimalFloatingPoint,
             decimal_scale=_dec_exponent(v),
             decimal_precision=-_dec_exponent(v),
            )
end
#====================================================================================================
\end{PageWriter}
====================================================================================================#

#====================================================================================================
\begin{ColumnWriter}
====================================================================================================#
"""
    defaultpagepartitions(n, npages)

A default partitioning of `1:n` into `npages`.  Tries to give the same number of values for each with the
last page being truncated to the remainder.

For example `defaultpagepartitions(10,3) == [1:4, 5:8, 9:10]`.
"""
function defaultpagepartitions(n::Integer, npages::Integer)
    k = 1
    parts = Vector{UnitRange{Int}}(undef, npages)
    for i ∈ 1:npages
        k′ = min(n, k+cld(n, npages)-1)
        parts[i] = k:k′
        k = k′ + 1
    end
    parts
end


mutable struct ColumnWriter{𝒱<:AbstractVector,𝒯<:ParquetType,ℛ,C}
    parqtype::𝒯
    data::𝒱
    name::String
    file_path::String
    compression_codec::Meta.CompressionCodec
    compute_statistics::Bool
    is_dict::Bool
    dict_refs::ℛ
    metadata::Dict{String,Any}
    partitions::Vector{UnitRange{Int}}

    compress::C

    # writing state
    nwritten::Int
    nuncompressed::Int
    has_null::Bool
    thrift_metadata::Union{Nothing,Meta.Column}
end

function ColumnWriter(name::AbstractString, v::AbstractVector, t::ParquetType=parqtype(eltype(v));
                      file_path::AbstractString="",
                      compression_codec::Union{Meta.CompressionCodec,Symbol}=Meta.UNCOMPRESSED,
                      compute_statistics::Bool=false,
                      metadata::AbstractDict=Dict(),
                      is_dict::Bool=!isnothing(DataAPI.refpool(v)),
                      npages::Integer=1,
                      partitions::Union{Nothing,AbstractVector}=nothing,
                     )
    refs = is_dict ? ParqRefVector(v) : nothing
    parts = if isnothing(partitions)
        n = length(is_dict ? refs : v)
        defaultpagepartitions(n, npages)
    else
        partitions
    end
    has_null = eltype(v) >: Missing
    ccodec = _compression_codec(compression_codec)
    comp = getcompressor(ccodec)
    CWT = ColumnWriter{typeof(v),typeof(t),typeof(refs),typeof(comp)}
    CWT(t, v, name, file_path, ccodec, compute_statistics, is_dict, refs, metadata, parts,
        comp, 0, 0, has_null, nothing,
    )
end

function Base.write(io::IO, cw::ColumnWriter)
    enctype = encodedtype(cw.parqtype)
    p₀ = position(io)  # initial position
    _writepages!(io, cw, parqtype(enctype), cw.compress;
                 compute_statistics=cw.compute_statistics,
                )
    encs = [Meta.PLAIN]
    cw.is_dict && push!(encs, Meta.RLE_DICTIONARY)
    cw.has_null && push!(encs, Meta.RLE)
    stats = cw.compute_statistics ? Meta.Statistics(cw.parqtype, parqtype(enctype), cw.data) : nothing
    md = Meta.ColumnMetaData(type=thrift_base_type(enctype),
                             encodings=encs,
                             path_in_schema=[cw.name],
                             codec=cw.compression_codec,
                             num_values=length(cw.data),
                             total_uncompressed_size=cw.nuncompressed,
                             total_compressed_size=cw.nwritten,
                             data_page_offset=p₀,
                             # leave metadata field null unless provided dict is non-empty
                             key_value_metadata=(isempty(cw.metadata) ? nothing : pack_thrift_metadata(cw.metadata)),
                             statistics=stats,
                            )
    o = Meta.Column(;file_offset=p₀, meta_data=md,
                    file_path=(isempty(cw.file_path) ? nothing : cw.file_path),
                   )
    cw.thrift_metadata = o
    cw.nwritten
end

function _write_page!(io::IO, cw::ColumnWriter, pw::PageWriter)
    δ = write(io, pw)
    cw.nuncompressed += δ - pw.nbytes_compressed + pw.nbytes_uncompressed
    cw.nwritten += δ
    cw.has_null = cw.has_null || pw.has_null
    pw
end

function _writepages_dictionary!(io::IO, cw::ColumnWriter, s::ParquetBitsType, compress; compute_statistics::Bool=false)
    # write pool
    pw = PageWriter(cw.parqtype, s, getpool(cw.dict_refs), Meta.PLAIN; compress, is_dict_pool=true)
    _write_page!(io, cw, pw)

    # write refs
    for p ∈ cw.partitions
        v = view(cw.data, p)
        r = collect(skipmissing(view(cw.dict_refs, p)))
        nm = cw.has_null ? .!ismissing.(v) : nothing
        pw = PageWriter(cw.parqtype, s, r, Meta.RLE_DICTIONARY, nm; compress)
        _write_page!(io, cw, pw)
    end
end
function _writepages_default!(io::IO, cw::ColumnWriter, s::ParquetBitsType, compress)
    for p ∈ cw.partitions
        pw = PageWriter(cw.parqtype, s, view(cw.data, p), Meta.PLAIN; compress)
        _write_page!(io, cw, pw)
    end
end

function _writepages!(io::IO, cw::ColumnWriter, s::ParquetBitsType, compress;
                      compute_statistics::Bool=false
                     )
    if cw.is_dict
        _writepages_dictionary!(io, cw, s, compress)
    else
        _writepages_default!(io, cw, s, compress)
    end
end
#====================================================================================================
\end{ColumnWriter}
====================================================================================================#


function _validate_table(tbl::Tables.Columns)
    length(tbl) == 0 && return  # don't error on empty table
    ℓ = length(first(tbl))
    # depending on the table, this can be surprisingly slow on large numbers of columns, so
    # for now we don't give the table name
    for v ∈ tbl
        if length(v) ≠ ℓ
            throw(ArgumentError("table is invalid; columns have inconsistent length"))
        end
    end
end


"""
    FileWriter

Data structure holding metadata inferred during the process of writing a parquet file.

A full table can be written with `writetable!`, for a more detailed example, see below.

## Constructors
```julia
FileWriter(io, path; kw...)
FileWriter(path; kw...)
```

## Arguments
- `io`: the `IO` object to which data will be written.
- `path`: the path of the file being written.  This is used in parquet metadata which is why it is possible
    to specify the path separately from the IO-stream.

### Keyword Arguments
The following arguments are relevant for the entire file:
- `metadata` (`Dict()`): Additional metadata to append at file-level.  Must provide an `AbstractDict`, the
    keys and values must both be strings.  This can be accessed from a written file with [`Parquet2.metadata`](@ref).
- `propagate_table_metadata` (`true`): Whether to propagate table metadata provided by the DataAPI.jl metadata interface
    for tables written to this file.  If `true` and multiple tables are written, the metadata will be merged.
    If this is undesirable users should set this to `false` and set via `metadata` instead.
    The `metadata` argument above will be merged with table metadata (with metadata from the option taking
    precedence).

The following arguments apply to specific columns and can be provided as a single value, `NamedTuple`, `AbstractDict`
or `ColumnOption`.  See [`ColumnOption`](@ref) for details.
- `npages` (`1`): The number of pages to write.  Some parquet readers are more efficient at reading multiple pages
    for large numbers of columns, but for the most part there's no reason to change this.
- `compression_codec` (`:snappy`): Compression codec to use.  Available options are `:uncompressed`,
    `:snappy`, `:gzip`, `:brotli`, and `:zstd`.
- `column_metadata` (`Dict()`): Additional metadata for specific columns.  This works the same way as file-level
    `metadata` and must be a dictionary with string keys and values.  Can be accessed from a written file by
    calling [`Parquet2.metadata`](@ref) on column objects.
- `compute_statistics` (`false`): Whether column statistics (minimum, maximum, number of nulls) should be computed
    when the file is written and stored in metadata.  When read back with `Dataset`, the loaded columns will
    be wrapped in a struct allowing these statistics to be efficiently retrieved, see [`VectorWithStatistics`](@ref).
- `json_columns` (`false`): Columns which should be JSON encoded.  Columns with types which can be naturally
    encoded as JSON but which have no other supported types, that is `AbstractVector` and `AbstractDict` columns,
    will be JSON encoded regardless of the value of this argument.
- `bson_columns` (`false`): Columns which should be BSON encoded.  By default, columns which need special encoding
    are JSON encoding, so they must be specified here to force them to be BSON.
- `propagate_col_metadata` (`true`): Whether to propagate column metadata provided by the DataAPI.jl metadata
    interface.  Metadata set with the `column_metadata` argument will be merged with this with the former taking
    precedence.

## Examples
```julia
open(filename, write=true) do io
    fw = Parquet2.FileWriter(io)
    Parquet2.writeiterable!(io, tbls)  # write tables as separate row groups, finalization is done automatically
end

df = DataFrame(A=1:5, B=randn(5))

# use `writefile` to write in a single call
writefile(filename, df)

# write to `IO` object
io = IOBuffer()
writefile(io, df)

# write to an `AbstractVector` buffer.
v = writefile(Vector{UInt8}, df)
```
"""
mutable struct FileWriter{ℐ<:IO}
    io::ℐ
    path::String
    colnames::Vector{String}  # this is to do a half-assed validation of new tables
    types::OrderedDict{String,ParquetType}
    nulls::Set{String}  # set of columns which should be considered nullable
    nrows::Int
    row_groups::Vector{Meta.RowGroup}
    options::WriteOptions
    meta::Union{Nothing,Meta.FileMetaData}
end

"""
    _initialize!(fw::FileWriter)

Write the initial bytes of a parquet file.  This is automatically called on construction of a `FileWriter`
and therefore this is an internal function which should not be called by users.
"""
_initialize!(fw::FileWriter) = (write(fw.io, MAGIC); fw)

function FileWriter(io::IO, path::AbstractString; kw...)
    fw = FileWriter{typeof(io)}(io, path, String[],
                                OrderedDict{String,ParquetType}(), Set{String}(), 0,
                                Vector{Meta.RowGroup}(),
                                WriteOptions(;kw...),
                                nothing)
    _initialize!(fw)
end
FileWriter(io::IO; kw...) = FileWriter(io, ""; kw...)

isfinalized(fw::FileWriter) = !isnothing(fw.meta)

"""
    _written_coltype

Determine the parquet type that will be used for writing provided the write options, name and element type
of the column.

Used in `writetable!`.
"""
function _written_coltype(opts::WriteOptions, name::AbstractString, t::Union{Type,Nothing}, v::AbstractVector)
    if evaloption(opts, :bson_columns, name, t)
        ParqBSON()
    elseif evaloption(opts, :json_columns, name, t)
        ParqJSON()
    else
        default_determine_type(v)
    end
end

function _get_col_metadata(tbl, i::Integer)
    DataAPI.colmetadatasupport(typeof(tbl)).read || return Dict{String,Any}()
    ks = colmetadatakeys(tbl, i)
    Dict{String,Any}(string(k)=>string(colmetadata(tbl, i, k)) for k ∈ ks)
end

function _writetable_get_col_meta(fw::FileWriter, name::AbstractString, type, tblorig, i::Integer)
    if evaloption(fw.options, :propagate_col_metadata, name, type)
        _get_col_metadata(tblorig, i)
    else
        Dict{String,Any}()
    end
end

function _writetable_column!(fw::FileWriter, name::AbstractString, i::Integer, v::AbstractVector, t, type, meta, cols)
    cw = ColumnWriter(name, v, t;
                      compression_codec=evaloption(fw.options, :compression_codec, name, type),
                      npages=evaloption(fw.options, :npages, name, type),
                      metadata=merge!(meta, evaloption(fw.options, :column_metadata, name, type)),
                      compute_statistics=evaloption(fw.options, :compute_statistics, name, type),
                     )
    write(fw.io, cw)
    cols[i] = cw.thrift_metadata
end

"""
    writetable!(fw::FileWriter, tbl)

Write a single table `tbl` with the `FileWriter` as a single row group.

[`finalize!`](@ref) **MUST** be called after using this or else it will result in an incomplete and unusable
parquet file.  It is recommended that users use either [`writefile`](@ref), [`writeiterable!`](@ref) or
[`writefile!`](@ref) instead of `writetable!`.
"""
function writetable!(fw::FileWriter, @nospecialize tbl)
    isfinalized(fw) && error("cannot write additional tables; file is already finalized")

    tblorig = tbl
    tbl = Tables.Columns(Tables.columns(tbl))
    _validate_table(tbl)

    names = Tables.columnnames(tbl)
    if isempty(fw.colnames)
        fw.colnames = isempty(names) ? String[] : collect(map(string, names))
    elseif any(((a, b),) -> string(a) ≠ b, zip(names, fw.colnames))
        throw(ArgumentError("tried to write a table which is incompatible with initialized schema;"*
                            "expected columns: $(fw.colnames)\ngot columns: $names"))
    end
    length(tbl) == 0 && return fw  # nothing more to do if empty
    nrows = Tables.rowcount(tbl)

    cols = Vector{Meta.Column}(undef, length(tbl))
    p₀ = position(fw.io)

    for (i, (syname, v)) ∈ enumerate(pairs(tbl))
        name = string(syname)
        type = Tables.columntype(tbl, syname)
        meta = _writetable_get_col_meta(fw, name, type, tblorig, i)
        t = _written_coltype(fw.options, name, type, v)

        # note whether column has missings; we use the type because may be future values
        (type >: Missing) && push!(fw.nulls, name)

        # this ensures we try to coerce into previously initialized type if it exists
        t = get!(fw.types, name, t)

        _writetable_column!(fw, name, i, v, t, type, meta, cols)
    end

    fw.nrows += ntablerows(tbl)  # update total number of rows written

    push!(fw.row_groups, Meta.RowGroup(;columns=cols, num_rows=nrows, total_byte_size=position(fw.io)-p₀))

    fw
end

"""
    finalize!(fw::FileWriter, extra_meta=Dict{String,String}())

Write the closing metadata to a parquet file.  No further data can be written after this.

It should not be necessary to call this externally, see [`writeiterable!`](@ref) and [`writefile!`](@ref).

`extra_meta` is additional metadata (as a `Dict`) which is not already part of `fw` (for cases where it is
not known when `fw` is created).
"""
function finalize!(fw::FileWriter; extra_meta::AbstractDict=Dict{String,String}())
    isfinalized(fw) && error("file is already finalized; cannot be finalized again")
    fw.meta = Meta.FileMetaData(fw.types, fw.nulls, fw.nrows, fw.row_groups;
                                metadata=merge!(extra_meta, fw.options[:metadata]),
                               )
    ml = write(CompactProtocol(fw.io), fw.meta)
    write(fw.io, Int32(ml))
    write(fw.io, MAGIC)
    fw
end

function _get_table_metadata(tbl)
    DataAPI.metadatasupport(typeof(tbl)).read || return Dict{String,Any}()
    ks = metadatakeys(tbl)
    Dict{String,Any}(string(k)=>string(metadata(tbl, k)) for k ∈ ks)
end

"""
    writeiterable!(fw::FileWriter, tbls)

Write each table returned by the iterable over Tables.jl compatible tables `tbls` to the parquet
file.  The file will then be finalized so that no further data can be written to it.
"""
function writeiterable!(fw::FileWriter, @nospecialize tbls)
    meta = Dict{String,String}()
    for stbl ∈ tbls
        fw.options.propagate_table_metadata && merge!(meta, _get_table_metadata(stbl))
        writetable!(fw, stbl)
    end
    finalize!(fw; extra_meta=meta)
    nothing
end

"""
    writefile!(fw::FileWriter, tbl)

Write the Tables.jl compatible table `tbl` to the parquet file.  If the table is partitioned (i.e. if
`Tables.partitions(tbl)` returns an iterable over more than one table) each partition will be written as
a parquet row group.  The file will then be finalized so that no further data can be written to it.
"""
writefile!(fw::FileWriter, @nospecialize tbl) = writeiterable!(fw, Tables.partitions(tbl))

"""
    writefile(io::IO, path, tbl; kw...)
    writefile(path, tbl; kw...)

Write the Tables.jl compatible table `tbl` to the `IO` or the file at `path`.  Note that the path is used in
parquet metadata, which is why it is possible to specify the path separately from the `io` stream.  See
[`FileWriter`](@ref) for a description of all possible arguments.

This function writes a file all in one call.  Files will be written as one parquet row group per table partition.
An intermediate [`FileWriter`](@ref) object is used.
"""
function writefile(io::IO, path::AbstractString, @nospecialize tbl; kw...)
    fw = FileWriter(io, path; kw...)
    writefile!(fw, tbl)
    nothing
end
writefile(io::IO, path::AbstractPath, @nospecialize tbl; kw...) = writefile(io, string(path), tbl; kw...)
writefile(io::IO, @nospecialize tbl; kw...) = writefile(io, "", tbl; kw...)
function writefile(path::Union{AbstractString,AbstractPath}, @nospecialize tbl; kw...)
    open(path; write=true) do io
        writefile(io, path, tbl; kw...)
    end
    nothing
end
function writefile(::Type{Vector{UInt8}}, path::Union{AbstractPath,AbstractString}, @nospecialize tbl; kw...)
    io = IOBuffer()
    writefile(io, path, tbl; kw...)
    take!(io)
end
writefile(::Type{Vector{UInt8}}, @nospecialize tbl; kw...) = writefile(Vector{UInt8}, "", tbl; kw...)
