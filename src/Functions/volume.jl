@params mutable struct VolumeFunction{T, dim} <: AbstractFunction{T}
    problem::StiffnessTopOptProblem{dim, T}
    solver::AbstractFEASolver
    cellvolumes::AbstractVector{T}
    grad::AbstractVector{T}
    total_volume::T
    fixed_volume::T
    tracing::Bool
	topopt_trace::TopOptTrace{T}
    fraction::Bool
    fevals::Int
    maxfevals::Int
end

@inline function Base.getproperty(vf::VolumeFunction, f::Symbol)
    f === :reuse && return false
    return getfield(vf, f)
end
@inline function Base.setproperty!(vf::VolumeFunction, f::Symbol, v)
    f === :reuse && return false
    return setfield!(vf, f, v)
end
GPUUtils.whichdevice(v::VolumeFunction) = whichdevice(v.cellvolumes)
@define_cu(VolumeFunction, :cellvolumes, :grad, :problem) # should be optimized to avoid replicating problem

function project(c::Constraint{<:VolumeFunction}, x)
    V, f = c.s, c.f
    cellvolumes = f.cellvolumes
    if f.fraction
        V = V * f.total_volume        
    end
    inds = sortperm(x, rev=true)
    total = zero(V)
    i = 0
    while i <= length(inds)
        i += 1
        ind = inds[i]
        _total = total + cellvolumes[ind]
        _total >= V && break
        total = _total
    end
    x = zeros(eltype(x), length(x))
    x[inds[1:i]] .= 1
    return x
end

function VolumeFunction(problem::StiffnessTopOptProblem{dim, T}, solver::AbstractFEASolver, ::Type{TI} = Int; fraction = true, tracing = true, maxfevals = 10^8) where {dim, T, TI}
    dh = problem.ch.dh
    varind = problem.varind
    black = problem.black
    white = problem.white
    vars = solver.vars
    cellvolumes = solver.elementinfo.cellvolumes

    grad = zeros(T, length(vars))
    for (i, cell) in enumerate(CellIterator(dh))
        if !(black[i]) && !(white[i])
            grad[varind[i]] = cellvolumes[i]
        end
    end
    total_volume = sum(cellvolumes)
    fixed_volume = dot(black, cellvolumes)

    return VolumeFunction(problem, solver, cellvolumes, grad, total_volume, fixed_volume, tracing, TopOptTrace{T, TI}(), fraction, 0, maxfevals)
end
function (v::VolumeFunction{T})(x, grad) where {T}
    varind = v.problem.varind
    black = v.problem.black
    white = v.problem.white
    cellvolumes = v.cellvolumes
    total_volume = v.total_volume
    fixed_volume = v.fixed_volume
    fraction = v.fraction
    v.fevals += 1

    tracing = v.tracing
    topopt_trace = v.topopt_trace
    dh = v.problem.ch.dh
    xmin = v.solver.xmin

    vol = compute_volume(cellvolumes, x, fixed_volume, varind, black, white)

    constrval = fraction ? vol / total_volume : vol
    if fraction
        constrval = vol / total_volume
        grad .= v.grad ./ total_volume
        if tracing
            push!(topopt_trace.v_hist, vol/total_volume)
        end
    else
        constrval = vol
        grad .= v.grad    
        if tracing
            push!(topopt_trace.v_hist, vol)
        end
    end

    return constrval
end

function compute_volume(cellvolumes::Vector, x, fixed_volume, varind, black, white)
    vol = fixed_volume
    for i in 1:length(cellvolumes)
        if !(black[i]) && !(white[i])
            #vol += density(x[varind[i]], xmin)*cellvolumes[i]
            vol += x[varind[i]]*cellvolumes[i]
        end
    end
    return vol
end

function compute_volume(cellvolumes::CuVector{T}, x, fixed_volume, varind, black, white, ::Val{blocksize} = Val(80), ::Val{threads} = Val(256)) where {T, blocksize, threads}
    result = similar(cellvolumes, T, (blocksize,))
    args = (result, cellvolumes, x, varind, black, white, Val(threads))
    @cuda blocks = blocksize threads = threads volume_kernel(args...)
    CUDAnative.synchronize()
    vol = reduce(+, Array(result)) + fixed_volume
    return vol
end

function volume_kernel(result, cellvolumes::AbstractVector{T}, x, varind, black, white, ::Val{LMEM}) where {T, LMEM}
    @mapreduce_block(i, length(cellvolumes), +, T, LMEM, result, begin
        if !(black[i]) && !(white[i])
            x[varind[i]]*cellvolumes[i]
        else
            zero(T)
        end
    end)

    return
end
