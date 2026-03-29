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
    -- reducer after consulting UiQuery's packed query plane. App/domain reducers
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
    --   UiSession.State + UiQuery.Scene + UiInput.Event
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
    -- Explicit flat topology + bound facet split.
    --
    -- Meaning:
    --   UiBound -> flatten -> UiFlat
    --
    -- This phase consumes ONLY recursive containment as implicit structure.
    -- It does NOT yet lower bound syntax into machine-facing facts.
    --
    -- It DOES:
    --   - canonicalize each bound entry into a region-local flat index space
    --   - preserve source identity
    --   - preserve bound meaning, but split it into orthogonal facet planes
    --   - make parent/child/subtree topology explicit once, not repeatedly
    --
    -- Leaf-first rule:
    --   lower phases should stop carrying one giant "whole node" record.
    --   The geometry, render, and query leaves consume different knowledge, so
    --   UiFlat is the point where we make those fact families explicit.
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

        NodeHeader* headers,
        LayoutFacet* layout,
        ContentFacet* content,
        VisualFacet* visual,
        QueryFacet* query,
        AccessibilityFacet* accessibility
    ) unique

    NodeHeader = (
        number index,
        number? parent_index,
        number? first_child_index,
        number child_count,
        number subtree_count,

        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role
    ) unique

    LayoutFacet = (
        UiBound.Flags flags,
        UiBound.Layout layout
    ) unique

    ContentFacet = (
        UiBound.Content content
    ) unique

    VisualFacet = (
        UiBound.Paint paint
    ) unique

    QueryFacet = (
        UiBound.Behavior behavior
    ) unique

    AccessibilityFacet = (
        UiBound.Accessibility accessibility
    ) unique
}



module UiLowered {

    -- ------------------------------------------------------------------------
    -- Lowered orthogonal fact planes.
    --
    -- Meaning:
    --   UiFlat -> lower -> UiLowered
    --
    -- This is the replacement for the old giant solver-input node. It keeps
    -- flat topology, but lowers each concern only into the form its consumer
    -- actually wants:
    --   - layout facts for geometry solving
    --   - render facts for later render projection
    --   - query facts for later query projection
    --   - accessibility facts for later accessibility projection
    --
    -- Important:
    --   - still backend-independent
    --   - still not solved geometry
    --   - anchor targets are region-local indices here
    --   - render/query data is normalized, but not yet projected into planes
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

