import Pkg; Pkg.activate("parquet-dev", shared=true)
include("ParquetMetadata/Metadata.jl")
import .Metadata; const Meta = Metadata
using Thrift2, MacroTools
using Thrift2: CompactProtocol, readfield
using MacroTools, BenchmarkTools

@thriftstruct struct Struct1
    x::Int
    y::Vector{String}
end

@thriftstruct struct Struct2
    x::Int
    y::Vector{String}
    z::Union{Nothing,Vector{Struct1}} = nothing
end


function makebenchbuf()
    p = CompactProtocol(IOBuffer())
    Struct1(7, 7.0)
    write(p, Struct1(7, 7.0))
    seekstart(p)
    p
end

function benchmark1()
    @benchmark read(p, Struct1) setup=(p=makebenchbuf()) evals=1
end


src1() = quote
    io = IOBuffer()
    p = CompactProtocol(io)

    t1 = Struct1(2, ["hello", "there"])

    t2 = Struct2(3, ["what"], [Struct1(4, []), Struct1(5, ["testing", "again"])])

    write(p, t2)
    write(p, t1)
    buf = take!(copy(p.io))
    seekstart(p)

    t1′ = read(p, Struct1)
    t2′ = read(p, Struct1)
end

src2() = quote
    t = Meta.LogicalType(INTEGER=Meta.IntType(0x08, false))
    p = CompactProtocol(IOBuffer())
    write(p, t)
    seekstart(p)
end

wtf1() = quote
    io = IOBuffer(UInt8[0x00])
    p = CompactProtocol(io)
end
