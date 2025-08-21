# This file is a part of Julia. License is MIT: https://julialang.org/license

using LinearAlgebra: AbstractTriangular, StridedMaybeAdjOrTransMat, UpperOrLowerTriangular,
    RealHermSymComplexHerm, checksquare, sym_uplo
using Random: rand!

# In matrix-vector multiplication, the correct orientation of the vector is assumed.
const DenseMatrixUnion = Union{StridedMatrix, BitMatrix}
const DenseTriangular  = UpperOrLowerTriangular{<:Any,<:DenseMatrixUnion}
const DenseInputVector = Union{StridedVector, BitVector}
const DenseVecOrMat = Union{DenseMatrixUnion, DenseInputVector}

for op ∈ (:+, :-), Wrapper ∈ (:Hermitian, :Symmetric)
    @eval begin
        $op(A::AbstractSparseMatrix, B::$Wrapper{<:Any,<:AbstractSparseMatrix}) = $op(A, sparse(B))
        $op(A::$Wrapper{<:Any,<:AbstractSparseMatrix}, B::AbstractSparseMatrix) = $op(sparse(A), B)

        $op(A::AbstractSparseMatrix, B::$Wrapper) = $op(A, collect(B))
        $op(A::$Wrapper, B::AbstractSparseMatrix) = $op(collect(A), B)
    end
end
for op ∈ (:+, :-)
    @eval begin
        $op(A::Symmetric{<:Any,  <:AbstractSparseMatrix}, B::Hermitian{<:Any,  <:AbstractSparseMatrix}) = $op(sparse(A), sparse(B))
        $op(A::Hermitian{<:Any,  <:AbstractSparseMatrix}, B::Symmetric{<:Any,  <:AbstractSparseMatrix}) = $op(sparse(A), sparse(B))
        $op(A::Symmetric{<:Real, <:AbstractSparseMatrix}, B::Hermitian{<:Any,  <:AbstractSparseMatrix}) = $op(Hermitian(parent(A), sym_uplo(A.uplo)), B)
        $op(A::Hermitian{<:Any,  <:AbstractSparseMatrix}, B::Symmetric{<:Real, <:AbstractSparseMatrix}) = $op(A, Hermitian(parent(B), sym_uplo(B.uplo)))
    end
end

LinearAlgebra.generic_matmatmul!(C::StridedMatrix, tA, tB, A::SparseMatrixCSCUnion, B::DenseMatrixUnion, _add::MulAddMul) =
    spdensemul!(C, tA, tB, A, B, _add)
LinearAlgebra.generic_matmatmul!(C::StridedMatrix, tA, tB, A::SparseMatrixCSCUnion, B::AbstractTriangular, _add::MulAddMul) =
    spdensemul!(C, tA, tB, A, B, _add)
LinearAlgebra.generic_matvecmul!(C::StridedVecOrMat, tA, A::SparseMatrixCSCUnion, B::DenseInputVector, _add::MulAddMul) =
    spdensemul!(C, tA, 'N', A, B, _add)

Base.@constprop :aggressive function spdensemul!(C, tA, tB, A, B, _add)
    if tA == 'N'
        _spmatmul!(C, A, LinearAlgebra.wrap(B, tB), _add.alpha, _add.beta)
    elseif tA == 'T'
        _At_or_Ac_mul_B!(transpose, C, A, LinearAlgebra.wrap(B, tB), _add.alpha, _add.beta)
    elseif tA == 'C'
        _At_or_Ac_mul_B!(adjoint, C, A, LinearAlgebra.wrap(B, tB), _add.alpha, _add.beta)
    elseif tA in ('S', 's', 'H', 'h') && tB == 'N'
        rangefun = isuppercase(tA) ? nzrangeup : nzrangelo
        diagop = tA in ('S', 's') ? identity : real
        odiagop = tA in ('S', 's') ? transpose : adjoint
        T = eltype(C)
        _mul!(rangefun, diagop, odiagop, C, A, B, T(_add.alpha), T(_add.beta))
    else
        LinearAlgebra._generic_matmatmul!(C, 'N', 'N', LinearAlgebra.wrap(A, tA), LinearAlgebra.wrap(B, tB), _add)
    end
    return C
end

function _spmatmul!(C, A, B, α, β)
    size(A, 2) == size(B, 1) || throw(DimensionMismatch())
    size(A, 1) == size(C, 1) || throw(DimensionMismatch())
    size(B, 2) == size(C, 2) || throw(DimensionMismatch())
    nzv = nonzeros(A)
    rv = rowvals(A)
    β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
    for k in 1:size(C, 2)
        @inbounds for col in 1:size(A, 2)
            αxj = B[col,k] * α
            for j in nzrange(A, col)
                C[rv[j], k] += nzv[j]*αxj
            end
        end
    end
    C
end

*(A::SparseMatrixCSCUnion{TA}, B::DenseTriangular) where {TA} =
    (T = promote_op(matprod, TA, eltype(B)); mul!(similar(B, T, (size(A, 1), size(B, 2))), A, B))

function _At_or_Ac_mul_B!(tfun::Function, C, A, B, α, β)
    size(A, 2) == size(C, 1) || throw(DimensionMismatch())
    size(A, 1) == size(B, 1) || throw(DimensionMismatch())
    size(B, 2) == size(C, 2) || throw(DimensionMismatch())
    nzv = nonzeros(A)
    rv = rowvals(A)
    β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
    for k in 1:size(C, 2)
        @inbounds for col in 1:size(A, 2)
            tmp = zero(eltype(C))
            for j in nzrange(A, col)
                tmp += tfun(nzv[j])*B[rv[j],k]
            end
            C[col,k] += tmp * α
        end
    end
    C
end

*(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, B::DenseTriangular) =
    (T = promote_op(matprod, eltype(A), eltype(B)); mul!(similar(B, T, (size(A, 1), size(B, 2))), A, B))

Base.@constprop :aggressive function LinearAlgebra.generic_matmatmul!(C::StridedMatrix, tA, tB, A::DenseMatrixUnion, B::AbstractSparseMatrixCSC, _add::MulAddMul)
    transA = tA == 'N' ? identity : tA == 'T' ? transpose : adjoint
    if tB == 'N'
        _spmul!(C, transA(A), B, _add.alpha, _add.beta)
    elseif tB == 'T'
        _A_mul_Bt_or_Bc!(transpose, C, transA(A), B, _add.alpha, _add.beta)
    else # tB == 'C'
        _A_mul_Bt_or_Bc!(adjoint, C, transA(A), B, _add.alpha, _add.beta)
    end
    return C
end
function _spmul!(C::StridedMatrix, X::DenseMatrixUnion, A::AbstractSparseMatrixCSC, α::Number, β::Number)
    mX, nX = size(X)
    nX == size(A, 1) || throw(DimensionMismatch())
    mX == size(C, 1) || throw(DimensionMismatch())
    size(A, 2) == size(C, 2) || throw(DimensionMismatch())
    rv = rowvals(A)
    nzv = nonzeros(A)
    β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
    @inbounds for col in 1:size(A, 2), k in nzrange(A, col)
        Aiα = nzv[k] * α
        rvk = rv[k]
        @simd for multivec_row in 1:mX
            C[multivec_row, col] += X[multivec_row, rvk] * Aiα
        end
    end
    C
end
function _spmul!(C::StridedMatrix, X::AdjOrTrans{<:Any,<:DenseMatrixUnion}, A::AbstractSparseMatrixCSC, α::Number, β::Number)
    mX, nX = size(X)
    nX == size(A, 1) || throw(DimensionMismatch())
    mX == size(C, 1) || throw(DimensionMismatch())
    size(A, 2) == size(C, 2) || throw(DimensionMismatch())
    rv = rowvals(A)
    nzv = nonzeros(A)
    β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
    for multivec_row in 1:mX, col in 1:size(A, 2)
        @inbounds for k in nzrange(A, col)
            C[multivec_row, col] += X[multivec_row, rv[k]] * nzv[k] * α
        end
    end
    C
end
*(X::StridedMaybeAdjOrTransMat, A::SparseMatrixCSCUnion{TvA}) where {TvA} =
    (T = promote_op(matprod, eltype(X), TvA); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))
*(X::Union{BitMatrix,AdjOrTrans{<:Any,BitMatrix}}, A::SparseMatrixCSCUnion{TvA}) where {TvA} =
    (T = promote_op(matprod, eltype(X), TvA); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))
*(X::DenseTriangular, A::SparseMatrixCSCUnion{TvA}) where {TvA} =
    (T = promote_op(matprod, eltype(X), TvA); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))

