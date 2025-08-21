using FNVHash
using Test

@testset "FNVHash.jl" begin

@testset "type $T" for T in [UInt32, UInt64, UInt128] 
    @test fnv1(T, "test") isa T
    @test fnv1a(T, "test") isa T
end

@testset "empty $T" for T in [UInt32, UInt64, UInt128]
    @test fnv1(T, "") == fnv_offset_basis(T)
    @test fnv1a(T, "") == fnv_offset_basis(T)
end

@testset "vector/string equivalence $T" for T in [UInt32, UInt64, UInt128]
    data = UInt8['a', 'b', 'c']
    s = String(copy(data))
    @test fnv1(T, data) == fnv1(T, s)
    @test fnv1a(T, data) == fnv1a(T, s)
end

@testset "changing $T" for T in [UInt32, UInt64, UInt128]
    @test fnv1(T, "test") != fnv1(T, "tesu")
    @test fnv1a(T, "test") != fnv1a(T, "tesu")
end

end
