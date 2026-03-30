return [=[
-- ============================================================================
-- ui3 ASDL scaffold
-- ----------------------------------------------------------------------------
-- Purpose:
--   new example line for the red-teamed lower architecture discovered during
--   the ui2 redesign work.
--
-- This file intentionally combines:
--   - the stable top/source-side UI language from ui2
--   - the new lower architecture from the redesign sketch
--
-- Status:
--   schema/scaffold only
--   no live implementations are installed yet
--   custom-family portions remain intentionally provisional
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
    --   UiSession.State + UiQueryMachineIR.Scene + UiInput.Event
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
    -- Layout facet
    -- ------------------------------------------------------------------------
    -- Layout is still semantic layout intent, but bind consumes one real fact
    -- here: anchored positions are validated against the current entry subtree.
    -- ------------------------------------------------------------------------
    Position = InFlow()
             | Absolute(
                   UiCore.EdgeMeasure left,
                   UiCore.EdgeMeasure top,
                   UiCore.EdgeMeasure right,
                   UiCore.EdgeMeasure bottom
               )
             | AnchoredTo(
                   UiCore.ElementId target,
                   UiCore.AnchorX self_x,
                   UiCore.AnchorY self_y,
                   UiCore.AnchorX target_x,
                   UiCore.AnchorY target_y,
                   number dx,
                   number dy
               )

    Layout = (
        UiDecl.Layout source,
        Position position
    ) unique

    -- ------------------------------------------------------------------------
    -- Content facet
    -- ------------------------------------------------------------------------
    -- Content is normalized into bound semantic forms only where bind consumes
    -- real knowledge. Text keeps a dedicated bound record because authored text
    -- style is normalized and font selection is resolved here.
    -- ------------------------------------------------------------------------
    BoundTextStyle = (
        UiCore.FontRef font,
        number size_px,
        UiCore.FontWeight weight,
        UiCore.FontSlant slant,
        number letter_spacing_px,
        number line_height_px,
        UiCore.Color color
    ) unique

    BoundText = (
        UiCore.TextValue value,
        BoundTextStyle style,
        UiCore.TextLayout layout
    ) unique

    Content = NoContent()
            | Text(BoundText text)
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
        UiDecl.Flags flags,
        Layout layout,
        UiDecl.Paint paint,
        Content content,
        UiDecl.Behavior behavior,
        Accessibility accessibility,
        Node* children
    ) unique
}


module UiFlatShape {
    -- --------------------------------------------------------------------
    -- Canonical shared flat header vocabulary.
    --
    -- Design rule:
    --   after `UiFlat`, all branch-side and solved phases should align by the
    --   same region-local node index space. These shared header records make
    --   that alignment explicit instead of leaving it as a convention.
    --
    -- Intended consumers:
    --   - UiGeometryInput
    --   - UiGeometry
    --   - UiRenderFacts
    --   - UiQueryFacts
    -- --------------------------------------------------------------------

    RegionHeader = (
        UiCore.ElementId id,
        string? debug_name,
        number root_index
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
}


module UiFlat {
    -- --------------------------------------------------------------------
    -- Shared aligned facet-plane layer.
    --
    -- Meaning:
    --   UiBound -> flatten -> UiFlat
    --
    -- Design rule:
    --   This is the first explicit shared structural spine after tree-shaped
    --   authored/bound structure.
    --
    -- It should contain:
    --   - canonical shared region/node headers
    --   - region semantics needed later by render/query branches
    --   - aligned facet planes that preserve bound/source-side meaning
    --
    -- It should NOT contain:
    --   - solved geometry
    --   - branch-specific lowered facts
    --   - machine-ir payload
    --   - runtime state schema
    --
    -- Alignment rule:
    --   every per-node facet plane in a region is aligned one-to-one with the
    --   shared `headers` array for that region.
    -- --------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    RenderRegionFacet = (
        number z_index
    ) unique

    QueryRegionFacet = (
        boolean modal,
        boolean consumes_pointer
    ) unique

    Region = (
        UiFlatShape.RegionHeader header,
        RenderRegionFacet render_region,
        QueryRegionFacet query_region,
        UiFlatShape.NodeHeader* headers,
        VisibilityFacet* visibility,
        InteractivityFacet* interactivity,
        LayoutFacet* layout,
        ContentFacet* content,
        PaintFacet* paint,
        BehaviorFacet* behavior,
        AccessibilityFacet* accessibility
    ) unique

