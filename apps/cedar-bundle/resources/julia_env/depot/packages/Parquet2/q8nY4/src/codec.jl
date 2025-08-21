
function _bitpack_select_bits(x, w::Integer, ω::Integer, b::Integer)
    r = min(w - ω + 1, 8 - b + 1)
    x = x >> (ω - 1)
    u = UInt8(x & bitmask(UInt8, 1, r)) << (b - 1)
    u, ω + r, b + r
end

"""
    bitpack!(o::AbstractVector{UInt8}, a, v::AbstractVector, w::Integer)
    bitpack!(io::IO, v::AbstractVector, w::Integer)

Pack the first `w` bits of each value of `v` into bytes in the vector `o` starting from index `a`.  If the values
of `v` have any non-zero bits beyond the first `w` they will be truncated.

**WARNING** the bytes of `o` to be written to *must* be initialized to zero or the result may be corrupt.
"""
function bitpack!(o::AbstractVector{UInt8}, a::Integer, v::AbstractVector, w::Integer)
    b = 1  # a is current index in o, b is bit in index
    for (i, x) ∈ enumerate(v)
        ω = 1  # current bit of value
        while ω ≤ w
            u, ω, b = _bitpack_select_bits(x, w, ω, b)
            # for now I'm going to be paranoid and bounds check here, that way if somebody lies
            # about the bit width it doesn't destroy the entire universe
            o[a] |= u
            b > 8 && (a +=1; b = 1)
        end
    end
    o
end

# this is the same as the above but for io instead of vector
function bitpack!(io::IO, v::AbstractVector, w::Integer)
    b = 1
    n = 0
    c = 0x00
    for (i, x) ∈ enumerate(v)
        ω = 1
        while ω ≤ w
            u, ω, b = _bitpack_select_bits(x, w, ω, b)
            c |= u
            b > 8 && (n += write(io, c); b = 1; c = 0x00)
        end
        b ≠ 1 && i == lastindex(v) && (n += write(io, c))
    end
    n
end

"""
    bitpack(v::AbstractVector, w)
    bitpack(io::IO, w)

Pack the first `w` bits of each value of `v` into the bytes of a new `Vector{UInt8}` buffer.
"""
bitpack(v::AbstractVector, w::Integer) = bitpack!(zeros(UInt8, cld(w*length(v), 8)), 1, v, w)
bitpack(io::IO, v::AbstractVector, w::Integer) = bitpack!(io, v, w)

"""
    bitmask(𝒯, α, β)
    bitmask(𝒯, β)

Create a bit mask of type `𝒯 <: Integer` where bits `α` to `β` (inclusive) are `1` and the rest are `0`, where
bit `1` is the least significant bit.  If only one argument is given it is taken as the *end* position `β`.
"""
function bitmask(::Type{𝒯}, α::Integer, β::Integer) where {𝒯<:Integer}
    o = zero(𝒯)
    for k ∈ α:β
        o += 𝒯(2)^(k-1)
    end
    o
end
bitmask(::Type{𝒯}, β::Integer) where {𝒯} = bitmask(𝒯, 1, β)

"""
    bitjustify(k, α, β)

Move bits `α` through `β` (inclusive) to the least significant bits of an integer of type `k`.
"""
function bitjustify(k::Integer, α::Integer, β::Integer)
    γ = 8sizeof(k) - β
    (k << γ) >> (α + γ - 1)
end

"""
    bitwidth(n::Integer)

Compute the width in bits needed to encode integer `n`, truncating leading zeros.  For example, `1` has a width of `1`,
`3` has a width of `2`, `8` has a width of `4`, et cetera.

The minimum value this returns for positive inputs is `1` for safety reasons.
"""
bitwidth(n::Integer) = max(1, ceil(Int, log(2, n+1)))

"""
    bytewidth(n::Integer)

Compute the width in bytes needed to encode integer `n` truncating leading zeros beyond the nearest byte boundary.
For example, anything expressible as a `UInt8` has a byte width of `1`, anything expressible as a `UInt16` has a
byte width of `2`, et cetera.
"""
bytewidth(n::Integer) = cld(bitwidth(n), 8)


"""
    leb128encode(n::Unsigned)
    leb128encode(io::IO, n::Unsigned)

Encode the integer `n` as a byte array according to the
[LEB128](https://en.wikipedia.org/wiki/LEB128) encoding scheme.
"""
function leb128encode(n::Unsigned)
    ℓ = 8*sizeof(n)
    o = UInt8[]
    while !iszero(n)
        b = UInt8(0x7f & n)
        n = n >> 7
        iszero(n) || (b = b | 0x80)
        push!(o, b)
    end
    o
