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

# ---------------------------------------------------------------------------
# Streaming: tdmsinfo / tdmsread / tdmsblocks read the metadata once and the
# samples on demand, so a file need never be held in memory whole. Every answer
# must equal what readtdms returns for the same file.
# ---------------------------------------------------------------------------
let dir=joinpath(@__DIR__, "example_files")
    # a single-channel Int16 file with several segments of awkward lengths (test-only encoder)
    function writesegments(path, segs)
        open(path, "w") do io
            for (k, seg) in enumerate(segs)
                m = IOBuffer()
                write(m, UInt32(2))
                for (p, n) in (("/", nothing), ("/'G'/'c'", length(seg)))
                    write(m, UInt32(ncodeunits(p))); write(m, codeunits(p))
                    if n === nothing; write(m, UInt32(0xFFFFFFFF))
                    else write(m, UInt32(20)); write(m, UInt32(2)); write(m, UInt32(1)); write(m, UInt64(n)) end
                    write(m, UInt32(0))
                end
                meta = take!(m); raw = reinterpret(UInt8, seg)
                write(io, codeunits("TDSm")); write(io, UInt32(0x2 | 0x4 | 0x8)); write(io, UInt32(4713))
                write(io, UInt64(length(meta) + length(raw))); write(io, UInt64(length(meta)))
                write(io, meta); write(io, raw)
            end
        end
        path
    end
    segs = [Int16.(rand(-300:300, n)) for n in (10_007, 3_331, 25_001, 999)]
    truth = vcat(segs...)
    big = writesegments(joinpath(mktempdir(), "segs.tdms"), segs)

    @testset "tdmsinfo: metadata only" begin
        i = tdmsinfo(TDMSReader._example_tdms)
        a = readtdms(TDMSReader._example_tdms)
        @test i.file.props == a.props && keys(i.file) == keys(a)
        @test i.file["Group"].props == a["Group"].props
        @test isempty(i.file["Group","Channel1"].data)             # nothing read
        @test i["Group","Channel1"].nsamples == 0
        j = tdmsinfo(big)
        @test j["G","c"].nsamples == length(truth) && j["G","c"].eltype == Int16
        @test j[1,1] === j["G","c"]
        @test collect(keys(j)) == [("G","c")]
        @test_throws KeyError j["G","nope"]
    end

    @testset "tdmsread: ranges by absolute sample index, any layout" begin
        @test tdmsread(big, "G", "c", 1:5) == truth[1:5]
        @test tdmsread(big, "G", "c", 10_001:10_020) == truth[10_001:10_020]      # segment 1 -> 2
        @test tdmsread(big, "G", "c", 13_330:13_345) == truth[13_330:13_345]      # segment 2 -> 3
        @test tdmsread(big, "G", "c", 1:length(truth)) == truth
        @test tdmsread(big, "G", "c", length(truth):length(truth)) == truth[end:end]
        @test isempty(tdmsread(big, "G", "c", 5:4))
        # interleaved and never-closed files stream like any other
        @test tdmsread(joinpath(dir, "interleaved.tdms"), "Group", "ch2", 3:6) == -Int16[3:6;]
        @test tdmsread(joinpath(dir, "never_closed.tdms"), "Group", "ch1", 11:19) == Int16[11:19;]
        # the incremental fixtures: every channel, whole, equals readtdms
        for fn in TDMSReader._example_incremental
            a = readtdms(fn)
            for (g, grp) in a.groups, (c, ch) in grp.channels
                n = tdmsinfo(fn)[g, c].nsamples
                @test n == length(ch.data)
                @test tdmsread(fn, g, c, 1:n) == ch.data
            end
        end
        # an info object stands in for the path, and is not re-walked
        j = tdmsinfo(big)
        @test tdmsread(j, "G", "c", 1:5) == truth[1:5]
    end

    @testset "bounds are checked, never clipped" begin
        n = length(truth)
        @test_throws BoundsError tdmsread(big, "G", "c", 0:5)
        @test_throws BoundsError tdmsread(big, "G", "c", n:n+1)
        @test_throws BoundsError tdmsread(big, "G", "c", n+1:n+1)
        @test_throws KeyError tdmsread(big, "G", "nope", 1:1)
        # a never-closed file's count is what the file holds, and reads stop there
        j = tdmsinfo(joinpath(dir, "never_closed.tdms"))
        @test j["Group","ch1"].nsamples == 19
        @test_throws BoundsError tdmsread(j, "Group", "ch1", 19:20)
    end

    @testset "tdmsblocks: one buffer, every sample once, in order" begin
        got = Int16[]; offs = Int[]; sizes = Int[]
        total = tdmsblocks(big, "G", "c"; blocksize = 4096) do x, off
            push!(offs, off); push!(sizes, length(x)); append!(got, x)
        end
        @test total == length(truth) && got == truth
        @test offs == 0:4096:(length(truth) - 1) && all(sizes[1:end-1] .== 4096)
        @test sizes[end] == (length(truth) - 1) % 4096 + 1                      # short, never padded
        il = Int16[]
        tdmsblocks(joinpath(dir, "interleaved.tdms"), "Group", "ch1"; blocksize = 3) do x, _; append!(il, x); end
        @test il == Int16[1:8;]
        nc = Int16[]
        tdmsblocks(joinpath(dir, "never_closed.tdms"), "Group", "ch1"; blocksize = 5) do x, _; append!(nc, x); end
        @test nc == Int16[1:19;]
        @test tdmsblocks((x, _) -> nothing, TDMSReader._example_tdms, "Group", "Channel1") == 0
    end

    @testset "memory bounds: a byte budget sizes the buffer, and readtdms refuses to exceed it" begin
        sizes = Int[]
        tdmsblocks(big, "G", "c"; memory = 1000) do x, _; push!(sizes, length(x)); end   # 1000 B / 2 B = 500
        @test maximum(sizes) == 500 && sum(sizes) == length(truth)
        @test_throws ArgumentError tdmsblocks((x, _) -> nothing, big, "G", "c"; memory = 1)   # not even one value
        # the whole file's data is 2 x length(truth) bytes; a smaller budget is a refusal, not a crash
        @test_throws ErrorException readtdms(big; memory = 2 * length(truth) - 1)
        @test occursin("tdmsblocks", sprint(showerror, try readtdms(big; memory = 10) catch e; e end))
        @test readtdms(big; memory = 2 * length(truth))["G", "c"].data == truth
        # the default budget is free RAM: a small file always fits
        @test readtdms(big)["G", "c"].data == truth
        @test TDMSReader.databytes(tdmsinfo(big)) == 2 * length(truth)
    end
