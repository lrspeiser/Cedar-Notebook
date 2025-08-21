module FNVHash

export fnv1, fnv1a, fnv_offset_basis, fnv_prime

const FNVInt = Union{UInt32, UInt64, UInt128}

@inline fnv_offset_basis(::Type{UInt32}) = 0x811c9dc5
@inline fnv_offset_basis(::Type{UInt64}) = 0xcbf29ce484222325
@inline fnv_offset_basis(::Type{UInt128}) = 0x6c62272e07bb014262b821756295c58d

@inline fnv_prime(::Type{UInt32}) = 0x01000193
@inline fnv_prime(::Type{UInt64}) = 0x00000100000001B3
@inline fnv_prime(::Type{UInt128}) = 0x0000000001000000000000000000013B

"""
    fnv1(T, p::Ptr{UInt8}, n::Integer)
    fnv1(T, x::Union{String, DenseVector{UInt8}})

Calculate the Fowler-Noll-Vo version 1 hash of the input for the bitwidth defined by T. T must unsigned.
"""
function fnv1 end

"""
    fnv1a(T, p::Ptr{UInt8}, n::Integer)
    fnv1a(T, x::Union{String, DenseVector{UInt8}})

Calculate the Fowler-Noll-Vo version 1a hash of the input for the bitwidth defined by T. T must unsigned.
"""
function fnv1a end

function fnv1(::Type{T}, p::Ptr{UInt8}, n::Integer) where T <: FNVInt
    h = fnv_offset_basis(T)
    for i in 1:n
        x = unsafe_load(p, i)
        h = (h * fnv_prime(T)) ⊻ x
    end
    h
end

function fnv1a(::Type{T}, p::Ptr{UInt8}, n::Integer) where T <: FNVInt
    h = fnv_offset_basis(T)
    for i in 1:n
        x = unsafe_load(p, i)
        h = (h ⊻ x) * fnv_prime(T)
    end
    h
end

fnv1(::Type{T}, s::Union{String, DenseVector{UInt8}}) where T <: FNVInt = GC.@preserve s fnv1(T, pointer(s), sizeof(s))
fnv1a(::Type{T}, s::Union{String, DenseVector{UInt8}}) where T <: FNVInt = GC.@preserve s fnv1a(T, pointer(s), sizeof(s))

end
