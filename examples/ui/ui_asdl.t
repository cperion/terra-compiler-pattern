return [=[
-- ============================================================================
-- Canonical UI Library ASDL Surface (Final Pass)
-- ----------------------------------------------------------------------------
-- This is the canonical UI layer directly under app-specific widgets.
-- App-specific widget editors lower concrete UI structure into UiDecl.
-- Raw UI input, reducer state, and semantic UI outputs live in sibling ASDL
-- modules so authored UI structure stays free of runtime interaction state.
--
-- Final-pass goals:
--   - keep the source ASDL small and canonical
--   - one element tree, not multiple unrelated trees
--   - layout / paint / content / behavior are facets on the same element identity
--   - stable ids and semantic refs flow through all UI phases
--   - no runtime objects, callbacks, style registries, or solved geometry in source
--   - layout and text shaping resolve together in UiLaid
--   - paint batching and behavior routing are sibling projections
-- ============================================================================


module UiCore {

    -- ------------------------------------------------------------------------
    -- Stable identities / references
    -- ------------------------------------------------------------------------
    ElementId     = (number value) unique
    SemanticRef   = (number domain, number value) unique

    FontRef       = (number value) unique
    ImageRef      = (number value) unique
    CursorRef     = (number value) unique

    CommandRef    = (number value) unique
    TextModelRef  = (number value) unique
    ScrollRef     = (number value) unique

    GlyphAtlasRef = (number value) unique

    -- ------------------------------------------------------------------------
    -- Geometry
    -- ------------------------------------------------------------------------
    Point = (
        number x,
        number y
    ) unique

    Size = (
        number w,
        number h
    ) unique

    Rect = (
        number x,
        number y,
        number w,
        number h
    ) unique

    Insets = (
        number top,
        number right,
        number bottom,
        number left
    ) unique

    Corners = (
        number top_left,
        number top_right,
        number bottom_right,
        number bottom_left
    ) unique

    Transform2D = (
        number m11, number m12,
        number m21, number m22,
        number tx,  number ty
    ) unique

    Aspect = (
        number width,
        number height
    ) unique

    -- ------------------------------------------------------------------------
    -- Layout vocabulary
    -- ------------------------------------------------------------------------
    Axis = Horizontal()
         | Vertical()
         | Both()

    Flow = None()
         | Row()
         | Column()
         | Stack()
         | Wrap(Axis axis)
         | Grid()

    MainAlign = Start()
              | Center()
              | End()
              | SpaceBetween()
              | SpaceAround()
              | SpaceEvenly()

    CrossAlign = CrossStart()
               | CrossCenter()
               | CrossEnd()
               | Stretch()

    Overflow = Visible()
             | Hidden()
             | Scroll()
             | OverflowAuto()

    Measure = Auto()
            | Px(number value)
            | Percent(number value)
            | Content()
            | Flex(number weight)

    EdgeMeasure = Unset()
                | EdgePx(number value)
                | EdgePercent(number value)

    SizeSpec = (
        Measure min,
        Measure preferred,
        Measure max
    ) unique

    Track = AutoTrack()
          | PxTrack(number value)
          | ContentTrack()
          | FlexTrack(number weight)

    AutoFlow = ByRow()
             | ByColumn()

    GridTemplate = (
        Track* columns,
        Track* rows,
        number column_gap,
        number row_gap,
        AutoFlow auto_flow
    ) unique

    GridCell = (
        number column_start,
        number column_span,
        number row_start,
        number row_span
    ) unique

    AnchorX = Left()
            | CenterX()
            | Right()

    AnchorY = Top()
            | CenterY()
            | Bottom()

    Position = InFlow()
             | Absolute(
                   EdgeMeasure left,
                   EdgeMeasure top,
                   EdgeMeasure right,
                   EdgeMeasure bottom
               )
             | Anchored(
                   ElementId target,
                   AnchorX self_x,
                   AnchorY self_y,
                   AnchorX target_x,
                   AnchorY target_y,
                   number dx,
                   number dy
               )

    -- ------------------------------------------------------------------------
    -- Paint vocabulary
    -- ------------------------------------------------------------------------
    Color = (
        number r,
        number g,
        number b,
        number a
    ) unique

    Stop = (
        number t,
        Color color
    ) unique

    Brush = Solid(Color color)
          | LinearGradient(Stop* stops, Point from, Point to)
          | RadialGradient(Stop* stops, Point center, number radius)

    StrokeAlign = Inside()
                | CenterStroke()
                | Outside()

    ShadowKind = DropShadow()
               | InnerShadow()

    BlendMode = BlendNormal()
              | BlendMultiply()
              | BlendScreen()
              | BlendOverlay()
              | BlendAdd()

    -- ------------------------------------------------------------------------
    -- Text vocabulary
    -- ------------------------------------------------------------------------
    FontWeight = Weight100()
               | Weight200()
               | Weight300()
               | Weight400()
               | Weight500()
               | Weight600()
               | Weight700()
               | Weight800()
               | Weight900()

    FontSlant = Roman()
              | Italic()
              | Oblique()

    TextWrap = NoWrap()
             | WrapWord()
             | WrapChar()

    TextOverflow = ClipText()
                 | Ellipsis()

    TextAlign = TextStart()
              | TextCenter()
              | TextEnd()
              | Justify()

    TextValue = (
        string value
    ) unique

    TextStyle = (
        FontRef? font,
        number? size_px,
        FontWeight? weight,
        FontSlant? slant,
        number? letter_spacing_px,
        number? line_height_px,
        Color? color
    ) unique

    TextLayout = (
        TextWrap wrap,
        TextOverflow overflow,
        TextAlign align,
        number line_limit
    ) unique

    -- ------------------------------------------------------------------------
    -- Image vocabulary
    -- ------------------------------------------------------------------------
    ImageFit = Fill()
             | Contain()
             | Cover()
             | StretchImage()
             | CenterImage()

    ImageSampling = Nearest()
                  | Linear()

    ImageStyle = (
        ImageFit fit,
        ImageSampling sampling,
        number opacity,
        Corners corners
    ) unique

    -- ------------------------------------------------------------------------
    -- Interaction vocabulary
    -- ------------------------------------------------------------------------
    PointerButton = Primary()
                  | Middle()
                  | Secondary()
                  | Button4()
                  | Button5()

    KeyEvent = KeyDown()
             | KeyUp()
             | KeyRepeat()

    KeyChord = (
        boolean ctrl,
        boolean alt,
        boolean shift,
        boolean meta,
        number keycode
    ) unique

    Gesture = Tap()
            | DoubleTap()
            | LongPress()
            | Drag()
            | Pan()

    FocusMode = TabFocus()
              | ClickFocus()
              | ProgrammaticFocus()
              | TextFocus()

    ToggleValue = Off()
                | On()
                | Mixed()

    DragPayload = Opaque(number kind, number value)
                | Semantic(SemanticRef ref)

    DropPolicy = AcceptAny()
               | AcceptKind(number kind)
               | AcceptSemantic(number domain)

    -- ------------------------------------------------------------------------
    -- Accessibility
    -- ------------------------------------------------------------------------
    AccessibleRole = AccNone()
                   | AccGroup()
                   | AccText()
                   | AccImage()
                   | AccButton()
                   | AccToggle()
                   | AccTextbox()
                   | AccList()
                   | AccListItem()
                   | AccScrollArea()
                   | AccDialog()
                   | AccCustom(number kind)

    -- ------------------------------------------------------------------------
    -- Solved helpers for downstream phases
    -- ------------------------------------------------------------------------
    ClipShape = ClipRect(Rect rect)
              | ClipRoundedRect(Rect rect, Corners corners)

    HitShape = HitRect(Rect rect)
             | HitRoundedRect(Rect rect, Corners corners)

    ScrollExtent = (
        number content_w,
        number content_h,
        number offset_x,
        number offset_y
    ) unique

    -- ------------------------------------------------------------------------
    -- Small role vocabulary
    -- ------------------------------------------------------------------------
    Role = View()
         | TextRole()
         | ImageRole()
         | ScrollPort()
         | ClipHost()
         | InputField()
         | ListHost()
         | OverlayHost()
         | CustomRole(number kind)
}



module UiAsset {

    -- ------------------------------------------------------------------------
    -- Explicit non-authored resource catalog.
    -- These are compiler inputs, not user-authored UI structure and not
    -- backend-global hidden state.
    -- ------------------------------------------------------------------------

    FontAsset = (
        UiCore.FontRef ref,
        string path
    ) unique

    ImageAsset = (
        UiCore.ImageRef ref,
        string path
    ) unique

    Catalog = (
        UiCore.FontRef default_font,
        FontAsset* fonts,
        ImageAsset* images
    ) unique
}



module UiDecl {

    -- ------------------------------------------------------------------------
    -- Canonical source phase.
    -- App-specific widgets lower into this tree.
    -- ------------------------------------------------------------------------

    Document = (
        number version,
        Root* roots,
        Overlay* overlays
    ) unique

    Root = (
        UiCore.ElementId id,
        string? debug_name,
        Element root
    ) unique

    Overlay = (
        UiCore.ElementId id,
        string? debug_name,
        Element root,
        number z_index,
        boolean modal,
        boolean consumes_pointer
    ) unique

    -- Element:
    --   Canonical noun for UI.
    --   App-specific widget concepts lower to Element trees.
    Element = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role,
        Flags flags,
        Layout layout,
        Paint paint,
        Content content,
        Behavior behavior,
        Accessibility accessibility,
        Element* children
    ) unique

    Flags = (
        boolean visible,
        boolean enabled
    ) unique

    -- ------------------------------------------------------------------------
    -- Layout facet
    -- ------------------------------------------------------------------------
    Layout = (
        UiCore.SizeSpec width,
        UiCore.SizeSpec height,
        UiCore.Position position,
        UiCore.Flow flow,
        UiCore.GridTemplate? grid,
        UiCore.GridCell? cell,
        UiCore.MainAlign main_align,
        UiCore.CrossAlign cross_align,
        UiCore.Insets padding,
        UiCore.Insets margin,
        number gap,
        UiCore.Overflow overflow_x,
        UiCore.Overflow overflow_y,
        UiCore.Aspect? aspect
    ) unique

    -- ------------------------------------------------------------------------
    -- Paint facet
    -- ------------------------------------------------------------------------
    -- Paint is declarative visual intent, not renderer commands.
    Paint = (
        PaintOp* ops
    ) unique

    PaintOp = Box(
                  UiCore.Brush fill,
                  UiCore.Brush? stroke,
                  number stroke_width,
                  UiCore.StrokeAlign align,
                  UiCore.Corners corners
              )
            | Shadow(
                  UiCore.Brush brush,
                  number blur,
                  number spread,
                  number dx,
                  number dy,
                  UiCore.ShadowKind kind,
                  UiCore.Corners corners
              )
            | Clip(
                  UiCore.Corners corners
              )
            | Opacity(
                  number value
              )
            | Transform(
                  UiCore.Transform2D xform
              )
            | Blend(
                  UiCore.BlendMode mode
              )
            | CustomPaint(
                  number kind,
                  number payload
              )

    -- ------------------------------------------------------------------------
    -- Content facet
    -- ------------------------------------------------------------------------
    -- Content is distinct from decorative paint because layout, shaping,
    -- accessibility, and editing all depend on it structurally.
    Content = NoContent()
            | Text(
                  UiCore.TextValue value,
                  UiCore.TextStyle style,
                  UiCore.TextLayout layout
              )
            | Image(
                  UiCore.ImageRef image,
                  UiCore.ImageStyle style
              )
            | CustomContent(
                  number kind,
                  number payload
              )

    -- ------------------------------------------------------------------------
    -- Behavior facet
    -- ------------------------------------------------------------------------
    -- Behavior is semantic interaction intent.
    -- No callbacks, closures, runtime widget instances, or event buses.
    Behavior = (
        HitPolicy hit,
        FocusPolicy focus,
        PointerRule* pointer,
        ScrollRule? scroll,
        KeyRule* keys,
        EditRule? edit,
        DragDropRule* drag_drop
    ) unique

    HitPolicy = HitNone()
              | HitSelf()
              | HitSelfAndChildren()
              | HitChildrenOnly()

    FocusPolicy = NotFocusable()
                | Focusable(
                      UiCore.FocusMode mode,
                      number? order
                  )

    PointerRule = Hover(
                      UiCore.CursorRef? cursor,
                      UiCore.CommandRef? enter,
                      UiCore.CommandRef? leave
                  )
                | Press(
                      UiCore.PointerButton button,
                      number click_count,
                      UiCore.CommandRef command
                  )
                | Toggle(
                      UiCore.ToggleValue value,
                      UiCore.PointerButton button,
                      UiCore.CommandRef? command
                  )
                | Gesture(
                      UiCore.Gesture gesture,
                      UiCore.CommandRef command
                  )

    ScrollRule = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    KeyRule = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    EditRule = (
        UiCore.TextModelRef model,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    DragDropRule = Draggable(
                       UiCore.DragPayload payload,
                       UiCore.CommandRef? begin,
                       UiCore.CommandRef? finish
                   )
                 | DropTarget(
                       UiCore.DropPolicy policy,
                       UiCore.CommandRef command
                   )

    -- ------------------------------------------------------------------------
    -- Accessibility facet
    -- ------------------------------------------------------------------------
    Accessibility = (
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        boolean hidden,
        number sort_priority
    ) unique
}



module UiInput {

    -- ------------------------------------------------------------------------
    -- Canonical UI input language.
    -- These are raw UI-facing events before routing.
    -- ------------------------------------------------------------------------

    Event = PointerMoved(
                UiCore.Point position
            )
          | PointerPressed(
                UiCore.Point position,
                UiCore.PointerButton button
            )
          | PointerReleased(
                UiCore.Point position,
                UiCore.PointerButton button
            )
          | PointerExited()
          | WheelScrolled(
                UiCore.Point position,
                number dx,
                number dy
            )
          | KeyChanged(
                UiCore.KeyEvent when,
                UiCore.KeyChord chord
            )
          | TextEntered(
                string text
            )
          | FocusChanged(
                boolean focused
            )
          | ViewportResized(
                UiCore.Size viewport
            )
}



module UiSession {

    -- ------------------------------------------------------------------------
    -- Pure interaction state owned by the UI reducer.
    -- This is not authored UI structure and not renderer state.
    -- ------------------------------------------------------------------------

    State = (
        UiCore.Size viewport,
        UiCore.Point pointer,
        boolean pointer_in_bounds,
        boolean window_focused,
        PointerPress* pressed,
        UiCore.ElementId? hovered,
        UiCore.ElementId? focused,
        UiCore.ElementId? captured,
        DragSession? drag
    ) unique

    PointerPress = (
        UiCore.PointerButton button,
        UiCore.ElementId target,
        number click_count
    ) unique

    DragSession = (
        UiCore.ElementId source,
        UiCore.DragPayload payload,
        UiCore.Point origin
    ) unique
}



module UiLaid {

    -- ------------------------------------------------------------------------
    -- Coupled layout + text shaping phase.
    -- Produces solved boxes, shaped text, clip facts, and normalized behavior.
    -- ------------------------------------------------------------------------

    Scene = (
        Root* roots,
        Overlay* overlays,
        UiCore.Size viewport
    ) unique

    Root = (
        UiCore.ElementId id,
        string? debug_name,
        Element root
    ) unique

    Overlay = (
        UiCore.ElementId id,
        string? debug_name,
        Element root,
        number z_index,
        boolean modal,
        boolean consumes_pointer
    ) unique

    Element = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role,
        boolean visible,
        boolean enabled,

        UiCore.Rect border_box,
        UiCore.Rect padding_box,
        UiCore.Rect content_box,

        UiCore.ScrollExtent? scroll_extent,
        UiCore.ClipShape* clip_stack,

        DrawOp* draw,
        BehaviorNode behavior,
        Accessibility accessibility,

        Element* children
    ) unique

    -- ------------------------------------------------------------------------
    -- Solved visual instances
    -- ------------------------------------------------------------------------
    DrawOp = BoxDraw(
                 UiCore.Rect rect,
                 UiCore.Brush fill,
                 UiCore.Brush? stroke,
                 number stroke_width,
                 UiCore.StrokeAlign align,
                 UiCore.Corners corners
             )
           | ShadowDraw(
                 UiCore.Rect rect,
                 UiCore.Brush brush,
                 number blur,
                 number spread,
                 number dx,
                 number dy,
                 UiCore.ShadowKind kind,
                 UiCore.Corners corners
             )
           | TextDraw(
                 ShapedText text
             )
           | ImageDraw(
                 UiCore.ImageRef image,
                 UiCore.Rect rect,
                 UiCore.ImageStyle style
             )
           | ClipDraw(
                 UiCore.ClipShape shape
             )
           | OpacityDraw(
                 number value
             )
           | TransformDraw(
                 UiCore.Transform2D xform
             )
           | BlendDraw(
                 UiCore.BlendMode mode
             )
           | CustomDraw(
                 number kind,
                 number payload,
                 UiCore.Rect bounds
             )

    ShapedText = (
        UiCore.Rect bounds,
        number baseline_y,
        string text,
        UiCore.TextWrap wrap,
        UiCore.TextAlign align,
        ShapedLine* lines
    ) unique

    ShapedLine = (
        number baseline_y,
        UiCore.Rect ink_bounds,
        ShapedRun* runs
    ) unique

    ShapedRun = (
        UiCore.FontRef font,
        number size_px,
        UiCore.Color color,
        string text,
        Glyph* glyphs
    ) unique

    Glyph = (
        number glyph_id,
        number cluster,
        UiCore.Point origin,
        UiCore.Rect ink_bounds
    ) unique

    -- ------------------------------------------------------------------------
    -- Normalized behavior facts
    -- ------------------------------------------------------------------------
    BehaviorNode = (
        UiCore.HitShape? hit_shape,
        FocusNode? focus,
        PointerNode* pointer,
        ScrollNode? scroll,
        KeyNode* keys,
        EditNode? edit,
        DragDropNode* drag_drop
    ) unique

    FocusNode = (
        UiCore.FocusMode mode,
        number order,
        UiCore.Rect bounds
    ) unique

    PointerNode = Hover(
                      UiCore.CursorRef? cursor,
                      UiCore.CommandRef? enter,
                      UiCore.CommandRef? leave
                  )
                | Press(
                      UiCore.PointerButton button,
                      number click_count,
                      UiCore.CommandRef command
                  )
                | Toggle(
                      UiCore.ToggleValue value,
                      UiCore.PointerButton button,
                      UiCore.CommandRef? command
                  )
                | Gesture(
                      UiCore.Gesture gesture,
                      UiCore.CommandRef command
                  )

    ScrollNode = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport,
        UiCore.Size content_size
    ) unique

    KeyNode = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    EditNode = (
        UiCore.TextModelRef model,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed,
        UiCore.Rect bounds
    ) unique

    DragDropNode = Draggable(
                       UiCore.DragPayload payload,
                       UiCore.CommandRef? begin,
                       UiCore.CommandRef? finish
                   )
                 | DropTarget(
                       UiCore.DropPolicy policy,
                       UiCore.CommandRef command
                   )

    Accessibility = (
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        boolean hidden,
        number sort_priority,
        UiCore.Rect bounds
    ) unique
}