    -- --------------------------------------------------------------------
    -- Facet planes.
    -- --------------------------------------------------------------------
    -- These are intentionally close to bound/source semantics. The lower_* phases
    -- should still do real work when producing geometry/query/render-specific
    -- lowered languages.
    -- Visibility is kept as source truth rather than being prematurely folded
    -- into geometry or render semantics.
    VisibilityFacet = (
        boolean visible
    ) unique

    -- Enabled/interactivity source truth should not be bundled together with
    -- visibility just because an earlier phase grouped them as `Flags`.
    InteractivityFacet = (
        boolean enabled
    ) unique

    LayoutFacet = (
        UiBound.Layout layout
    ) unique

    ContentFacet = (
        UiBound.Content content
    ) unique

    -- --------------------------------------------------------------------
    -- Content is one real facet, and flatten should preserve the already-bound
    -- semantic truth rather than restating it in a near-isomorphic UiFlat-
    -- local vocabulary.
    PaintFacet = (
        UiDecl.Paint paint
    ) unique

    -- --------------------------------------------------------------------
    -- Paint is one real facet. Flatten preserves ordered local paint intent;
    -- `lower_render_facts` remains the boundary that classifies it into
    -- render-specific effects, decorations, and custom render facts.
    BehaviorFacet = (
        UiDecl.Behavior behavior
    ) unique

    -- --------------------------------------------------------------------
    -- Behavior is one real facet. Flatten preserves the already-bound
    -- interaction truth; `lower_query_facts` remains the boundary that lowers
    -- it into direct query facts and access paths.
    AccessibilityFacet = (
        UiBound.Accessibility accessibility
    ) unique

    -- Accessibility remains a separate facet from behavior because it is a
    -- distinct semantic concern even if the same later query branch consumes
    -- both.
}


module UiGeometryInput {
    -- --------------------------------------------------------------------
    -- Shared geometry-solver input language.
    --
    -- Meaning:
    --   UiFlat -> lower_geometry -> UiGeometryInput
    --
    -- Design rule:
    --   This phase must contain only what the geometry solver actually needs.
    --   It is not the general lowered truth for render/query/accessibility.
    --
    -- Consumption rule:
    --   `lower_geometry` should consume only:
    --   - shared headers/topology
    --   - visibility source
    --   - layout source
    --   - content source
    --
    -- It should not consume:
    --   - interactivity source
    --   - paint source
    --   - behavior source
    --   - accessibility source
    --   - render/query region facets
    --
    -- So this module should contain:
    --   - explicit flat topology
    --   - identity/header information needed to reattach solved geometry later
    --   - geometry-relevant participation truth
    --   - layout specs
    --   - intrinsic size descriptors
    --
    -- And it should NOT contain:
    --   - draw instances
    --   - query instances
    --   - resource/custom identity unless the solver truly branches on it
    --   - machine state schema
    --   - packed render/query routing payload
    -- --------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    Region = (
        UiFlatShape.RegionHeader header,
        UiFlatShape.NodeHeader* headers,
        Participation* participation,
        AxisSpec* width_specs,
        AxisSpec* height_specs,
        PositionOp* positions,
        FlowOp* flows,
        UiCore.Insets* paddings,
        UiCore.Insets* margins,
        ScrollModel* scroll_models,
        IntrinsicMetrics* intrinsics
    ) unique

    -- --------------------------------------------------------------------
    -- Geometry participation truth.
    -- --------------------------------------------------------------------
    -- Keep only the truth the solver actually cares about.
    -- This is intentionally narrower than UI-wide participation semantics.
    Participation = (
        boolean included_in_layout
    ) unique

    -- --------------------------------------------------------------------
    -- Compiled axis measurement program.
    -- --------------------------------------------------------------------
    -- mode codes:
    --   0 = auto
    --   1 = px
    --   2 = percent
    --   3 = content
    --   4 = flex
    AxisSpec = (
        number min_mode,
        number min_value,
        number preferred_mode,
        number preferred_value,
        number max_mode,
        number max_value
    ) unique

