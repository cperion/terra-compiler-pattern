local U = require("unit")

return function(T, U, P)
    local tests = {}

    local function bytecode_catalog()
        return T.CrochetRealizeLua.Catalog({
            T.CrochetRealizeLua.BytecodeInstall(
                "entry",
                1,
                "@crochet-realize:entry",
                "entry|artifact",
                "return function(x)\n  return x + inc\nend\n",
                {
                    T.CrochetRealizeLua.CaptureInstall(
                        "inc",
                        1,
                        1,
                        T.CrochetRealizeRuntime.ValueRef("inc", 4)
                    ),
                }
            ),
            T.CrochetRealizeLua.BytecodeInstall(
                "square",
                2,
                "@crochet-realize:square",
                "square|artifact",
                "return function(x)\n  return x * x\nend\n",
                {}
            ),
        }, 1, T.CrochetRealizeLua.BytecodeArtifact)
    end

    local function source_catalog()
        return T.CrochetRealizeLua.Catalog({
            T.CrochetRealizeLua.SourceInstall(
                "entry",
                1,
                "@crochet-realize:entry",
                "entry|artifact",
                "return function(x)\n  return x + 1\nend\n"
            ),
            T.CrochetRealizeLua.SourceInstall(
                "square",
                2,
                "@crochet-realize:square",
                "square|artifact",
                "return function(x)\n  return x * x\nend\n"
            ),
        }, 1, T.CrochetRealizeLua.SourceArtifact)
    end

    local function closure_catalog()
        return T.CrochetRealizeLua.Catalog({
            T.CrochetRealizeLua.ClosureInstall(
                "entry",
                1,
                "closure|entry|artifact",
                {
                    T.CrochetRealizeLua.ParamInstall("n", 1),
                },
                {
                    T.CrochetRealizeLua.CaptureInstall(
                        "inc",
                        1,
                        1,
                        T.CrochetRealizeRuntime.ValueRef("inc", 4)
                    ),
                },
                T.CrochetRealizeLua.ClosureInstallBlock({
                    T.CrochetRealizeLua.LetInstall(
                        T.CrochetRealizeLua.LocalInstall("acc", 1),
                        T.CrochetRealizeLua.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("zero", 0))
                    ),
                    T.CrochetRealizeLua.ForRangeInstall(
                        T.CrochetRealizeLua.LocalInstall("i", 2),
                        T.CrochetRealizeLua.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeLua.ParamExpr(1),
                        T.CrochetRealizeLua.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeLua.ClosureInstallBlock({
                            T.CrochetRealizeLua.SetInstall(
                                1,
                                T.CrochetRealizeLua.BinaryExpr(
                                    T.CrochetRealizeLua.AddOp,
                                    T.CrochetRealizeLua.LocalExpr(1),
                                    T.CrochetRealizeLua.LocalExpr(2)
                                )
                            ),
                        })
                    ),
                    T.CrochetRealizeLua.ReturnInstall(
                        T.CrochetRealizeLua.BinaryExpr(
                            T.CrochetRealizeLua.AddOp,
                            T.CrochetRealizeLua.LocalExpr(1),
                            T.CrochetRealizeLua.CaptureExpr(1)
                        )
                    ),
                })
            ),
        }, 1, T.CrochetRealizeLua.ClosureArtifact)
    end

    function tests.test_install_bytecode_catalog_realizes_granular_blobs()
        local unit = bytecode_catalog():install()
        local artifact = unit.fn(nil)

        assert(artifact.mode == "bytecode")
        assert(artifact.entry(5) == 9)
        assert(artifact:realize("square")(6) == 36)
        assert(artifact:realize(2)(7) == 49)
        assert(artifact.protos.entry.bytecode ~= nil)
        assert(artifact.protos.square.bytecode ~= nil)
        assert(artifact.bytecode_cache["entry|artifact"] ~= nil)
        assert(artifact.bytecode_cache["square|artifact"] ~= nil)
    end

    function tests.test_install_source_catalog_realizes_lazily()
        local unit = source_catalog():install()
        local artifact = unit.fn(nil)

        assert(artifact.mode == "source")
        assert(artifact.protos.entry ~= nil)
        assert(artifact.protos.entry.bytecode == nil)
        assert(artifact.entry(3) == 4)
        assert(artifact:realize("square")(4) == 16)
    end

    function tests.test_install_closure_catalog_realizes_direct_closure()
        local unit = closure_catalog():install()
        local artifact = unit.fn(nil)

        assert(artifact.mode == "closure")
        assert(artifact.entry(5) == 19)
        assert(artifact.protos.entry.bytecode == nil)
        assert(artifact.protos.entry.source == nil)
        assert(artifact:realize("entry") == artifact.entry)
    end

    return tests
end