end

# A minimal TDMS 2.0 writer, after NI's "TDMS File Format Internal Structure": the
# 28-byte lead-in, meta data (object paths, raw data indexes, string properties),
# then the raw data. Objects are (path, T, nvalues, props); T === nothing: no raw data.
tdms_str(s) = vcat(collect(reinterpret(UInt8, [UInt32(ncodeunits(s))])), codeunits(s))
function tdms_segment(io, objs, raw::AbstractVector{UInt8}; interleaved = false)
    meta = IOBuffer()
    write(meta, UInt32(length(objs)))
    for (path, T, n, props) in objs
        write(meta, tdms_str(path))
        T === nothing ? write(meta, 0xFFFFFFFF) : write(meta, UInt32(20), UInt32(2), UInt32(1), UInt64(n))  # Int16
        write(meta, UInt32(length(props)))
        for (k, v) in props
            write(meta, tdms_str(k), UInt32(0x20), tdms_str(v))
        end
    end
    m = take!(meta)
    toc = UInt32(1 << 1 | 1 << 2) | (isempty(raw) ? UInt32(0) : UInt32(1 << 3)) | (interleaved ? UInt32(1 << 5) : UInt32(0))
    write(io, b"TDSm", toc, UInt32(4713), UInt64(length(m) + length(raw)), UInt64(length(m)), m, raw)
end

