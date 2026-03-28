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
                  number family,
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



module UiIntent {

    -- ------------------------------------------------------------------------
    -- Semantic UI outputs.
    --
    -- These are the interaction-language products emitted by the pure UI
    -- reducer after consulting UiPlan's packed query plane. App/domain reducers
    -- can translate these into app-domain events without having to inspect the
    -- UI query structures directly.
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
    -- Pure UI reducer result.
    --
    -- The reducer consumes:
    --   UiSession.State + UiPlan.Scene + UiInput.Event
    --
    -- and produces:
    --   updated UiSession.State + emitted UiIntent.Event*
    --
    -- This keeps interaction as an explicit pure boundary rather than hiding
    -- semantic dispatch inside backend helpers or callback-style code.
    -- ------------------------------------------------------------------------

    Result = (
        UiSession.State session,
        UiIntent.Event* intents
    ) unique
}



module UiBound {

    -- ------------------------------------------------------------------------
    -- Bound / validated UI tree.
    --
    -- Meaning:
    --   UiDecl -> bind -> UiBound
    --
    -- This phase keeps the authored tree shape but consumes:
    --   - roots/overlays into canonical entries
    --   - local semantic defaults / fallbacks
    --   - ref and asset validation
    --   - authored facet normalization into bound semantic forms
    --
    -- Important:
    --   - still a tree
    --   - not flattened yet
    --   - not solver-facing yet
    --   - not solved yet
    -- ------------------------------------------------------------------------

    Document = (
        Entry* entries
    ) unique

    Entry = (
        UiCore.ElementId id,
        string? debug_name,
        Node root,
        number z_index,
        boolean modal,
        boolean consumes_pointer
    ) unique

    -- ------------------------------------------------------------------------
    -- Local state
    -- ------------------------------------------------------------------------
    Flags = (
        boolean visible,
        boolean enabled
    ) unique

    -- ------------------------------------------------------------------------
    -- Layout facet
    -- ------------------------------------------------------------------------
    -- Layout is still semantic layout intent, but it is now bound:
    --   - anchor targets are validated references
    --   - authored irregularity is normalized
    -- ------------------------------------------------------------------------
    AnchorTarget = (
        UiCore.ElementId target
    ) unique

    Position = InFlow()
             | Absolute(
                   UiCore.EdgeMeasure left,
                   UiCore.EdgeMeasure top,
                   UiCore.EdgeMeasure right,
                   UiCore.EdgeMeasure bottom
               )
             | Anchored(
                   AnchorTarget target,
                   UiCore.AnchorX self_x,
                   UiCore.AnchorY self_y,
                   UiCore.AnchorX target_x,
                   UiCore.AnchorY target_y,
                   number dx,
                   number dy
               )

    Layout = (
        UiCore.SizeSpec width,
        UiCore.SizeSpec height,
        Position position,
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
    -- Paint stays close to the authored language here. Binding does not yet
    -- solve geometry or emit draw atoms; it only preserves local visual intent
    -- in a bound phase-local vocabulary.
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
    -- Content is normalized into bound semantic forms.
    --
    -- The key binding move here is that text styling is made explicit:
    --   - resolved font ref is mandatory
    --   - optional source style fields become concrete values
    --   - authored text layout fields remain explicit but no longer optional
    --
    -- Text is still not measured or shaped here. That happens later.
    -- ------------------------------------------------------------------------
    BoundText = (
        UiCore.TextValue value,
        UiCore.FontRef font,
        number size_px,
        UiCore.FontWeight weight,
        UiCore.FontSlant slant,
        number letter_spacing_px,
        number line_height_px,
        UiCore.Color color,
        UiCore.TextWrap wrap,
        UiCore.TextOverflow overflow,
        UiCore.TextAlign align,
        number line_limit
    ) unique

    BoundImage = (
        UiCore.ImageRef image,
        UiCore.ImageStyle style
    ) unique

    Content = NoContent()
            | Text(BoundText text)
            | Image(BoundImage image)
            | CustomContent(
                  number family,
                  number payload
              )

    -- ------------------------------------------------------------------------
    -- Behavior facet
    -- ------------------------------------------------------------------------
    -- Behavior is still semantic interaction intent, but in bound form:
    -- refs are validated, defaults are canonicalized, and later phases do not
    -- need to reinterpret UiDecl.Behavior directly.
    -- ------------------------------------------------------------------------
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

    Behavior = (
        HitPolicy hit,
        FocusPolicy focus,
        PointerRule* pointer,
        ScrollRule? scroll,
        KeyRule* keys,
        EditRule? edit,
        DragDropRule* drag_drop
    ) unique

    -- ------------------------------------------------------------------------
    -- Accessibility facet
    -- ------------------------------------------------------------------------
    -- Binding consumes the authored hidden flag into an explicit sum type.
    -- Later phases can now distinguish clearly between:
    --   - no accessibility participation
    --   - exposed accessibility semantics
    -- ------------------------------------------------------------------------
    Accessibility = Hidden()
                  | Exposed(
                        UiCore.AccessibleRole role,
                        string? label,
                        string? description,
                        number sort_priority
                    )

    Node = (
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
        Node* children
    ) unique
}



module UiFlat {

