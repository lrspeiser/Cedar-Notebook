# DefineSingletons

[![GitHub Actions](https://github.com/tkf/DefineSingletons.jl/workflows/Run%20tests/badge.svg)](https://github.com/tkf/DefineSingletons.jl/actions?query=workflow%3A%22Run+tests%22)

Define singleton and it's pretty-printing `show` in one go:

```julia
julia> using DefineSingletons

julia> @def_singleton mysingleton;

julia> mysingleton
mysingleton

julia> Base.issingletontype(typeof(mysingleton))
true
```

See more in the docstring of `@def_singleton`.
