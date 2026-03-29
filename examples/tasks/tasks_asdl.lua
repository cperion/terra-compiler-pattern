return [=[
-- ============================================================================
-- Task Workspace Example — First Real-Life App ASDL
-- ----------------------------------------------------------------------------
-- This is the first concrete app layer ABOVE the canonical UI system.
--
-- Users work with task-workspace nouns:
--   workspace, project, task, tag, selection, filter, editor draft
--
-- Phase path:
--
--     TaskDoc + TaskSession + TaskEvent
--         ↓ apply
--       TaskApp.State
--         ↓ project_view
--       TaskView.Screen
--         ↓ decode (UiIntent -> TaskEvent)
--       TaskDecode.Result
--         ↓ lower (+ TaskCommand -> UiCore.CommandRef)
--       UiDecl.Document
--
-- Routed UI intents decode through TaskCommand and text-model refs before
-- becoming TaskEvent.Event for the app reducer.
--
-- Design goals:
--   - model a real app domain, not raw UI widgets
--   - keep authored task data separate from session/editor state
--   - keep the event language explicit and reducer-friendly
--   - make the app-specific view projection explicit before UiDecl lowering
--   - give later leaves concrete list/detail/dialog shapes to compile
-- ============================================================================


module TaskCore {

    -- ------------------------------------------------------------------------
    -- Stable identities
    -- ------------------------------------------------------------------------
    ProjectRef = (number value) unique
    TaskRef    = (number value) unique
    TagRef     = (number value) unique

    -- ------------------------------------------------------------------------
    -- Domain choices
    -- ------------------------------------------------------------------------
    TaskStatus = Todo()
               | InProgress()
               | Blocked()
               | Done()

    TaskPriority = NoPriority()
                 | Low()
                 | Medium()
                 | High()

    SortMode = ManualOrder()
             | PriorityOrder()
             | TitleOrder()
}



module TaskDoc {

    -- ------------------------------------------------------------------------
    -- Persisted authored task workspace.
    -- This is the user-visible saved document.
    -- ------------------------------------------------------------------------

    Workspace = (
        number version,
        string name,
        Project* projects,
        Tag* tags
    ) unique

    Project = (
        TaskCore.ProjectRef id,
        string name,
        boolean archived,
        Task* tasks
    ) unique

    Task = (
        TaskCore.TaskRef id,
        string title,
        string notes,
        TaskCore.TaskStatus status,
        TaskCore.TaskPriority priority,
        TaskCore.TagRef* tags
    ) unique

    Tag = (
        TaskCore.TagRef id,
        string name,
        UiCore.Color color
    ) unique
}



module TaskCommand {

    -- ------------------------------------------------------------------------
    -- App-specific UI command language.
    --
    -- TaskView lowering compiles these semantic commands into UiCore.CommandRef
    -- values on UiDecl behavior nodes. Routed UI intents decode back into this
    -- closed command set before becoming TaskEvent.Event.
    -- ------------------------------------------------------------------------

    Command = ClearSelection()
            | SelectProject(
                  TaskCore.ProjectRef project
              )
            | SelectTask(
                  TaskCore.TaskRef task
              )
            | ToggleStatusFilter(
                  TaskCore.TaskStatus status
              )
            | ToggleTagFilter(
                  TaskCore.TagRef tag
              )
            | SetIncludeDone(
                  boolean value
              )
            | SetSort(
                  TaskCore.SortMode sort
              )
            | BeginCreateTask(
                  TaskCore.ProjectRef project
              )
            | BeginEditTask(
                  TaskCore.TaskRef task
              )
            | RequestDeleteTask(
                  TaskCore.TaskRef task
              )
            | ConfirmDelete()
            | CancelOverlay()
            | SubmitEditor()
            | SetDraftStatus(
                  TaskCore.TaskStatus status
              )
            | SetDraftPriority(
                  TaskCore.TaskPriority priority
              )
            | ToggleDraftTag(
                  TaskCore.TagRef tag
              )
            | SetTaskStatus(
                  TaskCore.TaskRef task,
                  TaskCore.TaskStatus status
              )
            | SetTaskPriority(
                  TaskCore.TaskRef task,
                  TaskCore.TaskPriority priority
              )
}



module TaskSession {

    -- ------------------------------------------------------------------------
    -- Session/editor state.
    -- This is user-visible interaction state, but not authored document data.
    -- ------------------------------------------------------------------------

    Selection = NoSelection()
              | ProjectSelected(
                    TaskCore.ProjectRef project
                )
              | TaskSelected(
                    TaskCore.ProjectRef project,
                    TaskCore.TaskRef task
                )

    Filter = (
        string query,
        TaskCore.TaskStatus* statuses,
        TaskCore.TagRef* tags,
        boolean include_done
    ) unique

    Draft = (
        string title,
        string notes,
        TaskCore.TaskStatus status,
        TaskCore.TaskPriority priority,
        TaskCore.TagRef* tags
    ) unique

    Editor = NoEditor()
           | CreatingTask(
                 TaskCore.ProjectRef project,
                 Draft draft
             )
           | EditingTask(
                 TaskCore.TaskRef task,
                 Draft draft
             )
           | ConfirmingDelete(
                 TaskCore.TaskRef task
             )

    State = (
        Selection selection,
        Filter filter,
        TaskCore.SortMode sort,
        Editor editor
    ) unique
}



module TaskEvent {

    -- ------------------------------------------------------------------------
    -- App event language.
    -- These are semantic app events after mapping system input and routed
    -- TaskCommand/UI edit intents into reducer-level operations.
    -- ------------------------------------------------------------------------

    Event = Quit()
          | ClearSelection()
          | SelectProject(
                TaskCore.ProjectRef project
            )
          | SelectTask(
                TaskCore.TaskRef task
            )
          | SetQuery(
                string value
            )
          | ToggleStatusFilter(
                TaskCore.TaskStatus status
            )
          | ToggleTagFilter(
                TaskCore.TagRef tag
            )
          | SetIncludeDone(
                boolean value
            )
          | SetSort(
                TaskCore.SortMode sort
            )
          | BeginCreateTask(
                TaskCore.ProjectRef project
            )
          | BeginEditTask(
                TaskCore.TaskRef task
            )
          | UpdateDraftTitle(
                string value
            )
          | UpdateDraftNotes(
                string value
            )
          | UpdateDraftStatus(
                TaskCore.TaskStatus status
            )
          | UpdateDraftPriority(
                TaskCore.TaskPriority priority
            )
          | ToggleDraftTag(
                TaskCore.TagRef tag
            )
          | SubmitEditor()
          | CancelOverlay()
          | RequestDeleteTask(
                TaskCore.TaskRef task
            )
          | ConfirmDelete()
          | SetTaskStatus(
                TaskCore.TaskRef task,
                TaskCore.TaskStatus status
            )
          | SetTaskPriority(
                TaskCore.TaskRef task,
                TaskCore.TaskPriority priority
            )
}



module TaskDecode {

    -- ------------------------------------------------------------------------
    -- Decoded app-event batch from UiIntent.
    --
    -- TaskView.Screen consumes app-specific UiIntent semantics:
    --   command refs, text-model refs, and current visible field values
    -- and produces reducer-level TaskEvent.Event*.
    -- ------------------------------------------------------------------------

    Result = (
        TaskEvent.Event* events
    ) unique
}



module TaskApp {

    -- ------------------------------------------------------------------------
    -- Root reducer state for the task application.
    -- ------------------------------------------------------------------------

    State = (
        TaskDoc.Workspace workspace,
        TaskSession.State session,
        boolean running
    ) unique
}



module TaskView {

    -- ------------------------------------------------------------------------
    -- App-specific view projection above UiDecl.
    -- This is the visible task-app screen model, not the authored document.
    -- ------------------------------------------------------------------------

    Screen = (
        Sidebar sidebar,
        Content content,
        Overlay* overlays
    ) unique

    Sidebar = (
        WorkspaceHeader workspace,
        ProjectItem* projects,
        FilterPanel filter
    ) unique

    WorkspaceHeader = (
        string name
    ) unique

    ProjectItem = (
        TaskCore.ProjectRef id,
        string name,
        number open_count,
        number done_count,
        boolean selected
    ) unique

    FilterPanel = (
        UiCore.TextModelRef query_model,
        string query,
        StatusFilter* statuses,
        TagFilter* tags,
        boolean include_done,
        TaskCore.SortMode sort
    ) unique

    StatusFilter = (
        TaskCore.TaskStatus status,
        number count,
        boolean enabled
    ) unique

    TagFilter = (
        TaskCore.TagRef id,
        string name,
        UiCore.Color color,
        number count,
        boolean enabled
    ) unique

    Content = NothingSelected(
                  string title,
                  string message
              )
            | ProjectScreen(
                  ProjectHeader project,
                  UiCore.ScrollRef task_list_scroll,
                  UiCore.ScrollRef detail_scroll,
                  TaskRow* tasks,
                  DetailPane detail
              )

    ProjectHeader = (
        TaskCore.ProjectRef id,
        string name,
        number visible_count,
        number total_count
    ) unique

    TaskRow = (
        TaskCore.TaskRef id,
        string title,
        string notes_preview,
        TaskCore.TaskStatus status,
        TaskCore.TaskPriority priority,
        TagChip* tags,
        boolean selected
    ) unique

    TagChip = (
        number key,
        TaskCore.TagRef id,
        string name,
        UiCore.Color color
    ) unique

    DetailPane = NoDetail()
               | TaskDetail(
                     TaskCard task
                 )

    TaskCard = (
        TaskCore.TaskRef id,
        string title,
        string notes,
        TaskCore.TaskStatus status,
        TaskCore.TaskPriority priority,
        TagChip* tags
    ) unique

    Overlay = TaskEditorOverlay(
                  TaskEditor editor
              )
            | DeleteTaskOverlay(
                  DeleteDialog dialog
              )

    TaskEditorForm = (
        UiCore.TextModelRef title_model,
        UiCore.TextModelRef notes_model,
        string title,
        string notes,
        StatusChoice* statuses,
        PriorityChoice* priorities,
        TagChoice* tags
    ) unique

    TaskEditor = CreateTaskEditor(
                     TaskCore.ProjectRef project,
                     TaskEditorForm form
                 )
               | EditTaskEditor(
                     TaskCore.TaskRef task,
                     TaskEditorForm form
                 )

    StatusChoice = (
        TaskCore.TaskStatus status,
        boolean selected
    ) unique

    PriorityChoice = (
        TaskCore.TaskPriority priority,
        boolean selected
    ) unique

    TagChoice = (
        TaskCore.TagRef id,
        string name,
        UiCore.Color color,
        boolean selected
    ) unique

    DeleteDialog = (
        TaskCore.TaskRef task,
        string heading,
        string message
    ) unique
}

]=]