    -- --------------------------------------------------------------------
    -- Compiled position program.
    -- --------------------------------------------------------------------
    -- kind codes:
    --   0 = inflow
    --   1 = absolute
    --   2 = anchored
    --
    -- edge mode codes:
    --   0 = unset
    --   1 = px
    --   2 = percent
    --
    -- anchor codes:
    --   0 = start/left/top
    --   1 = center
    --   2 = end/right/bottom
    PositionOp = (
        number kind,
        number target_index,
        number left_mode,
        number left_value,
        number top_mode,
        number top_value,
        number right_mode,
        number right_value,
        number bottom_mode,
        number bottom_value,
        number self_x,
        number self_y,
        number target_x,
        number target_y,
        number dx,
        number dy
    ) unique

    -- --------------------------------------------------------------------
    -- Compiled flow program.
    -- --------------------------------------------------------------------
    -- kind codes:
    --   0 = none
    --   1 = row
    --   2 = column
    --   3 = stack
    FlowOp = (
        number kind,
        number gap
    ) unique

    ScrollModel = (
        boolean needs_scroll_x,
        boolean needs_scroll_y
    ) unique

    -- --------------------------------------------------------------------
    -- Geometry-facing measurable summaries.
    -- --------------------------------------------------------------------
    -- These are compiled measurable facts, not rich content grammar.
    IntrinsicMetrics = (
        number min_content_w,
        number min_content_h,
        number ideal_content_w,
        number ideal_content_h
    ) unique
}


module UiGeometry {
    -- --------------------------------------------------------------------
    -- Shared solved geometry coupling point.
    --
    -- Meaning:
    --   UiGeometryInput -> solve -> UiGeometry
    --
    -- Design rule:
    --   This module should contain the solved geometry truth shared by later
    --   render/query machine-ir projection.
    --
    -- It should contain:
    --   - solved boxes/rects
    --   - solved extents
    --   - stable headers/topology needed to reattach identity later
    --   - explicit solved placement presence/absence
    --
    -- It should NOT contain:
    --   - draw atoms
    --   - render instances
    --   - query instances
    --   - resource specs
    --   - render/query packed machine payloads
    --   - runtime state schema
    --
    -- Open design tension:
    --   later render/query projection will still need non-geometry facts from
    --   higher layers. This sketch keeps UiGeometry strictly geometry-shaped for
    --   now and treats those later projection inputs as a question still to be
    --   resolved in subsequent sketch iterations.
    -- --------------------------------------------------------------------

    Scene = (
        UiCore.Size viewport,
        Region* regions
    ) unique

    Region = (
        UiFlatShape.RegionHeader header,
        UiFlatShape.NodeHeader* headers,
        GeometryNode* nodes
    ) unique

    -- --------------------------------------------------------------------
    -- Solved geometry record.
    -- --------------------------------------------------------------------
    -- Keep this geometry-only.
    --
    -- Important design rule:
    --   do not mix "excluded from layout" with always-present solved rectangles in
    --   one record. Presence of solved placement is itself a sum-type distinction.
    PlacedNode = (
        UiCore.Rect border_box,
        UiCore.Rect padding_box,
        UiCore.Rect content_box,
        UiCore.Size content_extent,
        UiCore.ScrollExtent? scroll_extent
    ) unique

    GeometryNode = Excluded()
                 | Placed(PlacedNode node)
}


module UiRenderFacts {
    -- --------------------------------------------------------------------
    -- Render-specific lowered facts carried alongside solved geometry.
    --
    -- Meaning:
    --   UiFlat -> lower_render_facts -> UiRenderFacts
    --
    -- Design rule:
    --   This module contains render-relevant facts that geometry does not solve
    --   but later render machine-ir projection still needs.
    --
    -- It should contain things like:
    --   - visual effect facts
    --   - decoration facts
    --   - content facts relevant to render resource specs / use-sites
    --
    -- It should NOT contain:
    --   - solved geometry
    --   - runtime resource state
    --   - final machine-ir order/instance/resource tables
    -- --------------------------------------------------------------------

    Scene = (
        Region* regions
    ) unique

    -- Alignment invariant:
    --   `node_facts[i]` describes the same region-local flat node as the shared
    --   node/header index `i` in UiFlat / UiGeometryInput / UiGeometry.
    Region = (
        UiFlatShape.RegionHeader header,
        number z_index,
        Fact* node_facts
    ) unique

