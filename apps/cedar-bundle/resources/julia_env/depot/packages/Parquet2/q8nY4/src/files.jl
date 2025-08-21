
"""
    maybeparqfile(p)

Whether or not we think something is a parquet file based entirely on its file name.  Does not
include metadata.
"""
maybeparqfile(p::AbstractPath) = startswith(extension(p), "parq")

"""
    FileManager

Data structure containing references to `Vector{UInt8}` objects providing an interface to access any file in
a parquet file directory tree.  Is directory schema agnostic.
"""
struct FileManager{𝒫<:AbstractPath}
    directory::𝒫
    main_path::𝒫  # this is guaranteed to be the path to main_fetcher
    main::Buffer
    main_meta_only::Bool  # indicates main is metadata only (i.e. don't load row groups from here)
    aux::OrderedDict{𝒫,Union{Nothing,Buffer}}
    read_opts::ReadOptions
end

Base.dirname(fm::FileManager) = fm.directory

Base.joinpath(fm::FileManager, a...) = joinpath(dirname(fm), a...)

mainpath(fm::FileManager) = fm.main_path

function Base.read(opts::ReadOptions, p::AbstractPath)
    if p isa SystemPath && opts.use_mmap
        Mmap.mmap(p; grow=false, shared=opts.mmap_shared)
    else
        read(p)
    end
end

Base.read(fm::FileManager, p::AbstractPath) = read(fm.read_opts, p)

ReadOptions(fm::FileManager) = fm.read_opts

"""
    _should_load_initial(fm)

Decide whether it is appropriate to load initial row groups.  If the option is explicitly set, we obey it.

Otherwise, we try to load row groups iff there is a main metadata file.
"""
function _should_load_initial(fm::FileManager)
    if fm.read_opts.load_initial isa Bool
        fm.read_opts.load_initial
    else
        isempty(fm.aux)
    end
end

function Base.get(fm::FileManager, p::AbstractPath)
    isempty(p) && return fm.main  # we treat the empty path as a default path
    p = abspath(p) # I don't *think* this can ever result in remote calls...
    p == fm.main_path && return fm.main
    v = get(fm.aux, p, missing)
    ismissing(p) && throw(ArgumentError("path \"$p\" not known to Parquet2.FileManager"))
    if isnothing(v)
        v = read(fm, p)
        fm.aux[p] = v
    end
    v
end
Base.get(fm::FileManager) = fm.main

auxpaths(fm::FileManager) = keys(fm.aux)

function filelist(fm::FileManager)
    ps = collect(auxpaths(fm))
    fm.main_meta_only ? ps : [fm.main_path; ps]
end

# we don't keep file handles but this removes buffer references
function Base.close(fm::FileManager) 
    isempty(fm.aux) || keys(fm.aux) |> Map(k -> fm.aux[k] = nothing) |> foldxl(right)
    nothing
end

"""
    addpath!(fm::FileManager, p::AbstractPath)

Add the path of a file object to be managed.  This is lazy when using memory mapping but otherwise eager.
"""
addpath!(fm::FileManager, p::AbstractPath, v::Buffer) = (fm.aux[abspath(p)] = v)
addpath!(fm::FileManager, p::AbstractPath) = addpath!(fm, p, read(fm, p))

function _FileManager_file(p::AbstractPath, opts::ReadOptions)
    p = abspath(p)
    v = read(opts, p)
    FileManager{typeof(p)}(typeof(p)(), p, v, false, OrderedDict(), opts)
end

function _FileManager_dir(p::AbstractPath, opts::ReadOptions)
    p = abspath(p)
    # this should be the *only* call made to walkpath
    main = Ref{typeof(p)}()
    main_meta_only = false
    # we are careful not to call isdir because it might make remote calls
    fs = walkpath(p) |> Filter() do q
        maybeparqfile(q) && return true
        if basename(q) == "_metadata" && pathparent(q) == p
            main[] = q
            main_meta_only = true
        end
        false
    end |> collect |> sort!
    isempty(fs) && throw(ArgumentError("no parquet data found in directory \"$p\""))
    isassigned(main) || (main[] = popfirst!(fs))
    v = read(opts, main[])
    dct = OrderedDict{typeof(p),Union{typeof(v),Nothing}}(q=>nothing for q ∈ fs)
    FileManager{typeof(p)}(p, main[], v, main_meta_only, dct, opts)
