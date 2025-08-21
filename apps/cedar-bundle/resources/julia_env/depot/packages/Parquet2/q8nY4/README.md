# Parquet2

[![dev](https://img.shields.io/badge/docs-latest-blue?style=for-the-badge&logo=julia)](https://ExpandingMan.gitlab.io/Parquet2.jl/)
[![build](https://img.shields.io/gitlab/pipeline/ExpandingMan/Parquet2.jl/master?style=for-the-badge)](https://gitlab.com/ExpandingMan/Parquet2.jl/-/pipelines)

----------------------------------------------------

A pure Julia implementation of the [apache parquet
format](https://github.com/apache/parquet-format).


<div class="alert">
<strong>NOTICE</strong>
While Parquet2.jl *is* maintained, no new features are planned.  We suggest also considering
[DuckDB.jl](https://github.com/duckdb/duckdb) which is backed by a mature and well-maintained C++
library and has query support (see also [QuackIO.jl](https://github.com/JuliaAPlavin/QuackIO.jl)
for a simple convenience wrapper of this).
</div>


## Installation
```julia
using Pkg; Pkg.add("Parquet2")
```
or, in the REPL `]add Parquet2`

## Basic Usage
```julia
using Parquet2, Tables, DataFrames

ds = Parquet2.Dataset("/path/to/file")

sch = Tables.schema(ds)  # view table schema

t = Tables.columntable(ds)  # load as a NamedTuple of columns

df = DataFrame(ds; copycols=false)  # load entire dataset as a DataFrame

df1 = DataFrame(ds[1]; copycols=false)  # load first RowGroup as a DataFrame


# load *only* columns (col1, col2) as a DataFrame
dfc = ds |> TableOperations.select(:col1, :col2) |> DataFrame


using AWSS3  # for recognizing S3 url's
s3ds = Parquet2.Dataset("s3://path/to/file")

# can load multi-file datasets
dsd = Parquet2.Dataset("/path/to/directory/")
# multi-file datasets don't read everything by default
append!(dsd, A="1", B="alpha")  # can append by partition columns
# or read it all eagerly (WARNING! don't do this for gigantic directories)
dsd = Parquet2.Dataset("/path/to/directory/"; load_initial=true)

# write a file
df = DataFrame(A=1:5, B=randn(5))
Parquet2.writefile("/path/to/file", df)

# write a file to S3
Parquet2.writefile("s3://path/to/file", df)
```

For more information please see [the documentation](https://ExpandingMan.gitlab.io/Parquet2.jl/).

