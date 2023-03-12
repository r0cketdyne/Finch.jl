#TODO should we just have another IR? Ugh idk
shallowcopy(x::T) where T = T([getfield(x, k) for k ∈ fieldnames(T)]...)

kwfields(x::T) where T = Dict((k=>getfield(x, k) for k ∈ fieldnames(T))...)

function fill_range!(arr, v, i, j)
    @simd for k = i:j
        arr[k] = v
    end
    arr
end

function resize_if_smaller!(arr, i)
    if length(arr) < i
        resize!(arr, i)
    end
end

function lower_caches(ex)
    consumers = Dict()
    function collect_consumers(ex, parent)
        if ex isa Symbol
            push!(get!(consumers, parent, Set()), ex)
        elseif ex isa Expr
            if ex.head == :cache
                (var, body) = ex.args
                push!(get!(consumers, var, Set()), parent)
                collect_consumers(body, var)
            else
                args = map(ex.args) do arg
                    collect_consumers(arg, parent)
                end
            end
        end
    end
    collect_consumers(ex, nothing)
    used = Set()
    function mark_used(var)
        if !(var in used)
            push!(used, var)
            for var_2 in get(consumers, var, [])
                mark_used(var_2)
            end
        end
    end
    mark_used(nothing)
    function prune_caches(ex)
        if ex isa Expr
            if ex.head == :cache
                (var, body) = ex.args
                if var in used 
                    return prune_caches(body)
                else
                    quote end
                end
            else
                Expr(ex.head, map(prune_caches, ex.args)...)
            end
        else
            return ex
        end
    end
    return prune_caches(ex)
end

function lower_cleanup(ex, ignore=false)
    if ex isa Expr && ex.head == :cleanup
        (sym::Symbol, result, cleanup) = ex.args
        result = lower_cleanup(result, ignore)
        cleanup = lower_cleanup(cleanup, true)
        if ignore
            return quote
                $result
                $cleanup
            end
        else
            return quote
                $sym = $result
                $cleanup
                $sym
            end
        end
    elseif ex isa Expr && ex.head == :block
        Expr(:block, map(ex.args[1:end - 1]) do arg
            lower_cleanup(arg, true)
        end..., lower_cleanup(ex.args[end], ignore))
    elseif ex isa Expr && ex.head in [:if, :elseif, :for, :while]
        Expr(ex.head, lower_cleanup(ex.args[1]), map(arg->lower_cleanup(arg, ignore), ex.args[2:end])...)
    elseif ex isa Expr
        Expr(ex.head, map(lower_cleanup, ex.args)...)
    else
        ex
    end
end

unquote_literals(ex) = ex
unquote_literals(ex::Expr) = Expr(ex.head, map(unquote_literals, ex.args)...)
unquote_literals(ex::QuoteNode) = unquote_quoted(ex.value)

unquote_quoted(::Missing) = missing
unquote_quoted(ex) = QuoteNode(ex)

"""
    unblock(ex)
Flatten any redundant blocks into a single block, over the whole expression.
"""
function unblock(ex::Expr)
    Rewrite(Postwalk(Fixpoint(Chain([
        (@rule :block(~a..., :block(~b...), ~c...) => Expr(:block, a..., b..., c...)),
        (@rule :block(~a) => a),
    ]))))(ex)
end
unblock(ex) = ex

"""
    striplines(ex)
Remove line numbers
"""
function striplines(ex::Expr)
    islinenum(x) = x isa LineNumberNode
    Rewrite(Postwalk(Fixpoint(Chain([
        (@rule :block(~a..., ~b::islinenum, ~c...) => Expr(:block, a..., c...)),
        (@rule :macrocall(~a, ~b, ~c...) => Expr(:macrocall, a, nothing, c...)),
    ]))))(ex)
end
striplines(ex) = ex

(Base.:^)(T::Type, i::Int) = ∘(repeated(T, i)..., identity)
(Base.:^)(f::Function, i::Int) = ∘(repeated(f, i)..., identity)

"""
    scansearch(v, x, lo, hi)

return the first value of `v` greater than or equal to `x`, within the range
`lo:hi`. Return `hi+1` if all values are less than `x`.
"""
Base.@propagate_inbounds function scansearch(v, x, lo::T, hi::T)::T where T<:Integer
    u = T(1)
    stop = min(hi, lo + T(32))
    while lo + u < stop && v[lo] < x
        lo += u
    end
    lo = lo - u
    hi = hi + u
    while lo < hi - u
        m = lo + ((hi - lo) >>> 0x01)
        if v[m] < x
            lo = m
        else
            hi = m
        end
    end
    return hi
end

struct Cindex{T} <: Integer
    val::T
    Cindex{T}(i, b::Bool=true) where {T} = new{T}(T(i) - b)
    Cindex{T}(i::Cindex{T}) where {T} = i
end

cindex_types = [Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128, BigInt]
for S in cindex_types
    @eval begin
        @inline Base.promote_rule(::Type{Cindex{T}}, ::Type{$S}) where {T} = promote_type(T, $S)
        Base.convert(::Type{Cindex{T}}, i::$S) where {T} = Cindex(convert(T, i))
        Cindex(i::$S) = Cindex{$S}(i)
        (::Type{$S})(i::Cindex{T}) where {T} = convert($S, i.val + true)
        Base.convert(::Type{$S}, i::Cindex) = convert($S, i.val + true)
        @inline Base.:(<<)(a::Cindex{T}, b::$S) where {T} = T(a) << b
    end
end
for S in [Float32, Float64]
    @eval begin
        @inline Base.promote_rule(::Type{Cindex{T}}, ::Type{$S}) where {T} = Cindex{promote_type(T, $S)}
        (::Type{$S})(i::Cindex{T}) where {T} = convert($S, i.val + true)
    end
end
Base.promote_rule(::Type{Cindex{T}}, ::Type{Cindex{S}}) where {T, S} = promote_type(T, S)
Base.convert(::Type{Cindex{T}}, i::Cindex) where {T} = Cindex{T}(convert(T, i.val), false)
Base.hash(x::Cindex, h::UInt) = hash(typeof(x), hash(x.val, h))

for op in [:*, :+, :-, :min, :max]
    @eval @inline Base.$op(a::Cindex{T}, b::Cindex{T}) where {T} = Cindex($op(T(a), T(b)))
end

for op in [:*, :+, :-, :min, :max]
    @eval @inline Base.$op(a::Cindex{T}) where {T} = Cindex($op(T(a)))
end

for op in [:<, :<=, :isless]
    @eval @inline Base.$op(a::Cindex{T}, b::Cindex{T}) where {T} = $op(T(a), T(b))
end