end
function leb128encode(io::IO, n::Unsigned)
    ℓ = 8*sizeof(n)
    o = 0
    while !iszero(n)
        b = UInt8(0x7f & n)
        n = n >> 7
        iszero(n) || (b = b | 0x80)
        o += write(io, b)
    end
    o
end

"""
    leb128decode(𝒯, v, k)

Decode `v` (from index `k`) to an integer of type `𝒯 <: Unsigned` according to the
[LEB128](https://en.wikipedia.org/wiki/LEB128) encoding scheme.

Returns `o, j` where `o` is the decoded value and `j` is the index of `v` *after* reading
(i.e. the encoded byte is contained in data from `k` to `j-1` inclusive).
"""
function leb128decode(::Type{𝒯}, v::AbstractVector{UInt8}, k::Integer=1) where {𝒯<:Unsigned}
    o = zero(𝒯)
    δ = 0
    j = k
    while j ≤ length(v)
        b = v[j]
        o = o | ((𝒯(0x7f) & b) << δ)
        j += 1
        (0x80 & b) == 0 && break
        δ += 7
    end
    o, j
end

"""
    leb128decode(𝒯, io)

Decode `v` to an integer of type `𝒯 <: Unsigned` according to the
[LEB128](https://en.wikipedia.org/wiki/LEB128) encoding scheme.
"""
function leb128decode(::Type{𝒯}, io::IO) where {𝒯<:Unsigned}
    o = zero(𝒯)
    δ = 0
    while !eof(io)
        b = read(io, UInt8)
        o = o | ((𝒯(0x7f) & b) << δ)
        (0x80 & b) == 0 && break
        δ += 7
    end
    o
end

"""
    readfixed(io, 𝒯, N, v=zero(𝒯))
    readfixed(w::AbstractVector{UInt8}, 𝒯, N, i=1, v=zero(𝒯))

Read a `𝒯 <: Integer` from the first `N` bytes of `io`.  This is for reading integers which have had
their leading zeros truncated.
"""
function readfixed(io::IO, ::Type{𝒯}, N::Integer, v::𝒯=zero(𝒯)) where {𝒯<:Integer}
    for n ∈ 0:(N-1)
        b = 𝒯(read(io, UInt8))
        v = v | (b << 8n)
    end
    v
end
function readfixed(w::AbstractArray{UInt8}, ::Type{𝒯}, N::Integer, i::Integer=1, v::𝒯=zero(𝒯)) where {𝒯<:Integer}
    for n ∈ 0:(N-1)
        b = 𝒯(w[i])
        i += 1
        v = v | (b << 8n)
    end
    v
end

"""
    writefixed(io::IO, x::Integer)

Write the integer `x` using the minimal number of bytes needed to accurately represent `x`, i.e. by writing
`bytewidth(x)` bytes.
"""
function writefixed(io::IO, x::Integer)
    nb = bytewidth(x)
    v = reinterpret(UInt8, [x])
    foreach(j -> write(io, v[j]), 1:nb)
    nb
end

#====================================================================================================
       NOTE:

`HybridDecoder` is pretty tricky because it is very difficult to determine how many bytes to read
for each run.  In principle the spec allows for arbitrarily many separate bit-packed runs but
it seems unlikely that these will ever occur.  In the bit-packed case, the number of values
is stored in multiples of 8.

There are several tricks here to make this (hopefully) reliable.  They may not all be necessary
but it seems worth the tiny cost in performance
- Check if hit eof
- Check if the number of values read excedes the number of values indicated by metadata
- Check if we have surpassed the number of bytes read by metadata
- Make sure `h` (which gives number of values to read in a run) gives `0`.  If it does,
    it's likely an indiation that we hit padding. This shouldn't happen.
====================================================================================================#

# 𝒲 is the type of the view of 𝒱 (may not be easy to infer if 𝒱 is a view
"""
    HybridIterator

An iterable object for iterating over the parquet "hybrid encoding" described
[here](https://github.com/apache/parquet-format/blob/master/Encodings.md#run-length-encoding--bit-packing-hybrid-rle--3).

Each item in the collection is an `AbstractVector` with decoded values.
"""
struct HybridIterator{𝒯,𝒱<:AbstractVector{UInt8},𝒲<:AbstractVector}
    v::𝒱
    width::Int
    ℓ::Int
    nbytes::Int
    k₀::Int
end

function HybridIterator{𝒯}(v::AbstractVector, k::Integer, w::Integer, ℓ::Integer, nbytes::Integer) where {𝒯}
    ω = view(v, 1:0)  # we do this purely to determine the type of the view
    HybridIterator{𝒯,typeof(v),typeof(ω)}(v, w, ℓ, nbytes, k)
