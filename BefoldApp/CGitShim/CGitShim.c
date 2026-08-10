#include "include/CGitShim.h"

int befold_git_opts_set_search_path(int level, const char *path) {
    return git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, level, path);
}

int befold_git_opts_get_search_path(int level, git_buf *out) {
    return git_libgit2_opts(GIT_OPT_GET_SEARCH_PATH, level, out);
}
