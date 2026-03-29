return [=[

module DemoCore {

    -- ------------------------------------------------------------------------
    -- Small app-domain nouns for the ui2 demo.
    --
    -- These are not raw UI element ids. They are the tiny user-facing targets
    -- the demo app talks about semantically.
    -- ------------------------------------------------------------------------

    Target = TitleCard()
           | ImagePlaceholder()
           | CustomCard()
           | OverlayCard()
}



module DemoCommand {

    -- ------------------------------------------------------------------------
    -- Closed app-side command language compiled onto UiDecl behavior.
    -- ------------------------------------------------------------------------

    Command = SelectTarget(DemoCore.Target target)
}



module DemoEvent {

    -- ------------------------------------------------------------------------
    -- Demo app event language decoded from UiIntent.
    -- ------------------------------------------------------------------------

    Event = SelectTarget(DemoCore.Target target)
          | HoverTarget(DemoCore.Target? target)
          | FocusTarget(DemoCore.Target? target)
          | ScrollTarget(
                DemoCore.Target target,
                number dx,
                number dy
            )
}



module DemoDecode {

    -- ------------------------------------------------------------------------
    -- Decoded demo-event batch from UiIntent.
    -- ------------------------------------------------------------------------

    Result = (
        DemoEvent.Event* events
    ) unique
}



module DemoApp {

    -- ------------------------------------------------------------------------
    -- Tiny demo-app reducer state.
    -- ------------------------------------------------------------------------

    ScrollSample = (
        DemoCore.Target target,
        number dx,
        number dy
    ) unique

    LogEntry = SelectedTarget(DemoCore.Target target)
             | HoveredTarget(DemoCore.Target? target)
             | FocusedTarget(DemoCore.Target? target)
             | ScrolledTarget(
                   DemoCore.Target target,
                   number dx,
                   number dy
               )

    State = (
        DemoCore.Target? hovered,
        DemoCore.Target? focused,
        DemoCore.Target? selected,
        ScrollSample? last_scroll,
        LogEntry* log
    ) unique
}

]=]