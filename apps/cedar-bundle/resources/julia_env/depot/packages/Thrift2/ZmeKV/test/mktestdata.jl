#====================================================================================================
       This is a script for generating test data from the old Thrift.jl.
====================================================================================================#

using Thrift

include("ParquetMetadata/MetadataOld.jl")
using .MetadataOld


thriftget(x, s::Symbol, d) = hasproperty(x, s) ? getproperty(x, s) : d
thriftenum(t, v) = Symbol(lowercase(enumstr(t, v)))
thriftgetenum(t, x, s, d::Integer) = thriftenum(t, thriftget(x, s, Int32(d)))
function thriftgetenum(t, x, s, d::Symbol)
    hasproperty(x, s) || return d
    thriftenum(t, getproperty(x, s))
end
thriftenumcode(t, s::Symbol) = getproperty(t, Symbol(uppercase(string(s))))

readthrift(v::AbstractVector{UInt8}, ::Type{𝒯}) where {𝒯} = read(TCompactProtocol(TMemoryTransport(v)), 𝒯)
readthrift(io::IO, ::Type{𝒯}) where {𝒯} = read(TCompactProtocol(TFileTransport(io)), 𝒯)

function readthrift(io::IO, ::Type{𝒯}, i::Integer) where {𝒯}
    fixedpos(io) do o
        seek(o, i-1)
        readthrift(o, 𝒯)
    end
end
readthrift(v::AbstractVector{UInt8}, ::Type{𝒯}, i::Integer) where {𝒯} = readthrift(IOBuffer(v), 𝒯, i-1)

function writethrift(io::IO, x)
    p = position(io)
    write(TCompactProtocol(TFileTransport(io)), x)
    position(io) - p
end
function thrift(x)
    io = IOBuffer()
    writethrift(io, x)
    take!(io)
end


function sample(::Type{SchemaElement}, ::Val{1})
    lt = LogicalType(UNKNOWN=NullType())
    SchemaElement(_type=1,  # Int32
                  repetition_type=1,  # optional
                  name="test-element",
                  num_children=0,
                  converted_type=17,  # Int32
                  logicalType=lt,
                 )
end

function sample(::Type{PageHeader}, ::Val{1})
    stats = Statistics(max=[0x00, 0x01],
                       null_count=0,
                       max_value=[0x0a, 0x0b, 0x0c, 0x0d],
                      )
    h = DataPageHeaderV2(num_values=2,
                         num_nulls=0,
                         num_rows=2,
                         encoding=0,  # plain
                         definition_levels_byte_length=0,
                         repetition_levels_byte_length=0,
                         is_compressed=true,
                         statistics=stats,
                        )
    PageHeader(_type=3,  # data page v2
               uncompressed_page_size=16,
               compressed_page_size=8,
               data_page_header_v2=h,
              )
end

function sample(::Type{ColumnMetaData}, ::Val{1})
    ColumnMetaData(_type=6,  # byte array
                   encodings=[0, 2, 3], # plain, plain_dict, rle
                   path_in_schema=["a", "b"],
                   codec=1,  # snappy
                   num_values=100,
                   total_uncompressed_size=1024,
                   total_compressed_size=512,
                   key_value_metadata=[KeyValue(key="a")],
                   data_page_offset=2,
                  )
end

function sample(::Type{Column}, ::Val{1})
    Column(file_path="/path/to/file",
           file_offset=256,
           meta_data=sample(ColumnMetaData, Val(1)),
          )
end

function sample(::Type{RowGroup}, ::Val{1})
    RowGroup(columns=[sample(Column, Val(1))],
             total_byte_size=2048,
             num_rows=100,
             sorting_columns=[],  # make sure empty lists are ok, different from null
            )
end

function sample(::Type{FileMetaData}, ::Val{1})
    FileMetaData(version=2,
                 schema=[sample(SchemaElement, Val(1))],
                 row_groups=[sample(RowGroup, Val(1))],
                 num_rows=100,
                 footer_signing_key_metadata=[0x00, 0x01],
                )
end


samplespath() = joinpath(@__DIR__,"samples")

function samplefile(f, name::AbstractString)
    dir = samplespath()
    isdir(dir) || mkdir(dir)
    path = joinpath(dir, name)
    isfile(path) && rm(path)
    open(f, path, write=true)
end
writesamplefile(name::AbstractString, x) = samplefile(io -> writethrift(io, x), name)

samplename(::Type{T}, ::Val{n}) where {T,n} = string(T, n, ".thrift")

makesample(::Type{T}, v::Val) where {T} = writesamplefile(samplename(T, v), sample(T, v))
makesample(::Type{T}, n::Integer=1) where {T} = makesample(T, Val(n))

cleansamples() = rm(samplespath(), recursive=true, force=true)

function makesamples()
    cleansamples()
    makesample(SchemaElement)
    makesample(PageHeader)
    makesample(ColumnMetaData)
    makesample(Column)
    makesample(RowGroup)
    makesample(FileMetaData)
    nothing
end

