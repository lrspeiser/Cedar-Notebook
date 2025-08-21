
function _gencode_readfield_check!(sofar, T::Type, names, name::Symbol, ftype)
    rhs = :(readfield(p, s, $ftype))
    push!(sofar, name)
    id = length(sofar)
    :((s, $name) = readfield(p, s, Val($id), $ftype))
end


function _gencode_readfield_checks(T::Type)
    names = fieldnames(T)
    ftypes = fieldtypes(T)
    sofar = Symbol[]
    map(zip(names, ftypes)) do (name, ftype)
        tftype = typeof(_thrifttype(ftype))
        _gencode_readfield_check!(sofar, T, names, name, tftype)
    end
end

# the only reason this exists is to output the code of the below generated function
function _troubleshoot_read(p::CompactProtocol, ::Type{ThriftStruct{T}}) where {T}
    init = :(s = init(StructReadState, p))
    checks = _gencode_readfield_checks(T)
    skip = :(skipremainingstruct(p, s))
    final = :($T(;$(fieldnames(T)...)))
    Expr(:block, init, checks..., skip, final)
end

@generated function Base.read(p::CompactProtocol, ::Type{ThriftStruct{T}}) where {T}
    init = :(s = init(StructReadState, p))
    checks = _gencode_readfield_checks(T)
    skip = :(skipremainingstruct(p, s))
    final = :($T(;$(fieldnames(T)...)))
    Expr(:block, init, checks..., skip, final)
end


"""
    @thriftstruct struct_declaration

A macro which declares a struct and generates all code necessary for a struct that can be serialized using the
thrift protocol.  The fields of this struct must be of types which are accommodated by the protocol.
Optional fields of type `T` must be declared with type `Union{Nothing,T}` where `T` is the native
Julia type of the field.

This macro will in turn use the `@kwdef` macro which creates a keyword argument constructor and allows
field defaults to be specified in the struct declaration itself.  Optional fields should have the default value
`nothing` to comply with the protocol.

The declared type must be immutable and have no parameters, but it is allowed to be of any abstract type.

## Examples
```julia
@thriftstruct struct TestStruct <: AbstractTestType
    a::Vector{UInt8}  # mandatory bytes field
    b::Union{Nothing,Float64} = nothing  # optional floats field
    c::Nothing = nothing  # field 3 not defined in thrift schema, placeholder needed
    d::Union{Nothing,Vector{String}} = nothing  # optional arrays are just like any other optional
end
```
"""
macro thriftstruct(tdec)
    if !(@capture(tdec, struct T_ <: ST_ fields__ end) || @capture(tdec, struct T_ fields__ end))
        error("@thriftstruct must have struct definition as argument")
    end
    quote
        Base.@kwdef $tdec
        Base.:(==)(a::$T, b::$T) = all(j -> getfield(a, j) == getfield(b, j), 1:fieldcount($T))
        Thrift2.thrifttype(::Type{$T}) = Thrift2.ThriftStruct{$T}()
        Thrift2.read(p::CompactProtocol, ::Type{$T}) = read(p, Thrift2.ThriftStruct{$T})
    end |> esc
end