        NodeHeader* headers,
        LayoutNode* layout,
        RenderNode* render,
        QueryNode* query,
        AccessibilityNode* accessibility
    ) unique

    NodeHeader = (
        number index,
        number? parent_index,
        number? first_child_index,
        number child_count,
        number subtree_count,

        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        string? debug_name,
        UiCore.Role role
    ) unique

    Participation = (
        boolean visible,
        boolean enabled
    ) unique

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

    LayoutSpec = (
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

    Intrinsic = NoIntrinsic()
              | TextIntrinsic(
                    UiCore.TextValue value,
                    UiCore.FontRef font,
                    number size_px,
                    UiCore.FontWeight weight,
                    UiCore.FontSlant slant,
                    number letter_spacing_px,
                    number line_height_px,
                    UiCore.TextWrap wrap,
                    UiCore.TextOverflow overflow,
                    number line_limit,
                    number min_content_w,
                    number max_content_w
                )
              | ImageIntrinsic(
                    UiCore.ImageRef image,
                    UiCore.ImageStyle style,
                    UiCore.Size intrinsic
                )
              | CustomIntrinsic(
                    number family,
                    number payload
                )

    LayoutNode = (
        Participation state,
        LayoutSpec layout,
        Intrinsic intrinsic
    ) unique

    RenderEffect = LocalClip(UiCore.Corners corners)
                 | LocalOpacity(number value)
                 | LocalTransform(UiCore.Transform2D xform)
                 | LocalBlend(UiCore.BlendMode mode)

    Decoration = BoxDecor(
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

    RenderContent = NoRenderContent()
                  | TextContent(
                        UiCore.TextValue text,
                        UiCore.FontRef font,
                        number size_px,
                        UiCore.Color color,
                        UiCore.TextWrap wrap,
                        UiCore.TextAlign align
                    )
                  | ImageContent(
                        UiCore.ImageRef image,
                        UiCore.ImageStyle style
                    )
                  | CustomContent(
                        number family,
                        number payload
                    )

    RenderNode = (
        RenderEffect* effects,
        Decoration* decorations,
        RenderContent content
    ) unique

    HitSpec = NoHit()
            | SelfHit()
            | SelfAndChildrenHit()
            | ChildrenOnlyHit()

    FocusSpec = Focusable(
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

    ScrollSpec = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    KeyBinding = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    EditSpec = (
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

    QueryNode = (
        HitSpec hit,
        FocusSpec? focus,
        PointerBinding* pointer,
        ScrollSpec? scroll,
        KeyBinding* keys,
        EditSpec? edit,
        DragDropBinding* drag_drop
    ) unique

    AccessibilityNode = NoAccessibility()
                      | AccessibilitySpec(
                            UiCore.AccessibleRole role,
                            string? label,
                            string? description,
                            number sort_priority
                        )
}



module UiGeometry {

    -- ------------------------------------------------------------------------
    -- Solved geometry scene.
    --
    -- Meaning:
    --   UiLowered -> solve_geometry -> UiGeometry
    --
    -- This phase consumes only the layout coupling point:
    --   - topology
    --   - participation
    --   - layout specs
    --   - intrinsic size descriptors
    --
    -- It produces only solved geometry plus the orthogonal lowered fact planes
    -- that still need that geometry for later projection.
    --
    -- Important:
    --   - not node-centered "everything solved"
    --   - no draw atoms
    --   - no query tables
    --   - no clip stack projection yet
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

        UiLowered.NodeHeader* headers,
        GeometryNode* geometry,
        UiLowered.RenderNode* render,
        UiLowered.QueryNode* query,
        UiLowered.AccessibilityNode* accessibility
    ) unique

    GeometryNode = (
        UiLowered.Participation state,
        UiCore.Rect border_box,
        UiCore.Rect padding_box,
        UiCore.Rect content_box,
        UiCore.Size child_extent,
        UiCore.ScrollExtent? scroll_extent
    ) unique
}



module UiRender {

    -- ------------------------------------------------------------------------
    -- Packed render projection.
    --
    -- Meaning:
    --   UiGeometry -> project_render -> UiRender
    --
    -- This phase consumes solved geometry plus render facts and projects them
    -- into the homogeneous render planes the render machine actually wants.
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions,
        UiCore.ClipShape* clips,
        DrawBatch* draws
    ) unique

    Region = (
        number draw_start,
        number draw_count
    ) unique

    DrawState = (
        number? clip_index,
        UiCore.BlendMode blend,
        number opacity,
        UiCore.Transform2D? transform
    ) unique

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
                    TextItem* items
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

    TextItem = (
        number cache_key,
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



module UiQuery {

    -- ------------------------------------------------------------------------
    -- Packed query/reducer projection.
    --
    -- Meaning:
    --   UiGeometry -> project_query -> UiQuery
    --
    -- This phase consumes solved geometry plus query/accessibility facts and
    -- projects them into the homogeneous query planes the reducer/router wants.
    -- ------------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions,

        HitItem* hits,
        FocusItem* focus_chain,
        KeyRoute* key_routes,
        ScrollHost* scroll_hosts,
        EditHost* edit_hosts,
        AccessibilityItem* accessibility
    ) unique

    Region = (
        UiCore.ElementId id,
        string? debug_name,
        number z_index,
        boolean modal,
        boolean consumes_pointer,

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

    ScrollBinding = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    HitItem = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.HitShape shape,
        number z_index,
        UiLowered.PointerBinding* pointer,
        ScrollBinding? scroll,
        UiLowered.DragDropBinding* drag_drop
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
    -- Render-kernel-specific Machine IR.
    --
    -- Meaning:
    --   UiRender -> specialize_kernel -> UiKernel
    --
    -- This phase is not yet the canonical machine itself. Instead it is the
    -- render-specific Machine IR that feeds the machine layer immediately above
    -- Unit realization.
    --
    -- It makes two crucial machine inputs explicit:
    --
    --   Spec:
    --     code-shaping facts that feed machine `gen`
    --
    --   Payload:
    --     stable live machine input that feeds machine `param`
    --
    -- Important:
    --   - render-only: query planes from UiQuery are intentionally absent
    --   - lean: source/debug/query-only fields are dropped here
    --   - machine-oriented: payload mirrors the runtime state layout closely
    --   - still pure and typed: not yet `gen, param, state`
    --   - not yet Terra structs or backend-native buffers
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
    -- This payload is already narrowed from UiRender:
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
        TextItem* text_items,
        ImageItem* images,
        CustomItem* customs
    ) unique

    -- Region:
    --   Lean render-region header. By this phase the render kernel only needs
    --   draw spans; region modality / pointer-consumption semantics remain in
    --   UiQuery for pure/query consumers.
    Region = (
        number draw_start,
        number draw_count
    ) unique

    -- ------------------------------------------------------------------------
    -- Batch headers
    -- ------------------------------------------------------------------------
    -- UiRender still groups render output as variant batches with nested item
    -- lists. UiKernel narrows that one step further into a header stream plus
    -- family-specific payload arrays, which mirrors the stable runner's state
    -- layout more closely.
    -- Kernel batch families mirror the closed render families from UiRender.
    BatchKind = BoxKind()
              | ShadowKind()
              | TextKind()
              | ImageKind()
              | CustomKind(number family)

    Batch = (
        BatchKind kind,
        UiRender.DrawState state,
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

    TextItem = (
        number cache_key,
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



module UiMachine {

    -- ------------------------------------------------------------------------
    -- Canonical machine layer immediately above Unit realization.
    --
    -- Meaning:
    --   UiKernel -> define_machine -> UiMachine
    --
    -- This module makes explicit the abstract machine that backend realization
    -- will later package as `Unit { fn, state_t }`.
    --
    -- The key split is:
    --
    --   gen:
    --     the execution rule that will become `fn`
    --
    --   param:
    --     the stable machine environment that the rule reads
    --
    --   state:
    --     the mutable machine-state requirements that backend realization will
    --     own inside `state_t`
    --
    -- Design note:
    --   `state` here is not live mutable runtime state. It is a pure typed
    --   statement of what mutable runtime state the realized Unit must own.
    --
    -- In ui2 specifically:
    --   - UiKernel.Spec already isolates code-shaping facts, so it naturally
    --     feeds `gen`
    --   - UiKernel.Payload already isolates the packed stable render scene, so
    --     it naturally feeds `param`
    --   - StateModel makes explicit the runtime-owned slot requirements that
    --     the backend will realize inside `state_t`
    -- ------------------------------------------------------------------------

    Render = (
        Gen gen,
        Param param,
        StateModel state
    ) unique

    Gen = (
        UiKernel.Spec spec
    ) unique

    Param = (
        UiKernel.Payload payload
    ) unique

    -- ------------------------------------------------------------------------
    -- StateModel
    -- ------------------------------------------------------------------------
    -- This is intentionally structural and backend-neutral.
    --
    -- It does not describe Terra structs, LuaJIT cdata, GL handles, or SDL
    -- textures directly. Instead it states the mutable state ownership the
    -- realized machine will need at runtime.
    --
    -- The current ui2 render machine owns mutable slots corresponding to the
    -- packed payload families it materializes and updates across runs.
    StateModel = (
        number batch_count,
        number box_count,
        number shadow_count,
        number text_item_count,
        number image_count,
        number custom_count
    ) unique
}



]=]
