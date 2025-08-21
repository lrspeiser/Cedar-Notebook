module TestDefineSingletons

using DefineSingletons
using Documenter: doctest
using Test

abstract type SuperType end
struct NonparametricSingleton end
struct ParametricSingleton{T} end

@def_singleton singleton_gentype_gensym
@def_singleton singleton_gentype_withname::GenTypeName
@def_singleton singleton_gentype_withsuper1::GenSubTypeName1 <: SuperType
@def_singleton singleton_gentype_withsuper2::(GenSubTypeName2 <: SuperType)
@def_singleton singleton_gentype_withsuper3 isa SuperType
@def_singleton singleton_predefined_nonparametric = NonparametricSingleton()
@def_singleton singleton_predefined_parametric = ParametricSingleton{1}()

issingleton(x) = Base.issingletontype(typeof(x))

@testset "DefineSingletons.jl" begin
    @test issingleton(singleton_gentype_gensym)
    @test issingleton(singleton_gentype_withname)
    @test issingleton(singleton_gentype_withsuper1)
    @test issingleton(singleton_gentype_withsuper2)
    @test issingleton(singleton_gentype_withsuper3)
    @test issingleton(singleton_predefined_nonparametric)
    @test issingleton(singleton_predefined_parametric)

    @test singleton_gentype_withname isa GenTypeName
    @test singleton_gentype_withsuper1 isa GenSubTypeName1
    @test singleton_gentype_withsuper2 isa GenSubTypeName2
    @test singleton_gentype_withsuper3 isa SuperType
    @test GenSubTypeName1 <: SuperType
    @test GenSubTypeName2 <: SuperType

    kw = (; context = :limit => true)
    @test repr(singleton_gentype_gensym; kw...) === "singleton_gentype_gensym"
    @test repr(singleton_gentype_withname; kw...) === "singleton_gentype_withname"
    @test repr(singleton_gentype_withsuper1; kw...) === "singleton_gentype_withsuper1"
    @test repr(singleton_gentype_withsuper2; kw...) === "singleton_gentype_withsuper2"
    @test repr(singleton_gentype_withsuper3; kw...) === "singleton_gentype_withsuper3"
    @test repr(singleton_predefined_nonparametric; kw...) ===
          "singleton_predefined_nonparametric"
    @test repr(singleton_predefined_parametric; kw...) === "singleton_predefined_parametric"

    @test endswith(repr(singleton_gentype_gensym), ".singleton_gentype_gensym")
    @test endswith(repr(singleton_gentype_withname), ".singleton_gentype_withname")
    @test endswith(repr(singleton_gentype_withsuper1), ".singleton_gentype_withsuper1")
    @test endswith(repr(singleton_gentype_withsuper2), ".singleton_gentype_withsuper2")
    @test endswith(repr(singleton_gentype_withsuper3), ".singleton_gentype_withsuper3")
    @test endswith(
        repr(singleton_predefined_nonparametric),
        ".singleton_predefined_nonparametric",
    )
    @test endswith(
        repr(singleton_predefined_parametric),
        ".singleton_predefined_parametric",
    )

    @test string(singleton_gentype_gensym) == "singleton_gentype_gensym"
    @test string(singleton_gentype_withname) == "singleton_gentype_withname"
    @test string(singleton_gentype_withsuper1) == "singleton_gentype_withsuper1"
    @test string(singleton_gentype_withsuper2) == "singleton_gentype_withsuper2"
    @test string(singleton_gentype_withsuper3) == "singleton_gentype_withsuper3"
    @test string(singleton_predefined_nonparametric) == "singleton_predefined_nonparametric"
    @test string(singleton_predefined_parametric) == "singleton_predefined_parametric"
end

@testset "doctest" begin
    doctest(DefineSingletons; manual = false)
end

end  # module
