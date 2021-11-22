module Finch

using Pigeon
using Pigeon: Dimensions, dimensionalize!, DefaultStyle, getname
using Pigeon: visit!
using SymbolicUtils
using SymbolicUtils: istree, arguments, operation, similarterm
using SymbolicUtils: Postwalk, Prewalk
using TermInterface
using MacroTools

export Virtual
export lower_julia

include("lower.jl")
include("virtuals.jl")


end