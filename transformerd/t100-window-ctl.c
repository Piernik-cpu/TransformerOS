/* SPDX-License-Identifier: MIT
 * t100-window-ctl: Lightweight wlr-foreign-toplevel helper for TransformerOS.
 * Maximizes existing non-transient windows when switching into Tablet Mode.
 */
#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

struct toplevel_node {
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *app_id;
    char *title;
    int maximized;
    int has_parent;
    int closed;
    struct toplevel_node *next;
};

struct app_state {
    struct wl_display *display;
    struct wl_registry *registry;
    struct zwlr_foreign_toplevel_manager_v1 *manager;
    struct toplevel_node *toplevels;
};

static char *xstrdup(const char *s) {
    return s ? strdup(s) : NULL;
}

static void handle_title(void *data,
                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                         const char *title) {
    (void)handle;
    struct toplevel_node *node = data;
    free(node->title);
    node->title = xstrdup(title);
}

static void handle_app_id(void *data,
                          struct zwlr_foreign_toplevel_handle_v1 *handle,
                          const char *app_id) {
    (void)handle;
    struct toplevel_node *node = data;
    free(node->app_id);
    node->app_id = xstrdup(app_id);
}

static void handle_output_enter(void *data,
                                struct zwlr_foreign_toplevel_handle_v1 *handle,
                                struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void handle_output_leave(void *data,
                                struct zwlr_foreign_toplevel_handle_v1 *handle,
                                struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void handle_state(void *data,
                         struct zwlr_foreign_toplevel_handle_v1 *handle,
                         struct wl_array *state) {
    (void)handle;
    struct toplevel_node *node = data;
    node->maximized = 0;
    uint32_t *entry;
    wl_array_for_each(entry, state) {
        if (*entry == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED) {
            node->maximized = 1;
        }
    }
}

static void handle_done(void *data,
                        struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
}

static void handle_closed(void *data,
                          struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)handle;
    struct toplevel_node *node = data;
    node->closed = 1;
}

static void handle_parent(void *data,
                          struct zwlr_foreign_toplevel_handle_v1 *handle,
                          struct zwlr_foreign_toplevel_handle_v1 *parent) {
    (void)handle;
    struct toplevel_node *node = data;
    node->has_parent = (parent != NULL);
}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
    .title = handle_title,
    .app_id = handle_app_id,
    .output_enter = handle_output_enter,
    .output_leave = handle_output_leave,
    .state = handle_state,
    .done = handle_done,
    .closed = handle_closed,
    .parent = handle_parent,
};

static void manager_toplevel(void *data,
                             struct zwlr_foreign_toplevel_manager_v1 *manager,
                             struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)manager;
    struct app_state *st = data;
    struct toplevel_node *node = calloc(1, sizeof(*node));
    if (!node) {
        zwlr_foreign_toplevel_handle_v1_destroy(handle);
        return;
    }
    node->handle = handle;
    node->next = st->toplevels;
    st->toplevels = node;
    zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_listener, node);
}

static void manager_finished(void *data,
                             struct zwlr_foreign_toplevel_manager_v1 *manager) {
    struct app_state *st = data;
    if (st->manager == manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(manager);
        st->manager = NULL;
    }
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = manager_toplevel,
    .finished = manager_finished,
};

static void registry_global(void *data,
                            struct wl_registry *registry,
                            uint32_t name,
                            const char *interface,
                            uint32_t version) {
    struct app_state *st = data;
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0 && !st->manager) {
        uint32_t bind_ver = version < 3 ? version : 3;
        st->manager = wl_registry_bind(registry, name,
                                       &zwlr_foreign_toplevel_manager_v1_interface,
                                       bind_ver);
        zwlr_foreign_toplevel_manager_v1_add_listener(st->manager, &manager_listener, st);
    }
}

static void registry_global_remove(void *data,
                                   struct wl_registry *registry,
                                   uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void free_toplevels(struct app_state *st) {
    struct toplevel_node *cur = st->toplevels;
    while (cur) {
        struct toplevel_node *next = cur->next;
        if (cur->handle) {
            zwlr_foreign_toplevel_handle_v1_destroy(cur->handle);
        }
        free(cur->app_id);
        free(cur->title);
        free(cur);
        cur = next;
    }
    st->toplevels = NULL;
}

static void usage(FILE *out) {
    fprintf(out, "Usage: t100-window-ctl [maximize-all|unmaximize-all|list|--help]\n");
}

int main(int argc, char **argv) {
    const char *cmd = (argc > 1) ? argv[1] : "list";
    if (strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0) {
        usage(stdout);
        return 0;
    }
    if (strcmp(cmd, "maximize-all") != 0 &&
        strcmp(cmd, "unmaximize-all") != 0 &&
        strcmp(cmd, "list") != 0) {
        usage(stderr);
        return 2;
    }

    struct app_state st = {0};
    st.display = wl_display_connect(NULL);
    if (!st.display) {
        fprintf(stderr, "t100-window-ctl: unable to connect to Wayland display\n");
        return 1;
    }

    st.registry = wl_display_get_registry(st.display);
    wl_registry_add_listener(st.registry, &registry_listener, &st);
    wl_display_roundtrip(st.display);

    if (!st.manager) {
        fprintf(stderr, "t100-window-ctl: compositor lacks zwlr_foreign_toplevel_manager_v1\n");
        wl_registry_destroy(st.registry);
        wl_display_disconnect(st.display);
        return 1;
    }

    /* Receive initial toplevel handles and their title/app_id/state/parent events */
    wl_display_roundtrip(st.display);

    for (struct toplevel_node *n = st.toplevels; n; n = n->next) {
        if (n->closed || !n->handle) {
            continue;
        }
        if (strcmp(cmd, "maximize-all") == 0) {
            if (!n->has_parent && !n->maximized) {
                zwlr_foreign_toplevel_handle_v1_set_maximized(n->handle);
            }
        } else if (strcmp(cmd, "unmaximize-all") == 0) {
            if (!n->has_parent && n->maximized) {
                zwlr_foreign_toplevel_handle_v1_unset_maximized(n->handle);
            }
        } else {
            printf("%s\t%s\tmax=%d\n",
                   n->app_id ? n->app_id : "",
                   n->title ? n->title : "",
                   n->maximized);
        }
    }

    wl_display_roundtrip(st.display);
    wl_display_flush(st.display);

    free_toplevels(&st);
    if (st.manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(st.manager);
    }
    wl_registry_destroy(st.registry);
    wl_display_disconnect(st.display);
    return 0;
}
