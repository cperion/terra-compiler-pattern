#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>
#include <math.h>

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>

#ifndef BENCH_CLAY_HEADER
#  if defined(__has_include)
#    if __has_include("clay.h")
#      define BENCH_CLAY_HEADER "clay.h"
#    elif __has_include("../../third_party/clay/clay.h")
#      define BENCH_CLAY_HEADER "../../third_party/clay/clay.h"
#    elif __has_include("/home/cedric/dev/terraui/third_party/clay/clay.h")
#      define BENCH_CLAY_HEADER "/home/cedric/dev/terraui/third_party/clay/clay.h"
#    elif __has_include("/home/cedric/dev/cdaw/terraui/third_party/clay/clay.h")
#      define BENCH_CLAY_HEADER "/home/cedric/dev/cdaw/terraui/third_party/clay/clay.h"
#    endif
#  endif
#endif

#ifndef BENCH_CLAY_HEADER
#  error "Could not find clay.h. Pass -DBENCH_CLAY_HEADER=\"/absolute/path/to/clay.h\" when compiling."
#endif

#define CLAY_IMPLEMENTATION
#include BENCH_CLAY_HEADER

typedef struct {
    uint64_t *values;
    int count;
    int capacity;
} Samples;

typedef struct {
    char *title;
    char *notes;
    char *preview;
    char *meta;
    int project_index;
    int status_index;
    int priority_index;
    int tags[3];
    int tag_count;
} BenchTask;

typedef struct {
    int task_count;
    int project_count;
    int tag_count;
    int selected_project;
    int selected_task;
    bool modal_open;
    char *workspace_name;
    char **project_names;
    char **tag_names;
    BenchTask *tasks;
    char *draft_title;
    char *draft_notes;
    int modal_offset_y;
} BenchScene;

typedef struct {
    int total;
    int rectangles;
    int borders;
    int text;
    int images;
    int scissors;
    int custom;
} CommandCounts;

typedef struct {
    const char *font_path;
    int viewport_w;
    int viewport_h;
    int warmup;
    int iters;
    int tasks;
    int projects;
    int tags;
    const char *scenario;
} BenchConfig;

typedef struct {
    const char *path;
    int size;
    TTF_Font *font;
} FontCacheEntry;

static FontCacheEntry g_font_cache[32];
static int g_font_cache_count = 0;
static const char *g_font_path = NULL;
static Clay_Context *g_clay = NULL;
static Clay_Arena g_arena = {0};
static void *g_arena_memory = NULL;

static Clay_Color BG = { 15, 20, 28, 255 };
static Clay_Color SURFACE = { 26, 31, 40, 255 };
static Clay_Color SURFACE_ALT = { 31, 37, 48, 255 };
static Clay_Color SURFACE_HI = { 42, 50, 64, 255 };
static Clay_Color BORDER = { 60, 71, 89, 255 };
static Clay_Color TEXT = { 244, 249, 255, 255 };
static Clay_Color MUTED = { 173, 188, 209, 255 };
static Clay_Color ACCENT = { 97, 153, 250, 255 };
static Clay_Color ACCENT_SOFT = { 43, 67, 110, 255 };
static Clay_Color DANGER = { 217, 79, 92, 255 };
static Clay_Color SCRIM = { 5, 8, 13, 186 };
static Clay_Color TAG_COLORS[6] = {
    { 117, 171, 242, 255 },
    { 148, 212, 138, 255 },
    { 242, 161, 87, 255 },
    { 214, 138, 242, 255 },
    { 242, 204, 89, 255 },
    { 89, 214, 212, 255 },
};

static const char *STATUS_LABELS[4] = { "Todo", "In Progress", "Blocked", "Done" };
static const char *PRIORITY_LABELS[4] = { "No Priority", "Low", "Medium", "High" };

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static double ms(uint64_t ns) {
    return (double)ns / 1000000.0;
}

static void samples_push(Samples *s, uint64_t value) {
    if (s->count == s->capacity) {
        int new_capacity = s->capacity == 0 ? 16 : s->capacity * 2;
        s->values = (uint64_t *)realloc(s->values, (size_t)new_capacity * sizeof(uint64_t));
        s->capacity = new_capacity;
    }
    s->values[s->count++] = value;
}

static int cmp_u64(const void *a, const void *b) {
    uint64_t av = *(const uint64_t *)a;
    uint64_t bv = *(const uint64_t *)b;
    return (av > bv) - (av < bv);
}

static uint64_t samples_mean(const Samples *s) {
    if (s->count == 0) return 0;
    long double total = 0;
    for (int i = 0; i < s->count; ++i) total += (long double)s->values[i];
    return (uint64_t)(total / (long double)s->count);
}

