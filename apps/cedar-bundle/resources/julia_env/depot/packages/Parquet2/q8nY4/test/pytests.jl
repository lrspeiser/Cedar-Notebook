#import Pkg; Pkg.activate(joinpath(@__DIR__,"devenv"))
using Test, PythonCall, CondaPkg
using QuackIO: QuackIO
using Tables: columntable
#====================================================================================================
       pytests.jl

These are unit tests utilizing Python dependencies.  These do not run in CI/CD but should
be run locally to ensure Parquet2 output is correct.

Should be runnable after instantiating the environment in `devenv`

WARN: this environment is currently royally fucked becuase it always seems to fail to link its
libraries.  The horrible hack I have around this is: start julia in devenv, using PythonCall,
then copy and paste

const fastparquet = pyimport("fastparquet")
const pandas = pyimport("pandas")
const pyarrow = pyimport("pyarrow")
const pyarrowq = pyimport("pyarrow.parquet")
const pyuuid = pyimport("uuid")
const pydecimal = pyimport("decimal")

Don't know how to get around this right now and too frustrated to try.

And no it also does not work with refs, that's not the problem.
====================================================================================================#

include("genparquet.jl")
include("utils.jl")

if isdefined(@__MODULE__, :Revise)
    Revise.track("genparquet.jl")
    Revise.track("utils.jl")
end


@testset "pyarrow" begin
    # want to ensure we test tables of different sizes
    py_compare_pyarrow(standard_test_table(555))
    for _ ∈ 1:3
        py_compare_pyarrow(random_test_table())
    end
end

@testset "fastparquet" begin
    py_compare_fastparquet(standard_test_table(555))
    for _ ∈ 1:3
        py_compare_fastparquet(random_test_table())
    end
end

@testset "QuackIO codec $c" for c ∈ [:uncompressed, :snappy, :gzip, :zstd, :brotli]
        tbl = (;a=rand(1:100, 10000), b=rand(10000))
        path = tempname()
        qpath = tempname()
        QuackIO.write_table(qpath, tbl; format=:parquet, compression=c)
        writefile(path, tbl; compression_codec=c)
        table_compare(tbl, QuackIO.read_parquet(columntable, path))
        table_compare(tbl, QuackIO.read_parquet(columntable, qpath))
        table_compare(tbl, Dataset(path))
        table_compare(tbl, Dataset(qpath))
end
