---
name: Changelog
description: stable リリースのリリースノートを CHANGELOG.md に追記する
---

## Changelog

`/release-notes stable` で生成したリリースノートをリポジトリ直下の
`CHANGELOG.md` に永続化する。dev リリースでは追記しない
（GitHub Releases のみに記録する）。

### 使い方

引数として「タグ名」と「リリースノート本文（Markdown）」を受け取る。

### Steps

1. `CHANGELOG.md` が存在しなければ、以下のヘッダーで新規作成する:

   ```markdown
   # Changelog

   stable リリースのユーザー影響のある変更を記録する。
   dev リリースの全変更履歴は [GitHub Releases](https://github.com/YTommy109/befold/releases) を参照。
   ```

2. `# Changelog` ヘッダー（存在しない場合はヘッダー行の直後）の直下に、
   受け取ったリリースノートを新しいセクションとして挿入する
   （最新バージョンが常に先頭に来るように前方追記する）。
3. 既に同じタグの見出し（`## <タグ名>`）が存在する場合は、追記せず
   「既に記録済み」と報告して終える。
4. 変更をコミットする前提はない（呼び出し元の `/release` コマンドが
   バージョン bump コミットと合わせてコミットする）。
