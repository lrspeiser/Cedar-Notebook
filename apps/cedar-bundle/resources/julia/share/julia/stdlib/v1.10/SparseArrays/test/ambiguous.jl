# This file is a part of Julia. License is MIT: https://julialang.org/license

###
# We'll restore the original env at the end of this testgroup.
original_depot_path = copy(Base.DEPOT_PATH)
original_load_path = copy(Base.LOAD_PATH)
original_env = copy(ENV)
###

import Pkg

# Because julia CI doesn't run stdlib tests via `Pkg.test` test deps must be manually installed if missing
if Base.find_package("Aqua") === nothing
    @debug "Installing Aqua.jl for SparseArrays.jl tests"
    iob = IOBuffer()
    try
        # TODO: make this version tie to compat in Project.toml
        # or do this another safer way
        Pkg.add(name="Aqua", version="0.8", io=iob) # Needed for custom julia version resolve tests
    catch
        println(String(take!(iob)))
        rethrow()
    end
end

using Test, LinearAlgebra, SparseArrays, Aqua

@testset "code quality" begin
    @testset "Method ambiguity" begin
        Aqua.test_ambiguities([SparseArrays, Base, Core])
    end
    @testset "Unbound type parameters" begin
        @test_broken Aqua.detect_unbound_args_recursively(SparseArrays) == []
    end
    @testset "Undefined exports" begin
        Aqua.test_undefined_exports(SparseArrays)
    end
    @testset "Compare Project.toml and test/Project.toml" begin
        Aqua.test_project_extras(SparseArrays)
    end
    @testset "Stale dependencies" begin
        Aqua.test_stale_deps(SparseArrays)
    end
    @testset "Compat bounds" begin
        Aqua.test_deps_compat(SparseArrays)
    end

    @testset "Piracy" begin
        @test_broken Aqua.Piracy.hunt(SparseArrays) == Method[]
    end
end

let ambig = detect_ambiguities(SparseArrays; recursive=true)
    @test isempty(ambig)
    ambig = Set{Any}(((m1.sig, m2.sig) for (m1, m2) in ambig))
    expect = []
    good = true
    while !isempty(ambig)
        sigs = pop!(ambig)
        i = findfirst(==(sigs), expect)
        if i === nothing
            println(stderr, "push!(expect, (", sigs[1], ", ", sigs[2], "))")
            good = false
            continue
        end
        deleteat!(expect, i)
    end
    @test isempty(expect)
    @test good
end

## This was the older version that was disabled

# let ambig = detect_ambiguities(SparseArrays; recursive=true)
#     @test isempty(ambig)
#     ambig = Set{Any}(((m1.sig, m2.sig) for (m1, m2) in ambig))
#     expect = []
#     good = true
#     while !isempty(ambig)
#         sigs = pop!(ambig)
#         i = findfirst(==(sigs), expect)
#         if i === nothing
#             println(stderr, "push!(expect, (", sigs[1], ", ", sigs[2], "))")
#             good = false
#             continue
#         end
#         deleteat!(expect, i)
#     end
#     @test isempty(expect)
#     @test good
# end

###
# Now we restore the original env, as promised
empty!(Base.DEPOT_PATH)
empty!(Base.LOAD_PATH)
append!(Base.DEPOT_PATH, original_depot_path)
append!(Base.LOAD_PATH, original_load_path)

for k in setdiff(collect(keys(ENV)), collect(keys(original_env)))
    delete!(ENV, k)
end
for (k, v) in pairs(original_env)
    ENV[k] = v
end
###