static uint64_t samples_percentile(const Samples *s, double p) {
    if (s->count == 0) return 0;
    uint64_t *copy = (uint64_t *)malloc((size_t)s->count * sizeof(uint64_t));
    memcpy(copy, s->values, (size_t)s->count * sizeof(uint64_t));
    qsort(copy, (size_t)s->count, sizeof(uint64_t), cmp_u64);
    int idx = (int)floor(((double)(s->count - 1) * p) + 0.5);
    if (idx < 0) idx = 0;
    if (idx >= s->count) idx = s->count - 1;
    uint64_t out = copy[idx];
    free(copy);
    return out;
}

static void print_stats(const char *label, const Samples *s) {
    printf("%s mean=%.3fms p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms\n",
        label,
        ms(samples_mean(s)),
        ms(samples_percentile(s, 0.50)),
        ms(samples_percentile(s, 0.95)),
        ms(samples_percentile(s, 0.99)),
        ms(samples_percentile(s, 1.00))
    );
}

static void samples_free(Samples *s) {
    free(s->values);
    s->values = NULL;
    s->count = 0;
    s->capacity = 0;
}

static int getenv_int(const char *name, int fallback) {
    const char *raw = getenv(name);
    if (!raw || !raw[0]) return fallback;
    int value = atoi(raw);
    return value > 0 ? value : fallback;
}

static const char *getenv_str(const char *name, const char *fallback) {
    const char *raw = getenv(name);
    return (raw && raw[0]) ? raw : fallback;
}

static char *stringf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    va_list copy;
    va_copy(copy, args);
    int len = vsnprintf(NULL, 0, fmt, copy);
    va_end(copy);
    char *out = (char *)malloc((size_t)len + 1);
    vsnprintf(out, (size_t)len + 1, fmt, args);
    va_end(args);
    return out;
}

static Clay_String clay_string(const char *text) {
    Clay_String s;
    s.isStaticallyAllocated = false;
    s.length = (int32_t)strlen(text);
    s.chars = text;
    return s;
}

static TTF_Font *font_for_size(int size) {
    for (int i = 0; i < g_font_cache_count; ++i) {
        if (g_font_cache[i].size == size && strcmp(g_font_cache[i].path, g_font_path) == 0) {
            return g_font_cache[i].font;
        }
    }
    if (g_font_cache_count >= (int)(sizeof(g_font_cache) / sizeof(g_font_cache[0]))) {
        fprintf(stderr, "font cache exhausted\n");
        exit(1);
    }
    TTF_Font *font = TTF_OpenFont(g_font_path, (float)size);
    if (!font) {
        fprintf(stderr, "TTF_OpenFont(%s, %d) failed: %s\n", g_font_path, size, SDL_GetError());
        exit(1);
    }
    g_font_cache[g_font_cache_count++] = (FontCacheEntry) { g_font_path, size, font };
    return font;
}

static Clay_Dimensions measure_text(Clay_StringSlice text, Clay_TextElementConfig *config, void *userData) {
    (void)userData;
    int font_size = config && config->fontSize ? config->fontSize : 16;
    TTF_Font *font = font_for_size(font_size);
    int w = 0, h = 0;
    if (!TTF_GetStringSize(font, text.chars, (size_t)text.length, &w, &h)) {
        fprintf(stderr, "TTF_GetStringSize failed: %s\n", SDL_GetError());
        exit(1);
    }
    if (config && config->lineHeight > 0 && h < config->lineHeight) {
        h = config->lineHeight;
    }
    return (Clay_Dimensions) { (float)w, (float)h };
}

static void clay_error(Clay_ErrorData errorData) {
    fprintf(stderr, "clay error: %.*s\n", errorData.errorText.length, errorData.errorText.chars);
    exit(1);
}

static void ensure_clay_context(int max_elements, int max_words, int view_w, int view_h) {
    if (g_arena_memory) {
        free(g_arena_memory);
        g_arena_memory = NULL;
    }
    if (max_elements < 8192) max_elements = 8192;
    if (max_words < 16384) max_words = 16384;

    Clay_SetMaxElementCount(max_elements);
    Clay_SetMaxMeasureTextCacheWordCount(max_words);
    uint32_t min_memory = Clay_MinMemorySize();
    g_arena_memory = malloc(min_memory);
    if (!g_arena_memory) {
        fprintf(stderr, "failed to allocate clay arena\n");
        exit(1);
    }
    g_arena = Clay_CreateArenaWithCapacityAndMemory(min_memory, g_arena_memory);
    g_clay = Clay_Initialize(g_arena, (Clay_Dimensions) { (float)view_w, (float)view_h }, (Clay_ErrorHandler) { clay_error, NULL });
    Clay_SetCurrentContext(g_clay);
    Clay_SetMeasureTextFunction(measure_text, NULL);
}

