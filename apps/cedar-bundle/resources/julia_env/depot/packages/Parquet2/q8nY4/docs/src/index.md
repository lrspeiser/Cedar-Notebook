```@meta
CurrentModule = Parquet2
```

# Parquet2

This package implements the [parquet tabular data storage
format](https://github.com/apache/parquet-format) in pure Julia.  A particular emphasis is placed on
selective loading, schema introspection and the flexibility to load data from a variety of sources such
as S3 or min.io.  This package allows you to load specific "row groups" (subsets of rows which are
serialized separately) and columns to minimize the cost of loading specific subsets of data.  When
memory mapping can be used this is done without loading more of the file than necessary.

Parquet data loaded by Parquet2.jl is organized analogously to the underlying binary data schema:
```
Dataset (← Tables.jl table)
    ⎸ RowGroup (← Tables.jl table)
    ⎸   ⎸ Column1 (← lazy AbstractVector)
    ⎸   ⎸ Column2 (← lazy AbstractVector)
    ⎸   ⎸ ⋮
    ⎸   ⎸ ColumnN (← lazy AbstractVector)
    ⎸ RowGroup2 (← Tables.jl table)
    ⎸ ⋮
    ⎸ RowGroupN (← Tables.jl table)
    ⎸   ⋮
```
- [`Dataset`](@ref): a [Tables.jl table](https://tables.juliadata.org/dev/) and an indexable set of
    `RowGroup`.
- [`RowGroup`](@ref): a Tables.jl table and an indexable (by string name or integer) set of
    `Column`.
- [`Column`](@ref): an abstraction for getting `AbstractVector` objects, which contain the
    deserialized contents of the parquet column.

Parquet files are divided into ``n \ge 0`` `RowGroup`s each of which represents a contiguous
subset of rows in the full table.  `RowGroup`s typically correspond to files.  Parquet2.jl
treats the `RowGroup`s as full tables in-and-of themselves and they can be loaded just like the full
dataset.

## Initialing a Dataset
The first step in reading parquet data is creating a `Dataset` object which contains only metadata.
```julia
using FilePathsBase
using Parquet2: Dataset

ds = Dataset("/path/to/file")  # this only loads metadata
ds = Dataset("/path/to/dir.parquet/")  # parquets may be a directory that contain top-level metdata

using AWSS3
ds = Dataset(p"s3://path/to/file")  # can understand path types 
```

Showing the dataset will display the schema, here is one of the validation datasets:
```julia
◖◗ ds = Dataset("test/data/std_fastparquet.parq")
≔ Dataset (31016 bytes)
	1. "floats": Union{Missing, Float64}
	2. "floats_missing": Union{Missing, Float64}
	3. "ints": Union{Missing, Int64}
	4. "ints_missing": Union{Missing, Float64}
	5. "strings": Union{Missing, String}
	6. "strings_missing": Union{Missing, String}
	7. "timestamps": Union{Missing, DateTime}
	8. "timestamps_missing": Union{Missing, DateTime}
	9. "missings": Missing
	10. "dictionary": Union{Missing, Int64}
	11. "dictionary_missing": Union{Missing, Int64}
```

The dataset is an indexable, iterable collection of `RowGroup` objects
```julia
length(ds)  # gives the number of row groups

rg = ds[1]  # first row group


◖◗ for rg ∈ ds
        println(rg)
    end
≔ RowGroup (14486 bytes) (250 rows)
	1. "floats": Union{Missing, Float64}
	2. "floats_missing": Union{Missing, Float64}
	3. "ints": Union{Missing, Int64}
	4. "ints_missing": Union{Missing, Float64}
	5. "strings": Union{Missing, String}
	6. "strings_missing": Union{Missing, String}
	7. "timestamps": Union{Missing, DateTime}
	8. "timestamps_missing": Union{Missing, DateTime}
	9. "missings": Missing
	10. "dictionary": Union{Missing, Int64}
	11. "dictionary_missing": Union{Missing, Int64}

≔ RowGroup (14480 bytes) (250 rows)
	1. "floats": Union{Missing, Float64}
	2. "floats_missing": Union{Missing, Float64}
	3. "ints": Union{Missing, Int64}
	4. "ints_missing": Union{Missing, Float64}
	5. "strings": Union{Missing, String}
	6. "strings_missing": Union{Missing, String}
	7. "timestamps": Union{Missing, DateTime}
	8. "timestamps_missing": Union{Missing, DateTime}
	9. "missings": Missing
	10. "dictionary": Union{Missing, Int64}
	11. "dictionary_missing": Union{Missing, Int64}
```

Note that each `RowGroup` matches the schema of the `Dataset`.  The `RowGroup`s belonging to a
dataset need not have the same number of rows.


## Accessing Data
[`Dataset`](@ref) and [`RowGroup`](@ref) both satisfy the
[Tables.jl](https://github.com/JuliaData/Tables.jl) columnar table interface and can therefore be
easily converted to tables.
```julia
using Tables, DataFrames

using Parquet2: Dataset

# Dataset is an abstraction to provide an interface for loading data
ds = Dataset("/path/to/file")

sch = Tables.schema(ds)  # get the Tables.jl Schema object

c = Tables.getcolumn(ds, :col1)  # load *only* col1; others are not touched

c = Parquet2.load(ds, "col1")  # equivalent to the above


df = DataFrame(ds; copycols=false)  # load the entire table as a DataFrame

# it is suggested to do `copycols=false` unless you intend to write to the DataFrame
df = DataFrame(ds)

# columns are loaded in parallel by default, but this can be disabled
ds = Dataset("/path/to/file"; parallel_column_loading=false)

df1 = DataFrame(ds[1])  # load the first RowGroup as a DataFrame

meta = Parquet2.metadata(ds)  # auxiliary metadata can be accessed thusly
colmeta = Parquet2.metadata(ds[1]["col1"])  # auxiliary metadata by column
```

!!! note

    Columns will be read from the file or buffer and allocated every time `Parquet2.load` or,
    equivalently `Tables.getcolumn` is called on a `Dataset` or `RowGroup`.  These operations should
    be considered expensive, and the API assumes they will be used sparingly.  If you want to call
    something that frequently accesses columns, you should first make all `Parquet2.load` calls,
    returning fully materialized columns and then call your oprations on these.  For example, when
    performing operations on columns, it is usually better to first collect the table in-memory with
    `Tables.columntable` or `DataFrame`.


### Using TableOperations.jl to load Specific Columns
This package supports loading of specific columns leaving the rest untouched.  With the exception of
the top-level metadata, only data from selected columns is loaded.

While columns can easily be loaded individually with `Tables.getcolumn` or [`Parquet2.load`](@ref),
it is more convenient to select a subset of them using
[TableOperations.jl](https://github.com/JuliaData/TableOperations.jl).  In particular, see
[`TableOperations.select`](https://github.com/JuliaData/TableOperations.jl#tableoperationsselect).

For example
```julia
using TableOperations; const TO = TableOperations

ds = Parquet2.Dataset("/path/to/file")

# load *only* columns 1 and 2, others are skipped entirely
df = ds |> TO.select(:col1, :col2) |> DataFrame

# TableOperations is a dependency of Parquet2, so you can also do
df = ds |> Parquet2.select(:col3, :col4) |> DataFrame
```

## Writing Data
Files can be written with [`Parquet2.writefile`](@ref).  Tables being written must satisfy [the
Tables.jl interface](https://tables.juliadata.org/stable/) (most Julia-ecosystem tables such as
`DataFrame`s already do this).  They can be written to any filesystem which can be written to with
the `FilePathsBase` interface.

For example
```julia
using Parquet2, DataFrames

using Parquet2: writefile

tbl = DataFrame(A=1:5, B=rand(5))
writefile("testfile.parq", tbl)  # write to disk at testfile.parq

io = IOBuffer()
writefile(io, tbl)  # write to IO buffer

writefile(Vector{UInt8}, tbl)  # write to an array

tbl = (A=1:5, B=rand(5))  # a NamedTuple is the archetyple Tables.jl copmatible object

writefile("testfile2.parq", tbl;
          npages=2,  # number of pages per column
          compression_codec=Dict("A"=>:zstd, "B"=>:snappy),  # compression codec per column
          column_metadata="A"=>Dict("frank"=>"reynolds"),  # per column auxiliary metadata
          metadata=Dict("charlie"=>"kelley"),  # file wide metadata
         )
```

Note that any option which can be defined per-column such as `npages` and `compression_codec` can be
specified either by value, in which case it'll be applied to all columns, dictionary per column, or
pair for a single column.

### Writing Row Groups
`writefile` uses the Tables.jl `Tables.partitions` function to decide how to group rows into
`RowGroup`s.  Each partition is written as a single row group.

## Column Statistics
The parquet format includes the ability to store computed statistics values in metadata so that they
can be retrieved without the need to re-compute them.  Statistics which can be stored are
- Minimum value.
- Maximum value.
- Number of missing values.
- Number of distinct values.

This package provides the option to compute these values when data is serialized, as well as the
option to wrap the output `AbstractVector`s in a `struct` which will allow these to be retrieved
rather than being re-computed with methods from `Base`.

```julia
tbl = (A=1:5, B=6:10, C=1.0:5.0)

# compute statistics when writing only for columns A and C
v = writefile(Vector{UInt8}, tbl; compute_statistics=["A", "C"])

# only wrap column A
# (note that if `copycols=true` the wrapper will get destroyed)
df = DataFrame(Dataset(v; use_statistics=["A"]); copycols=false)

minimum(df.A)  # this is simply retrieved rather than being re-computed
minimum(df.B)  # this was not stored and had to be re-computed
maximum(df.C)  # this was computed, but we didn't include it so it's computed again here

stats = Parquet2.ColumnStatistics(df.C)  # we can still access that stats though
minimum(stats)
maximum(stats)
count(ismissing, stats)
Parquet2.ndistinct(stats)
```

## Multi-File Datasets

!!! note
    
    As far as we are aware, there is no formal specification for *any* multi-file parquet formats.
    The metadata contain fields which can indicate the locations of auxiliary files, but the most
    common multi-file formats do not even utilize this feature.  Therefore, support for multi-file
    formats has been a matter of trial and error.  We think Parquet2 currently supports the most
    common cases, described below.

Many parquet writers write output to many separate files with one or more row-groups per file.
There are two common directory schema
- Flat: a single directory containing many files.
- "Hive" tree: directory names specify column values.

In both cases all files have an identical schema, but in the latter case there are additional
implied columns with the values set depending on the location in the directory.  The metadata may or
may not be stored separately.

To load multiple files, the path of a directory containing parquet data can be passed to `Dataset`
which will try to infer the structure.  Because parquet directories structures are potentially
enormous and may contain millions of individual files, `Dataset` will only load metadata from
exactly one of these by default.  This gives users the ability to inspect the structure and decide
which files to load.
```julia
using Parquet2
using Parquet2: Dataset, filelist, appendall!, showtree

ds = Dataset("test/data/hive_fastparquet.parq")  # this is in the Parquet2 test directory

length(ds) == 0 # no row groups are active yet
```

The metadata for this dataset looks like:
```julia
≔ Dataset (1461 bytes)
        1. "A": String
        2. "B": String
        3. "data1": Union{Missing, Float64}
        4. "data2": Union{Missing, Float64}
```

The columns `A` and `B` are "implied", meaning they are only inferrable from the directory
structure.  `Dataset` shows these as `String` columns.  Columns inferred from directory structure
can only be strings.

Now we can inspect this dataset to decide what to load.  We can see an explicit list of files
```julia
◖◗ filelist(ds)
3-element Vector{PosixPath}:
 p"/home/expandingman/.julia/dev/Parquet2/test/data/hive_fastparquet.parq/A=1/B=alpha/part.0.parquet"
 p"/home/expandingman/.julia/dev/Parquet2/test/data/hive_fastparquet.parq/A=2/B=alpha/part.0.parquet"
 p"/home/expandingman/.julia/dev/Parquet2/test/data/hive_fastparquet.parq/A=3/B=beta/part.0.parquet"
```

Or the column and directory structure
```julia
◖◗ showtree(ds)
Root()
├─ "A" => "1"
│  └─ "B" => "alpha"
├─ "A" => "2"
│  └─ "B" => "alpha"
└─ "A" => "3"
   └─ "B" => "beta"
```

Row groups from these files can now be appended using `append!`
```julia
append!(ds, filelist(ds)[1])  # add row groups from the first file
append!(ds, 1)  # a pun for the above.  in this case it throws an error because we already added it

append!(ds, "B"=>"alpha")  # add all row groups with B="alpha" (the first 2 files); doesn't error
append!(ds, "A"=>"1", "B"=>"alpha")  # add all row groups with *both* A="1" and B="alpha" (first 2)
append!(ds, A="3", B="beta")  # can also do this with keyword arguments

append!(ds, A="1", verbose=true)  # gives helpful log messages so we can see what happened
```

Note that calling `append!` will *NOT* read in the *data* from the files, only the *metadata*.
Loading the data works the same way as in the single-file case, e.g. one can materialize columns
with `Parquet2.load`, `Tables.getcolumn` or materializing the whole table with `Tables.columns` or
`DataFrame`.  However, whenever data is loaded, it will be loaded only from the row groups for which
metadata has been loaded.

### TL;DR shutup, I just want to read all the data
```julia
Parquet2.Dataset(directory_name; load_initial=true)
```
or, equivalently
```julia
ds = Parquet2.Dataset(directory_name)
Parquet2.appendall!(ds)
# (again, you still need to load the data with DataFrame or whatever)
```

As we mentioned previously, parquet directory structures can be huge, and since there appears to be
no formal specification for commonly used multi-file parquet formats, it might behoove you to check
that Parquet2's idea of what files belong to the parquet is the same as yours with `filelist`.  So,
you should use these options only if you are sure it is a good idea!

