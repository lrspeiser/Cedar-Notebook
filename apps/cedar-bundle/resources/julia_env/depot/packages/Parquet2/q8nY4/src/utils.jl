
n_padding_bytes(n::Integer) = ALIGNMENT*cld(n, ALIGNMENT) - n

"""
    writepadded(io, x)

Like `write(io, x)` but fills with 0-padding up to 8-byte alignment.
"""
function writepadded(io::IO, x)
    n = write(io, x)
    # note doing this instead of seek is deliberate to support all IO types
    for i ∈ 1:n_padding_bytes(n)
        n += write(io, 0x00)
    end
    n
end

"""
    fixedpos(𝒻, io)

Call `𝒻(io)` and reset to the original position.  Requires `mark` and `reset`.
"""
function fixedpos(𝒻, io::IO)
    mark(io)
    o = 𝒻(io)
    reset(io)
    o
end

"""
    thriftget(x, s, d)

Unbelievably, this is not already a function made available by Thrift.jl.
"""
function thriftget(x, s, d)
    o = getfield(x, s)
    isnothing(o) ? d : o
end

"""
    unpack_thrift_metadata(obj)

Unpack the metadata stored in the `key_value_metadata` field of a thrift object.  This attempts to
parse values as JSON's since this is a common practice.
"""
function unpack_thrift_metadata(obj)
    kv = thriftget(obj, :key_value_metadata, nothing)
    isnothing(kv) && return Dict{String,Any}()
    Dict{String,Union{String,Nothing}}(κ.key=>thriftget(κ, :value, nothing) for κ ∈ kv)
end
unpack_thrift_metadata(::Nothing) = Dict{String,Union{String,Nothing}}()

"""
    pack_thrift_metadata(dict)

Pack the dictionary `dict` into a form which can be serialized as Thrift key-value metadata.  All values are
converted to strings using `JSON3.write`.
"""
pack_thrift_metadata(d::AbstractDict) = [Meta.KeyValue(p) for p ∈ d]

"""
    convertnothing(𝒯, x)

Converts to `𝒯`, unless `nothing`, in which case return `nothing`.  Useful for some thrift output.
"""
convertnothing(::Type{𝒯}, x) where {𝒯} = convert(𝒯, x)
convertnothing(::Type, ::Nothing) = nothing

"""
    readthriftδ(io, 𝒯)

Read the thrift typte `𝒯` returning `o, δ` where `o` is the object read and `δ` is the number of bytes read.
"""
function readthriftδ(io, ::Type{T}) where {T}
    n = position(io)
    o = read(CompactProtocol(io), T)
    δ = position(io) - n
    (o, δ)
end

"""
    vcat_check_single(vs)

If `vs` has more than one element, return a lazily concatenated array, otherwise, return the only element.
"""
vcat_check_single(vs) = length(vs) == 1 ? first(vs) : ChainedVector(vs)

"""
    concat_integer(v::AbstractVector)

Compute a 64 bit integer by concatenating the bits in `v`.
"""
function concat_integer(v::AbstractVector)
    length(v) > 8 && (v = @view v[(end-7):end])
    o = Int64(0)
    for (idx, i) ∈ zip(length(v):-1:1, 1:length(v))
        x = Int64(v[idx]) << (8*(i-1))
        o = o | x
    end
    o
end

"""
    int2staticarray(x)

Express the integer `x` as a static array.
"""
int2staticarray(x::Integer) = SVector(ntuple(n -> UInt8(0xff & (x >> 8(n - 1))), sizeof(x)))

"""
    staticarray2int(UInt128, v)

Convert a `StaticVector{16,UInt128}` to a `UInt128`.  This is the inverse of `int2staticarray`.
"""
function staticarray2int(::Type{UInt128}, v::StaticVector{16,UInt8})
    x = UInt128(0)
    for n ∈ 1:length(v)
        x = x | (Int128(v[n]) << 8(n - 1))
    end
    x
end

"""
    ntablerows(tbl)

Return the number of rows in an object implementing the Tables.jl interface.
"""
ntablerows(tbl) = length(Tables.rowaccess(tbl) ? Tables.rows(tbl) : Tables.getcolumn(tbl, 1))

"""
    ntablecolumns(tbl)

Return the number of columns in an object implementing the Tables.jl interface.
"""
function ntablecolumns(tbl)
    sch = Tables.schema(tbl)
    length(isnothing(sch) ? Tables.columnnames(tbl) : sch.names)
end

"""
    parqrefs(v::AbstractVector)

For a categorical vector `v`, return the array of references that would be used to represent it in
a dictionary encoding in the parquet format.  This requires that `v` satisfies the `DataAPI`
reference array interface.  Note that the number of elements in the output is not deterministic
since `missing` elements are skipped.
"""
function parqrefs(v::AbstractVector{>:Missing}, r::AbstractVector=DataAPI.refarray(v))
    o = Vector{UInt32}(undef, length(r))
    k = 1
    for i ∈ 1:length(r)
        ismissing(DataAPI.refvalue(v, r[i])) && continue
        o[k] = r[i] - 1
        k += 1
    end
    resize!(o, k-1)
