
"""
    Dataset <: ParquetTable

A complete parquet dataset created from top-level parquet metadata.  Each `Dataset` is an indexable collection of
[`RowGroup`](@ref)s each of which is a Tables.jl compatible columnar table in its own right.  The
`Dataset` is a [Tables.jl compatible](https://tables.juliadata.org/dev/) columnar table consisting of (lazily
by default) concatenated `RowGroup`s.  A `Dataset` can consist of data in any number of files depending on the
directory structure of the referenced parquet.

## Constructors
```julia
Dataset(fm::FileManager; kw...)
Dataset(p::AbstractPath; kw...)
Dataset(v::AbstractVector{UInt8}; kw...)
Dataset(io::IO; kw...)
Dataset(str::AbstractString; kw...)
```

## Arguments
- `fm`: A [`FileManager`](@ref) object describing a set of files to be loaded.
- `p`: Path to main metadata file or directory containing a `_metadata` file.  Loading behavior will depend on
    the type of path provided.
- `v`: An in-memory (or memory mapped) byte buffer.
- `io`: An `IO` object from which data can be loaded.
- `str`: File or directory path as a string.  Converted to `AbstractPath` with `Path(str)`.

### Keyword Arguments
The following keyword arguments are applicable for the dataset as a whole:
- `support_legacy` (`true`): Some parquet writers take bizarre liberties with the metadata, in particular
    many JVM-based writers use a specialized `UInt96` encoding of timestamps even though this is not described
    by the metadata.  When this option is `false` the metadata will be interpreted strictly.
- `use_mmap` (`true`): Whether to use memory mapping for reading the file.  Only applicable for files on the
    local file system.  In some cases enabling this can drastically increase read performance.
- `mmap_shared` (`true`): Whether memory mapped buffers can be shared with other processes.  See documentation
    for `Mmap.mmap`.
- `preload` (`false`):  Whether all data should be fetched on constructing the `Dataset` regardless of the
    above options.
- `load_initial` (`nothing`):  Whether the `RowGroup`s should be eagerly loaded into memory.  If `nothing`, this
    will be done only for parquets consisting of a single file.
- `parallel_column_loading`: Whether columns should be loaded using thread-based parallelism.  If `nothing`, this
    is true as long as Julia has multiple threads available to it.

The following keyword arguments are applicable to specific columns.  These can be passed either as a single value,
a `NamedTuple`, `AbstractDict` or `ColumnOption`.  See [`ColumnOption`](@ref) for details.
- `allow_string_copying` (`false`): Whether strings will be copied.  If `false` a reference to the underlying data
    buffer needs to be maintained, meaning it can't be garbage collected to free up memory.  Note also that
    there will potentially be a large number of references stored in the output colun if this is `false`,
    so setting this to `true` reduces garbage collector overhead.
- `lazy_dictionary` (`true`):  Whether output columns will use a Julia categorical array representation which in
    some cases can ellide a large number of allocations.
- `parallel_page_loading` (`false`): Whether data pages in the column should be loaded in parallel.  This comes
    with some additional overhead including an extra iteration over the entire page buffer, so it is of dubious
    benefit to turn this on, but it may be helpful in cases in which there is a large number of pages.
- `use_statistics` (`false`): Whether statistics included in the metadata will be used in the loaded column
    `AbstractVector`s so that statistics can be efficiently retrieved rather than being re-computed.
    Note that if this is `true` this will only be done for columns for which statistics are available.
    Otherwise, statistics can be retrieved with `ColumnStatistics(col)`.
- `eager_page_scanning` (`true`): It is not in general possible to infer all page metadata without iterating over
    the columns entire data buffer.  This can be elided, but doing so limits what can be done to accommodate data
    loaded from the column.  Turning this option off will reduce the overhead of loading metadata for the column
    but may increase the cost of allocating the output.  If `false` specialized string and dictionary outputs
    will not be used (loading the column will be maximally allocating).

## Usage
```julia
ds = Dataset("/path/to/parquet")
ds = Dataset(p"s3://path/to/parquet")  # understands different path types

length(ds)  # gives number of row groups

rg = ds[1]  # index to get row groups

for rg ∈ ds  # is an indexable, iterable collection of row groups
    println(rg)
end

df = DataFrame(ds)  # Tables.jl compatible, is concatenation of all row groups

# use TableOperations.jl to load only selected columns
df = ds |> TableOperations.select(:col1, :col2) |> DataFrame
```
"""
struct Dataset{ℱ<:FileManager} <: ParquetTable
    file_manager::ℱ
    meta_orig::Meta.FileMetaData
    schema::SchemaNode
    row_groups::Vector{RowGroup}
    row_group_index::Dict{AbstractPath,Set{Int}}
    name_index::NameIndex
    partition_tree::PartitionNode
    partition_column_names::OrderedSet{String}
    metadata::Dict{String,Any}