static Clay_TextElementConfig *text_cfg(uint16_t size, Clay_Color color, Clay_TextElementConfigWrapMode wrap) {
    return CLAY_TEXT_CONFIG({ .fontSize = size, .textColor = color, .wrapMode = wrap });
}

static void build_button(const char *label, Clay_Color fill, Clay_Color text_color) {
    CLAY_AUTO_ID({
        .layout = { .padding = { 12, 12, 10, 10 } },
        .backgroundColor = fill,
        .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
    }) {
        CLAY_TEXT(clay_string(label), text_cfg(14, text_color, CLAY_TEXT_WRAP_NONE));
    }
}

static void build_chip(const char *label, Clay_Color fill) {
    CLAY_AUTO_ID({
        .layout = { .padding = { 10, 10, 6, 6 } },
        .backgroundColor = fill
    }) {
        CLAY_TEXT(clay_string(label), text_cfg(12, (Clay_Color){ 14, 18, 25, 255 }, CLAY_TEXT_WRAP_NONE));
    }
}

static void build_input(const char *value) {
    CLAY_AUTO_ID({
        .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) }, .padding = { 12, 12, 12, 12 } },
        .backgroundColor = SURFACE_HI,
        .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
    }) {
        CLAY_TEXT(clay_string(value), text_cfg(14, TEXT, CLAY_TEXT_WRAP_WORDS));
    }
}

static const char *status_label(int index) {
    return STATUS_LABELS[index % 4];
}

static const char *priority_label(int index) {
    return PRIORITY_LABELS[index % 4];
}

static int task_in_selected_project(const BenchScene *scene, const BenchTask *task) {
    return task->project_index == scene->selected_project;
}

static int project_task_count(const BenchScene *scene, int project_index) {
    int total = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index == project_index) total += 1;
    }
    return total;
}

static int project_open_count(const BenchScene *scene, int project_index) {
    int total = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index == project_index && scene->tasks[i].status_index != 3) total += 1;
    }
    return total;
}

static int project_done_count(const BenchScene *scene, int project_index) {
    int total = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index == project_index && scene->tasks[i].status_index == 3) total += 1;
    }
    return total;
}

static int project_status_count(const BenchScene *scene, int project_index, int status_index) {
    int total = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index == project_index && scene->tasks[i].status_index == status_index) total += 1;
    }
    return total;
}

static int project_tag_count(const BenchScene *scene, int project_index, int tag_index) {
    int total = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index != project_index) continue;
        for (int t = 0; t < scene->tasks[i].tag_count; ++t) {
            if (scene->tasks[i].tags[t] == tag_index) {
                total += 1;
                break;
            }
        }
    }
    return total;
}

static int nth_task_index_in_project(const BenchScene *scene, int project_index, int n) {
    int seen = 0;
    for (int i = 0; i < scene->task_count; ++i) {
        if (scene->tasks[i].project_index != project_index) continue;
        if (seen == n) return i;
        seen += 1;
    }
    return 0;
}

static void build_choice_button(const char *label, bool active) {
    build_button(label, active ? ACCENT_SOFT : SURFACE_HI, TEXT);
}

