# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule snappy_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("snappy")
JLLWrappers.@generate_main_file("snappy", UUID("fe1e1685-f7be-5f59-ac9f-4ca204017dfd"))
end  # module snappy_jll
