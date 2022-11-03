rules = []
add_rules!(new_rules) = union!(rules, new_rules)

add_rules!(@slots a b c d e i j f g m n [
    (@rule call(f, a...) => if isliteral(f) && all(isliteral, a) && length(a) >= 1 literal(getvalue(f)(getvalue.(a)...)) end),

    #TODO default needs to get defined on all writable chunks
    (@rule assign(access(a, writer(m), i...), b) => if b == literal(default(a)) pass(a) end),

    (@rule loop(i, pass(a...)) => pass(a...)),
    (@rule chunk(i, a, pass(b...)) => pass(b...)),
    (@rule with(pass(a...), b) => pass(a...)),
    (@rule with(a, pass()) => a),
    (@rule multi(a..., pass(b...), pass(c...)) => multi(a..., pass(b..., c...))),
    (@rule multi(pass(a...)) => pass(a...)),
    (@rule multi() => pass()),

    (@rule with(a, b) => begin
        @slots c d i j f g m begin
            props = Dict()
            b_2 = Postwalk(Chain([
                (@rule assign(access(c, writer($(literal(false))), i...), d) => if isliteral(d)
                    props[getname(c)] = d
                    pass()
                end),
                (@rule pass(c...) => begin
                    for d in c
                        props[getname(d)] = literal(default(d)) #TODO is this okay?
                    end
                    pass()
                end),
            ]))(b)
            if b_2 != nothing
                a_2 = Rewrite(Postwalk(@rule access(c, reader(), i...) => get(props, getname(c), nothing)))(a)
                with(a_2, b_2)
            end
        end
    end),
    #(@rule @f(a where @pass(b...)) => a),#can't do this bc produced tensors won't get initialized ?
])

isassociative(f) = false
isassociative(::typeof(min)) = true
isassociative(::typeof(max)) = true
isassociative(::typeof(+)) = true
isassociative(::typeof(*)) = true
isassociative(::typeof(or)) = true
isassociative(::typeof(and)) = true

iscommutative(f) = false
iscommutative(::typeof(min)) = true
iscommutative(::typeof(max)) = true
iscommutative(::typeof(+)) = true
iscommutative(::typeof(*)) = true
iscommutative(::typeof(or)) = true
iscommutative(::typeof(and)) = true

isidempotent(f) = false
isidempotent(::typeof(min)) = true
isidempotent(::typeof(max)) = true

isidentity(f, x) = false
isidentity(::typeof(+), x) = iszero(x)
isidentity(::typeof(*), x) = isone(x)
isidentity(::typeof(min), x) = isinf(x) && x > 0
isidentity(::typeof(max), x) = isinf(x) && x < 0
isidentity(::typeof(or), x) = x == false
isidentity(::typeof(and), x) = x == true

isannihilator(f, x) = false
isannihilator(::typeof(+), x) = isinf(x)
isannihilator(::typeof(*), x) = iszero(x)
isannihilator(::typeof(min), x) = isinf(x) && x < 0
isannihilator(::typeof(max), x) = isinf(x) && x > 0
isannihilator(::typeof(or), x) = x == true
isannihilator(::typeof(and), x) = x == false

isinverse(f, g) = false
isinverse(::typeof(+), ::typeof(-)) = true
isinverse(::typeof(*), ::typeof(inv)) = true

isassociative(f::CINNode) = f.kind === literal && isassociative(f.val)
iscommutative(f::CINNode) = f.kind === literal && iscommutative(f.val)
isidempotent(f::CINNode) = f.kind === literal && isidempotent(f.val)
isabelian(f) = isassociative(f) && iscommutative(f)
isidentity(f::CINNode, x::CINNode) = isliteral(f) && isliteral(x) && isidentity(f.val, x.val)
isannihilator(f::CINNode, x::CINNode) = isliteral(f) && isliteral(x) && isannihilator(f.val, x.val)

isinverse(f::CINNode, x::CINNode) = isliteral(f) && isliteral(x) && isinverse(f.val, x.val)

