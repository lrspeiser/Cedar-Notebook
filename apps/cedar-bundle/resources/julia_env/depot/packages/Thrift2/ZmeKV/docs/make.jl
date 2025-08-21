using Thrift2
using Documenter

DocMeta.setdocmeta!(Thrift2, :DocTestSetup, :(using Thrift2); recursive=true)

makedocs(;
    modules=[Thrift2],
    authors="ExpandingMan <savastio@protonmail.com> and contributors",
    repo=Remotes.GitLab("ExpandingMan", "Thrift2.jl"),
    sitename="Thrift2.jl",
    pages=[
        "Home" => "index.md",
        "API" => "api.md",
    ],
    warnonly=true,
)
