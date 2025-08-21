using PythonCall, CondaPkg, Dates, UUIDs, DataFrames, Random, BenchmarkTools
using Parquet2
using Parquet2.LightBSON, Parquet2.Transducers, Parquet2.OrderedCollections, Parquet2.JSON3

include("gentables.jl")

const fastparquet = pyimport("fastparquet")
const pandas = pyimport("pandas")
const pyarrow = pyimport("pyarrow")
const pyarrowq = pyimport("pyarrow.parquet")
const pyuuid = pyimport("uuid")
const pydecimal = pyimport("decimal")


# this is slow but reliable
pyrecursive(x) = x
pyrecursive(x::AbstractVector) = pylist(map(pyrecursive, x))
pyrecursive(x::AbstractDict) = pydict(Dict(pyrecursive(k)=>pyrecursive(v) for (k, v) ∈ x))
pyrecursive(x::DateTime) = pydatetime(x)
pyrecursive(x::Time) = pytime(x)
pyrecursive(x::Date) = pydate(x)

function pandas_compat_col(k, v)
    any(ismissing, v) && (v = replace(v, missing=>nothing))
    if occursin("dictionar", string(k))
        pandas.Series(v, dtype="category")
    elseif occursin("ushort", string(k))
        pandas.Series(v, dtype="uint16")
    elseif occursin("short", string(k))
        pandas.Series(v, dtype="int16")
    elseif nonmissingtype(eltype(v)) <: Integer
        pandas.Series(v, dtype="Int64")
    elseif all(isnothing, v)
        pandas.Series(v, dtype="Int64")  # needed for pandas not to use refs
    else
        pandas.Series(v)
    end
end

function pandas_compat_dict(tbl)
    pairs(tbl) |> MapSplat((k,v) -> string(k)=>pandas_compat_col(k,v)) |> OrderedDict
end

"""
    to_pandas(tbl)

Convert a Tables.jl compatible table to a pandas table.  This is an alternative to the methods
provided by PythonCall that is more robust for Parquet2.jl testing.
"""
to_pandas(tbl) = pandas.DataFrame(tbl |> pandas_compat_dict |> pydict)

_col_names_with_nulls(df::Py) = filter(s -> occursin("missing", s), pyconvert(Vector{String}, df.columns.to_list()))


function save_standard_test_fastparquet(df=to_pandas(standard_test_table()))
    fastparquet.write(testfilename(:std_fastparquet), df; has_nulls=_col_names_with_nulls(df))
end

function save_random_test_fastparquet(df=to_pandas(random_test_table()))
    fastparquet.write(testfilename(:rand_fastparquet), df; has_nulls=_col_names_with_nulls(df))
end

function save_standard_test_pyarrow(df=to_pandas(standard_test_table()))
    pyarrowq.write_table(pyarrow.Table.from_pandas(df), testfilename(:std_pyarrow), row_group_size=df.shape[1]÷2,
                         version="2.6")
end

function save_random_test_pyarrow(df=to_pandas(random_test_table()))
    pyarrowq.write_table(pyarrow.Table.from_pandas(df), testfilename(:rand_pyarrow), row_group_size=df.shape[1]÷2,
                         version="2.6")
end

function save_extra_types_fastparquet()
    df = pandas.DataFrame()
    df["jsons"] = pyrecursive(make_json_dicts(5))
    #df["bsons"] = pyrecursive(make_json_dicts(5))  # fastparquet has dropped bson last I checked
    df["jvm_timestamps"] = pyrecursive([DateTime(2022,3,8) + Day(i) + Minute(1) for i ∈ 0:4])
    df["fixed_strings"] = ["a", "ab", "abc", "abcd", "abcde"]
    df["bools"] = [false, true, true, false, true]
    fastparquet.write(testfilename(:extra_types_fastparquet), df,
                      times="int96",
                      # it doesn't actually make these strings for some reason, but they are still
                      # fixed arrays
                      fixed_text=Dict("fixed_strings"=>5),
                      object_encoding=Dict("jsons"=>"json", "bsons"=>"bson", "bools"=>"bool")
                     )
    df
end

function save_extra_types_pyarrow()
    df = pandas.DataFrame()
    df["decimals"] = pydecimal.Decimal.(["1.0", "2.1", "3.2", "4.3", "5.4"])
    df["dates"] = pyrecursive([Date(1990,1,j) for j ∈ 1:5])
    df["times_of_day"] = pyrecursive([Time(j) for j ∈ 1:5])
    pyarrowq.write_table(pyarrow.Table.from_pandas(df), testfilename(:extra_types_pyarrow), version="2.6")
    df
end