static void build_sidebar(const BenchScene *scene) {
    CLAY(CLAY_ID("Sidebar"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_FIXED(320), .height = CLAY_SIZING_GROW(0) },
            .padding = { 20, 20, 20, 20 },
            .childGap = 18
        },
        .backgroundColor = SURFACE,
        .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
    }) {
        CLAY(CLAY_ID("WorkspaceHeader"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .childGap = 8 } }) {
            CLAY_TEXT(clay_string(scene->workspace_name), text_cfg(26, TEXT, CLAY_TEXT_WRAP_NONE));
            CLAY(CLAY_ID("WorkspaceCopy"), { .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) } } }) {
                CLAY_TEXT(clay_string("A focused workspace for planning, editing, and shipping work."), text_cfg(13, MUTED, CLAY_TEXT_WRAP_WORDS));
            }
        }

        CLAY(CLAY_ID("ProjectsSection"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .childGap = 10 } }) {
            CLAY_TEXT(CLAY_STRING("Projects"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < scene->project_count; ++i) {
                char *meta = stringf("%d open · %d done", project_open_count(scene, i), project_done_count(scene, i));
                CLAY(CLAY_IDI("ProjectItem", i), {
                    .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .padding = { 14, 14, 14, 14 }, .childGap = 4 },
                    .backgroundColor = i == scene->selected_project ? ACCENT_SOFT : SURFACE_ALT,
                    .border = { .color = i == scene->selected_project ? ACCENT : BORDER, .width = CLAY_BORDER_ALL(1) }
                }) {
                    CLAY_TEXT(clay_string(scene->project_names[i]), text_cfg(15, TEXT, CLAY_TEXT_WRAP_NONE));
                    CLAY_TEXT(clay_string(meta), text_cfg(12, MUTED, CLAY_TEXT_WRAP_WORDS));
                }
                free(meta);
            }
        }

        CLAY(CLAY_ID("FilterPanel"), {
            .layout = {
                .layoutDirection = CLAY_TOP_TO_BOTTOM,
                .sizing = { .width = CLAY_SIZING_GROW(0) },
                .padding = { 16, 16, 16, 16 },
                .childGap = 12
            },
            .backgroundColor = SURFACE_ALT,
            .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
        }) {
            CLAY_TEXT(CLAY_STRING("Refine"), text_cfg(17, TEXT, CLAY_TEXT_WRAP_NONE));
            CLAY(CLAY_ID("FilterCopy"), { .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) } } }) {
                CLAY_TEXT(CLAY_STRING("Use search, status, and tags to narrow the worklist."), text_cfg(12, MUTED, CLAY_TEXT_WRAP_WORDS));
            }
            build_input("Search tasks");
            CLAY_TEXT(CLAY_STRING("Status"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < 4; ++i) {
                char *label = stringf("%s · %d", status_label(i), project_status_count(scene, scene->selected_project, i));
                build_choice_button(label, false);
                free(label);
            }
            CLAY_TEXT(CLAY_STRING("Tags"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < scene->tag_count; ++i) {
                char *label = stringf("%s · %d", scene->tag_names[i], project_tag_count(scene, scene->selected_project, i));
                build_choice_button(label, false);
                free(label);
            }
            build_choice_button("Showing completed", true);
            build_choice_button("Sort: Manual", false);
        }
    }
}

static void build_task_row(const BenchTask *task, int index, bool selected) {
    CLAY(CLAY_IDI("TaskRow", index), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0) },
            .padding = { 16, 16, 16, 16 },
            .childGap = 10
        },
        .backgroundColor = selected ? ACCENT_SOFT : SURFACE_ALT,
        .border = { .color = selected ? ACCENT : BORDER, .width = CLAY_BORDER_ALL(1) }
    }) {
        CLAY_TEXT(clay_string(task->title), text_cfg(16, TEXT, CLAY_TEXT_WRAP_NONE));
        CLAY(CLAY_IDI("TaskNotesPreviewWrap", index), { .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) } } }) {
            CLAY_TEXT(clay_string(task->preview), text_cfg(13, MUTED, CLAY_TEXT_WRAP_WORDS));
        }
        CLAY(CLAY_IDI("TaskTags", index), { .layout = { .childGap = 8 } }) {
            for (int i = 0; i < task->tag_count; ++i) build_chip(task->meta + (i * 32), TAG_COLORS[task->tags[i] % 6]);
        }
    }
}

static void build_detail(const BenchScene *scene) {
    const BenchTask *task = &scene->tasks[scene->selected_task];
    CLAY(CLAY_ID("DetailScroll"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .padding = { 18, 18, 18, 18 },
            .childGap = 16
        },
        .backgroundColor = SURFACE,
        .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) },
        .clip = { .vertical = true, .horizontal = false, .childOffset = { 0, 0 } }
    }) {
        CLAY(CLAY_ID("TaskCard"), {
            .layout = {
                .layoutDirection = CLAY_TOP_TO_BOTTOM,
                .sizing = { .width = CLAY_SIZING_GROW(0) },
                .padding = { 16, 16, 16, 16 },
                .childGap = 12
            },
            .backgroundColor = SURFACE,
            .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
        }) {
            CLAY_TEXT(clay_string(task->title), text_cfg(24, TEXT, CLAY_TEXT_WRAP_WORDS));
            CLAY(CLAY_ID("TaskCardNotesWrap"), { .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) } } }) {
                CLAY_TEXT(clay_string(task->notes), text_cfg(14, MUTED, CLAY_TEXT_WRAP_WORDS));
            }
            CLAY(CLAY_ID("TaskCardTags"), { .layout = { .childGap = 8 } }) {
                for (int i = 0; i < task->tag_count; ++i) build_chip(scene->tag_names[task->tags[i]], TAG_COLORS[task->tags[i] % 6]);
            }
            {
                char *status_text = stringf("Status · %s", status_label(task->status_index));
                char *priority_text = stringf("Priority · %s", priority_label(task->priority_index));
                build_button(status_text, SURFACE_HI, TEXT);
                build_button(priority_text, SURFACE_HI, TEXT);
                free(status_text);
                free(priority_text);
            }
            CLAY(CLAY_ID("TaskActions"), { .layout = { .childGap = 10 } }) {
                build_button("Edit task", ACCENT, TEXT);
                build_button("Delete", DANGER, TEXT);
            }
        }
    }
}

