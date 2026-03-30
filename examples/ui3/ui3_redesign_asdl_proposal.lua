return [=[
-- ============================================================================
-- ui3 / ui4 redesign ASDL proposal snapshot
-- ----------------------------------------------------------------------------
-- Goal:
--   preserve the strong ui2/ui3 top language while rebuilding the lower half
--   so that every phase has one real verb and the installed render machine is
--   mechanically derivable.
--
-- This file intentionally captures the new proposal as a design artifact only.
-- It is not wired into the live ui3 scaffold yet; the current executable
-- example still follows the older `UiFlat -> ...` lower-half split.
--
-- High-level shape:
--   UiDecl
--     -> bind                -> UiBound
--     -> flatten             -> UiSpine
--     -> lower_measure       -> UiMeasure
--     -> solve               -> UiSolved
--
--   UiSpine
--     -> lower_render_semantics -> UiRenderSemantics
--   UiSolved + UiRenderSemantics
--     -> project_render_use     -> UiRenderUse
--     -> schedule_render        -> UiRenderPlan
--     -> define_render_machine  -> UiMachine.Render
--
--   UiSpine
--     -> lower_query_semantics  -> UiQuerySemantics
--   UiSolved + UiQuerySemantics
--     -> project_query_use      -> UiQueryUse
--     -> organize_query         -> UiQueryPlan
--
--   UiSession + UiQueryPlan + UiInput
--     -> reduce_ui              -> UiApply.Result
--
-- Notes:
--   - the top/source half intentionally stays close to the current ui3 scaffold
--   - the lower half is rebuilt around:
--       spine -> solved geometry -> branch semantics -> use-sites -> machine plan
--   - only render is currently frozen as a full canonical machine
--   - built-in query is still consumed directly by the pure reducer
--
-- The source-language modules below are copied from the proposal text so the
-- repository keeps the concrete vocabulary of the redesign together with the
-- pipeline sketch.

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
    -- Shared solved helpers
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
    -- App/domain-specific widgets lower into this tree.
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
                  UiCore.ShadowKind shadow_kind,
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
                  number family,
                  number payload
              )

    -- ------------------------------------------------------------------------
    -- Content facet
    -- ------------------------------------------------------------------------
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
            | InlineCustomContent(
                  number family,
                  number payload
              )
            | ResourceCustomContent(
                  number family,
                  number resource_payload,
                  number instance_payload
              )

    -- ------------------------------------------------------------------------
    -- Behavior facet
    -- ------------------------------------------------------------------------
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


module UiIntent {

    -- ------------------------------------------------------------------------
    -- Semantic UI outputs emitted by the pure reducer.
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

    -- The issue proposal excerpt continues beyond this point; keep the
    -- pipeline snapshot above as the authoritative new lower-half direction.
}
]=]
