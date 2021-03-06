mutable struct StandardSimplexe{T} <: AbstractStandard{T}
    M::Array{T, 2}
    A::Array{T, 2}
    b::Array{T, 1}
    c::Array{T, 1}
    Binv::Array{T, 2}
    b_idx_initial::Array{Int, 1}
    xstar::Array{T, 1}
    vstar::T
    b_idx::Array{Int, 1}
    status::AbstractStatus
    function StandardSimplexe(A::Array{T, 2}, b::Array{T, 1}, c::Array{T, 1}; verbose::Bool = true, b_idx::Array{Int, 1} = [-1]) where T
        m,n = size(A)
        @assert !(typeof(T) <: Integer)  "Type $T cannot be a subtype of Integer"
        @assert length(b) == m "dimension of A and b mismatch, size(A) = ($m, $n), length(b) = $(length(b)) != $m"
        @assert length(c) == n "dimension of A and c mismatch, size(A) = ($m, $n), length(c) = $(length(c)) != $n"
        @assert rank(A) == m "A is not a full rank Matrix"
        ss = new{T}()
        ss.xstar = T[],  
        ss.vstar = T(Inf) 
        ss.status = status
        ss.A = copy(A)
        ss.b = copy(b)
        ss.c = copy(c)
        
        if b_idx != [-1]
            #if a first base is given, we use it
            M = [A b; c' T(0)]
            @assert all(areisolate(M[:, b_idx[i]], i) for i in 1:m) "base given contains non isolated index" 
            BInv = Array{T, 2}(I, m, m)
            ss.Binv = Binv
            ss.b_idx = copy(b_idx)
            ss.b_idx_initial = copy(b_idx)
            ss.M = M
        else
            Binv = Array{T, 2}(I, m, m)
            for k in 1:m
                if b[k] <  0
                    Binv[i, i] = -one(T)
                    A[k, :] = -A[k, :]
                    b[k] = -b[k]
                end
            end
            M, b_idx = phase1(A,b,c, verbose = verbose)
            B = ss.A[:, b_idx]
            Binv = Binv*inv(B)#could be much better. Lazy code
            ss.Binv = Binv
            ss.b_idx = copy(b_idx)
            ss.b_idx_initial =  copy(b_idx)
            ss.M = M
            status = (b_idx == [-1]) ? Infeasible() : Unknown()
        end
        return ss
    end
end
function areisolate(v::Vector{T}, i::Int) where T
    m = length(v)
    return v[i] == one(T) && all(v[setdiff(1:m, i)] .== zero(T))
end
    
function xstar(ss::StandardSimplexe{T}) where T
    ss.status != Optimal() && @warn "probleme not optimal"
    return ss.xstar
end
function vstar(ss::StandardSimplexe{T}) where T
    ss.status != Optimal() && @warn "probleme not optimal"
    return ss.vstar
end
    

function println(ss::StandardSimplexe)
    m, n = size(ss.M)
    prd = "+" * prod("-------+" for _ in 1:n+1)
    println(prd)
    print("| V.B.  |")
    for k in 1:n-1
        s = ""
        xk = " x_$k "
        s*= xk
        s*= prod(" " for _ in 1:7-length(xk))
        print(s)
        print("|")
    end
    
    print(" T.D.  |")
    println()
    println(prd)
    for i in 1:m
        if i != m
            s = "| "#------"
            xk = "x_$(ss.b_idx[i])"
            s*= xk
            s*= prod(" " for _ in 1:6-length(xk))
            print(s)
        else
            print("| -z    ")
        end
        for j in 1:n
            print("| ")
            str = string(Float64(ss.M[i, j]))
            if length(str) >= 5
                str = str[1:5]
            end
            print(str)
            if length(1:(5 - length(str))) != 0
                print(prod(" "  for _ in 1:(5 - length(str))))
            end
            print(" ")
        end
        println("|")
        println(prd)
    end
end

function phase1(A::Matrix{T},b::Vector,c::Vector; verbose::Bool = false) where  T
    m, n = size(A)
    base = -ones(Int, m)
    for k in 1:n
        if count(t -> t > 0, A[:, k]) == 1#recherche d'une variable isol??e
            i = findfirst(t -> t > 0,  A[:, k])
            base[i] = k
        end
    end
    #we need to add an artificial variable for all line with no isolated variables
    added = findall(t -> t == -1, base)
    
    for (i, j) in enumerate(base)
        if j > 0
            pivot!(A, i, j)
        end
    end
    
    if length(added) == 0
        M = [A b; c' T(0)]
        for (i,j) in enumerate(base)
            pivot!(M, i, j)
        end
        return M, base
    end

    M = [A hcat([ei(T, k, m) for k in added]...) b; zeros(T, 1, n) ones(T, 1, length(added)) zero(T)]
    
    base[added] = n+1:n+length(added)
    for k in 1:length(base)
        if base[k] > n
            pivot!(M, k, base[k])
        end
    end
    
    phase1 = StandardSimplexe(M, base)
    verbose && println("simplexe array of phase 1")
    verbose && println(phase1)
    solve!(phase1)
    verbose && println("solved simplexe array of phase 1")
    verbose && println(phase1)
    #if the simplexe array  is optimal but the objective value is different then 0
    if (phase1.status == Optimal()) && (phase1.vstar != zero(T))
        println("probleme is unfeasible")
        return [phase1.M[1:m, 1:n] phase1.M[1:m, end]; c' zero(T)], [-1]
    else
        @assert issubset(base, 1:n) "artificial variable in base of phase 1"
        M = [phase1.M[1:m, 1:n] phase1.M[1:m, end]; c' zero(T)]
        base = phase1.b_idx
        for (i,j) in enumerate(base)
            pivot!(M, i, j)
        end

        return M, base
    end
end
                                
function isOptimal(ss::StandardSimplexe{T}) where T
    return all(ss.M[end, 1:end-1] .>= -10*eps())
end                     


function solve!(ss::StandardSimplexe{T}; verbose::Bool = false, kmax = 1000, pivotrule::Function = findpivot) where T
    k = 0
    if ss.status == Infeasible()
        return ss.status
    end
    m2, n2 = size(ss.M)
    m, n = m2 - 1,  n2 -1
    while !isOptimal(ss) && (k+=1) <= kmax
        verbose && println(ss)
        i, j = pivotrule(ss, verbose = verbose)
        if i == -1
            ss.status = Unbounded()
            break
        end
        pivot!(ss.M, i, j)
        ss.b_idx[i] = j
    end
    if isOptimal(ss) 
        ss.status = Optimal()
        ss.xstar = zeros(T, n)
        ss.xstar[ss.b_idx] = ss.M[1:end-1, end]
        ss.vstar = -ss.M[end, end]
    end  
    status = ss.status
    verbose &&(println("$status Simplexe");  println(ss))
    ss.Binv = ss.M[1:end-1, b_idx_initial] * ss.Binv
    ss.status
end

function findpivot(ss::StandardSimplexe{T}; verbose::Bool = false) where T
    M = ss.M
    m = size(M, 2) - 1 #changed 1 to 2
    c = ss.M[end, 1:end-1]
    b=  ss.M[1:end-1, end]
    entering = argmin(b) #argmin(c) changed to b
    verbose && @show entering
    @assert c[entering] < 0 "simplexe is in an optimal state" #ss was optimal
    val = T(Inf)
    leaving = -1
    for k in 1:m
        if (M[k, entering] > 0) && ((tobeat = c[k]/M[k, entering]) < val) #changed b to c
            leaving = k
            val = tobeat
        end
    end
    verbose && @show leaving
    return leaving, entering
end

function findpivotUsingBlandrules(ss::StandardSimplexe{T}; verbose::Bool = false) where T
    M = ss.M
    m = size(M, 1) - 1
    c = ss.M[end, 1:end-1]
    b=  ss.M[1:end-1, end]
    
    
    entering = findfirst(t -> t < 0, c)
    verbose && @show entering
    @assert !isnothing(entering) "simplexe is in an optimal state"
    yls = M[1:end-1, entering]
    val = T(Inf)
    leaving = -1
    for k in 1:m
        if (M[k, entering] > 0) && ((tobeat = b[k]/M[k, entering]) < val)
            leaving = k
            val = tobeat
        end
    end
    verbose && @show leaving
    return leaving, entering
end
    
    
    