static void build_project_content(const BenchScene *scene) {
    CLAY(CLAY_ID("MainContent"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .childGap = 20
        }
    }) {
        CLAY(CLAY_ID("ProjectHeader"), {
            .layout = {
                .layoutDirection = CLAY_TOP_TO_BOTTOM,
                .sizing = { .width = CLAY_SIZING_GROW(0) },
                .padding = { 16, 16, 16, 16 },
                .childGap = 10
            },
            .backgroundColor = SURFACE,
            .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) }
        }) {
            char *summary = stringf("%d visible · %d total", project_task_count(scene, scene->selected_project), project_task_count(scene, scene->selected_project));
            CLAY_TEXT(clay_string(scene->project_names[scene->selected_project]), text_cfg(28, TEXT, CLAY_TEXT_WRAP_NONE));
            CLAY_TEXT(clay_string(summary), text_cfg(13, MUTED, CLAY_TEXT_WRAP_WORDS));
            build_button("New Task", ACCENT, TEXT);
            free(summary);
        }

        CLAY(CLAY_ID("Columns"), {
            .layout = {
                .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
                .childGap = 20
            }
        }) {
            CLAY(CLAY_ID("TaskList"), {
                .layout = {
                    .layoutDirection = CLAY_TOP_TO_BOTTOM,
                    .sizing = { .width = CLAY_SIZING_FIXED(420), .height = CLAY_SIZING_GROW(0) },
                    .padding = { 18, 18, 18, 18 },
                    .childGap = 14
                },
                .backgroundColor = SURFACE,
                .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) },
                .clip = { .vertical = true, .horizontal = false, .childOffset = { 0, 0 } }
            }) {
                for (int i = 0; i < scene->task_count; ++i) {
                    if (!task_in_selected_project(scene, &scene->tasks[i])) continue;
                    build_task_row(&scene->tasks[i], i, i == scene->selected_task);
                }
            }
            build_detail(scene);
        }
    }
}