function _A_mul_Bt_or_Bc!(tfun::Function, C::StridedMatrix, A::AbstractMatrix, B::AbstractSparseMatrixCSC, α::Number, β::Number)
    mA, nA = size(A)
    nA == size(B, 2) || throw(DimensionMismatch())
    mA == size(C, 1) || throw(DimensionMismatch())
    size(B, 1) == size(C, 2) || throw(DimensionMismatch())
    rv = rowvals(B)
    nzv = nonzeros(B)
    β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
    @inbounds for col in 1:size(B, 2), k in nzrange(B, col)
        Biα = tfun(nzv[k]) * α
        rvk = rv[k]
        @simd for multivec_col in 1:mA
            C[multivec_col, rvk] += A[multivec_col, col] * Biα
        end
    end
    C
end
*(X::StridedMaybeAdjOrTransMat, A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) =
    (T = promote_op(matprod, eltype(X), eltype(A)); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))
*(X::Union{BitMatrix,AdjOrTrans{<:Any,BitMatrix}}, A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) =
    (T = promote_op(matprod, eltype(X), eltype(A)); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))
*(X::DenseTriangular, A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) =
    (T = promote_op(matprod, eltype(X), eltype(A)); mul!(similar(X, T, (size(X, 1), size(A, 2))), X, A, true, false))

# Sparse matrix multiplication as described in [Gustavson, 1978]:
# http://dl.acm.org/citation.cfm?id=355796

const SparseTriangular{Tv,Ti} = Union{UpperTriangular{Tv,<:SparseMatrixCSCUnion{Tv,Ti}},LowerTriangular{Tv,<:SparseMatrixCSCUnion{Tv,Ti}}}
const SparseOrTri{Tv,Ti} = Union{SparseMatrixCSCUnion{Tv,Ti},SparseTriangular{Tv,Ti}}

*(A::SparseOrTri, B::AbstractSparseVector) = spmatmulv(A, B)
*(A::SparseOrTri, B::SparseColumnView) = spmatmulv(A, B)
*(A::SparseOrTri, B::SparseVectorView) = spmatmulv(A, B)
*(A::SparseMatrixCSCUnion, B::SparseMatrixCSCUnion) = spmatmul(A,B)
*(A::SparseTriangular, B::SparseMatrixCSCUnion) = spmatmul(A,B)
*(A::SparseMatrixCSCUnion, B::SparseTriangular) = spmatmul(A,B)
*(A::SparseTriangular, B::SparseTriangular) = spmatmul1(A,B)
*(A::SparseOrTri, B::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) = spmatmul(A, copy(B))
*(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, B::SparseOrTri) = spmatmul(copy(A), B)
*(A::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}, B::AdjOrTrans{<:Any,<:AbstractSparseMatrixCSC}) = spmatmul(copy(A), copy(B))

# Gustavson's matrix multiplication algorithm revisited.
# The result rowval vector is already sorted by construction.
# The auxiliary Vector{Ti} xb is replaced by a Vector{Bool} of same length.
# The optional argument controlling a sorting algorithm is obsolete.
# depending on expected execution speed the sorting of the result column is
# done by a quicksort of the row indices or by a full scan of the dense result vector.
# The last is faster, if more than ≈ 1/32 of the result column is nonzero.
# TODO: extend to SparseMatrixCSCUnion to allow for SubArrays (view(X, :, r)).
function spmatmul(A::SparseOrTri, B::Union{SparseOrTri,AbstractCompressedVector,SubArray{<:Any,<:Any,<:AbstractSparseArray}})
    Tv = promote_op(matprod, eltype(A), eltype(B))
    Ti = promote_type(indtype(A), indtype(B))
    mA, nA = size(A)
    nB = size(B, 2)
    nA == size(B, 1) || throw(DimensionMismatch())

    nnzC = min(estimate_mulsize(mA, nnz(A), nA, nnz(B), nB) * 11 ÷ 10 + mA, mA*nB)
    colptrC = Vector{Ti}(undef, nB+1)
    rowvalC = Vector{Ti}(undef, nnzC)
    nzvalC = Vector{Tv}(undef, nnzC)

    @inbounds begin
        ip = 1
        xb = fill(false, mA)
        for i in 1:nB
            if ip + mA - 1 > nnzC
                nnzC += max(mA, nnzC>>2)
                resize!(rowvalC, nnzC)
                resize!(nzvalC, nnzC)
            end
            colptrC[i] = ip
            ip = spcolmul!(rowvalC, nzvalC, xb, i, ip, A, B)
        end
        colptrC[nB+1] = ip
    end

    resize!(rowvalC, ip - 1)
    resize!(nzvalC, ip - 1)

    # This modification of Gustavson algorithm has sorted row indices
    C = SparseMatrixCSC(mA, nB, colptrC, rowvalC, nzvalC)
    return C
end

# process single rhs column
function spcolmul!(rowvalC, nzvalC, xb, i, ip, A, B)
    rowvalA = rowvals(A); nzvalA = nonzeros(A)
    rowvalB = rowvals(B); nzvalB = nonzeros(B)
    mA = size(A, 1)
    ip0 = ip
    k0 = ip - 1
    @inbounds begin
        for jp in nzrange(B, i)
            nzB = nzvalB[jp]
            j = rowvalB[jp]
            for kp in nzrange(A, j)
                nzC = nzvalA[kp] * nzB
                k = rowvalA[kp]
                if xb[k]
                    nzvalC[k+k0] += nzC
                else
                    nzvalC[k+k0] = nzC
                    xb[k] = true
                    rowvalC[ip] = k
                    ip += 1
                end
            end
        end
        if ip > ip0
            if prefer_sort(ip-k0, mA)
                # in-place sort of indices. Effort: O(nnz*ln(nnz)).
                sort!(rowvalC, ip0, ip-1, QuickSort, Base.Order.Forward)
                for vp = ip0:ip-1
                    k = rowvalC[vp]
                    xb[k] = false
                    nzvalC[vp] = nzvalC[k+k0]
                end
            else
                # scan result vector (effort O(mA))
                for k = 1:mA
                    if xb[k]
                        xb[k] = false
                        rowvalC[ip0] = k
                        nzvalC[ip0] = nzvalC[k+k0]
                        ip0 += 1
                    end
                end
            end
        end
    end
    return ip
end

# special cases of same twin Upper/LowerTriangular
spmatmul1(A, B) = spmatmul(A, B)
function spmatmul1(A::UpperTriangular, B::UpperTriangular)
    UpperTriangular(spmatmul(A, B))
end
function spmatmul1(A::LowerTriangular, B::LowerTriangular)
    LowerTriangular(spmatmul(A, B))
end
# exploit spmatmul for sparse vectors and column views
function spmatmulv(A, B)
    spmatmul(A, B)[:,1]
end

# estimated number of non-zeros in matrix product
# it is assumed, that the non-zero indices are distributed independently and uniformly
# in both matrices. Over-estimation is possible if that is not the case.
function estimate_mulsize(m::Integer, nnzA::Integer, n::Integer, nnzB::Integer, k::Integer)
    p = (nnzA / (m * n)) * (nnzB / (n * k))
    p >= 1 ? m*k : p > 0 ? Int(ceil(-expm1(log1p(-p) * n)*m*k)) : 0 # (1-(1-p)^n)*m*k
end

if VERSION < v"1.10.0-DEV.299"
    top_set_bit(x::Base.BitInteger) = 8 * sizeof(x) - leading_zeros(x)
else
    top_set_bit(x::Base.BitInteger) = Base.top_set_bit(x)
end
# determine if sort! shall be used or the whole column be scanned
# based on empirical data on i7-3610QM CPU
# measuring runtimes of the scanning and sorting loops of the algorithm.
# The parameters 6 and 3 might be modified for different architectures.
prefer_sort(nz::Integer, m::Integer) = m > 6 && 3 * top_set_bit(nz) * nz < m

# Frobenius dot/inner product: trace(A'B)
function dot(A::AbstractSparseMatrixCSC{T1,S1},B::AbstractSparseMatrixCSC{T2,S2}) where {T1,T2,S1,S2}
    m, n = size(A)
    size(B) == (m,n) || throw(DimensionMismatch("matrices must have the same dimensions"))
    r = dot(zero(T1), zero(T2))
    @inbounds for j = 1:n
        ia = getcolptr(A)[j]; ia_nxt = getcolptr(A)[j+1]
        ib = getcolptr(B)[j]; ib_nxt = getcolptr(B)[j+1]
        if ia < ia_nxt && ib < ib_nxt
            ra = rowvals(A)[ia]; rb = rowvals(B)[ib]
            while true
                if ra < rb
                    ia += oneunit(S1)
                    ia < ia_nxt || break
                    ra = rowvals(A)[ia]
                elseif ra > rb
                    ib += oneunit(S2)
                    ib < ib_nxt || break
                    rb = rowvals(B)[ib]
                else # ra == rb
                    r += dot(nonzeros(A)[ia], nonzeros(B)[ib])
                    ia += oneunit(S1); ib += oneunit(S2)
                    ia < ia_nxt && ib < ib_nxt || break
                    ra = rowvals(A)[ia]; rb = rowvals(B)[ib]
                end
            end
        end
    end
    return r
