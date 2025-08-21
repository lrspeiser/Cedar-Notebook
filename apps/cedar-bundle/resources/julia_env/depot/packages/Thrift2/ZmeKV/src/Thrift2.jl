module Thrift2

using OrderedCollections
using MacroTools


abstract type ThriftProtocol end

"""
    CompactProtocol{I<:IO}

A struct which wraps an `IO` objects facilitating the reading and writing of
objects using the
[thrift compact protocol](https://erikvanoosten.github.io/thrift-missing-specification/#_thrift_compact_protocol_encoding).

This object deliberately does not support arbitrary reading and writing like an `IO`, but only objects which can be
written using the appropriate protocol.  This does *NOT* guaratee that such data is written in a sequence which is
permissable under the protocol.

## Constructors
```julia
CompactProtocol(io)  # wrap an existing IO object
CompactProtocol(v)  # wrap a byte array
CompactProtocol()  # create a buffer
```

## Arguments
- `io::IO`: Any `IO` object.
- `v::AbstractVector{UInt8}`: a mutable byte vector.

## Examples
```julia
p = open(CompactProtocol, filename, write=true)
write(p, ThriftObject())
seekstart(p)  # supports seekstart if the IO does
```
"""
struct CompactProtocol{I<:IO} <: ThriftProtocol
    io::I
end

CompactProtocol(x::AbstractVector{UInt8}) = CompactProtocol(IOBuffer(x))
CompactProtocol() = CompactProtocol(IOBuffer())

Base.seekstart(p::CompactProtocol) = (seekstart(p.io); p)

Base.close(p::CompactProtocol) = close(p.io)


"""
    ThriftType

The abstract type for all thrift metadata types.
Each valid instance of a `ThrifType` corresponds to a concrete Julia type,
which can be seen using [`juliatype`](@ref) and [`thrifttype`](@ref).
"""
abstract type ThriftType end

abstract type ThriftReal <: ThriftType end
abstract type ThriftInteger <: ThriftReal end

"""
    juliatype(t::ThriftType)
    juliatype(::Type{T}) where {T<:ThrifType}

Determines the native Julia type which corresponds to a give thrift type.
This is guaranteed to be inferrable at compile time.
"""
function juliatype end

"""
    thrifttype(T::Type)

Returns the [`ThriftType`](@ref) object which corresponds to a given native
Julia type `T`.  Note that this returns an *instance* of a `ThriftType`,
not the type.  Only a specific subset of native Julia types have defined
`ThriftType`s.
"""
function thrifttype end

#WARN: this is a horrifying hack because of possible generated func world age issue, still exploring
_thrifttype(::Type{Union{Nothing,T}}) where {T} = _thrifttype(T)
_thrifttype(::Type{T}) where {T} = ThriftStruct{T}()

struct ThriftFloat64 <: ThriftReal end
juliatype(::Type{<:ThriftFloat64}) = Float64
thrifttype(::Type{Float64}) = ThriftFloat64()
_thrifttype(::Type{Float64}) = ThriftFloat64()

# the thrift protocol often encodes boolean values with data
struct ThriftBool{B} <: ThriftInteger end
valueof(::Type{ThriftBool{B}}) where {B} = B
valueof(b::ThriftBool) = valueof(typeof(b))
ThriftBool() = ThriftBool{false}()
juliatype(::Type{<:ThriftBool}) = Bool
thrifttype(::Type{Bool}) = ThriftBool()
_thrifttype(::Type{Bool}) = ThriftBool()

struct ThriftInt8 <: ThriftInteger end
juliatype(::Type{<:ThriftInt8}) = Int8
thrifttype(::Type{Int8}) = ThriftInt8()
_thrifttype(::Type{Int8}) = ThriftInt8()

struct ThriftInt16 <: ThriftInteger end
juliatype(::Type{<:ThriftInt16}) = Int16
thrifttype(::Type{Int16}) = ThriftInt16()
_thrifttype(::Type{Int16}) = ThriftInt16()

struct ThriftInt32 <: ThriftInteger end
juliatype(::Type{<:ThriftInt32}) = Int32
thrifttype(::Type{Int32}) = ThriftInt32()
_thrifttype(::Type{Int32}) = ThriftInt32()

struct ThriftEnum{T<:Enum} <: ThriftType end
juliatype(::Type{ThriftEnum{T}}) where {T} = T
thrifttype(::Type{T}) where {T<:Enum} = ThriftEnum{T}()
_thrifttype(::Type{T}) where {T<:Enum} = ThriftEnum{T}()

struct ThriftInt64 <: ThriftInteger end
juliatype(::Type{<:ThriftInt64}) = Int64
thrifttype(::Type{Int64}) = ThriftInt64()
_thrifttype(::Type{Int64}) = ThriftInt64()

abstract type ThriftBinary <: ThriftType end

struct ThriftBytes <: ThriftBinary end
juliatype(::Type{<:ThriftBytes}) = Vector{UInt8}
thrifttype(::Type{Vector{UInt8}}) = ThriftBytes()
_thrifttype(::Type{Vector{UInt8}}) = ThriftBytes()

