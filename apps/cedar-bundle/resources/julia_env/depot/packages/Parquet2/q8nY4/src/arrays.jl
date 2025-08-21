
"""
    BitUnpackVector{𝒯}

A vector type that unpacks underlying data into values of type `𝒯` when indexed.
"""
struct BitUnpackVector{𝒯,𝒱<:AbstractArray{UInt8}} <: AbstractVector{𝒯}
    data::𝒱
    width::Int
    length::Int
end

function BitUnpackVector{𝒯}(v::AbstractVector{UInt8}, width::Integer, ℓ::Integer=fld(8*length(v), width)) where {𝒯}
    BitUnpackVector{𝒯,typeof(v)}(v, width, ℓ)
end

BitUnpackVector{𝒯}() where {𝒯} = BitUnpackVector{𝒯}(UInt8[], 0, 0)

Base.size(v::BitUnpackVector) = (v.length,)

Base.IndexStyle(::Type{<:BitUnpackVector}) = IndexLinear()

function Base.getindex(v::BitUnpackVector{𝒯}, i::Int) where {𝒯}
    a₀, b₀ = fldmod1((i-1)*v.width+1, 8)
    a₁, b₁ = fldmod1(i*v.width, 8)
    x = zero(𝒯)
    if a₀ == a₁
        return x | bitjustify(@inbounds(v.data[a₀]), b₀, b₁)
    end
    ns = 0
    for α ∈ a₀:a₁
        δ = ns
        if α == a₀
            ns += 8 + 1 - b₀
            @inbounds m = bitjustify(v.data[α], b₀, 8)
        elseif α == a₁
            ns += b₁
            @inbounds m = bitjustify(v.data[α], 1, b₁)
        else
            ns += 8
            @inbounds m = v.data[α]
        end
        x = x | (𝒯(m) << δ)
    end
    x
end


"""
    StringViewVector <: AbstractVector

A 1-dimensional array of byte views (`AbstractVector{UInt8}`) which, when indexed, will return strings.

Note that it is expected that the underlying data elements are some sort of view, since `String` will be called
on them directly, meaning that the data will be "stolen" if it happens to be a `Vector{UInt8}`.  In other words,
don't use this on `Vector{UInt8}`.
"""
struct StringViewVector{𝒯,𝒱,ℛ} <: AbstractVector{𝒯}
    ref::RefValue{ℛ}
    parent::Vector{𝒱}
end

function StringViewVector(v::AbstractVector{𝒱}, ref::Ref{ℛ}=Ref(nothing)) where {𝒱,ℛ}
    𝒯 = eltype(v) >: Missing ? Union{Missing,String} : String
    StringViewVector{𝒯,𝒱,ℛ}(ref, v)
end

Base.parent(v::StringViewVector) = v.parent

Base.size(v::StringViewVector) = size(parent(v))

Base.IndexStyle(::Type{<:StringViewVector}) = IndexLinear()

Base.@propagate_inbounds function Base.getindex(v::StringViewVector, i::Int)
    @boundscheck checkbounds(v, i)
    @inbounds String(v.parent[i])
end

Base.@propagate_inbounds function Base.getindex(v::StringViewVector{Union{Missing,𝒯}}, i::Int) where {𝒯}
    @boundscheck checkbounds(v, i)
    @inbounds o = v.parent[i]
    ismissing(o) ? missing : String(o)
end


"""
    PooledVector <: AbstractVector

A simple implementation of a "pooled" (or "dictionary encoded) rank-1 array, providing read-only access.
The underlying references and value pool are required to have the form naturally returned when reading
from a parquet.
"""
struct PooledVector{𝒯,ℛ<:AbstractVector{<:Union{Integer,Missing}},𝒱} <: AbstractVector{𝒯}
    pool::𝒱
    refs::ℛ
end

PooledVector{𝒯}(vs, rs) where {𝒯} = PooledVector{𝒯,typeof(rs),typeof(vs)}(vs, rs)
function PooledVector(vs, rs)
    𝒯 = eltype(rs) >: Missing ? Union{eltype(vs),Missing} : eltype(vs)
    PooledVector{𝒯}(vs, rs)
end

Base.size(v::PooledVector) = size(v.refs)

Base.IndexStyle(::Type{<:PooledVector}) = IndexLinear()

function DataAPI.refarray(v::PooledVector) 
    # we deliberately use UInt64 so that we never run out of integers
    k = UInt64(eltype(v) >: Missing)
    BroadcastVector(1:length(v.refs)) do j
        ismissing(v.refs[j]) ? k : UInt64(v.refs[j]+k+1)
    end