    -- ------------------------------------------------------------------------
    -- Explicit flat topology preserving bound semantics.
    --
    -- Meaning:
    --   UiBound -> flatten -> UiFlat
    --
    -- This phase consumes ONLY recursive containment as implicit structure.
    -- It does NOT yet:
    --   - prepare solver demand models
    --   - convert bound refs into solver indices
    --   - compute effective propagated geometry facts
    --   - solve layout / text / clips
    --   - emit draw atoms or route tables
    --
    -- It DOES:
    --   - canonicalize each bound entry into a region-local node array
    --   - preserve source identity and all bound semantic facets
    --   - make parent/child/subtree topology explicit
    --
    -- Flattening policy:
    --   - one node array per region
    --   - region-local index space
    --   - pre-order depth-first node order
    --   - each subtree is contiguous in the node array
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    -- Region:
    --   Flat topology for one bound entry (root or overlay).
    --
    -- root_index:
    --   Explicit root node index for the region. Usually the first node, but
    --   kept explicit so downstream phases do not depend on hidden conventions.
    --
    -- z_index / modal / consumes_pointer:
    --   Preserved from UiBound.Entry. These are still region semantics, not yet
    --   render-kernel payload.
    Region = (
        UiCore.ElementId id,
        string? debug_name,
        number root_index,
        number z_index,
        boolean modal,
        boolean consumes_pointer,
        Node* nodes
    ) unique

    -- Node:
    --   One bound node with explicit structural position.
    --
    -- Topology invariants:
    --   - index is unique within the region
    --   - parent_index is nil only for the region root
    --   - if child_count == 0 then first_child_index is nil
    --   - if child_count > 0 then first_child_index points at the first
    --     immediate child in source order
    --   - subtree_count includes the node itself
    --   - because flattening is pre-order depth-first, the full subtree span is:
    --         [index, index + subtree_count - 1]
    --
    -- Semantic policy:
    --   - preserve bound ids / refs / role / facets unchanged
    --   - do not derive effective visibility, solver refs, demand models, or
    --     other prepared facts here; that belongs to UiDemand
    Node = (
        number index,
        number? parent_index,
        number? first_child_index,
        number child_count,
        number subtree_count,

        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role,

        UiBound.Flags flags,
        UiBound.Layout layout,
        UiBound.Paint paint,
        UiBound.Content content,
        UiBound.Behavior behavior,
        UiBound.Accessibility accessibility
    ) unique
}



module UiDemand {

    -- ------------------------------------------------------------------------
    -- Explicit solver input language.
    --
    -- Meaning:
    --   UiFlat -> prepare_demands -> UiDemand
    --
    -- This phase preserves the flat region/node topology from UiFlat, but
    -- converts bound semantic payload into the forms the solver actually wants:
    --   - explicit effective participation state
    --   - solver-facing layout refs
    --   - prepared intrinsic demand models
    --   - normalized visual input
    --   - geometry-query behavior demands
    --   - geometry-query accessibility demands
    --
    -- Important:
    --   - still not solved
    --   - still no draw atoms / route tables / packed plan arrays
    --   - anchor targets are region-local node indices here
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    Region = (
        UiCore.ElementId id,
        string? debug_name,
        number root_index,
        number z_index,
        boolean modal,
        boolean consumes_pointer,
        Node* nodes
    ) unique

