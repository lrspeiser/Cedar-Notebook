using Thrift2
using Thrift2: CompactProtocol

samplespath() = joinpath(@__DIR__,"samples")

samplename(T, ::Val{n}) where {n}  = string(last(split(string(T), ".")), n, ".thrift")

getsample(T, v::Val{n}) where {n} = open(read, joinpath(samplespath(),samplename(T, v)))
getsample(T, n::Integer=1) = getsample(T, Val(n))

readsample(::Type{T}, v::Val{n}) where {T,n} = read(CompactProtocol(getsample(T, v)), T)
readsample(::Type{T}, n::Integer=1) where {T} = readsample(T, Val(n))