    Use = DefaultUse()
        | ImageUse(UiCore.Corners corners)

    Fact = (
        Effect* effects,
        Decoration* decorations,
        Content content,
        Use use
    ) unique

    Effect = LocalClip(UiCore.Corners corners)
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

    -- --------------------------------------------------------------------
    -- Resource identity should be lowerable from these content facts, but not
    -- fused here with solved geometry or runtime state.
    -- --------------------------------------------------------------------
    -- Final text resource identity likely depends on solved geometry
    -- (especially width/wrap), so do not freeze the final resource key here.
    -- But keep the full render-relevant text identity facts here so later
    -- projection does not need to rediscover them from earlier phases.
    TextContent = (
        UiCore.TextValue text,
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

    -- Image identity lives here; image occurrence shape (e.g. rounded corners)
    -- should stay in `Use`/later instances rather than be fused into identity.
    ImageContent = (
        UiCore.ImageRef image,
        UiCore.ImageFit fit,
        UiCore.ImageSampling sampling
    ) unique

    CustomContent = InlineCustomContent(
                        number family,
                        number payload
                    )
                  | ResourceCustomContent(
                        number family,
                        number resource_payload,
                        number instance_payload
                    )

    Content = NoContent()
            | Text(TextContent text)
            | Image(ImageContent image)
            | Custom(CustomContent custom)
}


module UiRenderScene {
    -- --------------------------------------------------------------------
    -- Concrete render occurrence scene.
    --
    -- Meaning:
    --   UiGeometry + UiRenderFacts -> project_render_scene -> UiRenderScene
    --
    -- Design rule:
    --   This phase resolves node-aligned render facts against solved geometry
    --   into concrete ordered render occurrences.
    --
    -- It should contain:
    --   - region-level occurrence spans/order
    --   - occurrence-level resolved draw state
    --   - concrete draw occurrences with solved geometry attached
    --
    -- It should NOT contain:
    --   - resource refs
    --   - clip refs
    --   - batch headers
    --   - deduped resource tables
    --   - runtime state schema
    -- --------------------------------------------------------------------

    Scene = (
        Region* regions,
        Occurrence* occurrences
    ) unique

    Region = (
        UiFlatShape.RegionHeader header,
        number z_index,
        number occurrence_start,
        number occurrence_count
    ) unique

    OccurrenceState = (
        UiCore.ClipShape* clips,
        UiCore.BlendMode blend,
        number opacity,
        UiCore.Transform2D? transform
    ) unique

    Occurrence = Box(BoxOccurrence box)
               | Shadow(ShadowOccurrence shadow)
               | Text(TextOccurrence text)
               | Image(ImageOccurrence image)
               | Custom(CustomOccurrence custom)

    BoxOccurrence = (
        OccurrenceState state,
        UiCore.Rect rect,
        UiCore.Brush fill,
        UiCore.Brush? stroke,
        number stroke_width,
        UiCore.StrokeAlign align,
        UiCore.Corners corners
    ) unique

    ShadowOccurrence = (
        OccurrenceState state,
        UiCore.Rect rect,
        UiCore.Brush brush,
        number blur,
        number spread,
        number dx,
        number dy,
        UiCore.ShadowKind shadow_kind,
        UiCore.Corners corners
    ) unique

    TextOccurrence = (
        OccurrenceState state,
        UiRenderFacts.TextContent text,
        UiCore.Rect bounds
    ) unique

    ImageOccurrence = (
        OccurrenceState state,
        UiRenderFacts.ImageContent image,
        UiCore.Rect rect,
        UiCore.Corners corners
    ) unique

