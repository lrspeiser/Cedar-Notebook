# FNVHash

[![Build Status](https://github.com/ancapdev/FNVHash.jl/workflows/CI/badge.svg)](https://github.com/ancapdev/FNVHash.jl/actions)

Implementations of the Fowler–Noll–Vo hash functions.
See [Wikipedia](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function) for details.

## Usage
Two variants are implemented, `fnv1()` and `fnv1a()`, the latter is preferred for slightly better avalance characteristics

### Hashing strings
```Julia
s = "string to hash"
fnv1a(UInt32, s)  # 0xf474bad3
fnv1a(UInt64, s)  # 0xff0f01f28783a2d3
fnv1a(UInt128, s) # 0xe676f50e87fe52607a2c13a4c192bca3
```

### Hashing byte vectors
```Julia
data = [0x0, 0x1, 0x2, 0x3]
fnv1a(UInt32, data)  # 0xc3aa51b1
fnv1a(UInt64, data)  # 0x4475327f98e05411
fnv1a(UInt128, data) # 0x66ad33ec62757277b806e89d2ca0ff79
```

### Hashing raw data
```Julia
data = [0x0, 0x1, 0x2, 0x3]
GC.@preserve data begin
    raw = pointer(data)
    raw_len = sizeof(data)
    fnv1a(UInt32, raw, raw_len)  # 0xc3aa51b1
    fnv1a(UInt64, raw, raw_len)  # 0x4475327f98e05411
    fnv1a(UInt128, raw, raw_len) # 0x66ad33ec62757277b806e89d2ca0ff79
end
```

