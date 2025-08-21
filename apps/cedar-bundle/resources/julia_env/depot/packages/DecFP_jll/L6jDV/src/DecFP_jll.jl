# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule DecFP_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("DecFP")
JLLWrappers.@generate_main_file("DecFP", UUID("47200ebd-12ce-5be5-abb7-8e082af23329"))
end  # module DecFP_jll
