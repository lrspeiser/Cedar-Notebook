using Parquet2
using Test, Random, Dates, DecFP, UUIDs
using Tables

using Parquet2: Dataset, writefile, VectorWithStatistics

include("gentables.jl")
include("utils.jl")

if isdefined(@__MODULE__, :Revise)
    Revise.track("gentable.jl")
    Revise.track("utils.jl")
end

@info """
Parquet2.jl Unit Tests:
    these do not include tests that other implementations can read our output,
    please run pytests.jl for full compatibility tests.
"""


@testset "read" begin
    @testset "std" begin
        tbl = standard_test_table()
        @testset "fastparquet" begin
            table_compare(tbl, testload(:std_fastparquet))
        end
        @testset "pyarrow" begin
            # disabling parallel loading here is just to make sure we cover sequential case
            table_compare(tbl, testload(:std_pyarrow; parallel_column_loading=false))
        end
    end

    @testset "rand" begin
        tbl = random_test_table()
        @testset "fastparquet" begin
            table_compare(tbl, testload(:rand_fastparquet; parallel_column_loading=false))
        end
        @testset "pyarrow" begin
            table_compare(tbl, testload(:rand_pyarrow))
        end
    end

    @testset "compressed" begin
        tbl = standard_test_table()
        @testset "fastparquet" begin
            table_compare(tbl, testload(:compressed_fastparquet))
        end
        tbl = random_test_table()  # try to get a bit more variety in tests
        @testset "pyarrow" begin
            table_compare(tbl, testload(:compressed_pyarrow; eager_page_scanning=false))
        end
        # Test edge case where DataPageHeaderV2 is used
        # but no data needs to be compressed.
        # The behavior of pyarrow changed in v20
        # Ref: https://github.com/apache/arrow/pull/45367
        # This data was generated with the script from:
        # https://github.com/apache/parquet-testing/pull/71
        # This was ran on pyarrow v19.0.1 and the v20.0.0 RC2.
        #=
            import pyarrow as pa
            import pyarrow.parquet as pq

            # Create an array of 10 null values with integer type
            data = [None] * 10
            int_column = pa.array(data, type=pa.int32())

            # Create a table with one column
            table = pa.Table.from_arrays([int_column], names=['data'])

            # Write the table to a parquet file with specified settings
            pq.write_table(
                table,
                'null_integers.parquet',
                compression='zstd',  # Zstandard compression
                data_page_version='2.0'  # Explicitly set DataPageV2
            )
        =#
        tbl = (;data=Vector{Union{Missing,Int32}}(missing, 10),)
        @testset "pyarrow v19 page v2" begin
            table_compare(tbl, testload(:pyarrow_v19_page_v2_empty))
        end
        @testset "pyarrow v20 page v2" begin
            table_compare(tbl, testload(:pyarrow_v20_page_v2_empty))
        end
    end

    @testset "extratypes_fastparquet" begin
        ds = testload(:extra_types_fastparquet)
        tbl = Tables.Columns(ds)
        dct = make_json_dicts(1)[1]
        @test all(==(dct), tbl.jsons)
        @test tbl.jvm_timestamps == [DateTime(2022,3,8) + Day(i) + Minute(1) for i ∈ 0:4]
        # note that fastparquet outputs these not as strings but arrays
        vs = [b"a\0\0\0\0", b"ab\0\0\0", b"abc\0\0", b"abcd\0", b"abcde"]
        @test tbl.fixed_strings == vs
    end

    @testset "extratypes_pyarrow" begin
        ds = testload(:extra_types_pyarrow)
        tbl = Tables.Columns(ds)
        @test all(x -> x isa DecFP.DecimalFloatingPoint, tbl.decimals)
        @test tbl.decimals == Dec64[1.0, 2.1, 3.2, 4.3, 5.4]
        @test tbl.dates == [Date(1990,1,i) for i ∈ 1:5]
        @test tbl.times_of_day == [Time(i) for i ∈ 1:5]
    end

    @testset "hive_fastparquet" begin
        ds = testload(:hive_fastparquet; load_initial=true)
        tbl = Tables.Columns(ds)
        @test tbl.A == string.([1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3])
        @test tbl.B == [fill("alpha", 8); fill("beta", 4)]
        @test tbl.data1 == 1.0:12.0
        @test tbl.data2 ≐ [1:11; missing]
    end

    @testset "directory_tree" begin
        ds = testload(:hive_fastparquet)
        @test length(ds) == 0  # this shouldn't load until say so
        @test names(ds) == ["A", "B", "data1", "data2"]
        append!(ds, A="3", B="alpha")  # this one doesn't exist
        @test length(ds) == 0
        append!(ds, "A"=>"1", "B"=>"alpha")
        tbl = Tables.Columns(ds)
        @test tbl.A == fill("1", 4)
        @test tbl.B == fill("alpha", 4)
        Parquet2.appendall!(ds)
        @test length(ds) == 3
        tbl = Tables.Columns(ds)
        @test names(ds) == ["A", "B", "data1", "data2"]
        @test tbl.A == [fill("1", 4); fill("2", 4); fill("3", 4)]
        @test tbl.B == [fill("alpha", 8); fill("beta", 4)]
    end

    @testset "simple_spark" begin
        ds = testload(:simple_spark)
        Parquet2.appendall!(ds)
        tbl = Tables.Columns(ds)
        @test tbl.A == ["test1", "test2"]
        @test tbl.id == [1, 2]
        @test tbl.Date == [Date(2020,1,1), Date(2020,1,2)]
    end

    @testset "read_modes" begin
        tbl = random_test_table()
        @testset "from_vector" begin
            ds = Dataset(read(testfilename(:rand_fastparquet)))
            table_compare(tbl, ds)
        end
        @testset "from_io" begin
            open(testfilename(:rand_pyarrow)) do io
                table_compare(tbl, Dataset(io))
            end
        end
        @testset "by_column" begin
            ds = Dataset(testfilename(:rand_fastparquet), subset_length=512, fetch_by_column=true)
            table_compare(tbl, ds)
        end
    end

    @testset "select" begin
        tbl = random_test_table()
        nt = testload(:rand_pyarrow) |> Parquet2.select(:floats, :ints) |> Tables.columntable
        @test keys(nt) == (:floats, :ints)
        @test nt.floats ≐ tbl.floats
        @test nt.ints ≐ tbl.ints
    end

    @testset "pyarrow_dec128" begin
        tbl = (rate=Dec64.([0.8275, 0.5104, 0.3421, 0.9132, 0.4081]),)
        table_compare(testload(:pyarrow_dec128), tbl)
    end