module UiBatched {

    -- ------------------------------------------------------------------------
    -- Paint-domain projection from UiLaid.
    -- Renderer-friendly batch plan, still pure canonical data.
    --
    -- Important:
    --   clip facts are carried structurally on the batch / effect item itself.
    --   The backend leaf must not need a scene-global clip lookup registry.
    -- ------------------------------------------------------------------------

    Scene = (
        Batch* batches,
        UiCore.Rect bounds
    ) unique

    Batch = BoxBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                BoxItem* items
            )
          | ShadowBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                ShadowItem* items
            )
          | ImageBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                UiCore.ImageRef image,
                UiCore.ImageSampling sampling,
                ImageItem* items
            )
          | GlyphBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                UiCore.FontRef font,
                UiCore.GlyphAtlasRef atlas,
                GlyphItem* items
            )
          | TextBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                UiCore.FontRef font,
                number size_px,
                TextItem* items
            )
          | EffectBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                EffectItem* items
            )
          | CustomBatch(
                number sort_key,
                UiCore.ClipShape? clip,
                number kind,
                number payload
            )

    BoxItem = (
        UiCore.Rect rect,
        UiCore.Brush fill,
        UiCore.Brush? stroke,
        number stroke_width,
        UiCore.StrokeAlign align,
        UiCore.Corners corners
    ) unique

    ShadowItem = (
        UiCore.Rect rect,
        UiCore.Brush brush,
        number blur,
        number spread,
        number dx,
        number dy,
        UiCore.ShadowKind kind,
        UiCore.Corners corners
    ) unique

    ImageItem = (
        UiCore.Rect rect,
        UiCore.ImageStyle style
    ) unique

    GlyphItem = (
        number glyph_id,
        UiCore.Point origin,
        UiCore.Color color
    ) unique

    TextItem = (
        string text,
        UiCore.Rect bounds,
        UiCore.Color color,
        UiCore.TextWrap wrap,
        UiCore.TextAlign align
    ) unique

    EffectItem = PushOpacity(number value)
               | PopOpacity()
               | PushTransform(UiCore.Transform2D xform)
               | PopTransform()
               | PushBlend(UiCore.BlendMode mode)
               | PopBlend()
               | PushClip(UiCore.ClipShape shape)
               | PopClip()
}



