import PrecompileTools

PrecompileTools.@compile_workload begin
    N = 20
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
           # we don't currently have PooledArray as a real dependency, so can't do this
           #dictionary=PooledArray([repeat([1], a); repeat([2], a); repeat([3], a+b)]),
           #dictionary_missing=PooledArray([1; missing; repeat([3], N-2)]),
          )
    v = writefile(Vector{UInt8}, tbl)
    ds = Dataset(v)
    df = Tables.columntable(ds)
end