end

"""
    FileManager(p::AbstractPath; use_mmap=true)

Create a Parquet2 file manager for root path `p`, using memory mapping for opening all files if
`use_mmap`.
"""
function FileManager(p::AbstractPath, opts::ReadOptions=ReadOptions())
    if isdir(p)
        _FileManager_dir(p, opts)
    elseif isfile(p)
        _FileManager_file(p, opts)
    else
        throw(ArgumentError("no file exists at \"$p\""))
    end
end
FileManager(p::AbstractString, opts::ReadOptions=ReadOptions()) = FileManager(Path(p), opts)

"""
    FileManager(v::AbstractVector, other_buffers::AbstractDict)

Create a Parquet2 file manager object directly only in-memory data.  Secondary buffers can be provided in a
dictionary with keys that are strings or `AbstractPath` objects giving the paths of the other buffers as
they would be specified in the parquet schema.
"""
function FileManager(v::Union{AbstractVector{UInt8},IO},
                     dct::AbstractDict=Dict();
                     kw...)
    p = Path()
    v = if v isa AbstractVector
        convert(Vector{UInt8}, v)
    else
        read(v)
    end
    opts = ReadOptions(;kw...)
    dct = OrderedDict{typeof(p),Union{Nothing,typeof(v)}}(Path(k)=>read(opts, v) for (k,v) ∈ dct)
    FileManager(Path(), p, v, false, dct, ReadOptions(;kw...))
end


"""
    PartitionNode

Representation of a node in a hive parquet schema partition tree.  Sastisfies the
[AbstractTrees](https://github.com/JuliaCollections/AbstractTrees.jl) interface.
"""
struct PartitionNode{𝒫<:AbstractPath}
    is_root::Bool
    path::𝒫
    name::String
    value::String
    children::Vector{PartitionNode{𝒫}}
end

AbstractTrees.children(n::PartitionNode) = n.children

function PartitionNode(wlk, dir::AbstractPath; is_root::Bool=false)
    name, value = if is_root
        "", ""
    else
        o = split(string(filename(dir)), "=")
        # we assume that if this only has one element it is the name
        length(o) == 1 ? (o[1], "") : (o[1], o[2])
    end
    # wlk is result of walkpath; must only be called once because of remote file systems
    ch = wlk |> Filter(p -> pathparent(p) == dir) |> Filter(p -> occursin("=", string(filename(p)))) |> collect
    # the below is because lazy recursion is horribly confusing
    ch = [PartitionNode(wlk, p; is_root=false) for p ∈ ch]
    PartitionNode{typeof(dir)}(is_root, dir, name, value, ch)
end

#TODO: this is still painfully inefficient... probably need to use walkpath result
function PartitionNode(dir::AbstractPath, files; kw...)
    wlk = files |> Map() do q
        parents(q) |> Filter(ρ -> isparent(dir, ρ))
    end |> Cat() |> collect
    PartitionNode(wlk, dir; kw...)
end

# use this function to create a dict that lives in RowGroups
function columns(n::PartitionNode{𝒫}, dir::𝒫, ℓ::Integer) where {𝒫<:AbstractPath}
    prs = Set(parents(dir))  # this is not returned as a set by default
    ns = PreOrderDFS(n) |> Filter(ν -> !ν.is_root) |> Filter(ν -> ν.path ∈ prs) |> Map() do ν
        ν.name => Fill{String}(ν.value, ℓ)
    end |> OrderedDict
end

Base.Pair(n::PartitionNode) = n.name=>n.value

columnnames(n::PartitionNode) = PreOrderDFS(n) |> Filter(ν -> !ν.is_root) |> Map(ν -> ν.name) |> Unique() |> collect

PartitionNode() = PartitionNode(true, Path(), "", "", PartitionNode{typeof(Path())}[])

PartitionNode(fm::FileManager) = PartitionNode(dirname(fm), keys(fm.aux); is_root=true)

directorystring(s::Pair{<:AbstractString,<:AbstractString}) = join((s[1], s[2]), "=")

function showtree(io::IO, n::PartitionNode)
    print_tree(io, n) do i, x
        if isempty(x.name) && isempty(x.value)
            print(i, "Root()")
        else
            show(i, Pair(x))
        end
    end
end
showtree(n::PartitionNode) = showtree(stdout, n)