# Reading should cost about the data it returns: not a boxed value per sample
# (interleaved rows), and not a 64 KiB buffer per string in the meta data.
@testset "Reading costs about the data" begin
    dir = mktempdir()
    n = 200_000
    chans = [Int16.(mod.(k .* (1:n), 2001) .- 1000) for k in 1:4]
    p = joinpath(dir, "interleaved_large.tdms")
    open(p, "w") do io
        objs = [("/", nothing, 0, []), ("/'G'", nothing, 0, []), [("/'G'/'c$k'", Int16, n, []) for k in 1:4]...]
        tdms_segment(io, objs, reinterpret(UInt8, vec(permutedims(hcat(chans...)))); interleaved = true)
    end
    a = TDMSReader.readtdms(p)
    @test all(a["G", "c$k"].data == chans[k] for k in 1:4)
    @test @allocated(TDMSReader.readtdms(p)) < 4 * (4n * sizeof(Int16))

    q = joinpath(dir, "segments.tdms")
    open(q, "w") do io
        for s in 1:300
            objs = [("/", nothing, 0, ["name" => "segments"]), ("/'G'", nothing, 0, ["unit" => "V"]),
                    ("/'G'/'x'", Int16, 10, ["unit_string" => "V"])]
            tdms_segment(io, objs, reinterpret(UInt8, Int16[10s-9:10s;]))
        end
    end
    b = TDMSReader.readtdms(q)
    @test b["G", "x"].data == Int16[1:3000;]
    @test b.props["name"] == "segments" && b["G", "x"].props["unit_string"] == "V"
    @test @allocated(TDMSReader.readtdms(q)) < 300 * 16 * 1024
end

# The same for the streaming functions: readtdms allocates the data once, sized from
# the meta data; a channel's back-to-back chunks are one run on disk, read at once;
# and an interleaved channel is gathered through a bounded buffer, not the whole span.
@testset "Streaming costs about the data" begin
    dir = mktempdir()
    nch, per, chunks = 4, 1000, 400
    vals = [Int16.(mod.(k .* (1:per*chunks), 3001) .- 1500) for k in 1:nch]
    p = joinpath(dir, "logging.tdms")        # one segment, 400 chunks of 4 channels x 1000 values
    open(p, "w") do io
        objs = [("/", nothing, 0, []), ("/'G'", nothing, 0, []), [("/'G'/'c$k'", Int16, per, []) for k in 1:nch]...]
        tdms_segment(io, objs, reduce(vcat, [reinterpret(UInt8, vals[k][(j-1)*per+1:j*per]) for j in 1:chunks for k in 1:nch]))
    end
    @test all(tdmsread(p, "G", "c$k", 1:per*chunks) == vals[k] for k in 1:nch)
    f = readtdms(p)
    @test all(f["G", "c$k"].data == vals[k] for k in 1:nch)
    @test @allocated(readtdms(p)) < 1.5 * TDMSReader.databytes(tdmsinfo(p)) + (1 << 20)

    q = joinpath(dir, "one_channel.tdms")    # one channel in 400 chunks, back to back on disk
    open(q, "w") do io
        tdms_segment(io, [("/", nothing, 0, []), ("/'G'", nothing, 0, []), ("/'G'/'x'", Int16, per, [])], reinterpret(UInt8, vals[1]))
    end
    @test length(tdmsinfo(q)["G", "x"].runs) == 1
    @test tdmsread(q, "G", "x", 1:per*chunks) == vals[1]
    @test tdmsread(q, "G", "x", 999:1002) == vals[1][999:1002]

    n = 1_000_000                            # four Int16 channels, sample-interleaved
    chans = [Int16.(mod.(k .* (1:n), 2001) .- 1000) for k in 1:4]
    r = joinpath(dir, "interleaved.tdms")
    open(r, "w") do io
        objs = [("/", nothing, 0, []), ("/'G'", nothing, 0, []), [("/'G'/'c$k'", Int16, n, []) for k in 1:4]...]
        tdms_segment(io, objs, reinterpret(UInt8, vec(permutedims(hcat(chans...)))); interleaved = true)
    end
    info = tdmsinfo(r)
    @test tdmsread(info, "G", "c3", 1:n) == chans[3]
    @test tdmsread(info, "G", "c3", 70_000:70_010) == chans[3][70_000:70_010]
    @test @allocated(tdmsread(info, "G", "c3", 1:n)) < 2 * n * sizeof(Int16)
end
