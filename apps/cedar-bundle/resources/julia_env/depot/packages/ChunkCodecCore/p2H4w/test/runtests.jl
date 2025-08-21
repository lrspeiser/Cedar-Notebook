using Random: Random
using ChunkCodecCore:
    ChunkCodecCore,
    NoopCodec, NoopEncodeOptions, NoopDecodeOptions,
    ShuffleCodec, ShuffleEncodeOptions, ShuffleDecodeOptions,
    DecodedSizeError, decode, decode!
using ChunkCodecTests:ChunkCodecTests, test_codec, test_encoder_decoder
using Aqua: Aqua
using Test: @test, @testset, @test_throws

Aqua.test_all(ChunkCodecCore; persistent_tasks = false)
Aqua.test_all(ChunkCodecTests; persistent_tasks = false)

Random.seed!(1234)

@testset "noop codec" begin
    test_codec(NoopCodec(), NoopEncodeOptions(), NoopDecodeOptions(); trials=100)
    # codec can be used as decoder
    test_encoder_decoder(NoopEncodeOptions(), NoopCodec(); trials=20)
end
@testset "shuffle codec" begin
    for element_size in [1:10; typemax(Int64); typemax(Int64)-1;]
        c = ShuffleCodec(element_size)
        test_codec(
            c,
            ShuffleEncodeOptions(c),
            ShuffleDecodeOptions(c);
            trials=20,
        )
    end
    c = ShuffleCodec(8)
    # ShuffleCodec can be used as an encoder and decoder
    test_encoder_decoder(c, c; trials=20)
    # negative or zero element size should error
    @test_throws ArgumentError ShuffleCodec(0)
    @test_throws ArgumentError ShuffleCodec(-1)
    @test_throws ArgumentError ShuffleCodec(typemin(Int64))
end
@testset "errors" begin
    @test sprint(Base.showerror, DecodedSizeError(1, 2)) == "DecodedSizeError: decoded size: 2 is greater than max size: 1"
    @test sprint(Base.showerror, DecodedSizeError(2, 1)) == "DecodedSizeError: decoded size: 1 is less than expected size: 2"
    @test sprint(Base.showerror, DecodedSizeError(1, nothing)) == "DecodedSizeError: decoded size is greater than max size: 1"
end
@testset "check helpers" begin
    @test_throws Exception ChunkCodecCore.check_contiguous(@view(zeros(UInt8, 8)[1:2:end]))
    @test_throws Exception ChunkCodecCore.check_contiguous(0x00:0xFF)
    if VERSION ≥ v"1.11"
        @test isnothing(ChunkCodecCore.check_contiguous(Memory{UInt8}(undef, 3)))
    end
    @test isnothing(ChunkCodecCore.check_contiguous(Vector{UInt8}(undef, 3)))
    @test isnothing(ChunkCodecCore.check_contiguous(@view(zeros(UInt8, 8)[1:1:end])))
    @test_throws ArgumentError ChunkCodecCore.check_in_range(1:6; x=0)
    @test_throws ArgumentError ChunkCodecCore.check_in_range(1:6; x=7)
    @test isnothing(ChunkCodecCore.check_in_range(1:6; x=6))
    @test isnothing(ChunkCodecCore.check_in_range(1:6; x=1))

    x = zeros(UInt8, 0)
    for m in [typemin(Int64), Int64(-1), Int64(0)]
        @test isnothing(ChunkCodecCore.grow_dst!(x, m))
        @test length(x) == 0
    end
    @test ChunkCodecCore.grow_dst!(x, Int64(1)) === Int64(1)
    @test length(x) == 1
    @test ChunkCodecCore.grow_dst!(x, typemax(Int64)) == length(x)
    n1 = length(x)
    @test n1 > 1
    @test isnothing(ChunkCodecCore.grow_dst!(x, Int64(n1)))
    @test length(x) == n1
    @test ChunkCodecCore.grow_dst!(x, Int64(n1 + 1)) == n1 + 1
    @test length(x) == n1 + 1
end

# version of NoopDecodeOptions that returns unknown try_find_decoded_size
struct TestDecodeOptions <: ChunkCodecCore.DecodeOptions
    codec::NoopCodec
end
function TestDecodeOptions(;
        codec::NoopCodec=NoopCodec(),
        kwargs...
    )
    TestDecodeOptions(codec)
end
ChunkCodecCore.try_find_decoded_size(::TestDecodeOptions, src::AbstractVector{UInt8}) = nothing
function ChunkCodecCore.try_decode!(::TestDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    if dst_size < src_size
        nothing
    else
        copyto!(dst, src)
        src_size
    end
end

@testset "decode with unknown decoded size" begin
    test_codec(NoopCodec(), NoopEncodeOptions(), TestDecodeOptions(); trials=100)
end

@testset "decode size_hint and resizing" begin
    d = TestDecodeOptions()
    @test decode(d, ones(UInt8, Int64(100)); size_hint=Int64(200)) == ones(UInt8, Int64(100))
    @test decode(d, ones(UInt8, Int64(100)); size_hint=Int64(99)) == ones(UInt8, Int64(100))
    @test decode(d, ones(UInt8, Int64(100)); size_hint=Int64(99), max_size=Int64(100)) == ones(UInt8, Int64(100))
    @test_throws DecodedSizeError decode(d, ones(UInt8, Int64(100)); size_hint=Int64(200), max_size=Int64(99))
    # negative max_size
    @test_throws DecodedSizeError(Int64(-1), nothing) decode(d, ones(UInt8, Int64(100)); max_size=Int64(-1))
    @test_throws DecodedSizeError(typemin(Int64), nothing) decode(d, ones(UInt8, Int64(100)); max_size=typemin(Int128))
end
@testset "decode!" begin
    d = TestDecodeOptions()
    @test_throws DecodedSizeError(3, 2) decode!(d, zeros(UInt8, 3), ones(UInt8, 2))
    @test_throws DecodedSizeError(3, nothing) decode!(d, zeros(UInt8, 3), ones(UInt8, 4))
    dst = zeros(UInt8, 3)
    @test decode!(d, dst, ones(UInt8, 3)) === dst
    @test dst == ones(UInt8, 3)
end
