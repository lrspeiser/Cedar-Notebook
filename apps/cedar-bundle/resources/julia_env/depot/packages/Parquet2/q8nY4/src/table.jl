
"""
    ParquetTable

Tables.jl compatible abstract type of parquet table-like objects, such as `Dataset` and `RowGroup`.
"""
abstract type ParquetTable end

isnrowsknown(t::ParquetTable) = false


Tables.getcolumn(t::ParquetTable, i::Int) = load(t, i)

Tables.getcolumn(t::ParquetTable, nm::Symbol) = load(t, string(nm))

Tables.getcolumn(t::ParquetTable, ::Type, i::Int, nm::Symbol) = load(t, i)

function Tables.columnnames(t::ParquetTable)
    cols = names(t)
    ntuple(i -> Symbol(cols[i]), length(cols))
end

"""
    useparallel(t::ParquetTabe)

Whether to load the columns of the parquet table `t` in parallel, else sequentially.  This option is set on reading
metadata, i.e. by the `parallel_column_loading` argument to `DataSet`.  The option is propagated to all `RowGroup`s
belonging to the `Dataset`.
"""
useparallel(::ParquetTable) = false  # all should implement this

NameIndex(t::ParquetTable) = t.name_index

partition_column_names(t::ParquetTable) = OrderedSet{String}()

npartitioncols(t::ParquetTable) = length(partition_column_names(t))

root_schema_node(t::ParquetTable) = t.schema


column_schema_nodes(t::ParquetTable) = collect(children(root_schema_node(t)))

Base.names(t::ParquetTable) = names(NameIndex(t))

DataAPI.ncol(t::ParquetTable) = length(names(t))
# methods for getting schema nodes in with SchemaNode in schema.jl

function check_partition_column(t::ParquetTable, n::Integer)
    if n < 1
        throw(BoundsError(t, n))
    elseif n ≤ npartitioncols(t)
        true
    elseif n ≤ ncol(t)
        false
    else
        throw(BoundsError(t, n))
    end
end

function parqtype(t::ParquetTable, n::Integer)
    check_partition_column(t, n) ? ParqString() : parqtype(SchemaNode(t, n - npartitioncols(t)))
end
parqtype(t::ParquetTable, n::AbstractString) = parqtype(t, NameIndex(t)[Int, n])

function juliatype(t::ParquetTable, n::Integer)
    check_partition_column(t, n) ? String : juliatype(SchemaNode(t, n - npartitioncols(t)))
end
juliatype(t::ParquetTable, n::AbstractString) = juliatype(t, NameIndex(t)[Int, n])

function juliamissingtype(t::ParquetTable, n::Integer)
    check_partition_column(t, n) ? String : juliamissingtype(SchemaNode(t, n - npartitioncols(t)))
end
juliamissingtype(t::ParquetTable, n::AbstractString) = juliatype(t, NameIndex(t)[Int, n])

juliatypes(t::ParquetTable) = [juliamissingtype(t, n) for n ∈ 1:ncol(t)]


Tables.istable(::Type{<:ParquetTable}) = true

Tables.columnaccess(::Type{<:ParquetTable}) = true

Tables.schema(t::ParquetTable) = Tables.Schema(names(t), juliatypes(t))

# we overload this to decide whether we need to use parallel
function Tables.columns(t::ParquetTable)
    clct = useparallel(t) ? tcollect : collect
    #NOTE: this weirdness to work around https://github.com/JuliaFolds/Transducers.jl/issues/524
    o = names(t) |> Map(Symbol) |> Map(n -> n=>Ref(Tables.getcolumn(t, n))) |> clct
    Tables.CopiedColumns(NamedTuple(n=>v[] for (n, v) ∈ o))
end

# overload methods of Select so we know whether to load in parallel
function Tables.columns(s::Select{<:ParquetTable})
    clct = useparallel(s.source) ? tcollect : collect
    names(s) |> Map(Symbol) |> Map(n -> n=>Tables.getcolumn(s.source, n)) |> clct |> NamedTuple |> Tables.CopiedColumns
end

# this is to prevent default select method from calling `columns` and materializing the whole table
TableOperations.select(t::ParquetTable, names...) = TableOperations.Select{typeof(t),true,names}(t)