static void build_modal(const BenchScene *scene, int view_w, int view_h) {
    CLAY(CLAY_ID("ModalScrim"), {
        .layout = {
            .sizing = { .width = CLAY_SIZING_FIXED((float)view_w), .height = CLAY_SIZING_FIXED((float)view_h) }
        },
        .backgroundColor = SCRIM,
        .floating = {
            .attachTo = CLAY_ATTACH_TO_ROOT,
            .attachPoints = { CLAY_ATTACH_POINT_LEFT_TOP, CLAY_ATTACH_POINT_LEFT_TOP },
            .pointerCaptureMode = CLAY_POINTER_CAPTURE_MODE_CAPTURE,
            .offset = { 0, 0 },
            .zIndex = 100
        }
    }) {
        CLAY(CLAY_ID("ModalCard"), {
            .layout = {
                .layoutDirection = CLAY_TOP_TO_BOTTOM,
                .sizing = { .width = CLAY_SIZING_FIXED(620) },
                .padding = { 24, 24, 24, 24 },
                .childGap = 14
            },
            .backgroundColor = SURFACE,
            .border = { .color = BORDER, .width = CLAY_BORDER_ALL(1) },
            .floating = {
                .attachTo = CLAY_ATTACH_TO_PARENT,
                .attachPoints = { CLAY_ATTACH_POINT_CENTER_TOP, CLAY_ATTACH_POINT_CENTER_TOP },
                .pointerCaptureMode = CLAY_POINTER_CAPTURE_MODE_CAPTURE,
                .offset = { 0, (float)scene->modal_offset_y },
                .zIndex = 101
            }
        }) {
            CLAY_TEXT(CLAY_STRING("Create task"), text_cfg(24, TEXT, CLAY_TEXT_WRAP_NONE));
            CLAY(CLAY_ID("ModalCopyWrap"), { .layout = { .sizing = { .width = CLAY_SIZING_GROW(0) } } }) {
                CLAY_TEXT(CLAY_STRING("Capture the intent, then refine status, priority, and tags."), text_cfg(13, MUTED, CLAY_TEXT_WRAP_WORDS));
            }
            build_input(scene->draft_title);
            build_input(scene->draft_notes);
            CLAY_TEXT(CLAY_STRING("Status"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < 4; ++i) {
                char *label = stringf("%s %s", i == 1 ? "●" : "○", status_label(i));
                build_choice_button(label, i == 1);
                free(label);
            }
            CLAY_TEXT(CLAY_STRING("Priority"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < 4; ++i) {
                char *label = stringf("%s %s", i == 3 ? "●" : "○", priority_label(i));
                build_choice_button(label, i == 3);
                free(label);
            }
            CLAY_TEXT(CLAY_STRING("Tags"), text_cfg(12, MUTED, CLAY_TEXT_WRAP_NONE));
            for (int i = 0; i < scene->tag_count; ++i) {
                char *label = stringf("%s %s", i < 2 ? "[x]" : "[ ]", scene->tag_names[i]);
                build_choice_button(label, i < 2);
                free(label);
            }
            CLAY(CLAY_ID("ModalActions"), { .layout = { .childGap = 10 } }) {
                build_button("Save", ACCENT, TEXT);
                build_button("Cancel", SURFACE_HI, TEXT);
            }
        }
    }
}

static Clay_RenderCommandArray build_layout(const BenchScene *scene, int view_w, int view_h) {
    Clay_SetCurrentContext(g_clay);
    Clay_SetLayoutDimensions((Clay_Dimensions) { (float)view_w, (float)view_h });
    Clay_SetPointerState((Clay_Vector2) { 0, 0 }, false);
    Clay_UpdateScrollContainers(false, (Clay_Vector2) { 0, 0 }, 0.016f);

    Clay_BeginLayout();
    CLAY(CLAY_ID("Outer"), {
        .layout = {
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .padding = { 20, 20, 20, 20 },
            .childGap = 20
        },
        .backgroundColor = BG
    }) {
        build_sidebar(scene);
        build_project_content(scene);
        if (scene->modal_open) {
            build_modal(scene, view_w, view_h);
        }
    }
    return Clay_EndLayout();
}

static CommandCounts count_commands(Clay_RenderCommandArray commands) {
    CommandCounts counts = {0};
    counts.total = commands.length;
    for (int i = 0; i < commands.length; ++i) {
        Clay_RenderCommand *cmd = Clay_RenderCommandArray_Get(&commands, i);
        switch (cmd->commandType) {
            case CLAY_RENDER_COMMAND_TYPE_RECTANGLE: counts.rectangles++; break;
            case CLAY_RENDER_COMMAND_TYPE_BORDER: counts.borders++; break;
            case CLAY_RENDER_COMMAND_TYPE_TEXT: counts.text++; break;
            case CLAY_RENDER_COMMAND_TYPE_IMAGE: counts.images++; break;
            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
            case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END: counts.scissors++; break;
            case CLAY_RENDER_COMMAND_TYPE_CUSTOM: counts.custom++; break;
            default: break;
        }
    }
    return counts;
}

static void scene_init(BenchScene *scene, const BenchConfig *cfg) {
    memset(scene, 0, sizeof(*scene));
    scene->task_count = cfg->tasks;
    scene->project_count = cfg->projects;
    scene->tag_count = cfg->tags;
    scene->selected_project = 0;
    scene->selected_task = 0;
    scene->modal_open = strcmp(cfg->scenario, "modal") == 0;
    scene->workspace_name = stringf("Terra Tasks Bench");
    scene->project_names = (char **)calloc((size_t)scene->project_count, sizeof(char *));
    scene->tag_names = (char **)calloc((size_t)scene->tag_count, sizeof(char *));
    scene->tasks = (BenchTask *)calloc((size_t)scene->task_count, sizeof(BenchTask));
    scene->draft_title = stringf("A newly captured task with a title long enough to wrap cleanly in the modal");
    scene->draft_notes = stringf("These draft notes intentionally span multiple sentences so the Clay benchmark exercises wrapped text and a larger editor subtree.");
    scene->modal_offset_y = 72;

    for (int i = 0; i < scene->project_count; ++i) {
        scene->project_names[i] = i == 0 ? stringf("Inbox") : stringf("Project %d", i + 1);
    }
    for (int i = 0; i < scene->tag_count; ++i) {
        scene->tag_names[i] = stringf("tag-%d", i + 1);
    }

    int task_id = 0;
    for (int project = 0; project < scene->project_count; ++project) {
        int project_tasks = scene->task_count / scene->project_count;
        if (project < (scene->task_count % scene->project_count)) project_tasks += 1;
        for (int k = 0; k < project_tasks; ++k) {
            BenchTask *task = &scene->tasks[task_id];
            int n = task_id + 1;
            task->project_index = project;
            task->title = stringf("Task %d · Ship a cleaner compiler-shaped UI slice", n);
            task->notes = stringf(
                "This benchmark task exists to exercise text layout, list rows, detail panes, tags, and wrapping. Iteration %d verifies that the UI pipeline keeps behaving like a compiler and not an interpreter.",
                n
            );
            task->preview = stringf("%.77s...", task->notes);
            task->status_index = task_id % 4;
            task->priority_index = task_id % 4;
            task->tag_count = 1;
            task->tags[0] = task_id % scene->tag_count;
            if (task_id % 3 == 0 && scene->tag_count > 1) task->tags[task->tag_count++] = (task_id + 1) % scene->tag_count;
            if (task_id % 5 == 0 && scene->tag_count > 2) task->tags[task->tag_count++] = (task_id + 3) % scene->tag_count;
            task->meta = (char *)calloc(3, 32);
            for (int t = 0; t < task->tag_count; ++t) {
                snprintf(task->meta + (t * 32), 32, "%s", scene->tag_names[task->tags[t]]);
            }
            task_id += 1;
        }
    }
    if (project_task_count(scene, scene->selected_project) > 0) {
        scene->selected_task = nth_task_index_in_project(scene, scene->selected_project, 0);
    }
}

static void scene_destroy(BenchScene *scene) {
    free(scene->workspace_name);
    for (int i = 0; i < scene->project_count; ++i) free(scene->project_names[i]);
    for (int i = 0; i < scene->tag_count; ++i) free(scene->tag_names[i]);
    for (int i = 0; i < scene->task_count; ++i) {
        free(scene->tasks[i].title);
        free(scene->tasks[i].notes);
        free(scene->tasks[i].preview);
        free(scene->tasks[i].meta);
    }
    free(scene->project_names);
    free(scene->tag_names);
    free(scene->tasks);
    free(scene->draft_title);
    free(scene->draft_notes);
    memset(scene, 0, sizeof(*scene));
}

static void scene_step_full(BenchScene *scene, int iteration) {
    int project_tasks = project_task_count(scene, scene->selected_project);
    if (project_tasks > 0) scene->selected_task = nth_task_index_in_project(scene, scene->selected_project, iteration % project_tasks);
    if (scene->modal_open) scene->modal_offset_y = 72 + (iteration % 3) * 4;
}

static void scene_step_incremental(BenchScene *scene, int iteration) {
    if (scene->modal_open) {
        free(scene->draft_title);
        free(scene->draft_notes);
        if (iteration % 2 == 0) {
            scene->draft_title = stringf("Draft title edit %d keeps moving through the modal width", iteration);
            scene->draft_notes = stringf("Draft notes edit %d mutates one field while leaving the rest of the tree structurally the same from the app point of view.", iteration);
        } else {
            scene->draft_title = stringf("Draft title edit %d keeps moving", iteration);
            scene->draft_notes = stringf("Draft notes edit %d changes the wrapped content and forces Clay to re-layout the modal.", iteration);
        }
    } else {
        int project_tasks = project_task_count(scene, scene->selected_project);
        if (project_tasks > 0) {
            int current_slot = 0;
            for (int i = 0; i < scene->task_count; ++i) {
                if (scene->tasks[i].project_index != scene->selected_project) continue;
                if (i == scene->selected_task) break;
                current_slot += 1;
            }
            scene->selected_task = nth_task_index_in_project(scene, scene->selected_project, (current_slot + 1) % project_tasks);
        }
    }
}

static void benchmark_scene(const BenchConfig *cfg) {
    BenchScene scene;
    scene_init(&scene, cfg);

    int max_elements = cfg->tasks * 32 + 8192;
    int max_words = cfg->tasks * 96 + 16384;
    ensure_clay_context(max_elements, max_words, cfg->viewport_w, cfg->viewport_h);

    for (int i = 0; i < cfg->warmup; ++i) {
        scene_step_full(&scene, i);
        (void)build_layout(&scene, cfg->viewport_w, cfg->viewport_h);
    }

    Samples full = {0};
    Samples incr = {0};
    Samples apply = {0};
    CommandCounts command_counts = {0};

    for (int i = 0; i < cfg->iters; ++i) {
        scene_step_full(&scene, i + cfg->warmup);
        uint64_t t0 = now_ns();
        Clay_RenderCommandArray commands = build_layout(&scene, cfg->viewport_w, cfg->viewport_h);
        uint64_t t1 = now_ns();
        samples_push(&full, t1 - t0);
        if (i == 0) command_counts = count_commands(commands);
    }

    for (int i = 0; i < cfg->warmup; ++i) {
        scene_step_incremental(&scene, i);
        (void)build_layout(&scene, cfg->viewport_w, cfg->viewport_h);
    }

    for (int i = 0; i < cfg->iters; ++i) {
        uint64_t t0 = now_ns();
        scene_step_incremental(&scene, i + cfg->warmup);
        uint64_t t1 = now_ns();
        Clay_RenderCommandArray commands = build_layout(&scene, cfg->viewport_w, cfg->viewport_h);
        uint64_t t2 = now_ns();
        samples_push(&apply, t1 - t0);
        samples_push(&incr, t2 - t1);
        if (i == 0 && command_counts.total == 0) command_counts = count_commands(commands);
    }

    printf("scene=%s tasks=%d viewport=%dx%d warmup=%d iters=%d\n",
        cfg->scenario, cfg->tasks, cfg->viewport_w, cfg->viewport_h, cfg->warmup, cfg->iters);
    printf("mode=full-rebuild\n");
    printf("commands total=%d rect=%d border=%d text=%d image=%d scissor=%d custom=%d\n",
        command_counts.total, command_counts.rectangles, command_counts.borders, command_counts.text,
        command_counts.images, command_counts.scissors, command_counts.custom);
    print_stats("full total", &full);
    printf(
        "BENCH_SUMMARY engine=clay scene=%s tasks=%d mode=full-rebuild total_mean_ns=%llu total_p50_ns=%llu total_p95_ns=%llu total_p99_ns=%llu total_max_ns=%llu commands_total=%d commands_rect=%d commands_border=%d commands_text=%d commands_image=%d commands_scissor=%d commands_custom=%d\n",
        cfg->scenario,
        cfg->tasks,
        (unsigned long long)samples_mean(&full),
        (unsigned long long)samples_percentile(&full, 0.50),
        (unsigned long long)samples_percentile(&full, 0.95),
        (unsigned long long)samples_percentile(&full, 0.99),
        (unsigned long long)samples_percentile(&full, 1.00),
        command_counts.total,
        command_counts.rectangles,
        command_counts.borders,
        command_counts.text,
        command_counts.images,
        command_counts.scissors,
        command_counts.custom
    );
    printf("mode=incremental-edit\n");
    print_stats("incr apply", &apply);
    print_stats("incr total", &incr);
    printf("reuse n/a (clay full rebuild each layout)\n");
    printf(
        "BENCH_SUMMARY engine=clay scene=%s tasks=%d mode=incremental-edit apply_mean_ns=%llu apply_p50_ns=%llu apply_p95_ns=%llu apply_p99_ns=%llu apply_max_ns=%llu total_mean_ns=%llu total_p50_ns=%llu total_p95_ns=%llu total_p99_ns=%llu total_max_ns=%llu\n",
        cfg->scenario,
        cfg->tasks,
        (unsigned long long)samples_mean(&apply),
        (unsigned long long)samples_percentile(&apply, 0.50),
        (unsigned long long)samples_percentile(&apply, 0.95),
        (unsigned long long)samples_percentile(&apply, 0.99),
        (unsigned long long)samples_percentile(&apply, 1.00),
        (unsigned long long)samples_mean(&incr),
        (unsigned long long)samples_percentile(&incr, 0.50),
        (unsigned long long)samples_percentile(&incr, 0.95),
        (unsigned long long)samples_percentile(&incr, 0.99),
        (unsigned long long)samples_percentile(&incr, 1.00)
    );

    samples_free(&full);
    samples_free(&incr);
    samples_free(&apply);
    scene_destroy(&scene);
}

int main(void) {
    BenchConfig cfg;
    cfg.font_path = getenv_str("BENCH_FONT", "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf");
    cfg.viewport_w = getenv_int("BENCH_VIEW_W", 1100);
    cfg.viewport_h = getenv_int("BENCH_VIEW_H", 760);
    cfg.warmup = getenv_int("BENCH_WARMUP", 3);
    cfg.iters = getenv_int("BENCH_ITERS", 20);
    cfg.tasks = getenv_int("BENCH_TASKS", 100);
    cfg.projects = getenv_int("BENCH_PROJECTS", 1);
    cfg.tags = getenv_int("BENCH_TAGS", 6);
    cfg.scenario = getenv_str("BENCH_SCENARIO", "list");
    g_font_path = cfg.font_path;

    if (!TTF_Init()) {
        fprintf(stderr, "TTF_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    benchmark_scene(&cfg);

    for (int i = 0; i < g_font_cache_count; ++i) {
        if (g_font_cache[i].font) TTF_CloseFont(g_font_cache[i].font);
    }
    TTF_Quit();
    free(g_arena_memory);
    return 0;
}
