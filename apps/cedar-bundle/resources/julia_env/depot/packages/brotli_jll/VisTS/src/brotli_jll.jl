# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule brotli_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("brotli")
JLLWrappers.@generate_main_file("brotli", UUID("4611771a-a7d2-5e23-8d00-b1becdba1aae"))
end  # module brotli_jll
