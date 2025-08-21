module DefineSingletons

# Use README as the docstring of the module:
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    replace(read(path, String), r"^```julia"m => "```jldoctest README")
end DefineSingletons

export @def_singleton

"""
    @def_singleton singleton_name
    @def_singleton singleton_name::SingletonType
    @def_singleton singleton_name::SingletonType <: SuperType
    @def_singleton singleton_name isa SuperType
    @def_singleton singleton_name = SingletonType()

Define a singleton named `singleton_name` and its two-argument
`show(::IO, ::SingletonType)` method.

With the form `singleton_name = SingletonType()`, the type
`SingletonType` can be a parametric type as long as
`Base.issingletontype(SingletonType)` is `true`.

# Examples
```jldoctest
julia> using DefineSingletons

julia> @def_singleton mysingleton::MySingletonType;

julia> mysingleton
mysingleton

julia> mysingleton isa MySingletonType
true

julia> mysingleton === MySingletonType()
true
```

With supertype:

```jldoctest; setup = :(using DefineSingletons)
julia> abstract type MySuperType end;

julia> @def_singleton mysingleton2::MySingletonType2 <: MySuperType;

julia> mysingleton2
mysingleton2

julia> mysingleton2 isa MySingletonType2
true

julia> MySingletonType2 <: MySuperType
true

julia> @def_singleton mysingleton3 isa MySuperType;

julia> mysingleton3 isa MySuperType
true
```

With pre-existing parametric type:

```jldoctest; setup = :(using DefineSingletons)
julia> struct MyParametricType{T} end;

julia> @def_singleton P1 = MyParametricType{1}();

julia> P1
P1

julia> P1 isa MyParametricType{1}
true
```
"""
macro def_singleton(ex)
    ans = handle_gentype(ex)
    ans === nothing || return ans
    ans = handle_predefined(ex)
    ans === nothing || return ans
    throw(ArgumentError("invalid input: $ex"))
end

function handle_gentype(ex)
    super_type = Any
    type_name = nothing
    if ex isa Symbol
        singleton_name = ex
    elseif Meta.isexpr(ex, :(::), 2)
        singleton_name, type_name = ex.args
        if Meta.isexpr(type_name, :(<:), 2)
            type_name, super_type = type_name.args
        end
    elseif Meta.isexpr(ex, :(<:), 2)
        x, super_type = ex.args
        if Meta.isexpr(x, :(::), 2)
            singleton_name, type_name = x.args
        else
            return nothing
        end
    elseif Meta.isexpr(ex, :call, 3) && ex.args[1] === :isa
        _, singleton_name, super_type = ex.args
    else
        return nothing
    end
    if type_name === nothing
        type_name = gensym(string("typeof_", singleton_name))
    end
    show_def = define_show(singleton_name, type_name)
    singleton_name = esc(singleton_name)
    type_name = esc(type_name)
    super_type = super_type isa Type ? super_type : esc(super_type)
    quote
        struct $type_name <: $super_type end
        const $singleton_name = $type_name()
        $show_def
        $singleton_name
    end
end

function handle_predefined(ex)
    if Meta.isexpr(ex, :(=), 2)
        singleton_name, type_call = ex.args
        if Meta.isexpr(type_call, :call, 1)
            type_name, = type_call.args
        else
            return nothing
        end
    else
        return nothing
    end
    show_def = define_show(singleton_name, type_name)
    singleton_name = esc(singleton_name)
    type_name = esc(type_name)
    quote
        const $singleton_name = $type_name()
        $show_def
        $singleton_name
    end
end

function define_show(singleton_name::Symbol, type_name)
    type_name = esc(type_name)
    quote
        Base.show(io::IO, ::$type_name) = DefineSingletons.show_impl(
            io,
            parentmodule($type_name),
            $(QuoteNode(singleton_name)),
        )
        Base.print(io::IO, ::$type_name) = print(io, $(QuoteNode(singleton_name)))
    end
end

function show_impl(io::IO, namespace::Module, singleton_name::Symbol)
    if !get(io, :limit, false)
        # Don't show full name in REPL etc.:
        print(io, namespace, '.')
    end
    print(io, singleton_name)
end

end # module