    -- ------------------------------------------------------------------------
    -- Participation state
    -- ------------------------------------------------------------------------
    -- local_*:
    --   The node's own authored flags, preserved for diagnostics / inspection.
    --
    -- effective_*:
    --   The ancestry-folded participation truth the solver and later phases can
    --   consume directly without recomputing visibility / enablement.
    NodeState = (
        boolean local_visible,
        boolean local_enabled,
        boolean effective_visible,
        boolean effective_enabled
    ) unique

    -- ------------------------------------------------------------------------
    -- Solver-facing layout input
    -- ------------------------------------------------------------------------
    -- This is the first phase where bound semantic refs become solver refs.
    -- In particular, anchored targets are converted from validated ElementId
    -- references into region-local node indices.
    --
    -- Policy:
    --   geometry-coupled anchoring is region-local. If two nodes must anchor to
    --   each other geometrically, they must live in the same flattened region.
    PositionInput = InFlow()
                  | Absolute(
                        UiCore.EdgeMeasure left,
                        UiCore.EdgeMeasure top,
                        UiCore.EdgeMeasure right,
                        UiCore.EdgeMeasure bottom
                    )
                  | AnchoredTo(
                        number target_index,
                        UiCore.AnchorX self_x,
                        UiCore.AnchorY self_y,
                        UiCore.AnchorX target_x,
                        UiCore.AnchorY target_y,
                        number dx,
                        number dy
                    )