end

function Dataset(fm::FileManager)
    v = get(fm)
    m = readmeta(v; check=true)
    opts = ReadOptions(fm)
    r = SchemaNode(m.schema; support_legacy=opts.support_legacy)
    ptree = PartitionNode(fm)
    rgs = Vector{RowGroup}()
    ridx = Dict{AbstractPath,Set{Int}}()
    pnames = OrderedSet(columnnames(ptree))
    nidx = (pnames, children(r) |> Map(name)) |> Cat() |> collect |> NameIndex
    ds = Dataset{typeof(fm)}(fm, m, r, rgs, ridx, nidx, ptree, pnames, unpack_thrift_metadata(m))
    _should_load_initial(fm) && appendall!(ds)
    ds
end
function Dataset(p::AbstractPath; kw...)
    opts = filterkw(ReadOptions, kw)
    Dataset(FileManager(p, opts))
end
Dataset(io::IO; kw...) = Dataset(FileManager(read(io); kw...))
Dataset(v::AbstractVector{UInt8}; kw...)  = Dataset(FileManager(v; kw...))
Dataset(p::AbstractString; kw...) = Dataset(AbstractPath(p); kw...)

ReadOptions(ds::Dataset) = ReadOptions(ds.file_manager)

FileManager(ds::Dataset) = ds.file_manager

"""
    filelist(ds::Dataset)
    filelist(fm::FileManager)

Returns an `AbstractVector` containing the paths of all files associated with the dataset.
"""
filelist(ds::Dataset) = filelist(FileManager(ds))

# get underlying arrays
Base.get(ds::Dataset) = get(ds.file_manager)
Base.get(ds::Dataset, k) = get(ds.file_manager, k)

function _update_row_group_index!(ds::Dataset, p::AbstractPath, n::Integer)
    n == 0 && return nothing
    m = length(ds.row_groups)
    s = get(ds.row_group_index, p, Set{Int}())
    t = Set((m+1):(m+n))
    if isempty(s)
        ds.row_group_index[p] = t
    else
        union!(s, t)
    end
    nothing
end

"""
    append!(ds::Parquet2.Dataset, p; check=true, verbose=false)

Append all row groups from the file `p` to the dataset row group metadata.  If `check`, will check if path is a valid
parquet file first.  `p` must be a path that was discovered during the initial construction of the dataset.

If `verbose=true` an `INFO` level logging message will be printed for each appended row group.
"""
function Base.append!(ds::Dataset, p::AbstractPath; verbose::Bool=false, check::Bool=true)
    p ∈ keys(ds.row_group_index) && throw(ArgumentError("row groups for \"$p\" already exist in dataset"))
    v = get(ds.file_manager, p)
    m = readmeta(v; check)
    𝒻 = rg -> RowGroup(ds.file_manager, ds.schema, rg, ds.partition_tree; current_file=p)
    rgs = m.row_groups |> Map(𝒻) |> collect
    _update_row_group_index!(ds, p, length(rgs))
    append!(ds.row_groups, rgs)
    verbose && @info("appended row group from file $p")
    ds
end
Base.append!(ds::Dataset, p::AbstractString; kw...) = append!(ds, Path(p); kw...)

"""
    append!(ds::Parquet2.Dataset, col=>val...; check=true)
    append!(ds::Parquet2.Dataset; check=true, kw...)

Append row groups for which the columns specified by `col` have the value `val`.  This applies only to
"hive/drill" partition columns in file trees, therefore `col` and `val` must both be strings.  The selected
row groups must satisfy *all* passed pairs.

Alternatively, these can be passed as keyword arguments with the column names as the keys and the (string)
values as the value constraints.

## Examples
```julia
◖◗ showtree(ds)
Root()
├─ "A" => "1"
│  └─ "B" => "alpha"
├─ "A" => "2"
│  └─ "B" => "alpha"
└─ "A" => "3"
   └─ "B" => "beta"

◖◗ append!(ds, "A"=>"2", "B"=>"alpha", verbose=true);
[ Info: appended row group from file \$HOME/data/hive_fastparquet.parq/A=2/B=alpha/part.0.parquet

◖◗ append!(ds, A="3", B="alpha");  # in this case nothing is appended since now such row group exists
```
"""
function Base.append!(ds::Dataset, sps::Pair{<:AbstractString,<:AbstractString}...; kw...)
    𝒻 = s -> begin
        all(sp -> occursin(directorystring(sp), string(s)), sps)
    end
    foreach(f -> append!(ds, f; kw...), filelist(ds) |> Filter(p -> p ∉ keys(ds.row_group_index)) |> Filter(𝒻))
    ds
