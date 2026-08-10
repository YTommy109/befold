#ifndef BEFOLD_CGITSHIM_H
#define BEFOLD_CGITSHIM_H

#include <git2.h>

// libgit2 のプロセス全体オプションは `int git_libgit2_opts(int option, ...)` という
// C の可変長引数関数で公開されている。Swift は C の可変長引数関数を import できないため
// (va_list を受ける別名も libgit2 側に無い)、必要なオプションだけを固定引数へ落として
// 露出する。arm64 の呼び出し規約では可変長引数がスタック渡しになるため、
// `@convention(c)` の関数ポインタへ unsafeBitCast して固定引数として呼ぶ回避策は取れない。
//
// ここに足してよいのは「befold が実際に使うオプション」だけ。libgit2 の全オプションを
// 機械的にラップすると、使われないラッパの保守が残る。

/// 指定した config レベルの検索パスを設定する。
/// 空文字を渡すとそのレベルは無効化され、以降 libgit2 はそのレベルの config を読まない。
/// - Parameter level: `git_config_level_t` の生値。
/// - Returns: 0 で成功。負値は libgit2 のエラーコード。
int befold_git_opts_set_search_path(int level, const char *path);

/// 指定した config レベルの現在の検索パスを取得する。
/// - Parameter out: 呼び出し側が `git_buf_dispose` で解放する。
/// - Returns: 0 で成功。負値は libgit2 のエラーコード。
int befold_git_opts_get_search_path(int level, git_buf *out);

#endif
