```@meta
CurrentModule = Thrift2
```

# Thrift2

This package is a pure Julia implementation of the [Apache
Thrift](https://en.wikipedia.org/wiki/Apache_Thrift) protocol, designed to replace
[Thrift.jl](https://github.com/tanmaykm/Thrift.jl).  In contrast to Thrift.jl, structs read by this
package are immutable and fully declared at compile time, making reading and writing highly
efficient.

!!! note

    This package was developed specifically to resolve the performance issues caused for Parquet2.jl
    caused by Thrift.jl.  While I fully intend this package to be appropriate for all uses of the
    thrift protocol, it hasn't been tested much on objects other than those defined in the parquet
    metadata, and features not used by Parquet2.jl have so far had a low priority.  In particular, I
    have not yet written a parser for `*.thrift` schema.  If you are having trouble with a different
    application, please open an issue!


## Reading
To read data, one should wrap an `IO` or buffer in a `ThriftProtocol` object.  For example
```julia
p = open(CompactProtocol, filename)  # open the file `filename`

s = read(CompactProtocol, SomeStruct)  # read a SomeStruct object from the file

close(p)
```

## Writing
Only objects of a type declared with `@thriftstruct` can be written.  For example
```julia
p = CompactProtocol()  # create an in-memory buffer

n = write(p, s1)  # where s1 is some thrift struct declared with @thriftstruct
n += write(p, s2)  # we can keep writing into the buffer, but the protocol only understand individual
                   #   structs

n > 0  # write returns the bytes written just like it does for IO
```

## Declaring the Schema
Currently code generation for `*.thrift` schema has not been implemented, so users must declare the
objects in the schema semi-manually.  Enum objects are ordinary Julia `Base` enums.  Structs are
declared using the `@thriftsruct` macro.

A complete example from the parquet format metadata can be found
[here](https://gitlab.com/ExpandingMan/Thrift2.jl/-/blob/main/test/ParquetMetadata/Metadata.jl),
with the original thrift schema from which it was created
[here](https://gitlab.com/ExpandingMan/Thrift2.jl/-/blob/main/test/ParquetMetadata/Metadata.thrift).

The following are some important points to keep in mind when writing a schema:
- Only types which are understood by the thrift protocol can be used for fields.  Declaring a field
    of a type which the protocol does not support will return an error.
- Structs must not have any type parameters, however they can have any abstract type.
- Optional fields should be declared with type `Union{Nothing,T}` where `T` is the type of the
    corresponding non-optional field.  Such fields should be given a default value of `nothing`, for
    example, an optional double field named `x` should be written `x::Union{Nothing,Float64} =
    nothing`.
- Thrift union types are treated as normal structs with optional fields for every possible type.
    Currently Thrift2.jl does not enforce that exactly one of these fields is declared.  All fields
    of a union type must be optional.