    CustomOccurrence = InlineCustom(
                           OccurrenceState state,
                           number family,
                           number payload
                       )
                     | ResourceCustom(
                           OccurrenceState state,
                           number family,
                           number resource_payload,
                           number instance_payload
                       )
}


module UiRenderMachineIR {
    -- --------------------------------------------------------------------
    -- Render machine-feeding IR.
    --
    -- Meaning:
    --   UiRenderScene -> schedule_render_machine_ir -> UiRenderMachineIR
    --
    -- Canonical role:
    --   This is the typed machine-feeding layer for the render machine.
    --   It should make the following explicit:
    --
    --   - order
    --   - addressability
    --   - use-sites
    --   - resource identity
    --   - runtime ownership requirements
    --
    -- It exists so the canonical machine below it becomes trivial:
    --
    --   Shape       -> `gen`
    --   Input       -> `param`
    --   StateSchema -> `state`
    --
    -- Current design rule:
    --   this phase should schedule/pack an already-concrete render occurrence
    --   scene into machine-feeding tables.
    --   It should not still be responsible for discovering render occurrences
    --   from node-aligned facts.
    -- --------------------------------------------------------------------

    Render = (
        Shape shape,
        Input input,
        StateSchema state_schema
    ) unique

    -- --------------------------------------------------------------------
    -- Machine shape.
    -- --------------------------------------------------------------------
    -- Keep this intentionally small. It should only include facts that change
    -- execution shape, helper shape, or runtime state-family shape.
    Shape = (
        CustomFamily* custom_families
    ) unique

    CustomFamily = (
        number family
    ) unique

    -- --------------------------------------------------------------------
    -- Stable machine input.
    -- --------------------------------------------------------------------
    -- Input should be stable machine-feeding payload, not runtime-owned state.
    Input = (
        RegionSpan* regions,
        ClipPath* clips,
        BatchHeader* batches,

        TextResourceSpec* text_resources,
        ImageResourceSpec* image_resources,
        CustomResourceSpec* custom_resources,

        BoxInstance* boxes,
        ShadowInstance* shadows,
        TextDrawInstance* texts,
        ImageDrawInstance* images,
        CustomInstance* customs
    ) unique

    -- --------------------------------------------------------------------
    -- Order shapes.
    -- --------------------------------------------------------------------
    RegionSpan = (
        number batch_start,
        number batch_count
    ) unique

    BatchKind = BoxKind()
              | ShadowKind()
              | TextKind()
              | ImageKind()
              | CustomKind(number family)

    BatchHeader = (
        BatchKind kind,
        DrawState state,
        number item_start,
        number item_count
    ) unique

    -- --------------------------------------------------------------------
    -- Addressability / refs.
    -- --------------------------------------------------------------------

    ClipRef = (
        number index
    ) unique

    TextResourceRef = (
        number slot
    ) unique

    ImageResourceRef = (
        number slot
    ) unique

    CustomResourceRef = (
        number slot
    ) unique

    -- --------------------------------------------------------------------
    -- Shared input tables.
    -- --------------------------------------------------------------------
    DrawState = (
        ClipRef? clip,
        UiCore.BlendMode blend,
        number opacity,
        UiCore.Transform2D? transform
    ) unique

    ClipPath = (
        UiCore.ClipShape* shapes
    ) unique

    -- --------------------------------------------------------------------
    -- Resource identity.
    -- --------------------------------------------------------------------
    TextResourceSpec = (
        number key,
        UiCore.TextValue text,
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
        number width_px
    ) unique

    ImageResourceSpec = (
        number key,
        UiCore.ImageRef image,
        UiCore.ImageSampling sampling
    ) unique

    CustomResourceSpec = (
        number family,
        number payload
    ) unique

    -- --------------------------------------------------------------------
    -- Use-sites / instances.
    -- --------------------------------------------------------------------
    BoxInstance = (
        UiCore.Rect rect,
        UiCore.Brush fill,
        UiCore.Brush? stroke,
        number stroke_width,
        UiCore.StrokeAlign align,
        UiCore.Corners corners
    ) unique

    ShadowInstance = (
        UiCore.Rect rect,
        UiCore.Brush brush,
        number blur,
        number spread,
        number dx,
        number dy,
        UiCore.ShadowKind shadow_kind,
        UiCore.Corners corners
    ) unique

    TextDrawInstance = (
        TextResourceRef resource,
        UiCore.Rect bounds
    ) unique

    ImageDrawInstance = (
        ImageResourceRef resource,
        UiCore.Rect rect,
        UiCore.ImageFit fit,
        UiCore.Corners corners
    ) unique

    CustomInstance = InlineCustom(
                         number family,
                         number payload
                     )
                   | ResourceCustom(
                         number family,
                         CustomResourceRef resource,
                         number payload
                     )

