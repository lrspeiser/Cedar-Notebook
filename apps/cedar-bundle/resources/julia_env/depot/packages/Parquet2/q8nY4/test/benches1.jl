using Parquet2
using Tables
using BenchmarkTools, ProfileView, Profile, Cthulhu
using Random

using Parquet2: Dataset, writefile


function testtable()
    floatcols = map(j -> convert(Vector{Union{Missing,Float64}}, [fill(missing, 2); 1:498]), 1:100)
    stringcols = map(j -> convert(Vector{Union{Missing,String}}, [fill(missing, 2); fill("teststr", 498)]), 1:100)
    cols = [floatcols; stringcols]
    NamedTuple(map(j -> Symbol("x$j")=>cols[j], 1:length(cols)))
end

writetest() = writefile(Vector{UInt8}, testtable())

function bench_write()
    @benchmark writefile(Vector{UInt8}, tbl) setup=(tbl = testtable())
end

function _profile_write(tbl)
    for j ∈ 1:1000
        writefile(Vector{UInt8}, tbl)
    end
end

function profile_write()
    tbl = testtable()
    @profview _profile_write(tbl)
end

function bench_dataset()
    v = writefile(Vector{UInt8}, testtable())
    @benchmark Dataset($v)
end

function _profile_dataset(v)
    for j ∈ 1:1000
        Dataset(v)
    end
end

function profile_dataset()
    tbl = testtable()
    v = writefile(Vector{UInt8}, tbl)
    @profview _profile_dataset(v)
end

function bench_load()
    v = writefile(Vector{UInt8}, testtable())
    @benchmark Tables.columns(ds) setup=(ds = Dataset($v, parallel_column_loading=false))
end

function profile_load()
    tbl = testtable()
    v = writefile(Vector{UInt8}, tbl)
    Profile.clear()
    before = ProfileView.Gtk.is_eventloop_running()
    try
        ProfileView.Gtk.enable_eventloop(false, wait_stopped=true)
        for j ∈ 1:1000
            ds = Dataset(v, parallel_column_loading=false)
            @profile Tables.columns(ds)
        end
    finally
        ProfileView.Gtk.enable_eventloop(before, wait_stopped=true)
    end
    ProfileView.view(windowname="profile")
end
