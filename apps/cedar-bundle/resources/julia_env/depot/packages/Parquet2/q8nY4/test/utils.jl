using Test
using Parquet2
using Parquet2: Dataset, writefile


const ≐ = isequal

testload(file::Symbol; kw...) = Dataset(testfilename(file); kw...)

# this is deliberately broken into multiple tests to be more manageable
function table_compare(df1, df2)
    (cols1, cols2) = Tables.Columns.(Tables.columns.((df1, df2)))
    @test collect(propertynames(cols1)) == collect(propertynames(cols2))
    for ((k1,v1), (k2,v2)) ∈ zip(pairs(cols1), pairs(cols2))
        @test string(k1) == string(k2)
        @test v1 ≐ v2
    end
end

# we deliberately do this awkwardly to test reading/writing by filename
function write_file(𝒻, tbl)
    path = tempname()
    writefile(path, tbl)
    𝒻(path)
    isfile(path) && rm(path)
end

function py_compare(𝒻, tbl)
    v = writefile(Vector{UInt8}, tbl)
    table_compare(juliatable(𝒻(v)), tbl)
end
py_compare_fastparquet(tbl) = py_compare(pyloadbuffer_fastparquet, tbl)
py_compare_pyarrow(tbl) = py_compare(pyloadbuffer_pyarrow, tbl)