add_rules!(@slots a b c d e i j f g m n z [
    (@rule call($(literal(>=)), call($(literal(max)), a...), b) => call(or, map(x -> call(x >= b), a)...)),
    (@rule call($(literal(>)), call($(literal(max)), a...), b) => call(or, map(x -> call(x > b), a)...)),
    (@rule call($(literal(<=)), call($(literal(max)), a...), b) => call(and, map(x -> call(x <= b), a)...)),
    (@rule call($(literal(<)), call($(literal(max)), a...), b) => call(and, map(x -> call(x < b), a)...)),
    (@rule call($(literal(>=)), call($(literal(min)), a...), b) => call(and, map(x -> call(x >= b), a)...)),
    (@rule call($(literal(>)), call($(literal(min)), a...), b) => call(and, map(x -> call(x > b), a)...)),
    (@rule call($(literal(<=)), call($(literal(min)), a...), b) => call(or, map(x -> call(x <= b), a)...)),
    (@rule call($(literal(<)), call($(literal(min)), a...), b) => call(or, map(x -> call(x < b), a)...)),
    (@rule call(f::isassociative, a..., call(f, b...), c...) => call(f, a..., b..., c...)),
    (@rule call(f::iscommutative, a...) => if !(issorted(a, by = Lexicography))
        call(f, sort(a, by = Lexicography)...)
    end),
    (@rule call(f::isidempotent, a...) => if !allunique(a)
        call(f, unique(a)...)
    end),
    (@rule call(f::isassociative, a..., b::isliteral, c::isliteral, d...) => call(f, a..., f.val(b.val, c.val), d...)),
    (@rule call(f::isabelian, a..., b::isliteral, c..., d::isliteral, e...) => call(f, a..., f.val(b.val, d.val), c..., e...)),
    (@rule call(f, a..., b, c...) => if isannihilator(f, b) b end),
    (@rule call(f, a..., b, c, d...) => if isidentity(f, b)
        call(f, a..., c, d...)
    end),
    (@rule call(f, a..., b, c, d...) => if isidentity(f, c)
        call(f, a..., b, d...)
    end),
    (@rule call(f, a) => if isassociative(f) a end), #TODO

    (@rule call($(literal(/)), z::iszero, a) => z),
    (@rule call($(literal(ifelse)), $(literal(true)), a, b) => a),
    (@rule call($(literal(ifelse)), $(literal(false)), a, b) => b),
    (@rule call($(literal(ifelse)), a, b, b) => b),
    (@rule $(literal(-0.0)) => literal(0.0)),

    (@rule @f(or()) => @f false),
    (@rule @f(and()) => @f true),

    (@rule call(f, call(g, a, b...)) => if isinverse(g, f) && isassociative(g)
        call(g, call(f, a), call(f, call(g, b...)))
    end),
    (@rule @f($a[i...] += 0) => pass(a)),

    (@rule @f($a[i...] <<$f>>= $($(literal(missing)))) => pass(a)),
    (@rule @f($a[i..., $($(literal(missing))), j...] <<$f>>= $b) => pass(a)),
    (@rule @f($a[i..., $($(literal(missing))), j...]) => literal(missing)),
    (@rule @f(coalesce(a..., $($(literal(missing))), b...)) => @f coalesce(a..., b...)),
    (@rule @f(coalesce(a..., $b, c...)) => if isvalue(b) && !(Missing <: b.type); @f(coalesce(a..., $b)) end),
    (@rule @f(coalesce(a..., $b, c...)) => if isliteral(b) && b != literal(missing); @f(coalesce(a..., $b)) end),
    (@rule @f(coalesce($a)) => a),

    (@rule @f($a - $b) => @f $a + - $b),
    (@rule @f(- (- $a)) => a),

    (@rule @f((*)(a..., - $b, c...)) => @f -(*(a..., $b, c...))),
    (@rule @f($a[i...] *= 1) => pass(a)),
    (@rule @f(@sieve true $a) => a),
    (@rule @f(@sieve false $a) => pass(getresults(a)...)),

    (@rule @f(@chunk $i $a ($b[j...] <<min>>= $d)) => if Finch.isliteral(d) && i ∉ j
        @f (b[j...] <<min>>= $d)
    end),
    (@rule @f(@chunk $i $a @multi b... ($c[j...] <<min>>= $d) e...) => begin
        if Finch.isliteral(d) && i ∉ j
            @f @multi (c[j...] <<min>>= $d) @chunk $i a @f(@multi b... e...)
        end
    end),
    (@rule @f(@chunk $i $a ($b[j...] <<max>>= $d)) => if Finch.isliteral(d) && i ∉ j
        @f (b[j...] <<max>>= $d)
    end),
    (@rule @f(@chunk $i $a @multi b... ($c[j...] <<max>>= $d) e...) => begin
        if Finch.isliteral(d) && i ∉ j
            @f @multi (c[j...] <<max>>= $d) @chunk $i a @f(@multi b... e...)
        end
    end),
    (@rule @f(@chunk $i $a ($b[j...] += $d)) => begin
        if getname(i) ∉ getunbound(d) && i ∉ j
            @f (b[j...] += $(extent(a)) * $d)
        end
    end),
    (@rule @f(@chunk $i $a @multi b... ($c[j...] += $d) e...) => begin
        if getname(i) ∉ getunbound(d) && i ∉ j
            @f @multi (c[j...] += $(extent(a)) * $d) @chunk $i a @f(@multi b... e...)
        end
    end),
])

