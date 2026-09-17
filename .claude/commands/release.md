---
argument-hint: patch | minor | major | dev
---

# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major | dev、省略可）

## 手順

### 0. 引数省略時のレベル自動判定

`$ARGUMENTS` が空の場合、以下の方針でレベルを自動決定し、確認を挟まず
そのまま手順1以降を実行する。**`major` だけは commit 件名から機械的に
判定できない（破壊的変更の判断は意図的な人間の判断が必要）ため、自動選択
の対象外とし、明示的に `major` を指定された場合のみ扱う。**

判定は **stable 同士の比較を先に**行う。stable はユーザー影響の単位であり、
間に dev タグが挟まっていても、直前の stable 以降に出ていない変更があれば
stable 化の対象になる（dev タグとの比較だけで「リリース不要」とすると、
dev に載った修正が stable へ出ないまま止まる）。

1. 直前の **stable** タグ（`-` を含まないタグのうち最新のもの）から `HEAD`
   までのコミットを確認する:

   ```bash
   git tag --sort=-v:refname | grep -v -e '-' | head -1
   git log <直前の stable タグ>..HEAD --pretty=%s
   ```

   このコミット群から、`/release-notes stable` の除外方針
   （`docs:`/`chore:`/`test:`/`ci:`/`refactor:`/`style:`、内部実装のみの
   `feat:`/`fix:`）
   を適用してユーザー影響のある commit だけを残す。
   - 残った commit に `feat:`（ユーザー影響のある新機能）が 1 件以上ある
     → レベルは `minor`
   - `feat:` は無いが `fix:`（ユーザー影響のある不具合修正）がある
     → レベルは `patch`
   - 残った commit が 0 件 → 手順 0-2 へ（dev の判定）
