```@meta
CurrentModule = Parquet2
```

# API

```@index
```

## Basic Usage
```@docs
Dataset
readfile

FileWriter
writefile

filelist
showtree
append!(::Dataset)
append!(::Dataset, ::Integer)
append!(::Dataset, ::Pair{<:AbstractString,<:AbstractString}...)
append!(::Dataset, ::AbstractPath)
appendall!

ColumnOption
RowGroup
Column
load
metadata
writeiterable!
close(::Dataset)
```

## Schema and Introspection
```@docs
SchemaNode
PartitionNode
Page
ColumnStatistics
VectorWithStatistics
ndistinct

PageHeader
DataPageHeader
DictionaryPageHeader

parqtype
juliatype
juliamissingtype
nvalues
iscompressed
isdictencoded
pages
pages!
```

## Internals
See [Internals](@ref internals_api).