struct ThriftString <: ThriftBinary end
juliatype(::Type{<:ThriftString}) = String
thrifttype(::Type{String}) = ThriftString()
_thrifttype(::Type{String}) = ThriftString()

struct ThriftStruct{T} <: ThriftType end
juliatype(::Type{<:ThriftStruct{T}}) where {T} = T

struct ThriftMap{K<:ThriftType,V<:ThriftType} <: ThriftType
    keytype::K
    valtype::V
end
juliatype(::Type{ThriftMap{K,V}}) where {K,V} = OrderedDict{juliatype(K),juliatype(V)}
thrifttype(::Type{OrderedDict{K,V}}) where {K,V} = ThriftMap(thrifttype(K), thrifttype(V))
_thrifttype(::Type{OrderedDict{K,V}}) where {K,V} = ThriftMap(_thrifttype(K), _thrifttype(V))

abstract type ThriftSetlike{T<:ThriftType} <:ThriftType end
    
struct ThriftSet{T<:ThriftType} <: ThriftSetlike{T}
    eltype::T
end
juliatype(::Type{ThriftSet{T}}) where {T} = OrderedSet{juliatype(T)}
thrifttype(::Type{OrderedSet{T}}) where {T} = ThriftSet(thrifttype(T))
_thrifttype(::Type{OrderedSet{T}}) where {T} = ThriftSet(_thrifttype(T))

struct ThriftList{T<:ThriftType} <: ThriftSetlike{T}
    eltype::T
end
juliatype(::Type{ThriftList{T}}) where {T} = Vector{juliatype(T)}
thrifttype(::Type{Vector{T}}) where {T} = ThriftList(thrifttype(T))
_thrifttype(::Type{Vector{T}}) where {T} = ThriftList(_thrifttype(T))

struct ThriftUnknown <: ThriftType end

# we don't take nullity into account for thrifttype
thrifttype(::Type{Union{T,Nothing}}) where {T} = thrifttype(T)

# this can get used for missing or placeholder fields
thrifttype(::Type{Nothing}) = ThriftUnknown()
_thrifttype(::Type{Nothing}) = ThriftUnknown()

juliatype(t::ThriftType) = juliatype(typeof(t))
thrifttype(x) = thrifttype(typeof(x))
# the below method is so that the above method doesn't lead to stack overflows
thrifttype(::Type{T}) where {T} = throw(ArgumentError("no thrift type corresponding to type $T"))
thrifttype(x::Bool) = ThriftBool{x}()

"""
    encodetype(CompactProtocol, t::ThrifType)

Return the thrift compact protocol encoding integer corresponding to the type `t`.
"""
function encodetype(::Type{<:CompactProtocol}, t::T) where {T<:ThriftType}
    if T == ThriftInt8
        3
    elseif T == ThriftInt16
        4
    elseif T == ThriftInt32 || T <: ThriftEnum
        5
    elseif T == ThriftInt64
        6
    elseif T == ThriftFloat64
        7
    elseif T <: ThriftBinary
        8
    elseif T <: ThriftList
        9
    elseif T <: ThriftSet
        10
    elseif T <: ThriftMap
        11
    elseif T <: ThriftStruct
        12
    elseif T <: ThriftBool
        2 - valueof(T)
    else
        throw(ArgumentError("thrift type $t is invalid"))
    end
end

"""
    decodetype(CompactProtocol, a::Integer)::Type

Return the thrift type corresponding to the code `a` according to the thrift compact
protocol.  Note that this returns a type `T <: ThriftType` and *not* an instance of
the type metadata object.  This is because, in the general case, it is impossible to infer
the exact type from this code alone.
"""
function decodetype(::Type{<:CompactProtocol}, a::Integer)::Type
    if a == 1
        ThriftBool{true}
    elseif a == 2
        ThriftBool{false}
    elseif a == 3
        ThriftInt8
    elseif a == 4
        ThriftInt16
    elseif a == 5  # not dealing with enums properly but should never need to
        ThriftInt32
    elseif a == 6
        ThriftInt64
    elseif a == 7
        ThriftFloat64
    elseif a == 8
        ThriftBinary
    elseif a == 9
        ThriftList
    elseif a == 10
        ThriftSet
    elseif a == 11
        ThriftMap
    elseif a == 12
        ThriftStruct
    else
        throw(ArgumentError("got invalid thrift type code: $a"))
    end
end

"""
    thriftfieldtype(ThriftStruct{T}, n)

Returns the thrift type of the `n`th field of the struct `T`.  `n` can also be a `Val` to ensure
that this function can be evaluated at compile time.
"""
thriftfieldtype(::Type{<:ThriftStruct{<:T}}, n::Integer) where {T} = thriftfieldtype(ThriftStruct{T}, Val(n))

abstract type ThriftError <: Exception end
abstract type ThriftReadError <: ThriftError end
abstract type ThriftWriteError <: ThriftError end


include("read.jl")
include("write.jl")
include("codegen.jl")


export CompactProtocol, @thriftstruct


end
