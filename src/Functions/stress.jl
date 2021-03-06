### Experimental ###

function backsolve!(solver, Mu, global_dofs)
    dh = getdh(solver.problem)
    solver.rhs .= 0
    for i in 1:length(Mu)
        celldofs!(global_dofs, dh, i)
        solver.rhs[global_dofs] .+= Mu[i]
    end
    solver(assemble_f = false)
    return solver.lhs
end

get_sigma_vm(E_e, utMu_e) = E_e * sqrt(utMu_e)

function get_E(x_e::T, penalty, E0, xmin) where T
    if PENALTY_BEFORE_INTERPOLATION
        return E0 * density(penalty(x_e), xmin)
    else
        return E0 * penalty(density(x_e, xmin))
    end
end

function get_E_dE(x_e::T, penalty, E0, xmin) where T
    d = ForwardDiff.Dual{T}(x_e, one(T))
    if PENALTY_BEFORE_INTERPOLATION
        p = density(penalty(d, xmin))
    else
        p = penalty(density(d, xmin))
    end
    g = p.partials[1] * E0
    return p.value * E0, g
end

@inline function get_ϵ(u, ∇ϕ, i, j)
	return 1/2*(u[i]*∇ϕ[j] + u[j]*∇ϕ[i])
end
@inline function apply_T!(Tu, u, dh, cellidx, global_dofs, cellvalues, ν, ::Val{2})
    # assumes cellvalues is initialized before passing
    Tu[:] .= 0
    # Generalize to higher order field basis functions
    q_point = 1
    n_basefuncs = getnbasefunctions(cellvalues)
    dim = 2
    for a in 1:n_basefuncs
        ∇ϕ = shape_gradient(cellvalues, q_point, a)
        _u = @view u[(@view global_dofs[dim*(a-1) + 1 : a*dim])]
        ϵ_11 = get_ϵ(_u, ∇ϕ, 1, 1)
        ϵ_22 = get_ϵ(_u, ∇ϕ, 2, 2)
        ϵ_12 = get_ϵ(_u, ∇ϕ, 1, 2)

        ϵ_sum = ϵ_11 + ϵ_22

        temp1 = ν/(1-ν^2)
        temp2 = ν*(1+ν)

        Tu[1] += temp1*ϵ_sum + temp2*ϵ_11 # σ[1,1] / E
        Tu[2] += temp1*ϵ_sum + temp2*ϵ_22 # σ[2,2] / E
        Tu[3] += temp2*ϵ_12 # σ[1,2] / E
    end
    return Tu
end
@inline function apply_T!(Tu, u, dh, global_dofs, cellvalues, ν, ::Val{3})
    # assumes cellvalues is initialized before passing
    Tu[:] .= 0
    q_point = 1
    n_basefuncs = getnbasefunctions(cellvalues)
    dim = 3
    for a in 1:n_basefuncs
        ∇ϕ = shape_gradient(cellvalues, q_point, a)
        _u = @view u[(@view global_dofs[dim*(a-1) + 1 : a*dim])]
        ϵ_11 = get_ϵ(_u, ∇ϕ, 1, 1)
        ϵ_22 = get_ϵ(_u, ∇ϕ, 2, 2)
        ϵ_33 = get_ϵ(_u, ∇ϕ, 3, 3)
        ϵ_12 = get_ϵ(_u, ∇ϕ, 1, 2)
        ϵ_23 = get_ϵ(_u, ∇ϕ, 2, 3)
        ϵ_31 = get_ϵ(_u, ∇ϕ, 3, 1)

        ϵ_sum = ϵ_11 + ϵ_22 + ϵ_33

        temp1 = ν/(1-ν^2)
        temp2 = ν*(1+ν)

        Tu[1] += temp1*ϵ_sum + temp2*ϵ_11 # σ[1,1] / E
        Tu[2] += temp1*ϵ_sum + temp2*ϵ_22 # σ[2,2] / E
        Tu[3] += temp1*ϵ_sum + temp2*ϵ_33 # σ[3,3] / E
        Tu[4] += temp2*ϵ_12 # σ[1,2] / E
        Tu[5] += temp2*ϵ_23 # σ[2,3] / E
        Tu[6] += temp2*ϵ_31 # σ[3,1] / E
    end
    return Tu
end

