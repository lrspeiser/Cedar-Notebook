```@meta
CurrentModule = Parquet2
```

# Internals


## [API](@id internals_api)
```@docs
ParquetType
PageBuffer
PageIterator
PageLoader
BitUnpackVector
PooledVector
ParqRefVector

decompressedpageview

bitpack
bitpack!
bitmask
bitjustify
bitwidth
bytewidth
readfixed
writefixed
HybridIterator
encodehybrid_bitpacked
encodehybrid_rle

maxdeflevel
maxreplevel
leb128encode
leb128decode

OptionSet
ReadOptions
WriteOptions
```