    LayoutInput = (
        UiCore.SizeSpec width,
        UiCore.SizeSpec height,
        PositionInput position,
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
    -- Prepared intrinsic demand models
    -- ------------------------------------------------------------------------
    -- These are local measurement models, not solved output.
    --
    -- Text remains width-sensitive: final wrapping / shaping is not done yet.
    -- However, all semantic text defaults have been consumed and enough
    -- intrinsic summaries are attached for the solver to ask meaningful local
    -- questions.
    PreparedText = (
        UiCore.TextValue value,

        UiCore.FontRef font,
        number size_px,
        UiCore.FontWeight weight,
        UiCore.FontSlant slant,
        number letter_spacing_px,
        number line_height_px,
        UiCore.Color color,

        UiCore.TextWrap wrap,
        UiCore.TextOverflow overflow,
        UiCore.TextAlign align,
        number line_limit,

        number min_content_w,
        number max_content_w
    ) unique

    PreparedImage = (
        UiCore.ImageRef image,
        UiCore.ImageStyle style,
        UiCore.Size intrinsic
    ) unique

    DemandModel = NoDemand()
                | TextDemand(PreparedText text)
                | ImageDemand(PreparedImage image)
                | CustomDemand(number family, number payload)

    -- ------------------------------------------------------------------------
    -- Normalized visual input
    -- ------------------------------------------------------------------------
    -- Paint is no longer carried as raw authored ops. Instead it is decomposed
    -- into:
    --   - local visual effects that modify later solved output
    --   - local decorations that become draw atoms once geometry exists
    --
    -- Overflow clipping is NOT represented here as an effect. It remains a
    -- consequence of solved geometry + overflow policy and therefore belongs to
    -- UiSolved.
    EffectInput = LocalClip(UiCore.Corners corners)
                | LocalOpacity(number value)
                | LocalTransform(UiCore.Transform2D xform)
                | LocalBlend(UiCore.BlendMode mode)

    DecorationInput = BoxDecor(
                          UiCore.Brush fill,
                          UiCore.Brush? stroke,
                          number stroke_width,
                          UiCore.StrokeAlign align,
                          UiCore.Corners corners
                      )
                    | ShadowDecor(
                          UiCore.Brush brush,
                          number blur,
                          number spread,
                          number dx,
                          number dy,
                          UiCore.ShadowKind shadow_kind,
                          UiCore.Corners corners
                      )
                    | CustomDecor(
                          number family,
                          number payload
                      )

    VisualInput = (
        EffectInput* effects,
        DecorationInput* decorations
    ) unique

    -- ------------------------------------------------------------------------
    -- Geometry-query behavior demand
    -- ------------------------------------------------------------------------
    -- This is no longer source behavior syntax. It is the set of geometry-
    -- dependent products later phases must be able to emit once solved boxes
    -- exist.
    HitDemand = NoHit()
              | SelfHit()
              | SelfAndChildrenHit()
              | ChildrenOnlyHit()

    FocusDemand = Focusable(
                      UiCore.FocusMode mode,
                      number? order
                  )

    PointerBinding = HoverBinding(
                         UiCore.CursorRef? cursor,
                         UiCore.CommandRef? enter,
                         UiCore.CommandRef? leave
                     )
                   | PressBinding(
                         UiCore.PointerButton button,
                         number click_count,
                         UiCore.CommandRef command
                     )
                   | ToggleBinding(
                         UiCore.ToggleValue value,
                         UiCore.PointerButton button,
                         UiCore.CommandRef? command
                     )
                   | GestureBinding(
                         UiCore.Gesture gesture,
                         UiCore.CommandRef command
                     )

    ScrollDemand = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    KeyBinding = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    EditDemand = (
        UiCore.TextModelRef model,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    DragDropBinding = DraggableBinding(
                          UiCore.DragPayload payload,
                          UiCore.CommandRef? begin,
                          UiCore.CommandRef? finish
                      )
                    | DropTargetBinding(
                          UiCore.DropPolicy policy,
                          UiCore.CommandRef command
                      )

    BehaviorInput = (
        HitDemand hit,
        FocusDemand? focus,
        PointerBinding* pointer,
        ScrollDemand? scroll,
        KeyBinding* keys,
        EditDemand? edit,
        DragDropBinding* drag_drop
    ) unique

    -- ------------------------------------------------------------------------
    -- Geometry-query accessibility demand
    -- ------------------------------------------------------------------------
    -- Hidden / non-participating accessibility is consumed into the type here.
    -- Later phases no longer branch on a hidden boolean.
    AccessibilityInput = NoAccessibility()
                       | AccessibilityDemand(
                             UiCore.AccessibleRole role,
                             string? label,
                             string? description,
                             number sort_priority
                         )

    Node = (
        number index,
        number? parent_index,
        number? first_child_index,
        number child_count,
        number subtree_count,

        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role,

        NodeState state,
        LayoutInput layout,
        DemandModel demand,
        VisualInput visual,
        BehaviorInput behavior,
        AccessibilityInput accessibility
    ) unique
}



module UiSolved {

    -- ------------------------------------------------------------------------
    -- Solved flat scene.
    --
    -- Meaning:
    --   UiDemand -> solve -> UiSolved
    --
    -- This phase preserves the flat topology from UiDemand while consuming the
    -- remaining geometry/content coupling:
    --   - layout constraints become solved boxes / extents
    --   - prepared text/image demand becomes solved content geometry
    --   - local visual effects become solved clips / visual state
    --   - geometry-query demands become solved interaction facts
    --   - accessibility demand becomes geometry-attached accessibility facts
    --
    -- Important:
    --   - still node-centered
    --   - still not packed into render/query planes
    --   - still backend-independent
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    Region = (
        UiCore.ElementId id,
        string? debug_name,
        number root_index,
        number z_index,
        boolean modal,
        boolean consumes_pointer,
        Node* nodes
    ) unique

    -- ------------------------------------------------------------------------
    -- Solved participation state
    -- ------------------------------------------------------------------------
    -- By this phase we keep the effective downstream truth only.
    SolvedState = (
        boolean visible,
        boolean enabled
    ) unique

    -- ------------------------------------------------------------------------
    -- Solved geometry
    -- ------------------------------------------------------------------------
    -- outer:
    --   Solved outer size allocated to the node.
    --
    -- border_box / padding_box / content_box:
    --   Explicit solved boxes used by later visual / query projections.
    --
    -- child_extent:
    --   Solved extent of laid-out child content.
    --
    -- scroll_extent:
    --   Present when the solved node participates as a scroll host.
    Geometry = (
        UiCore.Size outer,
        UiCore.Rect border_box,
        UiCore.Rect padding_box,
        UiCore.Rect content_box,
        UiCore.Size child_extent,
        UiCore.ScrollExtent? scroll_extent
    ) unique

    -- ------------------------------------------------------------------------
    -- Solved visual state and text output
    -- ------------------------------------------------------------------------
    -- Draw atoms are self-contained enough for later planning. UiPlan should be
    -- able to batch/project them without recomputing effective visual state.
    VisualState = (
        UiCore.ClipShape? clip,
        UiCore.BlendMode blend,
        number opacity,
        UiCore.Transform2D? transform
    ) unique

    ShapedText = (
        UiCore.TextValue text,
        UiCore.Rect bounds,
        UiCore.TextWrap wrap,
        UiCore.TextAlign align,
        ShapedLine* lines
    ) unique

    ShapedLine = (
        number baseline_y,
        number advance,
        ShapedRun* runs
    ) unique

    ShapedRun = (
        UiCore.FontRef font,
        number size_px,
        UiCore.Color color,
        GlyphPlacement* glyphs
    ) unique

    GlyphPlacement = (
        number glyph_id,
        number x,
        number y
    ) unique

    -- Shadow remains first-class through the solved/planned/kernel render path.
    -- It is not collapsed into CustomDraw because its payload shape is closed
    -- and known to the core UI vocabulary.
    DrawAtom = BoxDraw(
                   UiCore.Rect rect,
                   UiCore.Brush fill,
                   UiCore.Brush? stroke,
                   number stroke_width,
                   UiCore.StrokeAlign align,
                   UiCore.Corners corners,
                   VisualState state
               )
             | ShadowDraw(
                   UiCore.Rect rect,
                   UiCore.Brush brush,
                   number blur,
                   number spread,
                   number dx,
                   number dy,
                   UiCore.ShadowKind shadow_kind,
                   UiCore.Corners corners,
                   VisualState state
               )
             | TextDraw(
                   ShapedText shaped,
                   VisualState state
               )
             | ImageDraw(
                   UiCore.ImageRef image,
                   UiCore.Rect rect,
                   UiCore.ImageSampling sampling,
                   UiCore.Corners corners,
                   VisualState state
               )
             | CustomDraw(
                   number family,
                   number payload,
                   VisualState state
               )

    -- ------------------------------------------------------------------------
    -- Solved interaction facts
    -- ------------------------------------------------------------------------
    -- Geometry-dependent interaction products now exist explicitly per node.
    -- Later planning will extract packed hit/focus/key/scroll/edit tables from
    -- these solved node-local facts.
    HitNode = (
        UiCore.HitShape shape
    ) unique

    FocusNode = (
        UiCore.Rect rect,
        UiCore.FocusMode mode,
        number? order
    ) unique

    ScrollNode = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport_rect,
        UiCore.Size content_extent
    ) unique

    EditNode = (
        UiCore.TextModelRef model,
        UiCore.Rect rect,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    BehaviorNode = (
        HitNode? hit,
        FocusNode? focus,
        UiDemand.PointerBinding* pointer,
        ScrollNode? scroll,
        UiDemand.KeyBinding* keys,
        EditNode? edit,
        UiDemand.DragDropBinding* drag_drop
    ) unique

    -- ------------------------------------------------------------------------
    -- Solved accessibility facts
    -- ------------------------------------------------------------------------
    -- Hidden / non-participating accessibility is already consumed. A node now
    -- either has no accessibility output, or one explicit geometry-attached
    -- accessibility record.
    AccessibilityNode = (
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        UiCore.Rect rect,
        number sort_priority
    ) unique

    Node = (
        number index,
        number? parent_index,
        number? first_child_index,
        number child_count,
        number subtree_count,

        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role,

        SolvedState state,
        Geometry geometry,
        UiCore.ClipShape* local_clips,
        UiCore.ClipShape? active_clip,
        DrawAtom* draw,
        BehaviorNode behavior,
        AccessibilityNode? accessibility
    ) unique
}



module UiPlan {

    -- ------------------------------------------------------------------------
    -- Packed execution/query plan.
    --
    -- Meaning:
    --   UiSolved -> plan -> UiPlan
    --
    -- This phase consumes node-centered solved facts and projects them into
    -- sibling packed planes for the consumers that actually run/query the UI:
    --
    --   render plane:
    --     clips + draw batches
    --
    --   query plane:
    --     hits + focus chain + key routes + scroll hosts + edit hosts
    --     + accessibility items
    --
    -- Important:
    --   - no tree / node-centered structure remains here
    --   - no geometry solving happens here
    --   - planning may coalesce adjacent compatible draw atoms into batches,
    --     but must preserve semantic region/render order
    --   - still backend-independent and purely typed
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions,

        UiCore.ClipShape* clips,
        DrawBatch* draws,

        HitItem* hits,
        FocusItem* focus_chain,
        KeyRoute* key_routes,
        ScrollHost* scroll_hosts,
        EditHost* edit_hosts,
        AccessibilityItem* accessibility
    ) unique

    -- Region:
    --   Region-local spans into the scene-global execution/query planes.
    --
    -- The region still preserves top-level authored semantics useful to pure
    -- consumers (ordering, modality, pointer consumption), but the render/query
    -- payload itself lives in the global homogeneous arrays above.
    Region = (
        UiCore.ElementId id,
        string? debug_name,
        number z_index,
        boolean modal,
        boolean consumes_pointer,

        number draw_start,
        number draw_count,

        number hit_start,
        number hit_count,

        number focus_start,
        number focus_count,

        number key_start,
        number key_count,

        number scroll_start,
        number scroll_count,

        number edit_start,
        number edit_count,

        number accessibility_start,
        number accessibility_count
    ) unique

    -- ------------------------------------------------------------------------
    -- Render plane
    -- ------------------------------------------------------------------------
    -- Clip table:
    --   Deduplicated / indexed solved clip shapes used by DrawState.
    --   The clip array is scene-global; batches refer to clips by index.
    --
    -- Draw batching policy:
    --   Draw batches group adjacent compatible solved draw atoms. They do not
    --   reorder semantically distinct output across the scene.
    DrawState = (
        number? clip_index,
        UiCore.BlendMode blend,
        number opacity,
        UiCore.Transform2D? transform
    ) unique

    -- Shadow batching is explicit for the same reason as in UiSolved: it is a
    -- closed render family, not an open-ended custom escape hatch.
    DrawBatch = BoxBatch(
                    DrawState state,
                    BoxItem* items
                )
              | ShadowBatch(
                    DrawState state,
                    ShadowItem* items
                )
              | TextBatch(
                    DrawState state,
                    TextRun* runs
                )
              | ImageBatch(
                    DrawState state,
                    ImageItem* items
                )
              | CustomBatch(
                    DrawState state,
                    number family,
                    CustomItem* items
                )

    -- Lean render-only items.
    -- Source ids / semantic refs are dropped here because the render kernel
    -- does not need them; they remain available on the query plane.
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
        UiCore.ShadowKind shadow_kind,
        UiCore.Corners corners
    ) unique