module UiRouted {

    -- ------------------------------------------------------------------------
    -- Behavior-domain projection from UiLaid.
    -- Event-routing plan, not runtime callback dispatch.
    -- ------------------------------------------------------------------------

    Scene = (
        HitEntry* hits,
        FocusEntry* focus_chain,
        PointerRoute* pointer_routes,
        ScrollRoute* scroll_routes,
        KeyRoute* key_routes,
        EditRoute* edit_routes,
        AccessibilityNode* accessibility
    ) unique

    HitEntry = (
        UiCore.ElementId element,
        UiCore.SemanticRef? semantic_ref,
        UiCore.HitShape shape,
        number z_index
    ) unique

    FocusEntry = (
        UiCore.ElementId element,
        UiCore.SemanticRef? semantic_ref,
        number order,
        UiCore.FocusMode mode,
        UiCore.Rect bounds
    ) unique

    PointerRoute = HoverRoute(
                       UiCore.ElementId element,
                       UiCore.SemanticRef? semantic_ref,
                       UiCore.CursorRef? cursor,
                       UiCore.CommandRef? enter,
                       UiCore.CommandRef? leave
                   )
                 | PressRoute(
                       UiCore.ElementId element,
                       UiCore.SemanticRef? semantic_ref,
                       UiCore.PointerButton button,
                       number click_count,
                       UiCore.CommandRef command
                   )
                 | ToggleRoute(
                       UiCore.ElementId element,
                       UiCore.SemanticRef? semantic_ref,
                       UiCore.ToggleValue value,
                       UiCore.PointerButton button,
                       UiCore.CommandRef? command
                   )
                 | GestureRoute(
                       UiCore.ElementId element,
                       UiCore.SemanticRef? semantic_ref,
                       UiCore.Gesture gesture,
                       UiCore.CommandRef command
                   )

