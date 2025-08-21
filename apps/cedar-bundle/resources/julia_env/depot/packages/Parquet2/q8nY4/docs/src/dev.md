# Development Notes

## Efficiency
Frankly, much of the early development of this package was driven by overly optimistic ideas on my
part about the compatibility of the parquet encoding with conventional representations in memory
of Julia objects (or objects in most other languages, for that matter).  I wanted the option to do
just about anything lazily.

Unfortunately, there are several huge, CPU-intensive limitations to the format:
- Parquet takes nullable values *way* too seriously.  There are no placeholders for null values.
    While obviously this can lead to a drastic reduction in data size for tables containing lots of
    null data, it has the consequence that even the possibility of the presence of a single null in
    a column makes it completely impossible to predict the location of any particular piece of
    column data.  From my perspective as a scientific/numerical person this seems like an insane
    choice, especially since the format supports compression that in almost all cases will likely
    eliminate a lot of the redundancy of null placeholders.  The fact that parquet fully implements
    ["Dremel"](https://en.wikipedia.org/wiki/Dremel_(software)) might suggest that its designers had
    some incredibly specific use cases for the format mostly related to web servers, and I suspect
    that the unfortunate choice of how nulls are handled is an artifact of this.
- Imprudent use of pages by many parquet packages makes loading pages completely independently a
    dubious proposition.  If there is a large number of pages per columns, views of these would have
    to be somehow concatenated introducing an additional run-time cost if the entire column is not
    allocated ahead of time, not to mention the additional overhead of loading each page.
- Strings are stored inline with lengths rather than having separate offset data so that they can
    only be loaded sequentially and all at once.
- The use of dictionary encoding is poorly constrained, for example, it is perfectly acceptable to
    write an arbitrary mix of dictionary and non-dictionary pages in a single column, the only
    limitation being that the dictionary data can only have a single value page.  This means that
    you can't even decide how to handle the column outputs (i.e. what you should allocate) before
    reading all of the pages.
- While more recent versions of the spec do allow for storing page offsets in metadata, in practice
    no parquet files are actually written that way, and I'm not even sure if any writers exist that
    support it.  This means that reading pages is expensive, and because page metadata is stored
    inline with the pages, it's not even possible to obtain page metadata until the entire buffer
    has been iterated over.

All of the above paints a rather abysmal picture for CPU-efficiency of reading parquet files
(clearly the designers considered IO to be the only important consideraiton) but, far worse in our
case, it makes it nigh on impossible return lazy views into parquet data: in most cases and enormous
up-front cost must be paid to get *any* use of parquet data at all.  Many of the lazy optimizations
I most wanted when starting this package only work in special cases, and existing parquet writers
tend not to even care about those cases.

Having worked all this out has given me some additional perspective on the Apache arrow format which
I worked on somewhat previously.  While that format makes some odd choices and seems to suffer from
more than a little "feature creap", it's hard for me to imagine many cases in which parquet would be
preferable to arrow.

## Performance Issues
While I don't have a comprehensive set of benchmarks, microbenchmarks on performance critical pieces
of code show them to be highly optimized.  Anecdotally, Parquet2.jl should be about as fast as
other, older parquet readers (some of which are highly-optimized). Whatever performance issues might
still exist likely originate from somewhat "higher level" code, such as the code that handles the
`PageLoader` objects.

A huge portion of the development effort for this package was devoted to dealing with the so-called
["hybrid" integer
encoding](https://github.com/apache/parquet-format/blob/master/Encodings.md#run-length-encoding--bit-packing-hybrid-rle--3).
This mixes different types of integer array codings in a buffer in a way which it's not possible to
infer much about ahead of time.  As it is performance critical, it potentially introduces type
stability issues.  The solution I settled on is an iterator which returns the sub-arrays ("runs")
and we rely on Julia's union-splitting (efficient handling of small `Union` types) for iteration
over these to be performant.

During development I ran into a GC performance edge case (discussed in [this discourse
post](https://discourse.julialang.org/t/help-with-excessive-unpredictable-gc-time-from-string-allocations/77334))
in which the GC would constantly trigger inside of string-reading loops.  The solution to this was
to bypass the GC entirely which is mostly handled by
[WeakRefStrings.jl](https://github.com/JuliaData/WeakRefStrings.jl).

## Wanted Features
These are all considered "low priority" but would be nice to have.

### more complete introspection API
Some of the nice features I had early on while still mostly implemented stopped having a nice public
API as the package evolved.  In particular it's a bit annoying to dig into the details of serialized
columns and pages.  It would be nice to have a well-thought-out set of methods for dealing with file
internals.

### full support for column and page indexing
The most recent version of the metadata supports giving exact positions of pages in the buffer and a
few other pieces of metadata that are not otherwise accessible until pages are read.  In some cases,
Parquet2.jl internals can be drastically simplified with this, for example `PageLoader` objects
currently carry a mutable state because there is no way of determining a priori the location of page
metadata or the actual data buffers, perhaps even allowing `PageLoader` to be eliminated altogether.

Unfortunately, in practice there is likely to be little benefit to implementing this since I have
never even seen a package output parquets with full page metadata.  The simplifications this feature
could offer would be of little use since we'd always have to support the more complicated
no-metadata cases.

### more compression types
This should be very easy.  Of course we are limited by the options given in the spec.

### data encryption
Should be pretty easy, but it does involve some custom metadata that I don't quite understand yet.

### nested column types
This would require a comprehensive implementation of
["Dremel"](https://en.wikipedia.org/wiki/Dremel_(software)), ideally one that is not even specific
to parquet.  A full implementation of nested columns would likely involve a radical overhaul of
Parquet2.jl internals.  I very consciously decided *not* to implement it when I started.

### support decimal writing
The issue with decimals is that the scale and precision need to be determined for an entire column
(or at least entire column within a row-group) rather than per value.  As we don't currently have
any mechanism to do this, decimals are currently unsupported.