end
function HybridIterator{𝒯}(v::AbstractVector, k::Integer, w::Integer, ℓ::Integer, ::Nothing=nothing) where {𝒯}
    nbytes = reinterpret(UInt32, view(v, k:(k+4-1)))[1]
    HybridIterator{𝒯}(v, k+4, w, ℓ, nbytes)
end

BitUnpackVector(hi::HybridIterator{𝒯,𝒱}, idx) where {𝒯,𝒱} = BitUnpackVector{𝒯}(view(hi.v, idx), hi.width)

struct HybridState
    λ::Int
    k::Int
end

HybridState(hi::HybridIterator) = HybridState(0, hi.k₀)

Base.IteratorSize(::Type{<:HybridIterator}) = Base.SizeUnknown()

# WARN: this relies on union splitting for efficiency which is a little scary
# need to change this so you don't have to worry about it

function Base.iterate(hi::HybridIterator{𝒯}, s::HybridState=HybridState(hi)) where {𝒯}
    s.λ ≥ hi.ℓ && return nothing

    s.k - hi.k₀ < hi.nbytes || return nothing

    h, k = leb128decode(UInt32, hi.v, s.k)
    h = Int(h)

    h == 0 && return nothing

    if iseven(h)
        η = min(h >> 1, hi.ℓ - s.λ)  # run length
        δ = cld(hi.width, 8)
        x = readfixed(hi.v, 𝒯, δ, k)
        k += δ
        (Fill(x, η), HybridState(s.λ+η, k))
    else
        h = h >> 1
        η = 8h*hi.width  # number of *bits* of upcoming bitpack
        ℓ = min(hi.ℓ - s.λ, 8h)  # length in number of values of upcoming bitpack
        δ = cld(η, 8)  # number of *bytes* of upcoming bitpack
        k′ = min(length(hi.v), k+δ-1)
        bp = BitUnpackVector{𝒯}(view(hi.v, k:k′), hi.width, min(hi.ℓ - s.λ, 8h))
        k = k′ + 1
        (bp, HybridState(s.λ + ℓ, k))
    end
end


"""
    encodehybrid_bitpacked(io::IO, v::AbstractVector, w=bitwidth(maximum(v)); write_preface=true, additional_bytes=0)

Bit-pack `v` and encode it to `io` such that it can be read with `decodehybrid`.  This encodes all data in
`v` as a single bitpacked run.

If `write_preface` the `Int32` indicating the number of payload bytes will be written, with `additional_bytes`
additional payload bytes.

**WARNING** Parquet's horribly confusing encoding format does not appear to support arbitrary combinations
of bitpacked encoding with run-length encoding, because the number of bitpacked-values cannot in general
be uniquely determined... yeah...
"""
function encodehybrid_bitpacked(io::IO, v::AbstractVector, w::Integer=bitwidth(maximum(v));
                                write_preface::Bool=true, additional_bytes::Integer=0)
    h = cld(length(v), 8)  # can only give number of values in multiples of 8
    nbytes = w*h  # number of bytes we'll need
    H = leb128encode(UInt((h << 1) | 1))
    nbytes += additional_bytes
    k = 0
    write_preface && (k += write(io, UInt32(nbytes + length(H))))
    k += write(io, H)
    k′ = bitpack(io, v, w)
    # write padding if needed
    for i ∈ 1:(nbytes - k′)
        k += write(io, 0x00)
    end
    k + k′
end

"""
    encodehybrid_rle(io::IO, x::Integer, n::Integer; write_preface=false, additional_bytes=0)

Run-length encode a sequence of `n` copies of `x` to `io`.

If `write_preface` the `Int32` indicating the number of payload bytes will  be written, with `additional_bytes`
additional payload bytes.

**WARNING** This cannot be combined arbitrarily with `encodehybrid_bitpacked`, see that function's documentation.
"""
function encodehybrid_rle(io::IO, x::Integer, n::Integer; write_preface::Bool=true, additional_bytes::Integer=0)
    nbytes = bytewidth(x) + additional_bytes
    h = leb128encode(UInt(n) << 1)
    k = 0
    write_preface && (k += write(io, UInt32(nbytes + length(h))))
    k += write(io, h)
    k += encoderle1(io, x)
end

"""
    encodehybrid_rle(io::IO, v::AbstractVector{<:Integer})

Write the vector `v` to `io` using the parquet run-length encoding.
"""
function encodehybrid_rle(io::IO, v::AbstractVector{<:Integer})
    isempty(v) && return 0
    buf = IOBuffer()
    for w ∈ RunsIterator(v)
        encodehybrid_rle(buf, first(w), length(w); write_preface=false)
    end
    nbytes = position(buf)
    nw = write(io, UInt32(nbytes))
    nw += write(io, take!(buf))
end