    -- --------------------------------------------------------------------
    -- Runtime ownership requirements.
    -- --------------------------------------------------------------------
    -- This is a pure schema describing runtime-owned state families the
    -- eventual machine must realize. It is not live runtime state itself.
    StateSchema = (
        ResourceStateFamily* resources,
        CustomStateFamily* custom,
        InstallationStateFamily install
    ) unique

    ResourceStateFamily = TextResources()
                        | ImageResources()

    CustomStateFamily = (
        number family
    ) unique

    InstallationStateFamily = CapacityTracking()
}


module UiQueryFacts {
    -- --------------------------------------------------------------------
    -- Query-specific lowered facts carried alongside solved geometry.
    --
    -- Meaning:
    --   UiFlat -> lower_query_facts -> UiQueryFacts
    --
    -- Design rule:
    --   This module contains query/accessibility facts that geometry does not
    --   solve but later query machine-ir projection still needs.
    -- --------------------------------------------------------------------

    Scene = (
        Region* regions
    ) unique

    -- Alignment invariant:
    --   `node_facts[i]` describes the same region-local flat node as the shared
    --   node/header index `i` in UiFlat / UiGeometryInput / UiGeometry.
    Region = (
        UiFlatShape.RegionHeader header,
        number z_index,
        boolean modal,
        boolean consumes_pointer,
        Fact* node_facts
    ) unique

    Hit = NoHit()
        | SelfHit()
        | SelfAndChildrenHit()
        | ChildrenOnlyHit()

    Focus = Focusable(
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

    Scroll = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    Key = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    Edit = (
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

    Accessibility = NoAccessibility()
                  | Exposed(
                        UiCore.AccessibleRole role,
                        string? label,
                        string? description,
                        number sort_priority
                    )

    Fact = (
        Hit hit,
        Focus? focus,
        PointerBinding* pointer,
        Scroll? scroll,
        Key* keys,
        Edit? edit,
        DragDropBinding* drag_drop,
        Accessibility accessibility
    ) unique
}


module UiQueryScene {
    -- --------------------------------------------------------------------
    -- Concrete query occurrence scene.
    --
    -- Meaning:
    --   UiGeometry + UiQueryFacts -> project_query_scene -> UiQueryScene
    --
    -- Design rule:
    --   This phase resolves node-aligned query facts against solved geometry
    --   into concrete query occurrences.
    --
    -- It should contain:
    --   - region policy and raw per-kind spans
    --   - concrete hit/focus/key/edit/scroll/accessibility occurrences
    --
    -- It should NOT contain:
    --   - key buckets
    --   - focus-order access streams
    --   - other packed access structures better described as organization/indexing
    -- --------------------------------------------------------------------

    Scene = (
        Region* regions,
        HitOccurrence* hits,
        FocusOccurrence* focus,
        KeyOccurrence* keys,
        ScrollHostOccurrence* scroll_hosts,
        EditHostOccurrence* edit_hosts,
        AccessibilityOccurrence* accessibility
    ) unique

    Region = (
        UiFlatShape.RegionHeader header,
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

    HitOccurrence = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.HitShape shape,
        number z_index,
        PointerBinding* pointer,
        ScrollBinding? scroll,
        DragDropBinding* drag_drop
    ) unique

    FocusOccurrence = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Rect rect,
        UiCore.FocusMode mode,
        number? order
    ) unique

    KeyOccurrence = (
        UiCore.ElementId id,
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        UiCore.CommandRef command,
        boolean global
    ) unique

    ScrollHostOccurrence = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport_rect,
        UiCore.Size content_extent
    ) unique

    EditHostOccurrence = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.TextModelRef model,
        UiCore.Rect rect,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    AccessibilityOccurrence = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        UiCore.Rect rect,
        number sort_priority
    ) unique

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

