using Dates, UUIDs, Random, PooledArrays, OrderedCollections, JSON3, Transducers, StableRNGs


rand_len_string(rng::AbstractRNG, ℓ=rand(rng,0:16)) = randstring(rng, ℓ)
rand_len_strings(rng::AbstractRNG, N::Integer) = 1:N |> Map(i -> rand_len_string(rng)) |> collect

rand_timestamps(rng::AbstractRNG, N::Integer) = rand(rng, DateTime(1970,1,1):Second(1):DateTime(1985,11,5), N)


# this actually uses `nothing` instead of missing because of pandas
function rand_missing(rng::AbstractRNG, v::AbstractVector)
    n = length(v)
    rand(rng, Bool, n) |> Enumerate() |> MapSplat() do i, b
        b ? missing : v[i]
    end |> collect
end

function standard_test_table(N::Integer=500)
    (a, b) = divrem(N,3)
    tbl = (floats=collect(range(0.0, 1.0, length=N)),
           floats_missing=replace!(collect(Union{Missing,Float64}, 1.0:float(N)), 2.0=>missing),
           ints=collect(1:N),
           ints_missing=[1; missing; 3:N],
           ushorts=collect(UInt16(1):UInt16(N)),
           shorts=collect(Int16(1):Int16(N)),
           strings=[repeat(["kirk"], a); repeat(["spock"], a); repeat(["bones"], a+b)],
           strings_missing=["what up"; missing; repeat(["what up?"], N-2)],
           timestamps=DateTime(1970,1,1) .+ Minute.(1:N),
           timestamps_missing=[DateTime(1970,1,1); missing; DateTime(1970,1,1) .- Second.(3:N)],
           missings=fill(missing, N),
           dictionary=PooledArray([repeat([1], a); repeat([2], a); repeat([3], a+b)]),
           dictionary_missing=PooledArray([1; missing; repeat([3], N-2)]),
          )
end

function random_test_table(N::Integer=500, rng::AbstractRNG=StableRNG(999))
    tbl = (floats=randn(rng, N),
           floats_missing=rand_missing(rng, randn(rng, N)),
           ints=rand(rng, -1000:1000, N),
           ints_missing=rand_missing(rng, rand(rng, -1000:1000, N)),
           strings=rand_len_strings(rng, N),
           strings_missing=rand_missing(rng, rand_len_strings(rng, N)),
           timestamps=rand_timestamps(rng, N),
           timestamps_missing=rand_missing(rng, rand_timestamps(rng, N)),
           dictionary=PooledArray(rand(rng, -10:10, N)),
           dictionary_missing=PooledArray(rand_missing(rng, rand(rng, -10:10, N))),
          )
end

make_json_dicts(n::Integer=1) = repeat([Dict("a"=>1, "b"=>[1, "kirk"], "c"=>Dict("name"=>"chekov", "rank"=>100))], n)

testfilename(s::Symbol) = joinpath(@__DIR__,"data",string(s)*".parq")