end
function Base.append!(ds::Dataset; check::Bool=true, verbose::Bool=false, kw...)
    ps = pairs(kw) |> Map(p -> string(p[1])=>p[2])
    append!(ds, ps...; check, verbose)
end


"""
    append!(ds::Dataset, i::Integer; check=true)

Append row group number `i` to the dataset.  The index `i` is the index of the array returned by `filelist`,
that is, this is equivalent to `append!(ds, filelist(ds)[i])`.
"""
Base.append!(ds::Dataset, i::Integer; kw...) = append!(ds, filelist(ds)[i]; kw...)

"""
    appendall!(ds::Dataset; check=true)

Append all row groups to the dataset.

**WARNING**: Some parquet directory trees can be huge.  This function does nothing to check that what you are
about to do is a good idea, so use it judiciously.
"""
function appendall!(ds::Dataset; kw...)
    filelist(ds) |> Filter(p -> p ∉ keys(ds.row_group_index)) |> Map(p -> append!(ds, p; kw...)) |> foldxl(right, init=[])
    ds
end

"""
    showtree([io=stdout,] ds::Dataset)

Show the "hive/drill" directory tree of the dataset.  The pairs printed in this tree can be passed as arguments to
`append!` to append the corresponding row group to the dataset.
"""
showtree(io::IO, ds::Dataset) = showtree(io, ds.partition_tree)
showtree(ds::Dataset) = showtree(stdout, ds)

"""
    dirname(ds::Dataset)

Get the parent directory of the dataset.
"""
Base.dirname(ds::Dataset) = dirname(ds.file_manager)

"""
    partition_column_names(ds::Dataset)

Get a list of all columns names of columns in the dataset used for file partitioning.  This is for files which
have been written in the "hive/drill" file tree schema.
"""
partition_column_names(ds::Dataset) = ds.partition_column_names

"""
    pathof(ds::Parquet2.Dataset)

Get the main file path associated with the dataset.  Returns an empty path if the file is not associated
with any path (i.e. `isempty(pathof(ds))` is `true` in that case).
"""
Base.pathof(ds::Dataset) = ds.file_manager.main_path

nbytes(ds::Dataset) = ds |> FileManager |> get |> length

_min_parquet_size() = 2*length(MAGIC) + FOOTER_LENGTH

function checkparquet(v::Buffer)
    isempty(v) && throw(ArgumentError("invalid parquet: provided buffer is empty"))
    if length(v) < _min_parquet_size()
        throw(ArgumentError("invalid parquet: buffer of length $(length(v)) is shorter than minimum "*
                            "size $(_min_parquet_size())"))
    end
    mgc = v[(end-length(MAGIC)+1):end]
    if mgc ≠ MAGIC
        throw(ArgumentError("invalid parquet: final bytes are \"$(String(mgc))\", expect \"PAR1\""))
    end
end

function readmetalength(v::Buffer)
    j = length(v) - length(MAGIC) - FOOTER_LENGTH + 1
    only(reinterpret(Int32, v[j:(j+3)]))
end

function readmeta(v::Buffer; check::Bool=true)
    check && checkparquet(v)
    ℓ = readmetalength(v)
    a = length(v) - length(MAGIC) - FOOTER_LENGTH - ℓ
    io = IOBuffer(v)
    seek(io, a)
    m = read(CompactProtocol(io), Meta.FileMetaData)
    @debug("read parquet Dataset metadata")
    m
end

DataAPI.metadatasupport(::Type{<:Dataset}) = (read=true, write=false)
DataAPI.colmetadatasupport(::Type{<:Dataset}) = (read=true, write=false)

