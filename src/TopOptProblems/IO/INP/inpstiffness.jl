"""
Stiffness problem imported from a .inp file.
"""
struct InpStiffness{dim, N, TF, TI, TBool, Tch <: ConstraintHandler, GO, TInds <: AbstractVector{TI}, TMeta<:Metadata} <: StiffnessTopOptProblem{dim, TF}
    inp_content::InpContent{dim, TF, N, TI}
    geom_order::Type{Val{GO}}
    ch::Tch
    black::TBool
    white::TBool
    varind::TInds
    metadata::TMeta
end

"""
Imports stiffness problem from a .inp file.
"""
function InpStiffness(filepath_with_ext::AbstractString; keep_load_cells = false)
    problem = Parser.extract_inp(filepath_with_ext)
    return InpStiffness(problem; keep_load_cells = keep_load_cells)
end
function InpStiffness(problem::Parser.InpContent; keep_load_cells = false)
    ch = Parser.inp_to_juafem(problem)
    black, white = find_black_and_white(ch.dh)
    metadata = Metadata(ch.dh)
    geom_order = JuAFEM.getorder(ch.dh.field_interpolations[1])
    if keep_load_cells
        for k in keys(problem.cloads)
            for (c, f) in metadata.node_cells[k]
                black[c] = 1
            end
        end
    end
    varind = find_varind(black, white)
    return InpStiffness(problem, Val{geom_order}, ch, black, white, varind, metadata)
end

getE(p::InpStiffness) = p.inp_content.E
getν(p::InpStiffness) = p.inp_content.ν
nnodespercell(::InpStiffness{dim, N}) where {dim, N} = N
getgeomorder(p::InpStiffness{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, GO}) where {GO} = GO
getdensity(p::InpStiffness) = p.inp_content.density
getpressuredict(p::InpStiffness) = p.inp_content.dloads
getcloaddict(p::InpStiffness) = p.inp_content.cloads
getfacesets(p::InpStiffness) = p.inp_content.facesets