@kwdef mutable struct Simplify
    body
end

struct SimplifyStyle end

(ctx::Stylize{LowerJulia})(::Simplify) = SimplifyStyle()
combine_style(a::DefaultStyle, b::SimplifyStyle) = SimplifyStyle()
combine_style(a::ThunkStyle, b::SimplifyStyle) = ThunkStyle()
combine_style(a::SimplifyStyle, b::SimplifyStyle) = SimplifyStyle()

@kwdef struct SimplifyVisitor
    ctx
end

function (ctx::SimplifyVisitor)(node)
    if istree(node)
        similarterm(node, operation(node), map(ctx, arguments(node)))
    else
        node
    end
end

function (ctx::SimplifyVisitor)(node::CINNode)
    if node.kind === virtual
        convert(CINNode, ctx(node.val))
    elseif istree(node)
        similarterm(node, operation(node), map(ctx, arguments(node)))
    else
        node
    end
end

(ctx::SimplifyVisitor)(node::Simplify) = node.body

function simplify(node)
    global rules
    Rewrite(Fixpoint(Prewalk(Chain(rules))))(node)
end

function (ctx::LowerJulia)(root, ::SimplifyStyle)
    global rules
    root = SimplifyVisitor(ctx)(root)
    root = simplify(root)
    ctx(root)
end


IndexNotation.isliteral(::Simplify) =  false

struct Lexicography
    arg
end

function Base.isless(a::Lexicography, b::Lexicography)
    (a, b) = a.arg, b.arg
    #@assert which(priority, Tuple{typeof(a)}) == which(priority, Tuple{typeof(b)}) || priority(a) != priority(b)
    if a != b
        a_key = (priority(a), comparators(a)...)
        b_key = (priority(b), comparators(b)...)
        @assert a_key < b_key || b_key < a_key "a = $a b = $b a_key = $a_key b_key = $b_key"
        return a_key < b_key
    end
    return false
end

function Base.:(==)(a::Lexicography, b::Lexicography)
    (a, b) = a.arg, b.arg
    #@assert which(priority, Tuple{typeof(a)}) == which(priority, Tuple{typeof(b)}) || priority(a) != priority(b)
    a_key = (priority(a), comparators(a)...)
    b_key = (priority(b), comparators(b)...)
    return a_key == b_key
end

#=
priority(::Type) = (0, 5)
comparators(x::Type) = (string(x),)

priority(::Missing) = (0, 4)
comparators(::Missing) = (1,)

priority(::Number) = (1, 1)
comparators(x::Number) = (x, sizeof(x), typeof(x))

priority(::Function) = (1, 2)
comparators(x::Function) = (string(x),)

priority(::Symbol) = (2, 0)
comparators(x::Symbol) = (x,)

priority(::Expr) = (2, 1)
comparators(x::Expr) = (x.head, map(Lexicography, x.args)...)

#priority(::Workspace) = (3,3)
#comparators(x::Workspace) = (x.n,)

#TODO this works for now, but reconsider this later
priority(node::CINNode) = (3, 4)
function comparators(node::CINNode)
    if node.kind === value
        return (node.kind, Lexicography(node.val), Lexicography(node.type))
    elseif node.kind === literal
        return (node.kind, Lexicography(node.val))
    elseif node.kind === virtual
        return (node.kind, Lexicography(node.val))
    elseif node.kind === name
        return (node.kind, Lexicography(node.val))
    elseif istree(node)
        return (node.kind, map(Lexicography, node.children))
    else
        error("unimplemented")
    end
end
=#
#TODO these are nice defaults if we want to allow nondeterminism
priority(::Any) = (Inf,)
comparators(x::Any) = hash(x)