    DragDropBinding = DraggableBinding(
                          UiCore.DragPayload payload,
                          UiCore.CommandRef? begin,
                          UiCore.CommandRef? finish
                      )
                    | DropTargetBinding(
                          UiCore.DropPolicy policy,
                          UiCore.CommandRef command
                      )
}


module UiQueryMachineIR {
    -- --------------------------------------------------------------------
    -- Query/reducer-facing machine IR.
    --
    -- Meaning:
    --   UiQueryScene -> organize_query_machine_ir -> UiQueryMachineIR
    --
    -- Canonical role:
    --   This is the typed machine-feeding layer for query/routing/reducer work.
    --   It should make explicit:
    --
    --   - routing order
    --   - region-level query policy
    --   - direct query instances
    --   - any tiny state/schema facts query execution genuinely needs
    --
    -- Important asymmetry with render:
    --   built-in query likely wants little or no resource-spec/resource-state
    --   story. That asymmetry should stay visible in the types.
    --
    -- Current design rule:
    --   this phase should organize/index an already-concrete query scene into
    --   packed query tables and access paths.
    --   It should not still be responsible for discovering query occurrences
    --   from node-aligned facts.
    -- --------------------------------------------------------------------

    Scene = (
        Input input
    ) unique

    -- --------------------------------------------------------------------
    -- Stable machine input.
    -- --------------------------------------------------------------------
    Input = (
        RegionHeader* regions,
        HitInstance* hits,
        FocusInstance* focus,
        FocusOrderEntry* focus_order,
        KeyRouteBucket* key_buckets,
        KeyRouteInstance* key_routes,
        ScrollHostInstance* scroll_hosts,
        EditHostInstance* edit_hosts,
        AccessibilityInstance* accessibility
    ) unique

    -- --------------------------------------------------------------------
    -- Region routing header.
    -- --------------------------------------------------------------------
    -- Query execution likely wants one stable region-level routing stream rather
    -- than rediscovering modality/pointer-consumption/tree order dynamically.
    RegionHeader = (
        UiCore.ElementId id,
        string? debug_name,
        number z_index,
        boolean modal,
        boolean consumes_pointer,

        number hit_start,
        number hit_count,

        number focus_start,
        number focus_count,

        number focus_order_start,
        number focus_order_count,

        number key_bucket_start,
        number key_bucket_count,

        number scroll_start,
        number scroll_count,

        number edit_start,
        number edit_count,

        number accessibility_start,
        number accessibility_count
    ) unique

    -- --------------------------------------------------------------------
    -- Direct query instances.
    -- --------------------------------------------------------------------
    -- These are already the query use-sites the reducer/router should read.
    ScrollBinding = (
        UiCore.Axis axis,
        UiCore.ScrollRef? model
    ) unique

    HitInstance = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.HitShape shape,
        number z_index,
        PointerBinding* pointer,
        ScrollBinding? scroll,
        DragDropBinding* drag_drop
    ) unique

    FocusInstance = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Rect rect,
        UiCore.FocusMode mode,
        number? order
    ) unique

    FocusOrderEntry = (
        number focus_index
    ) unique

    KeyRouteScope = GlobalScope()
                  | FocusScope()

    KeyRouteBucket = (
        UiCore.KeyChord chord,
        UiCore.KeyEvent when,
        KeyRouteScope scope,
        number route_start,
        number route_count
    ) unique

    KeyRouteInstance = (
        UiCore.ElementId id,
        UiCore.CommandRef command
    ) unique

    ScrollHostInstance = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.Axis axis,
        UiCore.ScrollRef? model,
        UiCore.Rect viewport_rect,
        UiCore.Size content_extent
    ) unique

    EditHostInstance = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.TextModelRef model,
        UiCore.Rect rect,
        boolean multiline,
        boolean read_only,
        UiCore.CommandRef? changed
    ) unique

    AccessibilityInstance = (
        UiCore.ElementId id,
        UiCore.SemanticRef? semantic_ref,
        UiCore.AccessibleRole role,
        string? label,
        string? description,
        UiCore.Rect rect,
        number sort_priority
    ) unique

    -- --------------------------------------------------------------------
    -- Lowered binding vocabulary carried into query instances.
    -- --------------------------------------------------------------------
    -- Keep these explicit and direct; avoid a generic routing DSL.
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

    DragDropBinding = DraggableBinding(
                          UiCore.DragPayload payload,
                          UiCore.CommandRef? begin,
                          UiCore.CommandRef? finish
                      )
                    | DropTargetBinding(
                          UiCore.DropPolicy policy,
                          UiCore.CommandRef command
                      )

    -- --------------------------------------------------------------------
    -- Built-in query currently has no explicit runtime-owned machine state
    -- family in this sketch. If later routing/indexing proves persistent query
    -- machine state is required, add it only then.
}