"""
    metadata(ds::Dataset; style=false)

Get the auxiliary key-value metadata for the dataset.

Note that `Dataset` does not support `DataAPI.colmetadata` because it contains one instance of each column
per row group.  To access column metadata either call `metadata` on [`Column`](@ref) objects or
`colmetadata` on [`RowGroup`](@ref) objects.
"""
function DataAPI.metadata(ds::Dataset; style::Bool=false)
    style ? Dict(k=>(v, :default) for (k, v) in ds.metadata) : ds.metadata
end

"""
    metadata(ds::Dataset, k::AbstractString[, default]; style=false)

Get the key `k` from the key-value metadata for the dataset.  If `default` is provided it will be returned
if `k` is not present.
"""
function DataAPI.metadata(ds::Dataset, k::AbstractString; style::Bool=false)
    o = metadata(ds)[k]
    style ? (o, :default) : o
end
function DataAPI.metadata(ds::Dataset, k::AbstractString, default; style::Bool=false)
    o = get(metadata(ds), k, default)
    style ? (o, :default) : o
end

DataAPI.metadatakeys(ds::Dataset) = keys(metadata(ds))

function DataAPI.colmetadata(ds::Dataset, col::Union{Int,Symbol}; style::Bool=false)
    length(ds) ≠ 1 && throw(ArgumentError("dataset column metadata is ambiguous"))
    colmetadata(ds[1], col, k; style)
end

function DataAPI.colmetadata(ds::Dataset, col::Union{Int,Symbol}, k::AbstractString; style::Bool=false)
    length(ds) ≠ 1 && throw(KeyError(k))
    colmetadata(ds[1], col, k; style)
end
function DataAPI.colmetadata(ds::Dataset, col::Union{Int,Symbol}, k::AbstractString, default; style::Bool=false)
    length(ds) ≠ 1 && return default
    colmetadata(ds[1], col, k, default; style)
end

function DataAPI.colmetadatakeys(ds::Dataset, col::Union{Integer,Symbol})
    length(ds) ≠ 1 && return ()
    colmetadatakeys(ds[1], col)
end

function DataAPI.colmetadatakeys(ds::Dataset)
    length(ds) ≠ 1 && return ()
    colmetadatakeys(ds[1])
end

rowgroups(ds::Dataset) = ds.row_groups

nrowgroups(ds::Dataset) = length(ds.row_groups)

DataAPI.nrow(ds::Dataset) = sum(nrow, rowgroups(ds))

RowGroup(ds::Dataset, n::Integer) = rowgroups(ds)[n]

Base.length(ds::Dataset) = nrowgroups(ds)

Base.getindex(ds::Dataset, n::Integer) = RowGroup(ds, n)

"""
    close(ds::Dataset)

Close the `Dataset`, deleting all file buffers and row groups and freeing the memory.  If the buffers are
memory-mapped, this will free associated file handles.  Note that memory and handles are only freed once
garbage collection is executed (can be forced with `GC.gc()`).
"""
function Base.close(ds::Dataset) 
    empty!(ds.row_groups)
    close(ds.file_manager)
end

function Base.iterate(ds::Dataset, n::Integer=1)
    n > nrowgroups(ds) && return nothing
    (RowGroup(ds, n), n+1)
end

Column(ds::Dataset, r::Integer, c::Union{Integer,AbstractString}) = Column(RowGroup(ds, r), c)

function PageLoader(ds::Dataset, r::Integer, c::Union{Integer,AbstractString}, p::Integer=1)
    PageLoader(ds.schema, Column(ds, r, c), p)
end

"""
    load(ds::Dataset, n)

Load the (complete, all `RowGroup`s) column `n` (integer or string) from the dataset.
"""
function load(ds::Dataset, n::Union{Integer,AbstractString})
    if nrowgroups(ds) == 0
        Vector{juliamissingtype(ds, n)}()
    elseif nrowgroups(ds) == 1
        load(RowGroup(ds, 1), n)
    else
        ChainedVector(map(rg -> load(rg, n), rowgroups(ds)))
    end
end

Tables.partitions(ds::Dataset) = rowgroups(ds)

_useparallel(opt::Union{Nothing,Bool}) = isnothing(opt) ? (Base.Threads.nthreads() > 1) : opt

useparallel(ds::Dataset) = _useparallel(ReadOptions(ds).parallel_column_loading)

"""
    readfile(filename; kw...)
    readfile(io::IO; kw...)

An alias for [`Dataset`](@ref).  All arguments are the same, so see those docs.

This function is provided for consistency with the [`writefile`](@ref) function.
"""
readfile(a...; kw...) = Dataset(a...; kw...)
