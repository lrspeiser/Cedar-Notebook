using Thrift2

include("ParquetMetadata/Metadata.jl")
import .Metadata
using .Metadata: SchemaElement, ColumnMetaData, Column, RowGroup, FileMetaData
using .Metadata: IntType, NullType, LogicalType, KeyValue
using .Metadata: Statistics, DataPageHeaderV2, PageHeader, IndexPageHeader
using .Metadata: PLAIN, PLAIN_DICTIONARY, RLE, OPTIONAL, INT32, BYTE_ARRAY
using .Metadata: INT_32
using .Metadata: SNAPPY
using .Metadata: DATA_PAGE_V2


function sample(::Type{SchemaElement}, ::Val{1})
    lt = LogicalType(UNKNOWN=NullType())
    SchemaElement(type=INT32,
                  repetition_type=OPTIONAL,
                  name="test-element",
                  num_children=0,
                  converted_type=INT_32,
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
                         encoding=PLAIN,
                         definition_levels_byte_length=0,
                         repetition_levels_byte_length=0,
                         is_compressed=true,
                         statistics=stats,
                        )
    PageHeader(type=DATA_PAGE_V2,  # data page v2
               uncompressed_page_size=16,
               compressed_page_size=8,
               data_page_header_v2=h,
              )
end

function sample(::Type{ColumnMetaData}, ::Val{1})
    ColumnMetaData(type=BYTE_ARRAY,  # byte array
                   encodings=[PLAIN, PLAIN_DICTIONARY, RLE], # plain, plain_dict, rle
                   path_in_schema=["a", "b"],
                   codec=SNAPPY,
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


sample(::Type{T}, n::Integer=1) where {T} = sample(T, Val(n))