end

function dot(x::AbstractVector, A::AbstractSparseMatrixCSC, y::AbstractVector)
    require_one_based_indexing(x, y)
    m, n = size(A)
    (length(x) == m && n == length(y)) || throw(DimensionMismatch())
    if iszero(m) || iszero(n)
        return dot(zero(eltype(x)), zero(eltype(A)), zero(eltype(y)))
    end
    T = promote_type(eltype(x), eltype(A), eltype(y))
    r = zero(T)
    rvals = getrowval(A)
    nzvals = getnzval(A)
    @inbounds for col in 1:n
        ycol = y[col]
        if _isnotzero(ycol)
            temp = zero(T)
            for k in nzrange(A, col)
                temp += adjoint(x[rvals[k]]) * nzvals[k]
            end
            r += temp * ycol
        end
    end
    return r
end
function dot(x::SparseVector, A::AbstractSparseMatrixCSC, y::SparseVector)
    m, n = size(A)
    length(x) == m && n == length(y) || throw(DimensionMismatch())
    if iszero(m) || iszero(n)
        return dot(zero(eltype(x)), zero(eltype(A)), zero(eltype(y)))
    end
    r = zero(promote_type(eltype(x), eltype(A), eltype(y)))
    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    ynzind = nonzeroinds(y)
    ynzval = nonzeros(y)
    Acolptr = getcolptr(A)
    Arowval = getrowval(A)
    Anzval = getnzval(A)
    for (yi, yv) in zip(ynzind, ynzval)
        A_ptr_lo = Acolptr[yi]
        A_ptr_hi = Acolptr[yi+1] - 1
        if A_ptr_lo <= A_ptr_hi
            r += _spdot(dot, 1, length(xnzind), xnzind, xnzval,
                                            A_ptr_lo, A_ptr_hi, Arowval, Anzval) * yv
        end
    end
    r
end

const WrapperMatrixTypes{T,MT} = Union{
    SubArray{T,2,MT},
    Adjoint{T,MT},
    Transpose{T,MT},
    UpperOrLowerTriangular{T,MT},
    UpperHessenberg{T,MT},
    Symmetric{T,MT},
    Hermitian{T,MT},
}

function dot(A::Union{DenseMatrixUnion,WrapperMatrixTypes{<:Any,Union{DenseMatrixUnion,AbstractSparseMatrix}}}, B::AbstractSparseMatrixCSC)
    T = promote_type(eltype(A), eltype(B))
    (m, n) = size(A)
    if (m, n) != size(B)
        throw(DimensionMismatch())
    end
    s = zero(T)
    if m * n == 0
        return s
    end
    rows = rowvals(B)
    vals = nonzeros(B)
    @inbounds for j in 1:n
        for ridx in nzrange(B, j)
            i = rows[ridx]
            v = vals[ridx]
            s += dot(A[i,j], v)
        end
    end
    return s
end

function dot(A::AbstractSparseMatrixCSC, B::Union{DenseMatrixUnion,WrapperMatrixTypes{<:Any,Union{DenseMatrixUnion,AbstractSparseMatrix}}})
    return conj(dot(B, A))
end

## triangular sparse handling
## triangular multiplication
function LinearAlgebra.generic_trimatmul!(C::StridedVecOrMat, uploc, isunitc, tfun::Function, A::SparseMatrixCSCUnion, B::AbstractVecOrMat)
    require_one_based_indexing(A, C)
    nrowC = size(C, 1)
    ncol = checksquare(A)
    if nrowC != ncol
        throw(DimensionMismatch("A has $(ncol) columns and B has $(nrowC) rows"))
    end
    nrowB, ncolB  = size(B, 1), size(B, 2)
    C !== B && copyto!(C, B)
    aa = getnzval(A)
    ja = getrowval(A)
    ia = getcolptr(A)
    joff = 0
    unit = isunitc == 'U'
    Z = zero(eltype(C))

    if uploc == 'U'
        if tfun === identity
            # forward multiplication for UpperTriangular SparseCSC matrices
            for k = 1:ncolB
                for j = 1:nrowB
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    done = unit
        
                    bj = B[joff + j]
                    for ii = i1:i2
                        jai = ja[ii]
                        aii = aa[ii]
                        if jai < j
                            C[joff + jai] += aii * bj
                        elseif jai == j
                            if !unit
                                C[joff + j] = aii * bj
                                done = true
                            end
                        else
                            break
                        end
                    end
                    if !done
                        C[joff + j] = Z
                    end
                end
                joff += nrowB
            end
        else # tfun in (adjoint, transpose)
            # backward multiplication with adjoint and transpose of LowerTriangular CSC matrices
            for k = 1:ncolB
                for j = nrowB:-1:1
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    akku = Z
                    j0 = !unit ? j : j - 1
        
                    # loop through column j of A - only structural non-zeros
                    for ii = i1:i2
                        jai = ja[ii]
                        if jai <= j0
                            akku += tfun(aa[ii]) * B[joff + jai]
                        else
                            break
                        end
                    end
                    if unit
                        akku += oneunit(eltype(A)) * B[joff + j]
                    end
                    C[joff + j] = akku
                end
                joff += nrowB
            end
        end
    else # uploc == 'L'
        if tfun === identity
            # backward multiplication for LowerTriangular SparseCSC matrices
            for k = 1:ncolB
                for j = nrowB:-1:1
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    done = unit
        
                    bj = B[joff + j]
                    for ii = i2:-1:i1
                        jai = ja[ii]
                        aii = aa[ii]
                        if jai > j
                            C[joff + jai] += aii * bj
                        elseif jai == j
                            if !unit
                                C[joff + j] = aii * bj
                                done = true
                            end
                        else
                            break
                        end
                    end
                    if !done
                        C[joff + j] = Z
                    end
                end
                joff += nrowB
            end
        else # tfun in (adjoint, transpose)
            # forward multiplication for adjoint and transpose of LowerTriangular CSC matrices
            for k = 1:ncolB
                for j = 1:nrowB
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    akku = Z
                    j0 = !unit ? j : j + 1
        
                    # loop through column j of A - only structural non-zeros
                    for ii = i2:-1:i1
                        jai = ja[ii]
                        if jai >= j0
                            akku += tfun(aa[ii]) * B[joff + jai]
                        else
                            break
                        end
                    end
                    if unit
                        akku += oneunit(eltype(A)) * B[joff + j]
                    end
                    C[joff + j] = akku
                end
                joff += nrowB
            end
        end
    end
    return C
end
function LinearAlgebra.generic_trimatmul!(C::StridedVecOrMat, uploc, isunitc, ::Function, xA::AdjOrTrans{<:Any,<:SparseMatrixCSCUnion}, B::AbstractVecOrMat)
    A = parent(xA)
    nrowC = size(C, 1)
    ncol = checksquare(A)
    if nrowC != ncol
        throw(DimensionMismatch("A has $(ncol) columns and B has $(nrowC) rows"))
    end
    C !== B && copyto!(C, B)
    nrowB, ncolB  = size(B, 1), size(B, 2)
    aa = getnzval(A)
    ja = getrowval(A)
    ia = getcolptr(A)
    joff = 0
    unit = isunitc == 'U'
    Z = zero(eltype(C))

    if uploc == 'U'
        for k = 1:ncolB
            for j = 1:nrowB
                i1 = ia[j]
                i2 = ia[j + 1] - 1
                done = unit
    
                bj = B[joff + j]
                for ii = i1:i2
                    jai = ja[ii]
                    aii = conj(aa[ii])
                    if jai < j
                        C[joff + jai] += aii * bj
                    elseif jai == j
                        if !unit
                            C[joff + j] = aii * bj
                            done = true
                        end
                    else
                        break
                    end
                end
                if !done
                    C[joff + j] = Z
                end
            end
            joff += nrowB
        end
    else # uploc == 'L'
        for k = 1:ncolB
            for j = nrowB:-1:1
                i1 = ia[j]
                i2 = ia[j + 1] - 1
                done = unit
    
                bj = B[joff + j]
                for ii = i2:-1:i1
                    jai = ja[ii]
                    aii = conj(aa[ii])
                    if jai > j
                        C[joff + jai] += aii * bj
                    elseif jai == j
                        if !unit
                            C[joff + j] = aii * bj
                            done = true
                        end
                    else
                        break
                    end
                end
                if !done
                    C[joff + j] = Z
                end
            end
            joff += nrowB
        end
    end
    return C