end
DataAPI.refpool(v::PooledVector) = v.pool
function DataAPI.refpool(v::PooledVector{>:Missing})
    o = Vector{eltype(v)}(undef, length(v.pool)+1)
    o[1] = missing
    for j ∈ 2:length(o)
        o[j] = v.pool[j-1]
    end
    o
end
DataAPI.levels(v::PooledVector) = v.pool

Base.@propagate_inbounds function Base.getindex(v::PooledVector, i::Int)
    @boundscheck checkbounds(v, i)
    @inbounds v.pool[v.refs[i]+1]
end

Base.@propagate_inbounds function Base.getindex(v::PooledVector{>:Missing}, i::Int)
    @boundscheck checkbounds(v, i)
    @inbounds ismissing(v.refs[i]) ? missing : v.pool[v.refs[i]+1]
end


"""
    parqpool(v::AbstractVector)

Create a categorical array value pool from `v` appropriate for serialization to parquet.
"""
parqpool(v::AbstractVector) = unique(skipmissing(v))

"""
    ParqRefVector <: AbstractVector

An array wrapper for an `AbstractVector` which acts as a reference array for the wrapped vector
for its dictionary encoding.

Indexing this returns a `UInt32` reference, unless the underlying vector is `missing` at that
index, in which case it returns `missing`.
"""
struct ParqRefVector{𝒯,𝒮,𝒱<:AbstractVector} <: AbstractVector{𝒯}
    orig::𝒱
    invpool::OrderedDict{𝒮,UInt32}
end

function ParqRefVector(v::AbstractVector, pool=parqpool(v))
    𝒯 = eltype(v) >: Missing ? Union{UInt32,Missing} : UInt32
    𝒮 = nonmissingtype(eltype(v))
    invpool = OrderedDict(pool .=> UInt32.(0:(length(pool)-1)))
    ParqRefVector{𝒯,nonmissingtype(eltype(v)),typeof(v)}(v, invpool)
end

getpool(r::ParqRefVector) = collect(keys(r.invpool))

Base.parent(r::ParqRefVector) = r.orig
Base.size(r::ParqRefVector) = size(parent(r))
Base.IndexStyle(::Type{<:ParqRefVector}) = IndexLinear()

Base.@propagate_inbounds function Base.getindex(r::ParqRefVector, i::Int)
    @boundscheck checkbounds(r, i)
    @inbounds r.invpool[r.orig[i]]
end
Base.@propagate_inbounds function Base.getindex(r::ParqRefVector{>:Missing}, i::Int)
    @boundscheck checkbounds(r, i)
    @inbounds ismissing(r.orig[i]) ? missing : r.invpool[r.orig[i]]
end


"""
    StringRefVector{𝒯,𝒮} <: AbstractVector{𝒯}

An array (typically of strings) that stores references to buffers to keep them form being garbage collected.
The main use case for this is to allow safely storing an array of `WeakRefString` which need not all
point to the same buffer.
"""
struct StringRefVector{𝒯,𝒮} <: AbstractVector{𝒯}
    refs::Set{Ref}  # shouldn't need to be type-specific as its never accessed
    data::Vector{𝒮}
end

Base.size(v::StringRefVector) = size(v.data)
Base.IndexStyle(::Type{<:StringRefVector}) = IndexLinear()

addref!(v::StringRefVector, r::Ref) = push!(v.refs, r)

Base.@propagate_inbounds function Base.getindex(r::StringRefVector, i::Int)
    @boundscheck checkbounds(r, i)
    @inbounds convert(eltype(r), r.data[i])
end

Base.@propagate_inbounds function Base.getindex(r::StringRefVector{>:Missing}, i::Int)
    @boundscheck checkbounds(r, i)
    @inbounds ismissing(r.data[i]) ? missing : convert(eltype(r), r.data[i])
end


"""
    PageBuffer

Represents a view into a byte buffer that guarantees the underlying data is a `Vector{UInt8}`.
"""
struct PageBuffer
    v::Buffer
    a::Int
    b::Int
end

Base.view(pb::PageBuffer, δ::Integer=0) = view(pb.v, (pb.a + δ):pb.b)

Base.firstindex(pb::PageBuffer) = pb.a
Base.lastindex(pb::PageBuffer) = pb.b

Base.length(pb::PageBuffer) = pb.b - pb.a + 1
