
"""
    getcompressor(n::Union{Integer,Meta.CompressionCodec})

Get the function `𝒻(::AbstractVector{UInt8})::AbstractVector{UInt8}` for compressing data to codec `n`.
"""
function getcompressor(c::Meta.CompressionCodec)
    if c == Meta.UNCOMPRESSED
        identity
    elseif c == Meta.SNAPPY
        v -> encode(SnappyEncodeOptions(), Vector(v))
    elseif c == Meta.GZIP
        v -> encode(GzipEncodeOptions(), Vector(v))
    elseif c == Meta.BROTLI
        v -> encode(BrotliEncodeOptions(), Vector(v))
    elseif c == Meta.ZSTD
        v -> encode(ZstdEncodeOptions(), Vector(v))
    elseif c == Meta.LZ4_RAW
        # we don't currently support but this allows loading as empty col
        v -> throw(ArgumentError("lz4 compression codec not yet implemented"))
        # v -> encode(LZ4BlockEncodeOptions(), Vector(v))
    else
        throw(ArgumentError("compression codec $c is unsupported"))
    end
end
getcompressor(c::Integer) = getcompressor(Meta.CompressionCodec(c))

"""
    getdecompressor(c::Meta.CompressionCodec)

Get decoder that implement `ChunkCodecCore.try_decode!` for decompressing data from codec `c`.
"""
function getdecompressor(c::Meta.CompressionCodec)
    if c == Meta.UNCOMPRESSED
        NoopCodec()
    elseif c == Meta.SNAPPY
        SnappyCodec()
    elseif c == Meta.GZIP
        GzipCodec()
    elseif c == Meta.BROTLI
        BrotliCodec()
    elseif c == Meta.ZSTD
        ZstdCodec()
    elseif c == Meta.LZ4_RAW
        LZ4BlockCodec()
    else
        throw(ArgumentError("compression codec $c is unsupported"))
    end
end

# need this to support symbol options
function _compression_codec(s::Symbol)
    if s == :uncompressed
        Meta.UNCOMPRESSED
    elseif s == :snappy
        Meta.SNAPPY
    elseif s == :gzip
        Meta.GZIP
    elseif s == :lzo
        Meta.LZO
    elseif s == :brotli
        Meta.BROTLI
    elseif s == :lz4
        Meta.LZ4
    elseif s == :zstd
        Meta.ZSTD
    elseif s == :lz4_raw
        Meta.LZ4_RAW
    else
        throw(ArgumentError("invalid or unsupported compression codec $s"))
    end
end
_compression_codec(c::Meta.CompressionCodec) = c