end

@testset "write" begin
    @testset "std" begin
        tbl = standard_test_table()
        @testset "buffer" begin
            v = writefile(Vector{UInt8}, tbl; compression_codec=:zstd)
            table_compare(Dataset(v), tbl)
        end
        @testset "file" begin
            write_file(tbl) do path
                table_compare(Dataset(path), tbl)
            end
        end
    end

    @testset "rand" begin
        tbl = random_test_table()
        @testset "buffer" begin
            v = writefile(Vector{UInt8}, tbl; compression_codec=:snappy)
            table_compare(Dataset(v), tbl)
        end
        @testset "file" begin
            write_file(tbl) do path
                table_compare(Dataset(path), tbl)
            end
        end
    end

    @testset "decimal" begin
        tbl = (A=[Dec64(0.1), missing, Dec64(0.002), Dec64(0.3), Dec64(-0.04)],)
        v = writefile(Vector{UInt8}, tbl)
        table_compare(Dataset(v), tbl)
    end

    @testset "extra_compression_codecs" begin
        tbl = standard_test_table()
        #WARN: something incredibly fishy is happening here, works for some files but not others
        #@testset "lz4_raw" begin
        #    v = writefile(Vector{UInt8}, tbl; compression_codec=:lz4_raw)
        #    table_compare(Dataset(v), tbl)
        #end
        @testset "gzip" begin
            v = writefile(Vector{UInt8}, tbl; compression_codec=:gzip)
            table_compare(Dataset(v), tbl)
        end
        @testset "uncompressed" begin
            v = writefile(Vector{UInt8}, tbl; compression_codec=:uncompressed)
            table_compare(Dataset(v), tbl)
        end
    end

    @testset "extra_types" begin
        tbl = (dates=Date(1997,1,1) .+ Day.(1:5),
               times=Time(0) .+ Minute.(1:5),
               bools=[false,true,false,true,false],
               bools_missing=[false,missing,false,true,false],
               jsons=make_json_dicts(5),
               bsons=make_json_dicts(5),
               uuids=UUID.(UInt128.(1:5)),
               # decimals not yet supported
              )
        v = writefile(Vector{UInt8}, tbl; bson_columns=["bsons"])
        table_compare(Dataset(v), tbl)
    end

    @testset "yellow_tripdata" begin
        ds = testload(:yellow_tripdata)
        @test length(ds) == 0
        @test length(Parquet2.filelist(ds)) == 4
        append!(ds, 1)
        @test length(ds) == 1
        tbl = Tables.Columns(ds)
        @test length(tbl) == 22
        @test length(tbl.extra) == 10
        Parquet2.appendall!(ds)
        @test length(ds) == 4
        tbl = Tables.Columns(ds)
        @test length(tbl) == 22
        @test length(tbl.trip_distance) == 40
    end

    @testset "empty" begin
        tbl = (;)
        v = writefile(Vector{UInt8}, tbl)
        @test isempty(Tables.columntable(Dataset(v)))
    end

    @testset "partitions" begin
        tbls = ((A=1:3,), (A=4:6,))
        io = IOBuffer()
        fw = Parquet2.FileWriter(io)
        Parquet2.writeiterable!(fw, tbls)
        v = take!(io)
        ds = Dataset(v)
        table_compare(ds[1], tbls[1])
        table_compare(ds[2], tbls[2])
    end

    @testset "dictionary" begin
        v = [1, 1, 2, 2, missing]
        # this test will also validate PooledVector interface
        tbl = (A=Parquet2.PooledVector([1,2], Union{UInt32,Missing}[0,0,1,1,missing]),)
        buf = writefile(Vector{UInt8}, tbl)
        ds = Dataset(buf, lazy_dictionary=true)
        @test Parquet2.load(ds[1][1]) ≐ v

        # ensure no disaster happens when we dictionary encode with only a single ref value
        v = [1,1,1]
        tbl = (A=Parquet2.PooledVector([1], UInt32[0,0,0]),)
        buf = writefile(Vector{UInt8}, tbl)
        ds = Dataset(buf)
        @test Parquet2.load(ds[1][1]) ≐ v
    end

    @testset "filemove" begin
        oldfn = "test_filemove.parquet"
        newfn = "test_filemove_new.parquet"
        df = (;x=[1])
        Parquet2.writefile(oldfn, df)
        mv(oldfn, newfn, force=true)
        ds = Parquet2.Dataset(newfn)
        @test Tables.columntable(ds).x[1] == 1
        rm(newfn)
    end