    TextRun = (
        UiCore.TextValue text,
        UiCore.FontRef font,
        number size_px,
        UiCore.Color color,
        UiCore.Rect bounds,
        UiCore.TextWrap wrap,
        UiCore.TextAlign align
    ) unique

    ImageItem = (
        UiCore.ImageRef image,
        UiCore.Rect rect,
        UiCore.ImageSampling sampling,
        UiCore.Corners corners
    ) unique

    CustomItem = (
        number payload
    ) unique

    -- ------------------------------------------------------------------------
    -- Query plane
    -- ------------------------------------------------------------------------
    -- These arrays let pure routing / session logic operate on explicit solved
    -- payload instead of walking the authored tree again.
    ScrollBinding = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    HitItem = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.HitShape shape,
        number z_index,
        UiDemand.PointerBinding* pointer,
        ScrollBinding? scroll,
        UiDemand.DragDropBinding* drag_drop
    ) unique

    FocusItem = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Rect rect,
        UiCore.FocusMode mode,
        number? order
    ) unique

    KeyRoute = (
        UiCore.ElementId id,
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    ScrollHost = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport_rect,
        UiCore.Size content_extent
    ) unique

    EditHost = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.TextModelRef model,
        UiCore.Rect rect,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    AccessibilityItem = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        UiCore.Rect rect,
        number sort_priority
    ) unique
}