module UiMachine {
    -- --------------------------------------------------------------------
    -- Canonical machine layer.
    --
    -- Meaning:
    --   Machine IR -> define_machine -> UiMachine
    --
    -- Canonical rule:
    --   This is the layer immediately above `Unit`.
    --   It is not optional explanatory sugar.
    --   It is the actual machine model terminals should define before backend
    --   realization packages it as `Unit { fn, state_t }`.
    --
    -- Roles:
    --   Gen   = execution rule / code-shaping machine role
    --   Param = stable machine input role
    --   State = runtime-owned mutable state role
    -- --------------------------------------------------------------------

    -- --------------------------------------------------------------------
    -- Render machine.
    -- --------------------------------------------------------------------
    -- The current redesign pressure says render has the strongest and clearest
    -- machine split, so we sketch it first.
    Render = (
        RenderGen gen,
        RenderParam param,
        RenderState state
    ) unique

    RenderGen = (
        UiRenderMachineIR.Shape shape
    ) unique

    -- --------------------------------------------------------------------
    -- Important Layer-1 audit result:
    -- --------------------------------------------------------------------
    -- RenderParam should not merely wrap UiRenderMachineIR.Input directly.
    -- The machine layer should instead carry a more install-ready packed
    -- payload plus explicit runtime realization requests, so materialize()
    -- mostly installs state and realizes assets instead of re-lowering broad
    -- machine IR on every call.
    RenderParam = (
        PackedInput payload
    ) unique

    PackedInput = (
        UiRenderMachineIR.RegionSpan* regions,
        BatchParam* batches,
        BoxParam* boxes,
        ShadowParam* shadows,
        TextRequest* text_requests,
        TextDraw* texts,
        ImageRequest* image_requests,
        ImageDraw* images
    ) unique

    BatchParam = (
        UiRenderMachineIR.BatchKind kind,
        number item_start,
        number item_count,
        UiCore.Rect? clip_rect,
        number opacity,
        UiCore.BlendMode blend,
        UiCore.Transform2D? transform
    ) unique

    BoxParam = (
        UiCore.Rect rect,
        UiCore.Color fill,
        UiCore.Color? stroke,
        number stroke_width,
        UiCore.StrokeAlign align,
        UiCore.Corners corners
    ) unique

    ShadowParam = (
        UiCore.Rect rect,
        UiCore.Color color,
        number blur,
        number spread,
        number dx,
        number dy,
        UiCore.ShadowKind shadow_kind,
        UiCore.Corners corners
    ) unique

    TextRequest = (
        number key,
        UiCore.TextValue text,
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
        number width_px
    ) unique

    TextDraw = (
        number request_index,
        UiCore.Rect bounds
    ) unique

    ImageRequest = (
        number key,
        UiCore.ImageRef image,
        UiCore.ImageSampling sampling
    ) unique

    ImageDraw = (
        number request_index,
        UiCore.Rect rect,
        UiCore.ImageFit fit,
        UiCore.Corners corners
    ) unique

    TextResidency = (
        number request_index,
        number key
    ) unique

    ImageResidency = (
        number request_index,
        number key
    ) unique

    -- --------------------------------------------------------------------
    -- Important naming note:
    -- --------------------------------------------------------------------
    -- This type is named `RenderState` at the canonical machine layer even
    -- though the layer above may still call its pure description a
    -- `StateSchema`. The point here is to keep the machine role explicit:
    -- this is what will become the runtime-owned state role below `Unit`.
    --
    -- Layer-1 residency refinement:
    --   text/image realization should be modeled as explicit machine-owned
    --   residency slots, not left implicit inside backend-global caches.
    RenderState = (
        UiRenderMachineIR.StateSchema schema,
        TextResidency* text_residency,
        ImageResidency* image_residency
    ) unique

    -- --------------------------------------------------------------------
    -- Query machine.
    -- --------------------------------------------------------------------
    -- Current redesign judgment: query may not need a distinct UiMachine layer
    -- in code if the reducer can consume UiQueryMachineIR directly. So we do
    -- not freeze a query machine record here yet.
}

]=]
