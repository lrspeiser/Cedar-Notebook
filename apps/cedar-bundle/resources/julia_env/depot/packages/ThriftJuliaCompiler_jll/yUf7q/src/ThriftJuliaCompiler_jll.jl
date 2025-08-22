# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule ThriftJuliaCompiler_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("ThriftJuliaCompiler")
JLLWrappers.@generate_main_file("ThriftJuliaCompiler", UUID("815b9798-8dd0-5549-95cc-3cf7d01bce66"))
end  # module ThriftJuliaCompiler_jll
