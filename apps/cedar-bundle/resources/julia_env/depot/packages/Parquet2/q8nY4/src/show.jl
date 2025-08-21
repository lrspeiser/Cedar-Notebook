
show_nbytes(io::IO, n::Integer) = print(io, "(", n, " bytes)")

function show_schema_row(io::IO, n::Integer, name, type)
    print(io, "\t$n. ")
    printstyled(io, "\"", string(name), "\"", color=:yellow)
    print(io, ": ")
    printstyled(io, string(type), color=:cyan)
    print(io, "\n")
end

_split_type_string(obj) = split(sprint(show, typeof(obj)), "{")[1]

function Base.show(io::IO, ::MIME"text/plain", t::ParquetTable)
    printstyled(io, "≔ ", color=:blue)
    str = _split_type_string(t)
    print(io, str, " ")
    show_nbytes(io, nbytes(t))
    isnrowsknown(t) && printstyled(io, " (", nrow(t), " rows)", color=:green)
    print(io, "\n")
    sch = Tables.schema(t)
    if isempty(sch.names)
        printstyled(io, "\t[no columns]\n", color=:red)
    else
        foreach(tpl -> show_schema_row(io, tpl...), zip(1:length(sch.names), sch.names, sch.types))
    end
end
function Base.show(io::IO, t::ParquetTable)
    print(io, _split_type_string(t))
    print(io, "(ncolumns=", DataAPI.ncol(t), ")")
end

function Base.show(io::IO, ::MIME"text/plain", c::Column)
    printstyled(io, "⫶ ", color=:blue)
    print(io, typeof(c), " ")
    printstyled(io, sprint(show, name(c)), color=:yellow)
    isnothing(nbytes(c)) || show_nbytes(io, nbytes(c))
    if !isnothing(c.data) && c.data.compression_codec ≠ Meta.UNCOMPRESSED
        print(io, " ($(c.data.compression_codec) compressed) ")
    end
    printstyled(io, " (", nvalues(c), " rows)", color=:green)
    if !isnothing(c.data)
        print(io, "\n\t")
        if isempty(c.data.pages)
            printstyled(io, "[pages not loaded]")
        else
            printstyled(io, "[$(length(c.data.pages)) pages]", color=:magenta)
            hasdictencoding(c) && print(io, "  (dict encoded)")
        end
    end
end
Base.show(io::IO, c::Column) = print(io, typeof(c), "(\"", name(c), "\")")


function Base.show(io::IO, ::MIME"text/plain", fw::FileWriter)
    printstyled(io, "✏ ", color=:blue)
    print(io, typeof(fw), "(", fw.path, ")")
end