end
parqrefs(v::AbstractVector, r::AbstractVector=DataAPI.refarray(v)) = convert(Vector{UInt32}, r .- 1)

"""
    isparent(p::AbstractPath, q::AbstractPath)

Returns true if `p` is a parent of `q` (not necessarily a direct parent), else false.
"""
function isparent(p::𝒫, q::𝒫) where {𝒫<:AbstractPath}
    p.drive == q.drive || return false
    p.root == q.root || return false
    length(q.segments) ≥ length(p.segments) || return false
    for (i, s) ∈ enumerate(p.segments)
        q[i] == s || return false
    end
    true
end

"""
    pathparent(p::AbstractPath)

Find the immediate parent of path `p`.  As of writing, this is much more efficient than `parent` in
FilePathsBase.
"""
function pathparent(p::AbstractPath)
    hasparent(p) || return nothing
    Path(p; segments=p.segments[1:(length(p.segments)-1)])
end

#====================================================================================================
    NOTE:

The hash method for `AbstractUnitRange`s in Base is written such that it is consistent with other
`AbstractVector` types.  We don't want that here, because it's O(n) which is totally
unacceptable for us.  Therefore, we have to implement the below.
====================================================================================================#
struct HashableUnitRange{𝒯<:Integer} <: AbstractUnitRange{𝒯}
    start::𝒯
    stop::𝒯
end

HashableUnitRange{𝒯}(r::AbstractUnitRange) where {𝒯<:Integer} = HashableUnitRange{𝒯}(first(r), last(r))

HashableUnitRange(r::AbstractUnitRange) = HashableUnitRange{eltype(r)}(first(r), last(r))

Base.size(r::HashableUnitRange) = (r.stop - r.start + one(eltype(r)),)

Base.IndexStyle(::Type{<:HashableUnitRange}) = IndexLinear()

function Base.getindex(r::HashableUnitRange, i::Int)
    @boundscheck checkbounds(r, i)
    convert(eltype(r), r.start + i - one(eltype(r)))
end

Base.hash(r::HashableUnitRange, x::UInt) = foldr(hash, (r.start, r.stop, hash(typeof(r))), init=x)

Base.:(∈)(x, r::HashableUnitRange) = r.start ≤ x ≤ r.stop

Base.:(==)(r1::HashableUnitRange, r2::AbstractUnitRange) = (first(r1) == first(r2)) && (last(r1) == last(r2))
#===================================================================================================#


"""
    NameIndex

A data structure for efficiently looking up ordinal values that can be indexed by either integers
or strings.

## Example
```julia
idx = NameIndex(["a", "b", "c"])

idx[Int, 1] == 1
idx[String, 1] == "a"

idx[Int, "b"] == 2
idx[String, "b"] == "b"
```
"""
struct NameIndex
    names::Vector{String}
    rev::Dict{String,Int}
end

NameIndex(names) = NameIndex(names, Dict(names .=> 1:length(names)))

Base.getindex(idx::NameIndex, ::Type{Int}, n::Integer) = Int(n)
Base.getindex(idx::NameIndex, ::Type{String}, n::AbstractString) = String(n)

Base.getindex(idx::NameIndex, ::Type{Int}, n::AbstractString) = idx.rev[n]

Base.getindex(idx::NameIndex, ::Type{String}, n::Integer) = idx.names[n]

Base.names(idx::NameIndex) = idx.names


"""
    RunsIterator

An iterator which will return `Fill` arrays for each contiguous ordered set of like values in the provided
vector.  This is useful for parquet format "run length encoding".

## Example
```julia
◖◗ collect(RunsIterator([1,1,2,2,2,3]))
3-element Vector{Any}:
 2-element Fill{Int64}, with entries equal to 1
 3-element Fill{Int64}, with entries equal to 2
 1-element Fill{Int64}, with entry equal to 3

◖◗ vcat(ans...) == [1,1,2,2,2,3]
true
```
"""
struct RunsIterator{𝒱<:AbstractVector}
    v::𝒱
end

Base.IteratorSize(::Type{<:RunsIterator}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{<:RunsIterator}) = Base.HasEltype()
Base.eltype(ri::RunsIterator) = Fill{eltype(ri.v),1,Tuple{Base.OneTo{Int}}}

function Base.iterate(ri::RunsIterator, s=1)
    s > length(ri.v) && return nothing
    x = ri.v[s]
    r = 1  # number of instances seen
    s += 1
    while s ≤ length(ri.v)
        if ri.v[s] == x
            r, s = (r+1, s+1)
        else
            break
        end
    end
    Fill(x, r), s
end