@inline function fill_T!(T, ::Val{3}, cellvalues, ν)
    # assumes cellvalues is initialized before passing
    dim = 3
    temp1 = ν/(1-ν^2)
    temp2 = ν*(1+ν)
    q_point = 1
    n_basefuncs = size(T, 2) ÷ dim
    @assert size(T, 1) == 6
    for a in 1:n_basefuncs
        ∇ϕ = shape_gradient(cellvalues, q_point, a)
        cols = dim * (a - 1) + 1 : dim * a
        T[1, cols[1]] = (temp1 + temp2) * ∇ϕ[1]
        T[2, cols[1]] = temp1 * ∇ϕ[1]
        T[3, cols[1]] = temp1 * ∇ϕ[1]
        T[4, cols[1]] = temp2 * ∇ϕ[2] / 2
        T[5, cols[1]] = 0
        T[6, cols[1]] = temp2 * ∇ϕ[3] / 2
    
        T[1, cols[2]] = temp1 * ∇ϕ[2]
        T[2, cols[2]] = (temp1 + temp2) * ∇ϕ[2]
        T[3, cols[2]] = temp1 * ∇ϕ[2]
        T[4, cols[2]] = temp2 * ∇ϕ[1] / 2
        T[5, cols[2]] = temp2 * ∇ϕ[3] / 2
        T[6, cols[2]] = 0
    
        T[1, cols[3]] = temp1 * ∇ϕ[3]
        T[2, cols[3]] = temp1 * ∇ϕ[3]
        T[3, cols[3]] = (temp1 + temp2) * ∇ϕ[3]
        T[4, cols[3]] = 0
        T[5, cols[3]] = temp2 * ∇ϕ[2] / 2
        T[6, cols[3]] = temp2 * ∇ϕ[1] / 2
    end
    return T
end

@inline function fill_T!(T, ::Val{2}, cellvalues, ν)
    # assumes cellvalues is initialized before passing
    dim = 2
    temp1 = ν/(1-ν^2)
    temp2 = ν*(1+ν)
    q_point = 1
    n_basefuncs = size(T, 2) ÷ dim
    @assert size(T, 1) == 3
    for a in 1:n_basefuncs
        ∇ϕ = shape_gradient(cellvalues, q_point, a)
        cols = dim * (a - 1) + 1 : dim * a
        T[1, cols[1]] = (temp1 + temp2) * ∇ϕ[1]
        T[2, cols[1]] = temp1 * ∇ϕ[1]
        T[3, cols[1]] = temp2 * ∇ϕ[2] / 2
    
        T[1, cols[2]] = temp1 * ∇ϕ[2]
        T[2, cols[2]] = (temp1 + temp2) * ∇ϕ[2]
        T[3, cols[2]] = temp2 * ∇ϕ[1] / 2    
    end
    return T
end

@params struct StressTemp{T}
    VTu::AbstractVector{T}
    Tu::AbstractVector{T}
    Te::AbstractMatrix{T}
    global_dofs::AbstractVector{Int}
end
function StressTemp(solver)
    @unpack u, problem = solver
    @unpack dh = problem.ch
    T = eltype(u)
    dim = TopOptProblems.getdim(problem)
    k = dim == 2 ? 3 : 6
    VTu = zero(MVector{k, T})
    Tu = similar(VTu)
    n_basefuncs = getnbasefunctions(solver.elementinfo.cellvalues)
    Te = zero(MMatrix{k, dim*n_basefuncs, T})
    global_dofs = zeros(Int, ndofs_per_cell(dh))

    return StressTemp(VTu, Tu, Te, global_dofs)
end

function fill_Mu_utMu!(Mu, utMu, solver, stress_temp::StressTemp)
    @unpack problem, elementinfo, u = solver
    @unpack ch, ν = problem
    @unpack dh = ch
    @unpack VTu, Tu, Te, global_dofs = stress_temp

    _fill_Mu_utMu!(Mu, utMu, dh, elementinfo, u, ν, global_dofs, Tu, VTu, Te)
    return Mu, utMu
end

@inline function _fill_Mu_utMu!( Mu::AbstractVector, 
                        utMu::AbstractVector{T}, 
                        dh::DofHandler{3}, 
                        elementinfo, 
                        u, 
                        ν, 
                        global_dofs = zeros(Int, ndofs_per_cell(dh)), 
                        Tu = zeros(T, 6),
                        VTu = zeros(T, 6), 
                        Te = zeros(T, 6, ndofs_per_cell(dh))
                      ) where {T}
    dim = 3
    @unpack cellvalues = elementinfo
    for (cellidx, cell) in enumerate(CellIterator(dh))
        reinit!(cellvalues, cell)
        # Same for all elements
        fill_T!(Te, Val(3), cellvalues, ν)
        celldofs!(global_dofs, dh, cellidx)
        @views mul!(Tu, Te, u[global_dofs])

		VTu[1] = Tu[1] - Tu[2]/2 - Tu[3]/2
		VTu[2] = -Tu[1]/2 + Tu[2] - Tu[3]/2
		VTu[3] = -Tu[1]/2 - Tu[2]/2 + Tu[3]
		VTu[4] = 3*Tu[4]
		VTu[5] = 3*Tu[5]
		VTu[6] = 3*Tu[6]

        utMu_e = dot(Tu, VTu)
        @assert utMu_e > 0
        utMu[cellidx] = utMu_e
        Mu[cellidx] = Te' * VTu
	end
	return Mu, utMu
