using Parquet2
using Documenter

DocMeta.setdocmeta!(Parquet2, :DocTestSetup, :(using Parquet2); recursive=true)

makedocs(;
    modules=[Parquet2],
    authors="Expanding Man <savastio@protonmail.com> and contributors",
    repo=Remotes.GitLab("ExpandingMan", "Parquet2.jl"),
    sitename="Parquet2.jl",
    pages=[
        "Home" => "index.md",
        "API" => "api.md",
        "Developer Documentation" => ["internals.md",
                                      "dev.md",
                                     ],
        "FAQ" => "faq.md",
       ],
    warnonly=true,  #TODO: resolve issues and remove this
)