    ScrollRoute = (
        UiCore.ElementId element,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport,
        UiCore.Size content_size
    ) unique

    KeyRoute = (
        UiCore.ElementId? scope,
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    EditRoute = (
        UiCore.ElementId element,
        UiCore.SemanticRef? semantic_ref,
        UiCore.TextModelRef model,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed,
        UiCore.Rect bounds
    ) unique

    AccessibilityNode = (
        UiCore.ElementId element,
        UiCore.SemanticRef? semantic_ref,
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        boolean hidden,
        number sort_priority,
        UiCore.Rect bounds,
        AccessibilityNode* children
    ) unique
}



module UiIntent {

    -- ------------------------------------------------------------------------
    -- Semantic UI outputs.
    -- The UI reducer emits these after routing UiInput through UiRouted.
    -- App reducers can translate them into app-domain events.
    -- ------------------------------------------------------------------------

    CaretMotion = MoveLeft()
                | MoveRight()
                | MoveUp()
                | MoveDown()
                | MoveLineStart()
                | MoveLineEnd()
                | MoveWordLeft()
                | MoveWordRight()

    EditAction = InsertText(string text)
               | Backspace()
               | Delete()
               | MoveCaret(CaretMotion motion, boolean extend)
               | SelectAll()
               | Submit()