end

@inline function _fill_Mu_utMu!( Mu::AbstractVector, 
                        utMu::AbstractVector{T}, 
                        dh::DofHandler{2}, 
                        elementinfo, 
                        u, 
                        ν, 
                        global_dofs = zeros(Int, ndofs_per_cell(dh)), 
                        Tu = zeros(T, 3),
                        VTu = zeros(T, 3), 
                        Te = zeros(T, 3, ndofs_per_cell(dh))
                      ) where {T}
    dim = 2
    @unpack cellvalues = elementinfo
    for (cellidx, cell) in enumerate(CellIterator(dh))
        reinit!(cellvalues, cell)
        fill_T!(Te, Val(2), cellvalues, ν)
        celldofs!(global_dofs, dh, cellidx)
        @views mul!(Tu, Te, u[global_dofs])

        VTu[1] = Tu[1] - Tu[2]/2
		VTu[2] = -Tu[1]/2 + Tu[2]
		VTu[3] = 3*Tu[3]

        utMu_e = dot(Tu, VTu)
        @assert utMu_e > 0
        utMu[cellidx] = utMu_e
        Mu[cellidx] = Te' * VTu
	end
	return Mu, utMu
end

@params mutable struct GlobalStress{T} <: AbstractFunction{T}
    reducer
    reducer_g::AbstractVector{T}
    utMu::AbstractVector{T}
    Mu::AbstractArray
    sigma_vm::AbstractVector{T}
    solver
    global_dofs::AbstractVector{<:Integer}
    buffer::AbstractVector{T}
    stress_temp::StressTemp
    fevals::Int
    reuse::Bool
    maxfevals::Int
end
function GlobalStress(solver, reducer = WeightedKNorm(4, 1/length(solver.vars)); reuse = false, maxfevals = 10^8)
    T = eltype(solver.u)
    dh = solver.problem.ch.dh
    k = ndofs_per_cell(dh)
    N = getncells(dh.grid)
    global_dofs = zeros(Int, k)
    Mu = zeros(SVector{k, T}, N)
    utMu = zeros(T, N)
    stress_temp = StressTemp(solver)
    sigma_vm = similar(utMu)
    buffer = zeros(T, ndofs_per_cell(dh))
    reducer_g = similar(utMu)

    return GlobalStress(reducer, reducer_g, utMu, Mu, sigma_vm, solver, global_dofs, buffer, stress_temp, 0, reuse, maxfevals)
end

function (gs::GlobalStress{T})(x, g) where {T}
    @unpack sigma_vm, Mu, utMu, buffer, stress_temp = gs
    @unpack reuse, solver, global_dofs, buffer, reducer, reducer_g = gs
    @unpack elementinfo, u, penalty, problem, xmin = solver
    @unpack Kes = elementinfo
    @unpack dh = problem.ch
    E0 = problem.E
    gs.fevals += 1

    @assert length(global_dofs) == ndofs_per_cell(solver.problem.ch.dh)
    if !reuse
        solver()
        fill_Mu_utMu!(Mu, utMu, solver, stress_temp)
    end
    sigma_vm .= get_sigma_vm.(get_E.(x, Ref(penalty), E0, xmin), utMu)
    reduced = reducer(sigma_vm, reducer_g)
    for e in 1:length(Mu)
        Ee = get_E(x[e], penalty, E0, xmin)
        Mu[e] *= reducer_g[e] * Ee^2 / sigma_vm[e]
    end
    lhs = backsolve!(solver, Mu, global_dofs)

    for ep in 1:length(g)
        Eep, dEep = get_E_dE(x[ep], penalty, E0, xmin)
        celldofs!(global_dofs, dh, ep)
        t1 = reducer_g[ep] * Eep / sigma_vm[ep] * dEep * utMu[ep]
        @views t2 = -dEep * dot(lhs[global_dofs], bcmatrix(Kes[ep]) * u[global_dofs])
        g[ep] = t1 + t2
    end

    return reduced
end

struct LogSumExp <: Function end
function (lse::LogSumExp)(s, g_s)
    out = logsumexp(s)
    g_s .= exp.(s .- out)
    return out
end

struct KNorm <: Function
    k::Int
end
function (knorm::KNorm)(s, g_s)
    out = norm(s, knorm.k)
    g_s .= (s ./ out).^(k-1)
    return out
end

struct WeightedKNorm{T} <: Function
    k::Int
    w::T
end
function (wknorm::WeightedKNorm{T})(s, g_s) where {T}
    @unpack k, w = wknorm
    if T <: AbstractVector
        mw = MappedArray(w -> w^(1/k), w)
        out = norm(MappedArray(*, s, mw), k)
    else
        mw = w^(1/k)
        out = norm(BroadcastArray(*, s, mw), k)
    end
    g_s .= (s ./ out).^(k-1) .* mw
    return out
end
