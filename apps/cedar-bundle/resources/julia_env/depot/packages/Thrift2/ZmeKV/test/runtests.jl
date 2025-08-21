using Thrift2
using Test

include("sampledecs.jl")
include("utils.jl")


#WARN: need to set up testing reading with apache thrift via PythonCall!!


const TEST_TYPES = (SchemaElement, PageHeader, ColumnMetaData, Column, RowGroup, FileMetaData)


function writetest(T)
    p = CompactProtocol()
    s = sample(T)
    write(p, s)
    seekstart(p)
    read(p, T) == s
end


# these are structs that are supposed to be backward compatible with each other
@thriftstruct struct Struct1
    x::Int
    y::Vector{String}
end

@thriftstruct struct Struct2
    x::Int
    y::Vector{String}
    z::Union{Nothing,Vector{Struct1}} = nothing
end


@testset "Thrift2.jl" begin
    @testset "read" begin
        for T ∈ TEST_TYPES
            @test readsample(T) == sample(T)
        end
    end
    @testset "write" begin
        for T ∈ TEST_TYPES
            @test writetest(T)
        end

        p = CompactProtocol()
        # it's not necessarily *wrong* for these to change but you should be *very* careful if they do!
        @test write(p, sample(PageHeader, Val(1))) == 36
        @test write(p, sample(SchemaElement, Val(1))) == 27
        @test write(p, sample(Column, Val(1))) == 53
    end
    @testset "compat" begin
        t1 = Struct1(2, ["kirk", "spock"])
        t2 = Struct2(3, ["bones"], [Struct1(4, []), Struct1(4, ["uhura", "scotty"])])
        p = CompactProtocol()
        write(p, t1)
        write(p, t2)
        seekstart(p)

        t1′ = read(p, Struct1)
        t2′ = read(p, Struct1)
        @test t1′ == t1
        @test t2′ == Struct1(3, ["bones"])

        seekstart(p)

        t1′ = read(p, Struct2)
        t2′ = read(p, Struct2)
        @test t1′ == Struct2(2, ["kirk", "spock"], nothing)
        @test t2′ == t2

        p = CompactProtocol()
        write(p, t2)
        write(p, t1)
        seekstart(p)

        t2′ = read(p, Struct1)
        t1′ = read(p, Struct1)
        @test t2′ == Struct1(3, ["bones"])
        @test t1′ == t1

        seekstart(p)

        t2′ = read(p, Struct2)
        t1′ = read(p, Struct2)
        @test t2′ == t2
        @test t1′ == Struct2(2, ["kirk", "spock"], nothing)
    end
end