module UiKernel {

    -- ------------------------------------------------------------------------
    -- Render-kernel-specific machine phase.
    --
    -- Meaning:
    --   UiPlan -> specialize_kernel -> UiKernel
    --
    -- This phase is the last pure typed phase before Unit compilation. It
    -- makes the render-machine split explicit:
    --
    --   Spec:
    --     baked machine facts that actually affect emitted code / ABI
    --
    --   Payload:
    --     live render payload that will later be materialized into state_t
    --
    -- Important:
    --   - render-only: query planes from UiPlan are intentionally absent
    --   - lean: source/debug/query-only fields are dropped here
    --   - machine-oriented: payload mirrors the runtime state layout closely
    --   - still pure and typed: not yet Terra structs or backend-native buffers
    -- ------------------------------------------------------------------------

    Render = (
        Spec spec,
        Payload payload
    ) unique

    -- ------------------------------------------------------------------------
    -- Baked machine facts
    -- ------------------------------------------------------------------------
    -- Keep this intentionally minimal.
    -- Only facts that truly alter code shape / helper families / ABI belong
    -- here. Ordinary scene edits should mostly change Payload, not Spec.
    Spec = (
        CustomFamily* custom_families
    ) unique

    CustomFamily = (
        number family
    ) unique

    -- ------------------------------------------------------------------------
    -- Live render payload
    -- ------------------------------------------------------------------------
    -- This payload is already narrowed from UiPlan:
    --   - render-only
    --   - region headers are lean
    --   - batches use header + item span shape
    --   - item arrays are family-specific and render-only
    --
    -- The intent is that materializing state_t from Payload should be mostly a
    -- structural load, not another semantic transformation.
    Payload = (
        Region* regions,
        UiCore.ClipShape* clips,
        Batch* batches,
        BoxItem* boxes,
        ShadowItem* shadows,
        TextRun* text_runs,
        ImageItem* images,
        CustomItem* customs
    ) unique

