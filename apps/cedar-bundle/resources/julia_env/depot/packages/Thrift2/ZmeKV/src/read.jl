
"""
    StructReadState

Data structure representing a program state used while reading thrift structs.
"""
struct StructReadState
    index::Int
    type::Int
    stop::Bool
end

init(::Type{StructReadState}) = StructReadState(0, -1, false)

isterminal(s::StructReadState) = s.stop

"""
    unzigzag(x)

Invert the [zig-zag encoding](https://en.wikipedia.org/wiki/Variable-length_quantity#Zigzag_encoding)
of an integer `x`.  That is, `unzigzag(zigzag(x)) == x`.
"""
unzigzag(x::Integer) = -(x & Int64(1)) ⊻ (x >>> 1)

"""
    readvarint(io, ::Type{T}) where {T<:Integer}

Read a [varint encoded](https://en.wikipedia.org/wiki/Variable-length_quantity#Group_Varint_Encoding)
integer from the `io` stream.  The result is of integer type `T`.
"""
function readvarint(io::IO, ::Type{T}) where {T<:Integer}
    o = zero(T)
    n = 0
    b = UInt8(0x80)
    while (b & UInt8(0x80)) ≠ 0
        b = read(io, UInt8)
        o |= convert(T, b & 0x7f) << 7n
        n += 1
    end
    o
end

function skipvarint(io::IO)
    n = 0
    b = UInt8(0x80)
    while (b & UInt8(0x80)) ≠ 0
        b = read(io, UInt8)
        n += 1
    end
    nothing
end

Base.read(p::ThriftProtocol, t::ThriftType) = read(p, typeof(t))

function Base.read(p::CompactProtocol, ::Type{T}) where {T<:ThriftInteger}
    jt = juliatype(T)
    convert(jt, unzigzag(readvarint(p.io, jt)))
end
# bytes are special cased... this was the cause of great pain and misery
Base.read(p::CompactProtocol, ::Type{<:ThriftInt8}) = reinterpret(Int8, read(p.io, UInt8))
Base.read(p::CompactProtocol, ::Type{<:ThriftFloat64}) = reinterpret(Float64, ntoh(read(p.io, UInt64)))

Base.read(p::CompactProtocol, ::Type{ThriftEnum{T}}) where {T<:Enum} = T(read(p, ThriftInt32))

intsplit(a::Integer) = (Int(a >>> 4), Int(a & 0x0f))

function _read_setlike_elements(p::CompactProtocol, s::Integer, ::Type{T}) where {T<:ThriftType}
    o = Vector{juliatype(T)}(undef, s)
    for j ∈ 1:s
        o[j] = read(p, T)
    end
    o
end
function _read_setlike_elements(p::CompactProtocol, s::Integer, t::Integer)
    _read_setlike_elements(p, s, decodetype(CompactProtocol, t))
end

function _read_setlike_preamble(p::CompactProtocol)
    h = read(p.io, UInt8)
    s = h >> 4
    t = 0x0f & h
    s == 0x0f && (s = readvarint(p.io, Int32))  # special code for reading size separately
    (s, t)
end

# this method for when we know eltype from schema
function Base.read(p::CompactProtocol, ::Type{<:ThriftSetlike{T}}) where {T}
    (s, _) = _read_setlike_preamble(p)
    _read_setlike_elements(p, s, T)
end

# this method for when eltype is unknown
function Base.read(p::CompactProtocol, ::Type{ThriftSetlike})
    (s, t) = _read_setlike_preamble(p)
    _read_setlike_elements(p, s, t)
end

Base.read(p::CompactProtocol, ::Type{<:ThriftBytes}) = read(p.io, readvarint(p.io, Int32))

Base.read(p::CompactProtocol, ::Type{<:ThriftString}) = String(read(p, ThriftBytes))

skipbinary(p::CompactProtocol) = skip(p.io, readvarint(p.io, Int32))

function skipsetlike(p::CompactProtocol)
    (s, t) = _read_setlike_preamble(p)
    for j ∈ 1:s
        skip(p, t)
    end
    nothing
end

function skipmap(p::CompactProtocol)
    n = readvarint(p.io, Int32)
    n == 0 && return nothing
    (tk, tv) = intsplit(read(p.io, UInt8))
    for j ∈ 1:n
        skip(p, tk)
        skip(p, tv)
    end
    nothing
end

function Base.skip(p::CompactProtocol, t::Integer)
    # for t ∈ (1,2) we don't have to do anything
    if t == 3
        skip(p.io, 1)
    elseif 3 ≤ t ≤ 6
        skipvarint(p.io)
    elseif t == 7
        skip(p.io, 8)
    elseif t == 8
        skipbinary(p)
    elseif 9 ≤ t ≤ 10
        skipsetlike(p)
    elseif t == 11
        skipmap(p)
    elseif t == 12
        skipstruct(p)
    end
    nothing
end

function Base.read(p::CompactProtocol, ::Type{<:ThriftMap{K,V}}) where {K,V}
    o = OrderedDict{juliatype(K),juliatype(V)}()
    n = readvarint(p.io, Int32)
    n == 0 && return 0
    sizehint!(o, n)
    kv = read(p.io, UInt8)  # these give types, but we only support getting them from schema
    for j ∈ 1:n
        k = read(p, K)  # these are separate so that the order is really obvious
        v = read(p, V)
        o[k] = v
    end
    o
end

function readfieldheader(p::CompactProtocol, s::StructReadState)
    a = read(p.io, UInt8)
    a == 0 && return StructReadState(0, -1, true)
    (α, t) = intsplit(a)
    k′ = if iszero(α)  # long form
        Int(unzigzag(read(p.io, UInt16)))
    else
        s.index + α
    end
    StructReadState(k′, t, false)
end

_read(p::CompactProtocol, ::StructReadState, ::Type{T}) where {T<:ThriftType} = read(p, T)
_read(p::CompactProtocol, s::StructReadState, ::Type{T}) where {T<:ThriftBool} = (s.type == 1)

init(::Type{StructReadState}, p::CompactProtocol) = readfieldheader(p, StructReadState(0, -1, false))

"""
    readfield(p::CompactProtocol, s::StructReadState, ::Val{id}, ::Type{T})

Read a field with ID `id` of type `T` from the buffer `p` from struct read state `s`.  After reading the
value, it will read the next header and infer the next state.  This returns the tuple `(s′, val)` where
`s′` is the next state and `val` is the (possibly null) field value.
"""
function readfield(p::CompactProtocol, s::StructReadState, ::Val{id}, ::Type{T}) where {id,T<:ThriftType}
    isterminal(s) && return (s, nothing)
    if s.index == id
        o = _read(p, s, T)
        s′ = readfieldheader(p, s)
        (s′, o)
    else
        (s, nothing)
    end
end

"""
    skipfield(p::CompactProtocol, s::StructReadState)

Skip the subsequent field of a thrift struct.
"""
function skipfield(p::CompactProtocol, s::StructReadState)
    isterminal(s) && return (s, nothing)
    skip(p, s.type)
    readfieldheader(p, s)
end

function skipremainingstruct(p::CompactProtocol, s::StructReadState)
    while !isterminal(s)
        s = skipfield(p, s)
    end
end

"""
    skipstruct(p::CompactProtocol)

Skip the reading of an entire struct, i.e. from initial `StructReadState`.
"""
skipstruct(p::CompactProtocol) = skipremainingstruct(p, StructReadState(0, -1, false))