2. stable 化しない場合に限り、直前のタグ（stable/dev 問わず最新）から
   `HEAD` までのコミットを確認する:

   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --pretty=%s
   ```

   `docs:` / `chore:` / `test:` / `ci:` のみで、アプリの挙動に影響する
   コミット（`feat:` / `fix:` / `refactor:` などプロダクトコードの変更）が
   1件もない場合は、**リリース不要と判断してここで中断する**。中断する
   旨と該当コミット一覧をユーザーに報告して終了する。1 件でもあればレベルは `dev`。
3. 決定したレベルをユーザーに報告し、承認を待たずそのまま手順1へ進む。
   レベルの決定打となったコミット（特に Conventional Commits プレフィックスが
   付いていないもの）は、件名とどちらに分類したか・その根拠を明記する
   （`.claude/CLAUDE.md` の「設計・方針を提示するときは前提と裏付けを明示する」
   に従う）。プレフィックス無しコミットの分類に自信が持てない場合は、
   同時期の関連コミット（同じ機能への fix: 追随コミットの有無など）を
   参照材料として示す。
   例:「ユーザー影響のある変更に `fix:` 3件と、プレフィックス無しの
   `Use available width for CSV tables`（#679）があり、後者を新機能相当と
   判断したため minor でリリースします」

`$ARGUMENTS` が明示的に `patch` / `minor` / `major` / `dev` 指定された場合は
手順0を行わず、ユーザー指定のレベルをそのまま使う。

ただし `$ARGUMENTS` が `dev` と明示指定された場合に限り、**手順 0-1 の stable
化判定だけは実行し、条件を満たしていれば結果を一言添えて報告する**（レベルは
指定どおり `dev` のまま進め、確認は挟まない）。dev を指定し続けると、ユーザー
影響のある変更が stable へ出ないまま溜まり、条件充足に気づく経路が無くなるため。
報告例:「dev タグを作成しました。なお v1.13.3 以降にユーザー影響のある `feat:`
が 1 件あり、stable 化条件（minor）を満たしています。」

### 1. バージョン bump（またはdev タグ作成）

`/bump` コマンドと同じ手順で bump する（レベルは `$ARGUMENTS` が指定されて
いればそれを、省略時は手順0で決定した `dev` を使う）:

```bash
scripts/bump.sh <レベル>
```

エラー終了した場合はここで停止する（リカバリーしない）。

### 2. リリースノートの生成

`/release-notes` コマンドの手順に従い、最新タグと前回タグ間のコミットから
リリースノートを Markdown で生成する。

- **dev リリースの場合**（タグに `-` が含まれる場合）: `/release-notes dev` の
  方針（全コミット対象）で生成する。
- **stable リリースの場合**: `/release-notes stable` の方針（ユーザー影響の
  ある内容のみ）で生成する。除外したコミットがあれば、生成結果と合わせて
  ユーザーに提示する。

いずれの場合も、**英語セクションを先・日本語セクションを後**にした 1 本の
本文にする（`/release-notes` の「言語」の節）。

生成結果はユーザーに表示する。

### 3. GitHub リリース作成

最新タグ（`git describe --tags --abbrev=0`）を使い、リリースノートを body にして
GitHub リリースを作成する。

**dev リリースの場合**（タグに `-` が含まれる場合）:

```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>" --prerelease
```

**stable リリースの場合**:

```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>"
```

DMG のビルドと添付は GitHub Actions（release.yml）が自動で行うため、
ローカルでのビルド・DMG 作成は不要。

### 4. CHANGELOG.md への追記（stable リリースのみ）

**stable リリースの場合のみ**、`.claude/skills/changelog.md` スキルの手順に
従い、生成したリリースノートの**日本語セクションだけ**を `CHANGELOG.md` に
追記し（`CHANGELOG.md` は日本語のみで維持する）、
`git add CHANGELOG.md && ALLOW_MAIN_COMMIT=1 git commit -m "docs: CHANGELOG.md に <タグ> を追記する"`
でコミット・push する（バージョン bump コミットとは分けて新規コミットにする）。
main への直接コミットは pre-commit フックでブロックされるため `ALLOW_MAIN_COMMIT=1` が必須。

dev リリースの場合は追記しない。

各ステップの結果をユーザーに報告する。

## 誤ったレベルで bump・push してしまった場合の取り消し

手順0の判定が誤っていた等の理由で、間違ったレベルで `scripts/bump.sh` を
実行・push した後に気づいた場合、次の順で取り消す。

1. バージョン bump コミットを `git revert`（`ALLOW_MAIN_COMMIT=1` 付き）して push する。
2. 誤ったタグをローカル・リモート双方から削除する:
   `git tag -d v<誤ったバージョン>` / `git push origin --delete v<誤ったバージョン>`
3. **タグ push は GitHub Actions の release.yml を非同期にトリガーしている。**
   手順2のタグ削除だけでは止まらない。実測（2026-09-17）: bump 直後にタグを
   削除しても、既にトリガー済みのワークフロー実行が完了時に `gh release create`
   相当の処理を行い、削除したはずのタグと GitHub Release を**タグ無しの状態から
   自動的に作り直した**（デフォルトブランチの当時の HEAD に対して）。
   `gh run list --workflow=release.yml --limit 5` で該当コミットの実行を確認し、
   実行中なら `gh run cancel <id>`、既に完了して誤った Release/タグができて
   しまっていたら `gh release delete v<誤ったバージョン> --cleanup-tag -y` で
   Release とタグを一括削除する。
4. R2 バケット `befold-dist`（`site/wrangler.toml` の binding `DIST`）に
   同タグの成果物が残っていないか確認する。`releases/<誤ったバージョン>/`
   配下の DMG オブジェクトを削除し、`releases/latest.json` が誤った
   バージョンを指していないか確認する（stable の場合のみ更新される）。
5. `appcast.xml` / `appcast-develop.xml`（R2 直下、`APPCAST_KEY`）に
   誤ったバージョンの `<item>` が残っていないか確認する。残っていれば
   その `<item>` ブロックを削除し、R2 へ書き戻す
   （`wrangler r2 object put befold-dist/appcast.xml --remote --file <ローカルファイル> --content-type application/xml`）。
   実測（2026-09-17）: GitHub Release/タグ/R2 DMG を削除しても appcast は
   自動連動せず、リンク切れの `<item>` が Sparkle 配信フィードに残った。
6. 正しいレベルで `scripts/bump.sh <正しいレベル>` を再実行する。
