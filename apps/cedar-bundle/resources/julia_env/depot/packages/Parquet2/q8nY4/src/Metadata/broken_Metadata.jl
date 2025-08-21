#====================================================================================================
       WARNING

My thrift writer is broken and using the new metadata format produces what pyarrow claims is
invalid thrift.  This is despite my reader being able to read back both thrift produced by other
writers and its own thrift perfectly fine.  Other readers seem able to read the old metadata
format just fine (that's the one currently being used).

At this point the prospects for figuring out what's wrong are pretty grim, I'd have to do some kind
of careful introspection of the buffers using somebody elses writer.  As of writing I've been
unable to figure out why it's corrupt, so we are stuck with the old metadata format.
====================================================================================================#
module Metadata

using Thrift2

abstract type MetadataType end

@enum BitsType::Int32 begin
    BOOLEAN = 0
    INT32 = 1
    INT64 = 2
    INT96 = 3
    FLOAT = 4
    DOUBLE = 5
    BYTE_ARRAY = 6
    FIXED_LEN_BYTE_ARRAY = 7
end

@enum ConvertedType::Int32 begin
    UTF8 = 0

    MAP = 1
    MAP_KEY_VALUE = 2

    LIST = 3

    ENUM = 4

    DECIMAL = 5

    DATE = 6
    TIME_MILLIS = 7
    TIME_MICROS = 8
    TIMESTAMP_MILLIS = 9
    TIMESTAMP_MICROS = 10

    UINT_8 = 11
    UINT_16 = 12
    UINT_32 = 13
    UINT_64 = 14

    INT_8 = 15
    INT_16 = 16
    INT_32 = 17
    INT_64 = 18

    JSON = 19
    BSON = 20
    
    INTERVAL = 21
end

@enum FieldRepetitionType::Int32 begin
    REQUIRED = 0
    OPTIONAL = 1
    REPEATED = 2
end

@thriftstruct struct SizeStatistics <: MetadataType
    unencoded_byte_array_data_bytes::Union{Nothing,Int64}
    repetition_level_histogram::Union{Nothing,Vector{Int64}}
    definition_level_histogram::Union{Nothing,Vector{Int64}}
end

@thriftstruct struct Statistics <: MetadataType
    max::Union{Nothing,Vector{UInt8}} = nothing
    min::Union{Nothing,Vector{UInt8}} = nothing
    null_count::Union{Nothing,Int64} = nothing
    distinct_count::Union{Nothing,Int64} = nothing
    max_value::Union{Nothing,Vector{UInt8}} = nothing
    min_value::Union{Nothing,Vector{UInt8}} = nothing
    is_max_value_exact::Union{Nothing,Bool} = nothing
    is_min_value_exact::Union{Nothing,Bool} = nothing
end

@thriftstruct struct StringType <: MetadataType end
@thriftstruct struct UUIDType <: MetadataType end
@thriftstruct struct MapType <: MetadataType end
@thriftstruct struct ListType <: MetadataType end
@thriftstruct struct EnumType <: MetadataType end
@thriftstruct struct DateType <: MetadataType end
@thriftstruct struct Float16Type <: MetadataType end
@thriftstruct struct NullType <: MetadataType end

@thriftstruct struct DecimalType <: MetadataType
    scale::Int32
    precision::Int32
end

@thriftstruct struct MilliSeconds <: MetadataType end
@thriftstruct struct MicroSeconds <: MetadataType end
@thriftstruct struct NanoSeconds <: MetadataType end

@thriftstruct struct TimeUnit <: MetadataType
    MILLIS::Union{Nothing,MilliSeconds} = nothing
    MICROS::Union{Nothing,MicroSeconds} = nothing
    NANOS::Union{Nothing,NanoSeconds} = nothing
end

@thriftstruct struct TimestampType <: MetadataType
    isAdjustedToUTC::Bool
    unit::TimeUnit
end

@thriftstruct struct TimeType <: MetadataType
    isAdjustedToUTC::Bool
    unit::TimeUnit
end

@thriftstruct struct IntType <: MetadataType
    bitWidth::Int8
    isSigned::Bool
end

@thriftstruct struct JsonType <: MetadataType end
@thriftstruct struct BsonType <: MetadataType end

@thriftstruct struct LogicalType <: MetadataType
    STRING::Union{Nothing,StringType} = nothing
    MAP::Union{Nothing,MapType} = nothing
    LIST::Union{Nothing,ListType} = nothing
    ENUM::Union{Nothing,EnumType} = nothing
    DECIMAL::Union{Nothing,DecimalType} = nothing
    DATE::Union{Nothing,DateType} = nothing
    TIME::Union{Nothing,TimeType} = nothing
    TIMESTAMP::Union{Nothing,TimestampType} = nothing
    INTERVAL::Nothing = nothing  # not used
    INTEGER::Union{Nothing,IntType} = nothing
    UNKNOWN::Union{Nothing,NullType} = nothing
    JSON::Union{Nothing,JsonType} = nothing
    BSON::Union{Nothing,BsonType} = nothing
    UUID::Union{Nothing,UUIDType} = nothing
    FLOAT16::Union{Nothing,Float16Type} = nothing
end

@thriftstruct struct SchemaElement <: MetadataType
    type::Union{Nothing,BitsType} = nothing
    type_length::Union{Nothing,Int32} = nothing
    repetition_type::Union{Nothing,FieldRepetitionType} = nothing
    name::String
    num_children::Union{Nothing,Int32} = nothing
    converted_type::Union{Nothing,ConvertedType} = nothing
    scale::Union{Nothing,Int32} = nothing
    precision::Union{Nothing,Int32} = nothing
    field_id::Union{Nothing,Int32} = nothing
    logicalType::Union{Nothing,LogicalType} = nothing
end

@enum Encoding::Int32 begin
    PLAIN = 0
    PLAIN_DICTIONARY = 2
    RLE = 3
    BIT_PACKED = 4
    DELTA_BINARY_PACKED = 5
    DELTA_LENGTH_BYTE_ARRAY = 6
    DELTA_BYTE_ARRAY = 7
    RLE_DICTIONARY = 8
    BYTE_STREAM_SPLIT = 9
end

@enum CompressionCodec::Int32 begin
    UNCOMPRESSED = 0
    SNAPPY = 1
    GZIP = 2
    LZO = 3
    BROTLI = 4
    LZ4 = 5
    ZSTD = 6
    LZ4_RAW = 7
end

@enum PageType::Int32 begin
    DATA_PAGE = 0
    INDEX_PAGE = 1
    DICTIONARY_PAGE = 2
    DATA_PAGE_V2 = 3
end

@enum BoundaryOrder::Int32 begin
    UNORDERED = 0
    ASCENDING = 1
    DESCENDING = 2
end

@thriftstruct struct DataPageHeader <: MetadataType
    num_values::Int32
    encoding::Encoding
    definition_level_encoding::Encoding
    repetition_level_encoding::Encoding
    statistics::Union{Nothing,Statistics} = nothing
end

@thriftstruct struct IndexPageHeader <: MetadataType end

@thriftstruct struct DictionaryPageHeader <: MetadataType
    num_values::Int32
    encoding::Encoding
    is_sorted::Union{Nothing,Bool} = nothing
end

@thriftstruct struct DataPageHeaderV2 <: MetadataType
    num_values::Int32
    num_nulls::Int32
    num_rows::Int32
    encoding::Encoding
    definition_levels_byte_length::Int32
    repetition_levels_byte_length::Int32
    is_compressed::Union{Nothing,Bool} = true
    statistics::Union{Nothing,Statistics} = nothing
end

@thriftstruct struct SplitBlockAlgorithm <: MetadataType end

@thriftstruct struct BloomFilterAlgorithm <: MetadataType
    BLOCK::Union{Nothing,SplitBlockAlgorithm}
end

@thriftstruct struct XxHash <: MetadataType end

@thriftstruct struct BloomFilterHash <: MetadataType
    XXHASH::XxHash
end

@thriftstruct struct Uncompressed <: MetadataType end

@thriftstruct struct BloomFilterCompression <: MetadataType
    UNCOMPRESSED::Union{Nothing,Uncompressed}
end

@thriftstruct struct BloomFilterHeader <: MetadataType
    numBytes::Int32
    algorithm::BloomFilterAlgorithm
    hash::BloomFilterHash
    compression::BloomFilterCompression
end

@thriftstruct struct PageHeader <: MetadataType
    type::PageType
    uncompressed_page_size::Int32
    compressed_page_size::Int32
    crc::Union{Nothing,Int32} = nothing
    data_page_header::Union{Nothing,DataPageHeader} = nothing
    index_page_header::Union{Nothing,IndexPageHeader} = nothing
    dictionary_page_header::Union{Nothing,DictionaryPageHeader} = nothing
    data_page_header_v2::Union{Nothing,DataPageHeaderV2} = nothing
end

@thriftstruct struct KeyValue <: MetadataType
    key::String
    value::Union{Nothing,String} = nothing
end

@thriftstruct struct SortingColumn <: MetadataType
    column_idx::Int32
    descending::Bool
    nulls_first::Bool
end

@thriftstruct struct PageEncodingStats <: MetadataType
    page_type::PageType
    encoding::Encoding
    count::Int32
end

@thriftstruct struct ColumnMetaData <: MetadataType
    type::BitsType
    encodings::Vector{Encoding}
    path_in_schema::Vector{String}
    codec::CompressionCodec
    num_values::Int64
    total_uncompressed_size::Int64
    total_compressed_size::Int64
    key_value_metadata::Union{Nothing,Vector{KeyValue}} = nothing
    data_page_offset::Int64
    index_page_offset::Union{Nothing,Int64} = nothing
    dictionary_page_offset::Union{Nothing,Int64} = nothing
    statistics::Union{Nothing,Statistics} = nothing
    encoding_stats::Union{Nothing,Vector{PageEncodingStats}} = nothing
    bloom_filter_offset::Union{Nothing,Int64} = nothing
    bloom_filter_length::Union{Nothing,Int32} = nothing
    size_statistics::Union{Nothing,SizeStatistics} = nothing
end

@thriftstruct struct EncryptionWithFooterKey <: MetadataType end

@thriftstruct struct EncryptionWithColumnKey <: MetadataType
    path_in_schema::Vector{String}
    key_metadata::Union{Nothing,Vector{UInt8}} = nothing
end

@thriftstruct struct ColumnCryptoMetaData <: MetadataType
    ENCRYPTION_WITH_FOOTER_KEY::Union{Nothing,EncryptionWithFooterKey} = nothing
    ENCRYPTION_WITH_COLUMN_KEY::Union{Nothing,EncryptionWithColumnKey} = nothing
end

@thriftstruct struct Column <: MetadataType
    file_path::Union{Nothing,String} = nothing
    file_offset::Int64
    meta_data::Union{Nothing,ColumnMetaData} = nothing
    offset_index_offset::Union{Nothing,Int64} = nothing
    offset_index_length::Union{Nothing,Int32} = nothing
    column_index_offset::Union{Nothing,Int64} = nothing
    column_index_length::Union{Nothing,Int32} = nothing
    crypto_metadata::Union{Nothing,ColumnCryptoMetaData} = nothing
    encrypted_column_metadata::Union{Nothing,Vector{UInt8}} = nothing
end

@thriftstruct struct RowGroup <: MetadataType
    columns::Vector{Column}
    total_byte_size::Int64
    num_rows::Int64
    sorting_columns::Union{Nothing,Vector{SortingColumn}} = nothing
    file_offset::Union{Nothing,Int64} = nothing
    total_compressed_size::Union{Nothing,Int64} = nothing
    ordinal::Union{Nothing,Int16} = nothing
end

@thriftstruct struct TypeDefinedOrder <: MetadataType end

@thriftstruct struct ColumnOrder <: MetadataType
    TYPE_ORDER::Union{Nothing,TypeDefinedOrder} = nothing
end

@thriftstruct struct PageLocation <: MetadataType
    offset::Int64
    compressed_page_size::Int32
    first_row_index::Int64
end

@thriftstruct struct OffsetIndex <: MetadataType
    page_locations::Vector{PageLocation}
end

@thriftstruct struct ColumnIndex <: MetadataType
    null_pages::Vector{Bool}
    min_values::Vector{Vector{UInt8}}
    max_values::Vector{Vector{UInt8}}
    boundary_order::BoundaryOrder
    null_counts::Union{Nothing,Vector{Int64}} = nothing
    repetition_level_histograms::Union{Nothing,Vector{Int64}} = nothing
    definition_level_histograms::Union{Nothing,Vector{Int64}} = nothing
end

@thriftstruct struct AesGcmV1 <: MetadataType
    aad_prefix::Union{Nothing,Vector{UInt8}} = nothing
    aad_file_unique::Union{Nothing,Vector{UInt8}} = nothing
    supply_aad_prefix::Union{Nothing,Bool} = nothing
end

@thriftstruct struct AesGcmCtrV1 <: MetadataType
    aad_prefix::Union{Nothing,Vector{UInt8}} = nothing
    aad_file_unique::Union{Nothing,Vector{UInt8}} = nothing
    supply_aad_prefix::Union{Nothing,Bool} = nothing
end

@thriftstruct struct EncryptionAlgorithm <: MetadataType
    AES_GCM_V1::Union{Nothing,AesGcmV1} = nothing
    AES_GCM_CTR_V1::Union{Nothing,AesGcmCtrV1} = nothing
end

@thriftstruct struct FileMetaData <: MetadataType
    version::Int32
    schema::Vector{SchemaElement}
    num_rows::Int64
    row_groups::Vector{RowGroup}
    key_value_metadata::Union{Nothing,Vector{KeyValue}} = nothing
    created_by::Union{Nothing,String} = nothing
    column_orders::Union{Nothing,Vector{ColumnOrder}} = nothing
    encryption_algorithm::Union{Nothing,EncryptionAlgorithm} = nothing
    footer_signing_key_metadata::Union{Nothing,Vector{UInt8}} = nothing
end

@thriftstruct struct FileCryptoMetaData <: MetadataType
    encryption_algorithm::EncryptionAlgorithm
    key_metadata::Union{Nothing,Vector{UInt8}} = nothing
end



end
