
# FAQ

## Which format should I use?
First off, parquet is *very* much a *tabular* format.  If the data you are looking to store is not
explicitly tabular, you don't want to use parquet.  See alternatives such as
[HDF5.jl](https://github.com/JuliaIO/HDF5.jl), [JLD2.jl](https://github.com/JuliaIO/JLD2.jl),
[LightBSON.jl](https://github.com/ancapdev/LightBSON.jl) or
[UnROOT.jl](https://github.com/tamasgal/UnROOT.jl).

If your format is tabular, you *probably* want to use [Arrow.jl](https://github.com/JuliaData/Arrow.jl).
The reason is that the arrow format is much closer to a natural in-memory format and as such will
be much less computationally expensive and require far fewer extra allocations than parquet in most
cases.

Parquet is best for large tabular datasets (``\gtrsim 10~\textrm{GB}``) where some level of compression
is desirable and very often the datasets are partitioned into multiple separate files.  In some
cases, the more efficient data storage comes at a high cost in terms of CPU usage and extra memory
allocations.  For example, null values are still present (as arbitrary bytes) in the underlying data
buffer.  In parquet they are skipped, meaning that the locations of individual elements in nullable
parquet columns are not knowable *a priori*.  A consequence of this is that reading nullable values
from parquet will always be significantly less efficient than loading the same values from arrow,
but the parquet itself will be smaller, particularly if there is a large number of nulls.

Of course, the most likely reason you will have to use parquet as opposed to arrow is because you
have been provided a parquet and simply have no say in the matter.  Parquet is arguably the most
ubiquitous binary format in "big data" applications and is often output by unpleasant but commonly
used (particularly JVM-based) programs in this domain such as apache spark.

**TL;DR:** Don't use parquet if not explicitly tabular.  If tabular, you are probably better off
with [Arrow.jl](https://github.com/JuliaData/Arrow.jl).  If you have large quantities of data or
have been given a parquet, use parquet.

## Why start from scratch instead of improving [Parquet.jl](https://github.com/JuliaIO/Parquet.jl)?
Most of the features I wanted would have required (at least) a major re-write of the existing
Parquet.jl, such as:
- Lazy loading of specific row groups and columns.
- Flexibility to load from alternate file systems such as S3.
- Progressive, cached loading from remote file systems.
- An API that is more decomposable into the basic schema components.
- Easier user interface with features such as `RowGroup`s that are full Tables.jl tables.

There really would not have been much left of the original package by the time I was through.

## How is this package's performance?
Microbenchmarks look very good, but in some cases there is room for improvement in some of the
higher-level code.  Keep in mind that unless you are reading form your local file system there is a
very good chance that file reading is IO limited in the first place, in which case there is very
little this package or any other can do for you.

One should also bear in mind that it is not possible to choose default settings
which are optimal in all situations, some options the user might want to consider experimenting with
when reading include:
- `use_mmap`: Memory mapping is enabled by default and should always be strictly the better option
    where available.
- `parallel_page_loading`: Whether pages are loaded on parallel threads.  This has not been
    implemented for strings.  Non-string columns with very many pages may benefit from turning this
    on (many pages are more likely if there are a huge number of values per row group, certain
    parquet writers are also extremely page-happy).
- `parallel_column_loading`: This is enabled by default (if you are running Julia with multiple
    threads) and in some cases should drastically speed up reading.  There shouldn't be any
    situations where disabling it should make reading faster, but if you are IO limited it being
    enabled won't help you either.

Please note that the parquet format has significant unavoidable overhead particularly in the
presence of dictionary-encoded columns and strings.  It will *never* be as fast as formats which are
optimized for performance such as arrow or HDF5, and we strongly encourage you to use one of those
if computational performance is a major issue.

Of course, if you are experiencing performance difficulties which you believe are due to this
package, please [open an issue](https://gitlab.com/ExpandingMan/Parquet2.jl/-/issues).


## I'm having trouble reading parquet consisting of multiple files
We *intend* to support the following multi-file formats:
- The "hive" directory format in which files are written in a tree with directory names providing
    column names and values.
- Directories in which multiple files with identical schema are stored in the same directory.

Unfortunately, as far as I can tell, there is nothing resembling a formal specification for either
of these cases, making them very hard to support reliably.  We believe that most writers do these
consistently following some apache implementation, but it's not even entirely clear this is the
case, so it remains to be seen whether it is even possible to support all multi-file use cases
without the user needing to specify additional metadata.

Therefore, it's unsurprising if there are multi-file edge cases that are not correctly handled by
Parquet2 yet.  If you encounter a case in which Parquet2 is not behaving correctly, please
[open an issue](https://gitlab.com/ExpandingMan/Parquet2.jl/-/issues), but be aware that it might be
difficult or impossible to cover your case if you cannot provide a minimum working sample.

Of course, in the worst case scenario, you should be able to read in files individually in a loop.