end

## triangular solvers
_uconvert_copyto!(c, b, oA) = (c .= Ref(oA) .\ b)
_uconvert_copyto!(c::AbstractArray{T}, b::AbstractArray{T}, _) where {T} = copyto!(c, b)

function LinearAlgebra.generic_trimatdiv!(C::StridedVecOrMat, uploc, isunitc, tfun::Function, A::SparseMatrixCSCUnion, B::AbstractVecOrMat)
    mA, nA = size(A)
    nrowB, ncolB = size(B, 1), size(B, 2)
    if nA != nrowB
        throw(DimensionMismatch("second dimension of left hand side A, $nA, and first dimension of right hand side B, $nrowB, must be equal"))
    end
    if size(C) != size(B)
        throw(DimensionMismatch("size of output, $(size(C)), does not match size of right hand side, $(size(B))"))
    end
    C !== B && _uconvert_copyto!(C, B, oneunit(eltype(A)))
    aa = getnzval(A)
    ja = getrowval(A)
    ia = getcolptr(A)
    unit = isunitc == 'U'

    if uploc == 'L'
        if tfun === identity
            # forward substitution for LowerTriangular CSC matrices
            for k in 1:ncolB
                for j = 1:nrowB
                    i1 = ia[j]
                    i2 = ia[j + 1] - one(eltype(ia))

                    # find diagonal element
                    ii = searchsortedfirst(ja, j, i1, i2, Base.Order.Forward)
                    jai = ii > i2 ? zero(eltype(ja)) : ja[ii]

                    cj = C[j,k]
                    # check for zero pivot and divide with pivot
                    if jai == j
                        if !unit
                            cj /= LinearAlgebra._ustrip(aa[ii])
                            C[j,k] = cj
                        end
                        ii += 1
                    elseif !unit
                        throw(LinearAlgebra.SingularException(j))
                    end

                    # update remaining part
                    for i = ii:i2
                        C[ja[i],k] -= cj * LinearAlgebra._ustrip(aa[i])
                    end
                end
            end
        else # tfun in (adjoint, transpose)
            # backward substitution for adjoint and transpose of LowerTriangular CSC matrices
            for k in 1:ncolB
                for j = nrowB:-1:1
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    akku = B[j,k]
                    done = false
            
                    # loop through column j of A - only structural non-zeros
                    for ii = i2:-1:i1
                        jai = ja[ii]
                        if jai > j
                            akku -= C[jai,k] * tfun(aa[ii])
                        elseif jai == j
                            akku /= unit ? oneunit(eltype(A)) : tfun(aa[ii])
                            done = true
                            break
                        else
                            break
                        end
                    end
                    if !done && !unit
                        throw(LinearAlgebra.SingularException(j))
                    end
                    C[j,k] = akku
                end
            end
        end
    else # uploc == 'U'
        if tfun === identity
            # backward substitution for UpperTriangular CSC matrices
            for k in 1:ncolB
                for j = nrowB:-1:1
                    i1 = ia[j]
                    i2 = ia[j + 1] - one(eltype(ia))
            
                    # find diagonal element
                    ii = searchsortedlast(ja, j, i1, i2, Base.Order.Forward)
                    jai = ii < i1 ? zero(eltype(ja)) : ja[ii]
            
                    cj = C[j,k]
                    # check for zero pivot and divide with pivot
                    if jai == j
                        if !unit
                            cj /= LinearAlgebra._ustrip(aa[ii])
                            C[j,k] = cj
                        end
                        ii -= 1
                    elseif !unit
                        throw(LinearAlgebra.SingularException(j))
                    end
            
                    # update remaining part
                    for i = ii:-1:i1
                        C[ja[i],k] -= cj * LinearAlgebra._ustrip(aa[i])
                    end
                end
            end
        else # tfun in  (adjoint, transpose)
            # forward substitution for adjoint and transpose of UpperTriangular CSC matrices
            for k in 1:ncolB
                for j = 1:nrowB
                    i1 = ia[j]
                    i2 = ia[j + 1] - 1
                    akku = B[j,k]
                    done = false
            
                    # loop through column j of A - only structural non-zeros
                    for ii = i1:i2
                        jai = ja[ii]
                        if jai < j
                            akku -= C[jai,k] * tfun(aa[ii])
                        elseif jai == j
                            akku /= unit ? oneunit(eltype(A)) : tfun(aa[ii])
                            done = true
                            break
                        else
                            break
                        end
                    end
                    if !done && !unit
                        throw(LinearAlgebra.SingularException(j))
                    end
                    C[j,k] = akku
                end
            end
        end
    end
    C
end
function LinearAlgebra.generic_trimatdiv!(C::StridedVecOrMat, uploc, isunitc, ::Function, xA::AdjOrTrans{<:Any,<:SparseMatrixCSCUnion}, B::AbstractVecOrMat)
    A = parent(xA)
    mA, nA = size(A)
    nrowB, ncolB = size(B, 1), size(B, 2)
    if nA != nrowB
        throw(DimensionMismatch("second dimension of left hand side A, $nA, and first dimension of right hand side B, $nrowB, must be equal"))
    end
    if size(C) != size(B)
        throw(DimensionMismatch("size of output, $(size(C)), does not match size of right hand side, $(size(B))"))
    end
    C !== B && _uconvert_copyto!(C, B, oneunit(eltype(A)))

    aa = getnzval(A)
    ja = getrowval(A)
    ia = getcolptr(A)
    unit = isunitc == 'U'

    if uploc == 'L'
        # forward substitution for LowerTriangular CSC matrices
        for k in 1:ncolB
            for j = 1:nrowB
                i1 = ia[j]
                i2 = ia[j + 1] - one(eltype(ia))

                # find diagonal element
                ii = searchsortedfirst(ja, j, i1, i2, Base.Order.Forward)
                jai = ii > i2 ? zero(eltype(ja)) : ja[ii]

                cj = C[j,k]
                # check for zero pivot and divide with pivot
                if jai == j
                    if !unit
                        cj /= LinearAlgebra._ustrip(conj(aa[ii]))
                        C[j,k] = cj
                    end
                    ii += 1
                elseif !unit
                    throw(LinearAlgebra.SingularException(j))
                end

                # update remaining part
                for i = ii:i2
                    C[ja[i],k] -= cj * LinearAlgebra._ustrip(conj(aa[i]))
                end
            end
        end
    else # uploc == 'U'
        # backward substitution for UpperTriangular CSC matrices
        for k in 1:ncolB
            for j = nrowB:-1:1
                i1 = ia[j]
                i2 = ia[j + 1] - one(eltype(ia))
        
                # find diagonal element
                ii = searchsortedlast(ja, j, i1, i2, Base.Order.Forward)
                jai = ii < i1 ? zero(eltype(ja)) : ja[ii]
        
                cj = C[j,k]
                # check for zero pivot and divide with pivot
                if jai == j
                    if !unit
                        cj /= LinearAlgebra._ustrip(conj(aa[ii]))
                        C[j,k] = cj
                    end
                    ii -= 1
                elseif !unit
                    throw(LinearAlgebra.SingularException(j))
                end
        
                # update remaining part
                for i = ii:-1:i1
                    C[ja[i],k] -= cj * LinearAlgebra._ustrip(conj(aa[i]))
                end
            end
        end
    end
    C
end

function (\)(A::Union{UpperTriangular,LowerTriangular}, B::AbstractSparseMatrixCSC)
    require_one_based_indexing(B)
    TAB = LinearAlgebra._init_eltype(\, eltype(A), eltype(B))
    ldiv!(Matrix{TAB}(undef, size(B)), A, B)
end
function (\)(A::Union{UnitUpperTriangular,UnitLowerTriangular}, B::AbstractSparseMatrixCSC)
    require_one_based_indexing(B)
    TAB = LinearAlgebra._inner_type_promotion(\, eltype(A), eltype(B))
    ldiv!(Matrix{TAB}(undef, size(B)), A, B)
end
# (*)(L::DenseTriangular, B::AbstractSparseMatrixCSC) = lmul!(L, Array(B))

