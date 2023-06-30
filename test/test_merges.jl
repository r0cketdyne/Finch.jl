@testset "merges" begin
    @info "Testing Merge Kernels"
    using Base.Iterators
    #TODO this is a hack to get around the fact that we don't call leaf_instance on interpolated values
    #and leaf_instance isn't super robust
    using Finch.FinchNotation: literal_instance
    fmts = [
        (;fmt = (z) -> @fiber(d(sl(e(z)))), proto = [literal_instance(walk), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(sl(e(z)))), proto = [literal_instance(gallop), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(svb(e(z)))), proto = [literal_instance(walk), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(svb(e(z)))), proto = [literal_instance(gallop), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(sbm(e(z)))), proto = [literal_instance(walk), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(sbm(e(z)))), proto = [literal_instance(gallop), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(d(sc{1}(e(z)))), proto = [literal_instance(walk), literal_instance(follow)]),
        (;fmt = (z) -> @fiber(sc{2}(e(z))), proto = [literal_instance(walk), literal_instance(walk)]),
        (;fmt = (z) -> @fiber(d(sh{1}(e(z)))), proto = [literal_instance(walk),literal_instance(follow)]),
        (;fmt = (z) -> @fiber(sh{2}(e(z))), proto = [literal_instance(walk), literal_instance(walk)]),
        #(;fmt = (z) -> @fiber(d(rl(z))), proto = [walk, follow]),
        (;fmt = (z) -> @fiber(d(srl(e(z)))), proto = [walk, follow]),
    ]

    dtss = [
        (;default = 0.0, data = fill(0, 5, 5), ),
        (;default = 0.0, data = fill(1, 5, 5), ),
        (;default = 0.0, data = [
            0.0 0.1 0.0 0.0 0.0;
            0.0 0.8 0.0 0.0 0.0;
            0.0 0.2 0.1 0.0 0.0;
            0.4 0.0 0.3 0.5 0.2;
            0.0 0.4 0.8 0.1 0.5],),
        (;default = 0.0, data = [
            0.0 0.0 0.0 0.0 0.0;
            0.0 0.0 0.0 0.0 0.0;
            0.0 0.0 0.0 0.0 0.0;
            0.0 0.0 0.0 0.0 0.0;
            0.0 0.4 0.0 0.0 0.0],),
        (;default = 0.0, data = [
            0.0 0.0 0.0 0.0 0.0;
            0.2 0.2 0.0 0.0 0.0;
            0.0 0.0 0.2 0.7 0.0;
            0.0 0.0 0.0 0.0 0.1;
            0.0 0.0 0.0 0.0 0.0],),
    ]

    @testset "diagmask" begin
        for fmt in fmts
            @testset "$(summary(fmt.fmt(0.0)))[$(fmt.proto[1]), $(fmt.proto[2])]" begin
                for dts in dtss
                    a = dropdefaults!(fmt.fmt(dts.default), dts.data)
                    b = @fiber(sc{2}(e(dts.default)))

                    @finch (b .= 0; @loop j i b[i, j] = a[$(fmt.proto[1])(i), $(fmt.proto[2])(j)] * diagmask[i, j])

                    refdata = [dts.data[i, j] * (j == i) for (i, j) in product(axes(dts.data)...)]
                    ref = dropdefaults!(@fiber(sc{2}(e(dts.default))), refdata)
                    @test isstructequal(b, ref)
                end
            end
        end
    end

    @testset "lotrimask" begin
        for fmt in fmts
            @testset "$(summary(fmt.fmt(0.0)))[$(fmt.proto[1]), $(fmt.proto[2])]" begin
                for dts in dtss
                    a = dropdefaults!(fmt.fmt(dts.default), dts.data)
                    b = @fiber(sc{2}(e(dts.default)))
                    @finch (b .= 0; @loop j i b[i, j] = a[$(fmt.proto[1])(i), $(fmt.proto[2])(j)] * lotrimask[i, j])
                    refdata = [dts.data[i, j] * (j <= i) for (i, j) in product(axes(dts.data)...)]
                    ref = dropdefaults!(@fiber(sc{2}(e(dts.default))), refdata)
                    @test isstructequal(b, ref)
                end
            end
        end
    end

    @testset "uptrimask" begin
        for fmt in fmts
            @testset "$(summary(fmt.fmt(0.0)))[$(fmt.proto[1]), $(fmt.proto[2])]" begin
                for dts in dtss
                    a = dropdefaults!(fmt.fmt(dts.default), dts.data)
                    b = @fiber(sc{2}(e(dts.default)))
                    @finch (b .= 0; @loop j i b[i, j] = a[$(fmt.proto[1])(i), $(fmt.proto[2])(j)] * uptrimask[i, j])
                    refdata = [dts.data[i, j] * (j >= i) for (i, j) in product(axes(dts.data)...)]
                    ref = dropdefaults!(@fiber(sc{2}(e(dts.default))), refdata)
                    @test isstructequal(b, ref)
                end
            end
        end
    end

    #=
    @testset "bandmask" begin
        for fmt in fmts
            @testset "$(summary(fmt.fmt(0.0)))[$(fmt.proto[1]), $(fmt.proto[2])]" begin
                for dts in dtss
                    a = dropdefaults!(fmt.fmt(dts.default), dts.data)
                    b = @fiber(sc{2}(e(dts.default)))
                    @finch (b .= 0; @loop j i b[i, j] = a[$(fmt.proto[1])(i), $(fmt.proto[2])(j)] * bandmask[i, j - 1, j + 1])
                    refdata = [dts.data[i, j] * (j - 1 <= i <= j + 1) for (i, j) in product(axes(dts.data)...)]
                    ref = dropdefaults!(@fiber(sc{2}(e(dts.default))), refdata)
                    @test isstructequal(b, ref)
                end
            end
        end
    end
    =#

    @testset "plus times" begin
        n = 0
        for a_fmt in fmts
            for b_fmt in fmts[1:2]
                a_str = "$(summary(a_fmt.fmt(0.0)))[$(a_fmt.proto[1]), $(a_fmt.proto[2])]"
                b_str = "$(summary(b_fmt.fmt(0.0)))[$(b_fmt.proto[1]), $(b_fmt.proto[2])]"
                @testset "+* $a_str $b_str" begin
                    for a_dts in dtss
                        for b_dts in dtss
                            a = dropdefaults!(a_fmt.fmt(a_dts.default), a_dts.data)
                            b = dropdefaults!(b_fmt.fmt(b_dts.default), b_dts.data)
                            c = @fiber(sc{2}(e(a_dts.default)))
                            d = @fiber(sc{2}(e(a_dts.default)))
                            @finch (c .= 0; @loop j i c[i, j] = a[$(a_fmt.proto[1])(i), $(a_fmt.proto[2])(j)] + b[$(b_fmt.proto[1])(i), $(b_fmt.proto[2])(j)])
                            @finch (d .= 0; @loop j i d[i, j] = a[$(a_fmt.proto[1])(i), $(a_fmt.proto[2])(j)] * b[$(b_fmt.proto[1])(i), $(b_fmt.proto[2])(j)])
                            c_ref = dropdefaults!(@fiber(sc{2}(e(a_dts.default))), a_dts.data .+ b_dts.data)
                            d_ref = dropdefaults!(@fiber(sc{2}(e(a_dts.default))), a_dts.data .* b_dts.data)
                            @test isstructequal(c, c_ref)
                            @test isstructequal(d, d_ref)
                        end
                    end
                end
            end
        end
    end
end
