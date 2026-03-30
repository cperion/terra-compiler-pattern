return {
    stubs = {
        ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
        ["UiDecl.Document"] = "bind",
        ["UiBound.Document"] = "flatten",
        ["UiFlat.Scene"] = { "lower_geometry", "lower_render_facts", "lower_query_facts" },
        ["UiGeometryInput.Scene"] = "solve",
        ["UiGeometry.Scene"] = { "project_render_scene", "project_query_scene" },
        ["UiRenderScene.Scene"] = "schedule_render_machine_ir",
        ["UiQueryScene.Scene"] = "organize_query_machine_ir",
        ["UiRenderMachineIR.Render"] = "define_machine",
        ["UiMachine.RenderGen"] = "compile",
        ["UiMachine.Render"] = "materialize",
    },
}
