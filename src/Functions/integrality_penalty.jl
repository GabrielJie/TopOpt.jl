@params mutable struct BinPenalty{T} <: AbstractFunction{T}
    solver::AbstractFEASolver
    s::T
    grad::AbstractVector{T}
    fevals::Int
    maxfevals::Int
end

@inline function Base.getproperty(vf::BinPenalty, f::Symbol)
    f === :reuse && return false
    return getfield(vf, f)
end
@inline function Base.setproperty!(vf::BinPenalty, f::Symbol, v)
    f === :reuse && return false
    return setfield!(vf, f, v)
end

function project(c::Constraint{<:Any, <:BinPenalty}, x)
    return round.(x)
end

function BinPenalty(solver::AbstractFEASolver, s::Number; maxfevals = 10^8)
    grad = similar(solver.vars)
    return BinPenalty(solver, s, grad, 0, maxfevals)
end
function (v::BinPenalty{T})(x, grad = v.grad) where {T}
    v.fevals += 1
    grad .= v.s .* (1 .- 2 .* x)
    if grad !== v.grad
        v.grad .= grad
    end
    return v.s * sum(x[i] * (1 - x[i]) for i in 1:length(x))
end