function save_hive_fastparquet()
    # if you don't delete it might get bizarre mixed thing
    rm(testfilename(:hive_fastparquet), recursive=true, force=true)
    df = pandas.DataFrame()
    df["A"] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3]
    df["B"] = [fill("alpha", 8); fill("beta", 4)]
    df["data1"] = pylist(1.0:12.0)
    df["data2"] = pylist([1:11; nothing])
    fastparquet.write(testfilename(:hive_fastparquet), df,
                      file_scheme="hive",
                      partition_on=pylist(["A", "B"]),
                     )
    df
end

function _compression_arg(tbl, cs)
    o = Dict{String,Any}()
    for (i, (k,_)) ∈ enumerate(pairs(tbl))
        c = cs[mod1(i, length(cs))]
        o[string(k)] = c
    end
    pyrecursive(o)
end

function save_compressed_fastparquet(tbl=standard_test_table())
    df = to_pandas(tbl)
    fastparquet.write(testfilename(:compressed_fastparquet), df,
                      compression=_compression_arg(tbl, ["SNAPPY", "GZIP", "ZSTD"]),
                     )
end

function save_compressed_pyarrow(tbl=random_test_table())
    df = to_pandas(tbl)
    pyarrowq.write_table(pyarrow.Table.from_pandas(df), testfilename(:compressed_pyarrow), version="2.6",
                         compression=_compression_arg(tbl, ["LZ4", "SNAPPY", "GZIP", "ZSTD", "BROTLI"]),
                        )
end

# note that we are not currently generating the table "simple_spark" since we copy it from fastparquet
function save_all()
    isdir("data") || mkdir("data")
    save_standard_test_fastparquet()
    save_standard_test_pyarrow()
    save_random_test_fastparquet()
    save_random_test_pyarrow()
    save_extra_types_fastparquet()
    save_extra_types_pyarrow()
    save_hive_fastparquet()
    save_compressed_fastparquet()
    save_compressed_pyarrow()
end

pyload(file::AbstractString; kw...) = fastparquet.ParquetFile(file; kw...).to_pandas()
pyload(file::Symbol; kw...) = pyload(testfilename(file); kw...)

testload(file::Symbol; kw...) = Parquet2.Dataset(testfilename(file); kw...)

function pyloadbuffer_fastparquet(v::AbstractVector{UInt8}; kw...)
    mktemp() do path, io
        write(io, v)
        close(io)
        fastparquet.ParquetFile(path; kw...).to_pandas()
    end
end

function pyloadbuffer_pyarrow(v::AbstractVector{UInt8}; kw...)
    mktemp() do path, io
        write(io, v)
        close(io)
        pyarrowq.read_table(path; kw...).to_pandas()
    end
end

function _handle_py_timestamps_with_null(x::Py)
    map(x) do ξ
        if lowercase(string(ξ)) == "nat"
            missing
        else
            pyconvert(DateTime, ξ)
        end
    end
end

# this awfulness is slow but necessary to guarantee consistency between pyarrow and fastparquet
function _handle_py_byte_strings(x::Py)
    map(x) do ξ
        if pyconvert(Bool, pytype(ξ) == pybuiltins.str)
            pyconvert(String, ξ)
        elseif pyconvert(Bool, pytype(ξ) == pybuiltins.bytes)
            String(pyconvert(Vector{UInt8}, ξ))
        elseif pyconvert(Bool, ξ == pybuiltins.None)
            missing
        else
            error("got unhandled string object: $ξ")
        end
    end
end

# try to ensure a column from a pandas table is in the form we recognize
function _normalize_pycol(k, x::Py)
    o = if startswith(string(x.dtype), "float")
        o = pyconvert(Vector, x.to_list())
        # assume we intended NaN's as missing
        any(isnan, o) && (o = map(ξ -> isnan(ξ) ? missing : ξ, o))
        o
    elseif startswith(string(x.dtype), "datetime")
        if pyconvert(Int, sum(x.notnull())) == pyconvert(Int, x.size)
            pyconvert(Vector{DateTime}, x.to_list())
        else
            _handle_py_timestamps_with_null(x)
        end
    elseif string(x.dtype) == "object" && occursin("string", k)
        _handle_py_byte_strings(x)
    else
        pyconvert(Vector, x.to_list())
    end
    if eltype(o) >: Nothing
        o = map(ξ -> isnothing(ξ) ? missing : ξ, o)
    end
    o
end

"""
    juliatable(pydf::Py)

Convert a pandas table to a Julia `DataFrame`.

This is preferred over PythonCall methods such as `PyTable` as it is more reliable in getting the
correct datatypes for Parquet2.jl testing.
"""
function juliatable(pydf::Py)
    df = DataFrame()  # we deliberately don't use PyTable because it's a bit unreliable
    for k ∈ pyconvert(Vector{String}, pydf.columns.to_list())
        df[!, k] = _normalize_pycol(k, pydf[k])
    end
    df
end