## end of triangular

# symmetric/Hermitian

function _mul!(nzrang::Function, diagop::Function, odiagop::Function, C::StridedVecOrMat{T}, A, B, α, β) where T
    n = size(A, 2)
    m = size(B, 2)
    n == size(B, 1) == size(C, 1) && m == size(C, 2) || throw(DimensionMismatch())
    rv = rowvals(A)
    nzv = nonzeros(A)
    let z = T(0), sumcol=z, αxj=z, aarc=z, α = α
        β != one(β) && LinearAlgebra._rmul_or_fill!(C, β)
        @inbounds for k = 1:m
            for col = 1:n
                αxj = B[col,k] * α
                sumcol = z
                for j = nzrang(A, col)
                    row = rv[j]
                    aarc = nzv[j]
                    if row == col
                        sumcol += diagop(aarc) * B[row,k]
                    else
                        C[row,k] += aarc * αxj
                        sumcol += odiagop(aarc) * B[row,k]
                    end
                end
                C[col,k] += α * sumcol
            end
        end
    end
    C
end

# row range up to (and including if excl=false) diagonal
function nzrangeup(A, i, excl=false)
    r = nzrange(A, i); r1 = r.start; r2 = r.stop
    rv = rowvals(A)
    @inbounds r2 < r1 || rv[r2] <= i - excl ? r : r1:searchsortedlast(rv, i - excl, r1, r2, Forward)
end
# row range from diagonal (included if excl=false) to end
function nzrangelo(A, i, excl=false)
    r = nzrange(A, i); r1 = r.start; r2 = r.stop
    rv = rowvals(A)
    @inbounds r2 < r1 || rv[r1] >= i + excl ? r : searchsortedfirst(rv, i + excl, r1, r2, Forward):r2
end

dot(x::AbstractVector, A::RealHermSymComplexHerm{<:Any,<:AbstractSparseMatrixCSC}, y::AbstractVector) =
    _dot(x, parent(A), y, A.uplo == 'U' ? nzrangeup : nzrangelo, A isa Symmetric ? identity : real, A isa Symmetric ? transpose : adjoint)
function _dot(x::AbstractVector, A::AbstractSparseMatrixCSC, y::AbstractVector, rangefun::Function, diagop::Function, odiagop::Function)
    require_one_based_indexing(x, y)
    m, n = size(A)
    (length(x) == m && n == length(y)) || throw(DimensionMismatch())
    if iszero(m) || iszero(n)
        return dot(zero(eltype(x)), zero(eltype(A)), zero(eltype(y)))
    end
    T = promote_type(eltype(x), eltype(A), eltype(y))
    r = zero(T)
    rvals = getrowval(A)
    nzvals = getnzval(A)
    @inbounds for col in 1:n
        ycol = y[col]
        xcol = x[col]
        if _isnotzero(ycol) && _isnotzero(xcol)
            for k in rangefun(A, col)
                i = rvals[k]
                Aij = nzvals[k]
                if i != col
                    r += dot(x[i], Aij, ycol)
                    r += dot(xcol, odiagop(Aij), y[i])
                else
                    r += dot(x[i], diagop(Aij), ycol)
                end
            end
        end
    end
    return r
end
dot(x::SparseVector, A::RealHermSymComplexHerm{<:Any,<:AbstractSparseMatrixCSC}, y::SparseVector) =
    _dot(x, parent(A), y, A.uplo == 'U' ? nzrangeup : nzrangelo, A isa Symmetric ? identity : real)
function _dot(x::SparseVector, A::AbstractSparseMatrixCSC, y::SparseVector, rangefun::Function, diagop::Function)
    m, n = size(A)
    length(x) == m && n == length(y) || throw(DimensionMismatch())
    if iszero(m) || iszero(n)
        return dot(zero(eltype(x)), zero(eltype(A)), zero(eltype(y)))
    end
    r = zero(promote_type(eltype(x), eltype(A), eltype(y)))
    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    ynzind = nonzeroinds(y)
    ynzval = nonzeros(y)
    Arowval = getrowval(A)
    Anzval = getnzval(A)
    Acolptr = getcolptr(A)
    isempty(Arowval) && return r
    # plain triangle without diagonal
    for (yi, yv) in zip(ynzind, ynzval)
        A_ptr_lo = first(rangefun(A, yi, true))
        A_ptr_hi = last(rangefun(A, yi, true))
        if A_ptr_lo <= A_ptr_hi
            # dot is conjugated in the first argument, so double conjugate a's
            r += dot(_spdot((x, a) -> a'x, 1, length(xnzind), xnzind, xnzval,
                                            A_ptr_lo, A_ptr_hi, Arowval, Anzval), yv)
        end
    end
    # view triangle without diagonal
    for (xi, xv) in zip(xnzind, xnzval)
        A_ptr_lo = first(rangefun(A, xi, true))
        A_ptr_hi = last(rangefun(A, xi, true))
        if A_ptr_lo <= A_ptr_hi
            r += dot(xv, _spdot((a, y) -> a'y, A_ptr_lo, A_ptr_hi, Arowval, Anzval,
                                            1, length(ynzind), ynzind, ynzval))
        end
    end
    # diagonal
    for i in 1:m
        r1 = Int(Acolptr[i])
        r2 = Int(Acolptr[i+1]-1)
        r1 > r2 && continue
        r1 = searchsortedfirst(Arowval, i, r1, r2, Forward)
        ((r1 > r2) || (Arowval[r1] != i)) && continue
        r += dot(x[i], diagop(Anzval[r1]), y[i])
    end
    r
end
## end of symmetric/Hermitian

\(A::Transpose{<:Complex,<:Hermitian{<:Complex,<:AbstractSparseMatrixCSC}}, B::Vector) = copy(A) \ B

function rdiv!(A::AbstractSparseMatrixCSC{T}, D::Diagonal{T}) where T
    dd = D.diag
    if (k = length(dd)) ≠ size(A, 2)
        throw(DimensionMismatch("size(A, 2)=$(size(A, 2)) should be size(D, 1)=$k"))
    end
    nonz = nonzeros(A)
    @inbounds for j in 1:k
        ddj = dd[j]
        if iszero(ddj)
            throw(LinearAlgebra.SingularException(j))
        end
        for i in nzrange(A, j)
            nonz[i] /= ddj
        end
    end
    A
end

function ldiv!(D::Diagonal{T}, A::AbstractSparseMatrixCSC{T}) where {T}
    # require_one_based_indexing(A)
    if size(A, 1) != length(D.diag)
        throw(DimensionMismatch("diagonal matrix is $(length(D.diag)) by $(length(D.diag)) but right hand side has $(size(A, 1)) rows"))
    end
    nonz = nonzeros(A)
    Arowval = rowvals(A)
    b = D.diag
    for i=1:length(b)
        iszero(b[i]) && throw(SingularException(i))
    end
    @inbounds for col in 1:size(A, 2), p in nzrange(A, col)
        nonz[p] = b[Arowval[p]] \ nonz[p]
    end
    A
end

## triu, tril

function triu(S::AbstractSparseMatrixCSC{Tv,Ti}, k::Integer=0) where {Tv,Ti}
    m,n = size(S)
    colptr = Vector{Ti}(undef, n+1)
    nnz = 0
    for col = 1 : min(max(k+1,1), n+1)
        colptr[col] = 1
    end
    for col = max(k+1,1) : n
        for c1 in nzrange(S, col)
            rowvals(S)[c1] > col - k && break
            nnz += 1
        end
        colptr[col+1] = nnz+1
    end
    rowval = Vector{Ti}(undef, nnz)
    nzval = Vector{Tv}(undef, nnz)
    for col = max(k+1,1) : n
        c1 = getcolptr(S)[col]
        for c2 in colptr[col]:colptr[col+1]-1
            rowval[c2] = rowvals(S)[c1]
            nzval[c2] = nonzeros(S)[c1]
            c1 += 1
        end
    end
    SparseMatrixCSC(m, n, colptr, rowval, nzval)
end

