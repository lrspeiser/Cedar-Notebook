
const Setlike{T} = Union{AbstractVector{T},AbstractSet{T}}


"""
    zigzag(x)

[Zig-zag encode](https://en.wikipedia.org/wiki/Variable-length_quantity#Zigzag_encoding)
the integer `x`.  Returns and encoded integer of the same type.
"""
zigzag(x::Integer) = (x << 1) ⊻ (x >> (8sizeof(typeof(x))-1))

"""
    writevarint(io::IO, x::Integer)

Write a [varint encoded](https://en.wikipedia.org/wiki/Variable-length_quantity#Group_Varint_Encoding)
integer `x` to the stream `io`.
"""
function writevarint(io::IO, x::Integer)
    n = 0
    c = true
    while c
        b = x & 0x7f
        if (x >>>= 7) ≠ 0
            b |= 0x80
        else
            c = false
        end
        n += write(io, UInt8(b))
    end
    n
end

function packtuple(x::Integer, y::Integer)
    (x, y) = UInt8.((x, y))
    (x << 4) | (0x0f & y)
end

Base.write(p::CompactProtocol, x::Integer) = writevarint(p.io, zigzag(x))
Base.write(p::CompactProtocol, x::Union{Int8,UInt8}) = write(p.io, x)

Base.write(p::CompactProtocol, x::Enum) = write(p, Int32(x))

Base.write(p::CompactProtocol, x::Float64) = write(p.io, hton(reinterpret(UInt64, x)))

function _write_setlike_preamble_short(p::CompactProtocol, v::Setlike)
    a = length(v)
    b = encodetype(typeof(p), thrifttype(eltype(v)))
    write(p.io, packtuple(a, b))
end

function _write_setlike_preamble_long(p::CompactProtocol, v::Setlike)
    b = encodetype(typeof(p), thrifttype(eltype(v)))
    w = write(p.io, packtuple(0x0f, b))
    w + writevarint(p.io, Int32(length(v)))
end

function Base.write(p::CompactProtocol, v::Setlike)
    w = (length(v) < 15 ? _write_setlike_preamble_short : _write_setlike_preamble_long)(p, v)
    for x ∈ v
        w += write(p, x)
    end
    w
end

Base.write(p::CompactProtocol, v::AbstractVector{UInt8}) = writevarint(p.io, Int32(length(v))) + write(p.io, v)

Base.write(p::CompactProtocol, s::AbstractString) = write(p, codeunits(s))

function Base.write(p::CompactProtocol, m::AbstractDict{K,V}) where {K,V}
    w = writevarint(p.io, length(m))
    isempty(m) && return w
    ab = packtuple(encodetype(CompactProtocol, thrifttype(K)), encodetype(CompactProtocol, thrifttype(V)))
    w += write(p.io, ab)
    for (k, v) ∈ m
        w += write(p, k) + write(p, v)
    end
    w
end

function _write_short_field_header(p::CompactProtocol, id::Integer, lastid::Integer, x)
    ab = packtuple(id-lastid, encodetype(CompactProtocol, thrifttype(x)))
    write(p.io, ab)
end

function _write_long_field_header(p::CompactProtocol, id::Integer, lastid::Integer, x)
    _write_short_field_header(p, 0, 0, x) + write(p.io, zigzag(Int16(id)))
end

function _write_field_header(p::CompactProtocol, long::Bool, id::Integer, lastid::Integer, x)
    (long ? _write_long_field_header : _write_short_field_header)(p, id, lastid, x)
end

# this generated function as well as both Int assertions needed for write to be fully type-stable
@generated function _write_inner(p::CompactProtocol, x)::Int
    n = fieldcount(x)
    fhname = n > 15 ? :_write_long_field_header : :_write_short_field_header
    pamble = quote
        w = 0
        lastid = 0
    end
    fieldexprs = map(1:n) do id
        n = fieldnames(x)[id]
        ϕ = :(x.$n)
        quote
            if !isnothing($ϕ)
                w += $fhname(p, $id, lastid, $ϕ)
                ($ϕ isa Bool) || (w += write(p, $ϕ))
                lastid = $id  # still needed because of the isnothing
            end
        end
    end
    quote
        $pamble
        $(fieldexprs...)
        w
    end
end

function Base.write(p::CompactProtocol, x::T)::Int where {T}
    if !(thrifttype(T) isa ThriftStruct)
        throw(ArgumentError("no suitable thrift compact protocol write method for objects of type $T"))
    end
    _write_inner(p, x) + write(p.io, 0x00)
end