end

# extra functionality that doesn't quite fit into reading or writing alone
@testset "auxiliary" begin
    @testset "metadata" begin
        tbl = standard_test_table(5)
        file_metadata = Dict("pepe"=>"silvia", "carol"=>"hr")
        col_metadata_1 = Dict("mac"=>nothing)
        col_metadata_2 = Dict("dennis"=>"reynolds")
        v = writefile(Vector{UInt8}, tbl;
                      metadata=file_metadata,
                      column_metadata=Dict("ints"=>col_metadata_1, "floats"=>col_metadata_2),
                     )
        ds = Dataset(v)
        table_compare(ds, tbl)
        @test Parquet2.metadata(ds) == file_metadata
        @test Parquet2.metadata(ds[1]["ints"]) == col_metadata_1
        @test Parquet2.colmetadata(ds[1], :ints, "mac") ≡ nothing
        @test Parquet2.metadata(ds[1]["floats"]) == col_metadata_2
        @test Parquet2.colmetadata(ds[1], :floats, "dennis") == "reynolds"
        @test Parquet2.colmetadata(ds, :ints, "mac") ≡ nothing
        @test Parquet2.colmetadata(ds, :floats, "dennis") == "reynolds"
    end

    @testset "statistics" begin
        tbl = standard_test_table(5)
        statscols = ["floats", "ints_missing", "strings", "timestamps"]
        v = writefile(Vector{UInt8}, tbl; compute_statistics=statscols)
        popfirst!(statscols)
        ds = Dataset(v; use_statistics=statscols)
        o = Tables.columntable(ds)
        @test all(v -> v isa VectorWithStatistics, [getproperty(o, Symbol(n)) for n ∈ statscols])
        @test all(v -> !(v isa VectorWithStatistics), [getproperty(o, n) for n ∈ keys(o) if string(n) ∉ statscols])
        @test minimum(o.ints) == 1
        @test maximum(o.ints) == 5
        @test minimum(o.timestamps) == DateTime(1970,1,1,0,1)
        @test maximum(o.timestamps) == DateTime(1970,1,1,0,5)
        @test count(ismissing, o.ints_missing) == 1
        @test count(!ismissing, o.ints_missing) == 4
        @test Parquet2.ndistinct(o.strings) == length(unique(o.strings))

        # should still have computed stats for floats
        stats = Parquet2.ColumnStatistics(ds[1]["floats"])
        @test minimum(stats) == 0.0
        @test maximum(stats) == 1.0
        @test Parquet2.ndistinct(stats) == 5
    end

    # see https://github.com/JuliaFolds/Transducers.jl/issues/524
    @testset "promotions" begin
        tbl = (A=[1,2], B=[1.0,2.0])
        v = writefile(Vector{UInt8}, tbl)
        ds = Dataset(v)
        tbl′ = Tables.columns(ds)
        @test eltype(tbl′.A) ≡ Int
        @test eltype(tbl′.B) ≡ Float64
        @test tbl′.A == tbl.A
        @test tbl′.B == tbl.B
    end

    # want better de-init stuff in the future
    @testset "deinit" begin
        ds = testload(:extra_types_fastparquet)
        cols = Tables.columns(ds)  # ensure data is read in
        @test isnothing(close(ds))  # just testing to ensure no crash
    end

    @testset "PooledVector" begin
        v = Parquet2.PooledVector([1, 2, 3, 4], [missing, 0, 1, 2, 3])
        @test v ≐ [missing, 1, 2, 3, 4]
        @test Parquet2.DataAPI.refpool(v) ≐ [missing,1,2,3,4]
        @test Parquet2.DataAPI.refarray(v) == 1:5
    end

end

@warn("""
Are you absolutely sure you ran the python compat tests?
If you didn't and you merge this, you are an asshole who breaks other people's shit.     
""")