function tril(S::AbstractSparseMatrixCSC{Tv,Ti}, k::Integer=0) where {Tv,Ti}
    m,n = size(S)
    colptr = Vector{Ti}(undef, n+1)
    nnz = 0
    colptr[1] = 1
    for col = 1 : min(n, m+k)
        l1 = getcolptr(S)[col+1]-1
        for c1 = 0 : (l1 - getcolptr(S)[col])
            rowvals(S)[l1 - c1] < col - k && break
            nnz += 1
        end
        colptr[col+1] = nnz+1
    end
    for col = max(min(n, m+k)+2,1) : n+1
        colptr[col] = nnz+1
    end
    rowval = Vector{Ti}(undef, nnz)
    nzval = Vector{Tv}(undef, nnz)
    for col = 1 : min(n, m+k)
        c1 = getcolptr(S)[col+1]-1
        l2 = colptr[col+1]-1
        for c2 = 0 : l2 - colptr[col]
            rowval[l2 - c2] = rowvals(S)[c1]
            nzval[l2 - c2] = nonzeros(S)[c1]
            c1 -= 1
        end
    end
    SparseMatrixCSC(m, n, colptr, rowval, nzval)
end

## diff

function sparse_diff1(S::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    m,n = size(S)
    m > 1 || return SparseMatrixCSC(0, n, fill(one(Ti),n+1), Ti[], Tv[])
    colptr = Vector{Ti}(undef, n+1)
    numnz = 2 * nnz(S) # upper bound; will shrink later
    rowval = Vector{Ti}(undef, numnz)
    nzval = Vector{Tv}(undef, numnz)
    numnz = 0
    colptr[1] = 1
    for col = 1 : n
        last_row = 0
        last_val = 0
        for k in nzrange(S, col)
            row = rowvals(S)[k]
            val = nonzeros(S)[k]
            if row > 1
                if row == last_row + 1
                    nzval[numnz] += val
                    nzval[numnz]==zero(Tv) && (numnz -= 1)
                else
                    numnz += 1
                    rowval[numnz] = row - 1
                    nzval[numnz] = val
                end
            end
            if row < m
                numnz += 1
                rowval[numnz] = row
                nzval[numnz] = -val
            end
            last_row = row
            last_val = val
        end
        colptr[col+1] = numnz+1
    end
    deleteat!(rowval, numnz+1:length(rowval))
    deleteat!(nzval, numnz+1:length(nzval))
    return SparseMatrixCSC(m-1, n, colptr, rowval, nzval)
end

function sparse_diff2(a::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti}
    m,n = size(a)
    colptr = Vector{Ti}(undef, max(n,1))
    numnz = 2 * nnz(a) # upper bound; will shrink later
    rowval = Vector{Ti}(undef, numnz)
    nzval = Vector{Tv}(undef, numnz)

    z = zero(Tv)

    colptr_a = getcolptr(a)
    rowval_a = rowvals(a)
    nzval_a = nonzeros(a)

    ptrS = 1
    colptr[1] = 1

    n == 0 && return SparseMatrixCSC(m, n, colptr, rowval, nzval)

    startA = colptr_a[1]
    stopA = colptr_a[2]

    rA = startA : stopA - 1
    rowvalA = rowval_a[rA]
    nzvalA = nzval_a[rA]
    lA = stopA - startA

    for col = 1:n-1
        startB, stopB = startA, stopA
        startA = colptr_a[col+1]
        stopA = colptr_a[col+2]

        rowvalB = rowvalA
        nzvalB = nzvalA
        lB = lA

        rA = startA : stopA - 1
        rowvalA = rowval_a[rA]
        nzvalA = nzval_a[rA]
        lA = stopA - startA

        ptrB = 1
        ptrA = 1

        while ptrA <= lA && ptrB <= lB
            rowA = rowvalA[ptrA]
            rowB = rowvalB[ptrB]
            if rowA < rowB
                rowval[ptrS] = rowA
                nzval[ptrS] = nzvalA[ptrA]
                ptrS += 1
                ptrA += 1
            elseif rowB < rowA
                rowval[ptrS] = rowB
                nzval[ptrS] = -nzvalB[ptrB]
                ptrS += 1
                ptrB += 1
            else
                res = nzvalA[ptrA] - nzvalB[ptrB]
                if res != z
                    rowval[ptrS] = rowA
                    nzval[ptrS] = res
                    ptrS += 1
                end
                ptrA += 1
                ptrB += 1
            end
        end

        while ptrA <= lA
            rowval[ptrS] = rowvalA[ptrA]
            nzval[ptrS] = nzvalA[ptrA]
            ptrS += 1
            ptrA += 1
        end

        while ptrB <= lB
            rowval[ptrS] = rowvalB[ptrB]
            nzval[ptrS] = -nzvalB[ptrB]
            ptrS += 1
            ptrB += 1
        end

        colptr[col+1] = ptrS
    end
    deleteat!(rowval, ptrS:length(rowval))
    deleteat!(nzval, ptrS:length(nzval))
    return SparseMatrixCSC(m, n-1, colptr, rowval, nzval)
end

diff(a::AbstractSparseMatrixCSC; dims::Integer) = dims==1 ? sparse_diff1(a) : sparse_diff2(a)

## norm and rank
norm(A::AbstractSparseMatrixCSC, p::Real=2) = norm(view(nonzeros(A), 1:nnz(A)), p)

function opnorm(A::AbstractSparseMatrixCSC, p::Real=2)
    m, n = size(A)
    if m == 0 || n == 0 || isempty(A)
        return float(real(zero(eltype(A))))
    elseif m == 1
        if p == 1
            return norm(nzvalview(A), Inf)
        elseif p == 2
            return norm(nzvalview(A), 2)
        elseif p == Inf
            return norm(nzvalview(A), 1)
        end
    elseif n == 1 && p in (1, 2, Inf)
        return norm(nzvalview(A), p)
    else
        Tnorm = typeof(float(real(zero(eltype(A)))))
        Tsum = promote_type(Float64,Tnorm)
        if p==1
            nA::Tsum = 0
            for j=1:n
                colSum::Tsum = 0
                for i in nzrange(A, j)
                    colSum += abs(nonzeros(A)[i])
                end
                nA = max(nA, colSum)
            end
            return convert(Tnorm, nA)
        elseif p==2
            throw(ArgumentError("2-norm not yet implemented for sparse matrices. Try opnorm(Array(A)) or opnorm(A, p) where p=1 or Inf."))
        elseif p==Inf
            rowSum = zeros(Tsum,m)
            for i=1:length(nonzeros(A))
                rowSum[rowvals(A)[i]] += abs(nonzeros(A)[i])
            end
            return convert(Tnorm, maximum(rowSum))
        end
    end
    throw(ArgumentError("invalid operator p-norm p=$p. Valid: 1, Inf"))
end

# TODO rank

# cond
function cond(A::AbstractSparseMatrixCSC, p::Real=2)
    if p == 1
        normAinv = opnormestinv(A)
        normA = opnorm(A, 1)
        return normA * normAinv
    elseif p == Inf
        normAinv = opnormestinv(copy(A'))
        normA = opnorm(A, Inf)
        return normA * normAinv
    elseif p == 2
        throw(ArgumentError("2-norm condition number is not implemented for sparse matrices, try cond(Array(A), 2) instead"))
    else
        throw(ArgumentError("second argument must be either 1 or Inf, got $p"))
    end
end

function opnormestinv(A::AbstractSparseMatrixCSC{T}, t::Integer = min(2,maximum(size(A)))) where T
    maxiter = 5
    # Check the input
    n = checksquare(A)
    F = factorize(A)
    if t <= 0
        throw(ArgumentError("number of blocks must be a positive integer"))
    end
    if t > n
        throw(ArgumentError("number of blocks must not be greater than $n"))
    end
    ind = Vector{Int64}(undef, n)
    ind_hist = Vector{Int64}(undef, maxiter * t)

    Ti = typeof(float(zero(T)))

    S = zeros(T <: Real ? Int : Ti, n, t)

    function _any_abs_eq(v,n::Int)
        for vv in v
            if abs(vv)==n
                return true
            end
        end
        return false
    end

    # Generate the block matrix
    X = Matrix{Ti}(undef, n, t)
    X[1:n,1] .= 1
    for j = 2:t
        while true
            rand!(view(X,1:n,j), (-1, 1))
            yaux = X[1:n,j]' * X[1:n,1:j-1]
            if !_any_abs_eq(yaux,n)
                break
            end
        end
    end
    rmul!(X, inv(n))

    iter = 0
    local est
    local est_old
    est_ind = 0
    while iter < maxiter
        iter += 1
        Y = F \ X
        est = zero(real(eltype(Y)))
        est_ind = 0
        for i = 1:t
            y = norm(Y[1:n,i], 1)
            if y > est
                est = y
                est_ind = i
            end
        end
        if iter == 1
            est_old = est
        end
        if est > est_old || iter == 2
            ind_best = est_ind
        end
        if iter >= 2 && est <= est_old
            est = est_old
            break
        end
        est_old = est
        S_old = copy(S)
        for j = 1:t
            for i = 1:n
                S[i,j] = Y[i,j]==0 ? one(Y[i,j]) : sign(Y[i,j])
            end
        end

        if T <: Real
            # Check whether cols of S are parallel to cols of S or S_old
            for j = 1:t
                while true
                    repeated = false
                    if j > 1
                        saux = S[1:n,j]' * S[1:n,1:j-1]
                        if _any_abs_eq(saux,n)
                            repeated = true
                        end
                    end
                    if !repeated
                        saux2 = S[1:n,j]' * S_old[1:n,1:t]
                        if _any_abs_eq(saux2,n)
                            repeated = true
                        end
                    end
                    if repeated
                        rand!(view(S,1:n,j), (-1, 1))
                    else
                        break
                    end
                end
            end
        end

        # Use the conjugate transpose
        Z = F' \ S
        h_max = zero(real(eltype(Z)))
        h = zeros(real(eltype(Z)), n)
        h_ind = 0
        for i = 1:n
            h[i] = norm(Z[i,1:t], Inf)
            if h[i] > h_max
                h_max = h[i]
                h_ind = i
            end
            ind[i] = i
        end
        if iter >=2 && ind_best == h_ind
            break
        end
        p = sortperm(h, rev=true)
        h = h[p]
        permute!(ind, p)
        if t > 1
            addcounter = t
            elemcounter = 0
            while addcounter > 0 && elemcounter < n
                elemcounter = elemcounter + 1
                current_element = ind[elemcounter]
                found = false
                for i = 1:t * (iter - 1)
                    if current_element == ind_hist[i]
                        found = true
                        break
                    end
                end
                if !found
                    addcounter = addcounter - 1
                    for i = 1:current_element - 1
                        X[i,t-addcounter] = 0
                    end
                    X[current_element,t-addcounter] = 1
                    for i = current_element + 1:n
                        X[i,t-addcounter] = 0
                    end
                    ind_hist[iter * t - addcounter] = current_element
                else
                    if elemcounter == t && addcounter == t
                        break
                    end
                end
            end
        else
            ind_hist[1:t] = ind[1:t]
            for j = 1:t
                for i = 1:ind[j] - 1
                    X[i,j] = 0
                end
                X[ind[j],j] = 1
                for i = ind[j] + 1:n
                    X[i,j] = 0
                end
            end
        end
    end
    return est
end

## kron
const _SparseArraysCSC = Union{AbstractCompressedVector, AbstractSparseMatrixCSC}
const _SparseKronArrays = Union{_SparseArraysCSC, AdjOrTrans{<:Any,<:_SparseArraysCSC}}

const _Symmetric_SparseKronArrays = Symmetric{<:Any,<:_SparseKronArrays}
const _Hermitian_SparseKronArrays = Hermitian{<:Any,<:_SparseKronArrays}
const _Triangular_SparseKronArrays = UpperOrLowerTriangular{<:Any,<:_SparseKronArrays}
const _Annotated_SparseKronArrays = Union{_Triangular_SparseKronArrays, _Symmetric_SparseKronArrays, _Hermitian_SparseKronArrays}
const _SparseKronGroup = Union{_SparseKronArrays, _Annotated_SparseKronArrays}

const _SpecialArrays = Union{Diagonal, Bidiagonal, Tridiagonal, SymTridiagonal}
const _Symmetric_DenseArrays{T,A<:Matrix} = Symmetric{T,A}
const _Hermitian_DenseArrays{T,A<:Matrix} = Hermitian{T,A}
const _Triangular_DenseArrays{T,A<:Matrix} = UpperOrLowerTriangular{<:Any,A} # AbstractTriangular{T,A}
const _Annotated_DenseArrays = Union{_SpecialArrays, _Triangular_DenseArrays, _Symmetric_DenseArrays, _Hermitian_DenseArrays}
const _DenseConcatGroup = Union{Number, Vector, Adjoint{<:Any,<:Vector}, Transpose{<:Any,<:Vector}, Matrix, _Annotated_DenseArrays}

@inline function kron!(C::SparseMatrixCSC, A::AbstractSparseMatrixCSC, B::AbstractSparseMatrixCSC)
    mA, nA = size(A); mB, nB = size(B)
    mC, nC = mA*mB, nA*nB
    @boundscheck size(C) == (mC, nC) || throw(DimensionMismatch("target matrix needs to have size ($mC, $nC)," *
        " but has size $(size(C))"))
    rowvalC = rowvals(C)
    nzvalC = nonzeros(C)
    colptrC = getcolptr(C)

    nnzC = nnz(A)*nnz(B)
    resize!(nzvalC, nnzC)
    resize!(rowvalC, nnzC)

    col = 1
    @inbounds for j = 1:nA
        startA = getcolptr(A)[j]
        stopA = getcolptr(A)[j+1] - 1
        lA = stopA - startA + 1
        for i = 1:nB
            startB = getcolptr(B)[i]
            stopB = getcolptr(B)[i+1] - 1
            lB = stopB - startB + 1
            ptr_range = (1:lB) .+ (colptrC[col]-1)
            colptrC[col+1] = colptrC[col] + lA*lB
            col += 1
            for ptrA = startA : stopA
                ptrB = startB
                for ptr = ptr_range
                    rowvalC[ptr] = (rowvals(A)[ptrA]-1)*mB + rowvals(B)[ptrB]
                    nzvalC[ptr] = nonzeros(A)[ptrA] * nonzeros(B)[ptrB]
                    ptrB += 1
                end
                ptr_range = ptr_range .+ lB
            end
        end
    end
    return C
end
@inline function kron!(z::SparseVector, x::SparseVector, y::SparseVector)
    @boundscheck length(z) == length(x)*length(y) || throw(DimensionMismatch("length of " *
        "target vector needs to be $(length(x)*length(y)), but has length $(length(z))"))
    nnzx, nnzy = nnz(x), nnz(y)
    nzind = nonzeroinds(z)
    nzval = nonzeros(z)

    nnzz = nnzx*nnzy
    resize!(nzind, nnzz)
    resize!(nzval, nnzz)

    @inbounds for i = 1:nnzx, j = 1:nnzy
        this_ind = (i-1)*nnzy+j
        nzind[this_ind] = (nonzeroinds(x)[i]-1)*length(y) + nonzeroinds(y)[j]
        nzval[this_ind] = nonzeros(x)[i] * nonzeros(y)[j]
    end
    return z
end
kron!(C::SparseMatrixCSC, A::_SparseKronGroup, B::_DenseConcatGroup) =
    kron!(C, convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron!(C::SparseMatrixCSC, A::_DenseConcatGroup, B::_SparseKronGroup) =
    kron!(C, convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron!(C::SparseMatrixCSC, A::_SparseKronGroup, B::_SparseKronGroup) =
    kron!(C, convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron!(C::SparseMatrixCSC, A::_SparseVectorUnion, B::_AdjOrTransSparseVectorUnion) =
    broadcast!(*, C, A, B)
# disambiguation
kron!(C::SparseMatrixCSC, A::_SparseKronGroup, B::Diagonal) =
    kron!(C, convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron!(C::SparseMatrixCSC, A::Diagonal, B::_SparseKronGroup) =
    kron!(C, convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron!(C::SparseMatrixCSC, A::AbstractCompressedVector, B::AdjOrTrans{<:Any,<:AbstractCompressedVector}) =
    broadcast!(*, C, A, B)
kron!(c::SparseMatrixCSC, a::Number, b::_SparseKronGroup) = mul!(c, a, b)
kron!(c::SparseMatrixCSC, a::_SparseKronGroup, b::Number) = mul!(c, a, b)

function kron(A::AbstractSparseMatrixCSC, B::AbstractSparseMatrixCSC)
    mA, nA = size(A)
    mB, nB = size(B)
    mC, nC = mA*mB, nA*nB
    Tv = typeof(oneunit(eltype(A))*oneunit(eltype(B)))
    Ti = promote_type(indtype(A), indtype(B))
    C = spzeros(Tv, Ti, mC, nC)
    sizehint!(C, nnz(A)*nnz(B))
    return @inbounds kron!(C, A, B)
end
function kron(x::AbstractCompressedVector, y::AbstractCompressedVector)
    nnzx, nnzy = nnz(x), nnz(y)
    nnzz = nnzx*nnzy # number of nonzeros in new vector
    nzind = Vector{promote_type(indtype(x), indtype(y))}(undef, nnzz) # the indices of nonzeros
    nzval = Vector{typeof(oneunit(eltype(x))*oneunit(eltype(y)))}(undef, nnzz) # the values of nonzeros
    z = SparseVector(length(x)*length(y), nzind, nzval)
    return @inbounds kron!(z, x, y)
end
# extend to annotated sparse arrays, but leave out the (dense ⊗ dense)-case
kron(A::_SparseKronGroup, B::_SparseKronGroup) =
    kron(convert(SparseMatrixCSC, A), convert(SparseMatrixCSC, B))
kron(A::_SparseKronGroup, B::_DenseConcatGroup) = kron(A, sparse(B))
kron(A::_DenseConcatGroup, B::_SparseKronGroup) = kron(sparse(A), B)
kron(A::_SparseVectorUnion, B::_AdjOrTransSparseVectorUnion) = A .* B
# disambiguation
kron(A::AbstractCompressedVector, B::AdjOrTrans{<:Any,<:AbstractCompressedVector}) = A .* B
kron(a::Number, b::_SparseKronGroup) = a * b
kron(a::_SparseKronGroup, b::Number) = a * b

## det, inv, cond

inv(A::AbstractSparseMatrixCSC) = error("The inverse of a sparse matrix can often be dense and can cause the computer to run out of memory. If you are sure you have enough memory, please either convert your matrix to a dense matrix, e.g. by calling `Matrix` or if `A` can be factorized, use `\\` on the dense identity matrix, e.g. `A \\ Matrix{eltype(A)}(I, size(A)...)` restrictions of `\\` on sparse lhs applies. Alternatively, `A\\b` is generally preferable to `inv(A)*b`")

# TODO

## scale methods

# Copy colptr and rowval from one sparse matrix to another
function copyinds!(C::AbstractSparseMatrixCSC, A::AbstractSparseMatrixCSC)
    if getcolptr(C) !== getcolptr(A)
        resize!(getcolptr(C), length(getcolptr(A)))
        copyto!(getcolptr(C), getcolptr(A))
    end
    if rowvals(C) !== rowvals(A)
        resize!(rowvals(C), length(rowvals(A)))
        copyto!(rowvals(C), rowvals(A))
    end
end

# multiply by diagonal matrix as vector
function mul!(C::AbstractSparseMatrixCSC, A::AbstractSparseMatrixCSC, D::Diagonal)
    m, n = size(A)
    b    = D.diag
    (n==length(b) && size(A)==size(C)) || throw(DimensionMismatch())
    copyinds!(C, A)
    Cnzval = nonzeros(C)
    Anzval = nonzeros(A)
    resize!(Cnzval, length(Anzval))
    for col in 1:n, p in nzrange(A, col)
        @inbounds Cnzval[p] = Anzval[p] * b[col]
    end
    C
end

function mul!(C::AbstractSparseMatrixCSC, D::Diagonal, A::AbstractSparseMatrixCSC)
    m, n = size(A)
    b    = D.diag
    (m==length(b) && size(A)==size(C)) || throw(DimensionMismatch())
    copyinds!(C, A)
    Cnzval = nonzeros(C)
    Anzval = nonzeros(A)
    Arowval = rowvals(A)
    resize!(Cnzval, length(Anzval))
    for col in 1:n, p in nzrange(A, col)
        @inbounds Cnzval[p] = b[Arowval[p]] * Anzval[p]
    end
    C
end

function mul!(C::AbstractSparseMatrixCSC, A::AbstractSparseMatrixCSC, b::Number)
    size(A)==size(C) || throw(DimensionMismatch())
    copyinds!(C, A)
    resize!(nonzeros(C), length(nonzeros(A)))
    mul!(nonzeros(C), nonzeros(A), b)
    C
end

function mul!(C::AbstractSparseMatrixCSC, b::Number, A::AbstractSparseMatrixCSC)
    size(A)==size(C) || throw(DimensionMismatch())
    copyinds!(C, A)
    resize!(nonzeros(C), length(nonzeros(A)))
    mul!(nonzeros(C), b, nonzeros(A))
    C
end

function rmul!(A::AbstractSparseMatrixCSC, b::Number)
    rmul!(nonzeros(A), b)
    return A
end

function lmul!(b::Number, A::AbstractSparseMatrixCSC)
    lmul!(b, nonzeros(A))
    return A
end

function rmul!(A::AbstractSparseMatrixCSC, D::Diagonal)
    m, n = size(A)
    (n == size(D, 1)) || throw(DimensionMismatch())
    Anzval = nonzeros(A)
    @inbounds for col in 1:n, p in nzrange(A, col)
         Anzval[p] = Anzval[p] * D.diag[col]
    end
    return A
end

function lmul!(D::Diagonal, A::AbstractSparseMatrixCSC)
    m, n = size(A)
    (m == size(D, 2)) || throw(DimensionMismatch())
    Anzval = nonzeros(A)
    Arowval = rowvals(A)
    @inbounds for col in 1:n, p in nzrange(A, col)
        Anzval[p] = D.diag[Arowval[p]] * Anzval[p]
    end
    return A
end

function ldiv!(C::AbstractSparseMatrixCSC, D::Diagonal, A::AbstractSparseMatrixCSC)
    m, n = size(A)
    b    = D.diag
    (m==length(b) && size(A)==size(C)) || throw(DimensionMismatch())
    copyinds!(C, A)
    Cnzval = nonzeros(C)
    Anzval = nonzeros(A)
    Arowval = rowvals(A)
    resize!(Cnzval, length(Anzval))
    for col in 1:n, p in nzrange(A, col)
        @inbounds Cnzval[p] = b[Arowval[p]] \ Anzval[p]
    end
    C
end

function LinearAlgebra._rdiv!(C::AbstractSparseMatrixCSC, A::AbstractSparseMatrixCSC, D::Diagonal)
    m, n = size(A)
    b    = D.diag
    (n==length(b) && size(A)==size(C)) || throw(DimensionMismatch())
    copyinds!(C, A)
    Cnzval = nonzeros(C)
    Anzval = nonzeros(A)
    resize!(Cnzval, length(Anzval))
    for col in 1:n, p in nzrange(A, col)
        @inbounds Cnzval[p] = Anzval[p] / b[col]
    end
    C
end

function \(A::AbstractSparseMatrixCSC, B::AbstractVecOrMat)
    require_one_based_indexing(A, B)
    m, n = size(A)
    if m == n
        if istril(A)
            if istriu(A)
                return \(Diagonal(Vector(diag(A))), B)
            else
                return \(LowerTriangular(A), B)
            end
        elseif istriu(A)
            return \(UpperTriangular(A), B)
        end
        if ishermitian(A)
            return \(Hermitian(A), B)
        end
        return \(lu(A), B)
    else
        return \(qr(A), B)
    end
end
for (xformtype, xformop) in ((:Adjoint, :adjoint), (:Transpose, :transpose))
    @eval begin
        function \(xformA::($xformtype){<:Any,<:AbstractSparseMatrixCSC}, B::AbstractVecOrMat)
            A = xformA.parent
            require_one_based_indexing(A, B)
            m, n = size(A)
            if m == n
                if istril(A)
                    if istriu(A)
                        return \(Diagonal(($xformop.(diag(A)))), B)
                    else
                        return \(UpperTriangular($xformop(A)), B)
                    end
                elseif istriu(A)
                    return \(LowerTriangular($xformop(A)), B)
                end
                if ishermitian(A)
                    return \($xformop(Hermitian(A)), B)
                end
                return \($xformop(lu(A)), B)
            else
                return \($xformop(qr(A)), B)
            end
        end
    end
end

function factorize(A::AbstractSparseMatrixCSC)
    m, n = size(A)
    if m == n
        if istril(A)
            if istriu(A)
                return Diagonal(A)
            else
                return LowerTriangular(A)
            end
        elseif istriu(A)
            return UpperTriangular(A)
        end
        if ishermitian(A)
            return factorize(Hermitian(A))
        end
        return lu(A)
    else
        return qr(A)
    end
end

# function factorize(A::Symmetric{Float64,AbstractSparseMatrixCSC{Float64,Ti}}) where Ti
#     F = cholesky(A)
#     if LinearAlgebra.issuccess(F)
#         return F
#     else
#         ldlt!(F, A)
#         return F
#     end
# end
function factorize(A::LinearAlgebra.RealHermSymComplexHerm{Float64,<:AbstractSparseMatrixCSC})
    F = cholesky(A; check = false)
    if LinearAlgebra.issuccess(F)
        return F
    else
        ldlt!(F, A)
        return F
    end
end

eigen(A::AbstractSparseMatrixCSC) =
    error("eigen(A) not supported for sparse matrices. Use for example eigs(A) from the Arpack package instead.")
