using TDMSReader
using Test

let a=TDMSReader.readtdms( TDMSReader._example_tdms )
    g=a.groups["Group"]
    c=g.channels["Channel1"]
    @testset "Basic Example File" begin
        @test isempty(a.props)
        @test g.props == Dict("prop" => "value", "num" => 10)
        @test isempty(c.props)
        @test isempty(c.data)
    end

    @testset "Indexing and Keys" begin
        @test Set(["Group"]) == keys(a)
        @test a.groups["Group"] == a["Group"] == a[1]
        @test keys(g.channels) == Set(["Channel1"])
        @test a["Group"] == a[1]
        @test a["Group"]["Channel1"]==a["Group","Channel1"]
        @test a["Group"][1]==a["Group",1]
        @test a[1]["Channel1"]==a[1,"Channel1"]
        @test a[1][1]==a[1,1]
        @test_throws BoundsError a[2]
        @test_throws BoundsError a[1,2]
        @test_throws KeyError a["BadKey"]
        @test_throws KeyError a[1,"BadKey"]
    end

    @testset "Equality Test" begin
        b=deepcopy(a)
        @test a[1,1]==b[1,1]
        @test a[1]==b[1]
        @test a==b

        a.props["NewVal"]="Val"
        b.props["NewVal"]="Val"
        @test a==a
        b.props["NewVal"]="Changed"
        @test a != b

        a[1].props["NewVal"]="Val"
        b[1].props["NewVal"]="Val"
        @test a[1]==a[1]
        b[1].props["NewVal"]="Changed"
        @test a[1] != b[1]

        a[1,1].props["NewVal"]="Val"
        b[1,1].props["NewVal"]="Val"
        @test a[1,1] == b[1,1]
        let b=deepcopy(b)
            b[1,1].props["NewVal"]="Changed"
            @test a[1,1] != b[1,1]
        end
        push!(a[1,1].data,4)
        @test a[1,1] != b[1,1]
        push!(b[1,1].data,4)
        @test a[1,1] == b[1,1]

        b.props["NewVal"]="Val"
        b[1].props["NewVal"]="Val"
        b[1,1].props["NewVal"]="Val"
        @test a[1,1]==b[1,1]
        @test a[1]==b[1]
        @test a==b
    end
end

let fn=TDMSReader._example_incremental
    a=TDMSReader.readtdms(first(fn))
    @testset "Incremental Files" begin
        @test a[1,1].data==[1:3;] && a[1,2].data==[4:6;]

        b=TDMSReader.readtdms(fn[2])
        @test a != b
        append!(a[1,1].data, [1:3;])
        append!(a[1,2].data, [4:6;])
        @test a==b

        b=TDMSReader.readtdms(fn[3])
        @test a != b
        append!(a[1,1].data,[1:3;])
        append!(a[1,2].data, [4:6;])
        @test a[1,1].data == b[1,1].data && a[1,2].data == b[1,2].data
        @test a[1,1].props["prop"] == "valid" && b[1,1].props["prop"] == "error"
        @test a[1,1] != a[1,2]
        a[1,1].props["prop"]="error"
        @test a == b

        #Add new voltage channel
        b=TDMSReader.readtdms(fn[4])
        @test collect(keys(b[1]))==["channel1","channel2","voltage"]
        append!(a[1,1].data,[1:3;])
        append!(a[1,2].data,[4:6;])
        a[1].channels["voltage"]=TDMSReader.Channel{Int}()
        append!(a[1,"voltage"].data, [7:11;])
        @test a == b

        b=TDMSReader.readtdms(fn[5])
        append!(a[1,1].data,[1:3;])
        append!(a[1,2].data,[1:27;])
        append!(a[1,3].data,[7:11;])
        @test a[1,1] == b[1,1]
        @test a[1,2] == b[1,2]
        @test a[1,3] == b[1,3]
        @test a == b

        # Stop appending channel #2
        b=TDMSReader.readtdms(fn[6])
        append!(a[1,1].data,[1:3;])
        append!(a[1,3].data,[7:11;])
        @test a == b

    end
end

let dir=joinpath(@__DIR__, "example_files")
    # Two channels written sample-interleaved (kTocInterleavedData set): rows of
    # (ch1, ch2) = (1,-1), (2,-2), ... Reading them as two contiguous blocks
    # gives each channel half of the other's samples.
    @testset "Interleaved Channels" begin
        a=TDMSReader.readtdms(joinpath(dir, "interleaved.tdms"))
        @test a[1,"ch1"].data == Int16[1:8;]
        @test a[1,"ch2"].data == -Int16[1:8;]
    end

    # A file LabVIEW never closed: the last segment's next-segment offset is all
    # ones, its data runs to end of file, and the final chunk is partial (7 of the
    # declared 12 values, then a stray byte that is not a whole Int16).
    @testset "Never-Closed File" begin
        a=TDMSReader.readtdms(joinpath(dir, "never_closed.tdms"))
        @test a[1,"ch1"].data == Int16[1:19;]
    end

    # DAQmx raw data is not implemented; say so, rather than fail on an undefined variable
    @testset "DAQmx Refused" begin
        @test_throws ErrorException TDMSReader.readtdms(TDMSReader._example_DAQmx)
    end
end