    -- Region:
    --   Lean render-region header. By this phase the render kernel only needs
    --   draw spans; region modality / pointer-consumption semantics remain in
    --   UiPlan for pure/query consumers.
    Region = (
        number draw_start,
        number draw_count
    ) unique

    -- ------------------------------------------------------------------------
    -- Batch headers
    -- ------------------------------------------------------------------------
    -- UiPlan still grouped render output as variant batches with nested item
    -- lists. UiKernel narrows that one step further into a header stream plus
    -- family-specific payload arrays, which mirrors the stable runner's state
    -- layout more closely.
    -- Kernel batch families mirror the closed render families from UiPlan.
    BatchKind = BoxKind()
              | ShadowKind()
              | TextKind()
              | ImageKind()
              | CustomKind(number family)

    Batch = (
        BatchKind kind,
        UiPlan.DrawState state,
        number item_start,
        number item_count
    ) unique

    -- ------------------------------------------------------------------------
    -- Family-specific payload arrays
    -- ------------------------------------------------------------------------
    -- These are deliberately lean render-only payload records. They drop
    -- ElementId / SemanticRef because the render kernel does not need them.
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
        UiCore.ShadowKind shadow_kind,
        UiCore.Corners corners
    ) unique

    TextRun = (
        UiCore.TextValue text,
        UiCore.FontRef font,
        number size_px,
        UiCore.Color color,
        UiCore.Rect bounds,
        UiCore.TextWrap wrap,
        UiCore.TextAlign align
    ) unique

    ImageItem = (
        UiCore.ImageRef image,
        UiCore.Rect rect,
        UiCore.ImageSampling sampling,
        UiCore.Corners corners
    ) unique

    CustomItem = (
        number payload
    ) unique
}



]=]