    Event = Command(
                UiCore.CommandRef command,
                UiCore.ElementId? element,
                UiCore.SemanticRef? semantic_ref
            )
          | Toggle(
                UiCore.CommandRef? command,
                UiCore.ToggleValue value,
                UiCore.ElementId element,
                UiCore.SemanticRef? semantic_ref
            )
          | Scroll(
                UiCore.ScrollRef? model,
                number dx,
                number dy,
                UiCore.ElementId element,
                UiCore.SemanticRef? semantic_ref
            )
          | Edit(
                UiCore.TextModelRef model,
                EditAction action,
                UiCore.ElementId element,
                UiCore.SemanticRef? semantic_ref,
                UiCore.CommandRef? changed
            )
          | Focus(
                UiCore.ElementId? element,
                UiCore.SemanticRef? semantic_ref
            )
          | Hover(
                UiCore.ElementId? element,
                UiCore.SemanticRef? semantic_ref,
                UiCore.CursorRef? cursor
            )
}



module UiApply {

    -- ------------------------------------------------------------------------
    -- Pure interaction application result.
    --
    -- The UI reducer consumes:
    --   UiSession.State + UiRouted.Scene + UiInput.Event
    -- and produces:
    --   updated UiSession.State + emitted UiIntent.Event*
    --
    -- This keeps interaction as an explicit pure boundary instead of hiding
    -- routed behavior dispatch inside backend helpers or callback-style code.
    -- ------------------------------------------------------------------------

    Result = (
        UiSession.State session,
        UiIntent.Event* intents
    ) unique
}

]=]
