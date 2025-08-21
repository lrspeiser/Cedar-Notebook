"""
    Parquet2

Module for reading and writing binary data in the Apache
[parquet format](https://github.com/apache/parquet-format).
"""
module Parquet2

using Transducers, Tables, Dates, UUIDs, Mmap, StaticArrays, AbstractTrees, DataAPI, FilePathsBase, TableOperations
using BitIntegers, Thrift2, FillArrays, OrderedCollections, DecFP, JSON3, LightBSON, WeakRefStrings
#compression codecs
using ChunkCodecLibSnappy, ChunkCodecLibZlib, ChunkCodecLibBrotli, ChunkCodecLibZstd, ChunkCodecLibLz4
using ChunkCodecCore: ChunkCodecCore, encode, decode!, NoopCodec

using Thrift2: CompactProtocol
using TableOperations: select, Select

using Base: RefValue

using LazyArrays: BroadcastArray, BroadcastVector
using SentinelArrays: ChainedVector

using Transducers: R_, inner, halve

using DataAPI: nrow, ncol, metadata, colmetadata, metadatakeys, colmetadatakeys

# for debugging, not in dependencies
#using Infiltrator

# this is commonly used and I'd like it to be easy to swap out
const Buffer = Vector{UInt8}

const MAGIC = b"PAR1"
const FOOTER_LENGTH = 4

const ALIGNMENT = 8  # not required by spec


include("Metadata/Metadata.jl")
import .Metadata; const Meta = Metadata
include("arrays.jl")
include("options.jl")
include("utils.jl")
include("compression.jl")
include("table.jl")
include("files.jl")
include("schema.jl")
include("dataset.jl")
include("codec.jl")
include("read.jl")
include("write.jl")
include("show.jl")
include("precompile.jl")

end
