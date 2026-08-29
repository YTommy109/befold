---
id: TASK-550
title: 'ADR の file:line 引用がコード変更で静かにずれる問題に手を打つ'
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-24 15:19'
updated_date: '2026-08-25 00:08'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 798000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR がコードを `path:行番号` で引用しているが、コードを変えても追随しないため黙ってずれる。読み手（人にも AI にも）は「そこにその名前がある」と信じて読むので、ずれた引用は誤った前提を配る。

## 確認済みのずれ（2026-08-25、TASK-549 の作業中に発見）

`docs/adr/0007-distribution-site-custom-domain.md`:

| 行 | 記述 | 実態 |
| --- | --- | --- |
| 53 | ホスト名のハードコードは **`DOWNLOAD_URL` 1 箇所だけ**（`site/src/views/shared.tsx:13`） | `DOWNLOAD_URL` は**存在しない**（`site/` 全体を grep して 0 件）。現在は `DOWNLOAD_PATH`（`shared.tsx:34`）。しかもこれは相対パス `/download` でホスト名ではない。実際にホスト名を持つのは `REPO_URL`（`shared.tsx:14`） |
| 58 | クライアント状態は `localStorage` のみ（`site/src/views/shared.tsx:29,33`） | 現在その位置は `DOWNLOAD_PATH` の doc コメント。`localStorage` を触るのは `CLEANUP_SCRIPT`（`shared.tsx:80`） |
| 172 | **`DOWNLOAD_URL`（`site/src/views/shared.tsx:13`）は相対パス `/download` にする。** | 同上。名前も行番号もずれている |

同じ ADR には他にも行番号引用が 30 箇所あり（`public.tsx:20,33,106-128` / `landing.tsx:51,56,76,81,82` / `features.tsx:153,160,165,166` など）、TASK-549 で `landing.tsx` が 7 行ずれたのでそれらも現状と合っていない可能性が高い（未確認）。

行番号引用を持つ文書は他にもある: `docs/adr/0004` / `0005` / `0006` / `docs/dev/flaky-test-filewatcher-investigation.md`。

## なぜ検知されなかったか

`scripts/check-doc-symbols.sh` は **`型.メンバ` 形式の引用だけ**を検査する（CLAUDE.md に明記の設計判断で、単独の型名まで広げると除外リストのほうが重くなるため）。`DOWNLOAD_URL` のような単独の定数名と、`:13` のような行番号はどちらも検査対象外。

## 決めること

このタスクの本体は「0007 を直す」ことではなく、**同じずれが再発しない形にするか、諦めて引用の書き方を変えるか**を決めること。少なくとも次を検討する。

1. **行番号の引用をやめる。** ADR は「不可逆な設計判断とその理由」を残す層（CLAUDE.md の三層構造）であって、現在のコードの案内図ではない。行番号を落として**シンボル名だけ**にすれば、名前の変更は grep で見つかるし、行の移動では壊れなくなる
2. **単独のシンボル名も検査対象にする。** `check-doc-symbols.sh` を拡張し、バッククォート内の `SCREAMING_SNAKE_CASE` / `camelCase` の識別子が実在するかを見る。除外リストが重くなる懸念は CLAUDE.md に記録済みなので、実測してから決める
3. **ADR は書いた時点のスナップショットと割り切る。** `docs/superpowers/specs/*-design.md` に付けているのと同じ「これは YYYY-MM-DD 時点のもの」バナーを ADR にも置き、引用は当時のものとして読ませる

1 と 3 は両立する。2 を採るなら 1 とも両立する（名前だけ残して名前を検査する）。

## 範囲

上で決めた方針を 0007 に適用して直すところまで。0004 / 0005 / 0006 と dev/ 配下の同型のずれは、実測して件数を出したうえで同じタスクで直すか別に切るかを判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 docs/adr/0007 の DOWNLOAD_URL 3 箇所（53・58・172 行）が実態と合っている
- [x] #2 行番号引用を今後どう扱うかの方針が決まり、ADR かルール文書に記録されている
- [x] #3 決めた方針が破れたときに気づける手段がある（検査スクリプトの拡張、または引用形式そのものを壊れない形にする）
- [x] #4 0007 以外の文書（0004 / 0005 / 0006 / docs/dev/flaky-test-filewatcher-investigation.md）の同型のずれを実測し、このタスクで直すか別タスクにするかを Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実測: docs 配下の行番号引用を数え、どの層に集中しているかを出す（adr+dev = 64 件、superpowers = 212 件）
2. 方針を決める: 案 1（行番号をやめてシンボル名にする）+ 案 3（ADR の現状調査に日付を書く）を採り、案 2（単独シンボル名の実在検査）は採らない。理由は実測で偽陽性 89%
3. 検査を作る: scripts/check-doc-citations.sh。docs/adr/** と docs/dev/** で (a) 行番号引用を禁止、(b) 引用パスの実在を確認。self-test 付き、pre-commit へ配線
4. 方針を .claude/CLAUDE.md「設計文書の三層構造」節に記録する
5. 検知された既存のずれを直す（0007 は本体、0004/0005/0006 と docs/dev は並列のサブエージェントへ委譲）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこと

起票時の 3 案のうち **案 1（行番号引用をやめる）+ 案 3（現状調査に日付を書く）** を採り、**案 2（単独シンボル名の実在検査）は採らない**。

案 2 を採らない根拠（実測）: docs/adr/ 内のバッククォート識別子（SCREAMING_SNAKE / camelCase）79 件をリポジトリ全体で照合したところ 9 件が NOTFOUND。うち 8 件は「存在しないこと自体を述べた正しい記述」だった（0005 の `preBuildScripts` / `postCompileScripts` / `postBuildScripts` は project.yml に無い、0005 の `allowFileAccessFromFileURLs` は非公開プリファレンス、0008 の `verifiedBotCategory` は Cloudflare の API フィールド、0002 の `canOperateOnVisibleDocument`、0003 の `appliedGitStatusSequence` 等）。**偽陽性 89%** で、除外リストのほうが本体になる。ADR は「採らなかった案」「存在しないもの」「まだ実装していない決定」を論じる層なので、識別子の実在検査は原理的に噛み合わない。

## 入れた担保

`scripts/check-doc-citations.sh`（新規、pre-commit へ配線）。docs/adr/** と docs/dev/** に対して 2 つを見る。

1. 行番号引用（`path:12` / `path:12,34` / `path:12-20`）を禁止
2. 引用パスの実在（文書からの相対 → ROOT からの相対 → パス末尾一致の順で解決）

除外は `scripts/doc-citation-allowlist.txt` に「文書パス|引用」の組で書く（グローバルに素通しにすると別文書での陳腐化を検知できなくなるため）。現在 10 件で、内訳は ADR 0005 の歴史記述 3・product-code.md の歴史記述 2・例示のための架空名 2・R2 のオブジェクトキー 2。

self-test を既定実行のたびに通す（検知そのものが壊れてグリーンになるのを防ぐ）。**実測でフックが実際に落ちることを確認済み**: docs/dev/cli-launch.md に `site/src/views/shared.tsx:13` を足して commit すると pre-commit が該当行を指して拒否した。

規約は .claude/CLAUDE.md「設計文書の三層構造」節の下に「### 文書からコードを引用するときは行番号を書かない」として記録。

## AC#4: 0007 以外の実測結果

**このタスク内で全部直した**（同じ形の機械的な修正で、分けると検知だけ入って違反が残るため）。

行番号引用の件数: 0004=6 / 0005=11 / 0006=17 / 0007=28 / docs/dev/flaky-test-filewatcher-investigation.md=2。合計 64 件。docs/superpowers/ 配下（plans 35 本・specs 7 本、計 212 件）はスナップショット層なので検査対象外・無修正。

検査を回して**新たに見つかった 20 件のパス不存在**も直した。`viewer-src/*.js`（TASK-499 で全廃、現 .ts）が viewer-rendering-dataflow.md / rules/product-code.md / rules/testing.md に 13 件、`befold-cli/*.swift`（現 `BefoldCLI/`）が cli-launch.md に 6 件、`BefoldApp/befold/App/GitCommandRunner.swift`（TASK-435.5 で撤去）が 0006 に 1 件。

引用の突き合わせで見つかった**記述そのもののずれ**（行番号とは別）:

- 0006: 「`GIT_OPT_SET_SEARCH_PATH` で無効化するのは system と xdg の 2 つで global は有効のまま」→ **実装と逆**。`GitLibrary.disabledConfigLevels == [GIT_CONFIG_LEVEL_SYSTEM]` のみで、xdg は TASK-467 で撤回済み。担保テスト名 `keepsGlobalConfigSearchPathEnabled` も不在（実在は `disablesOnlySystemConfigSearchPath` / `keepsUserConfigSearchPathsEnabled`）。`GitStatusReader.parsePorcelainV2` も不在
- 0004: `bot-other` → 実装は `bot:other`（`BOT_OTHER`）
- 0005: `loadFileURL` の置き場（`ViewerRenderer.swift` → `ViewerWebViewFactory.makeWebView`）、`Package.swift` のリソース列挙件数
- 0007: `DOWNLOAD_URL` は起票時点では実在した（PR #518 = 本 ADR の実装が `DOWNLOAD_PATH` へ改名）。Context の見出しを「現状（実測 / 2026-08-14 時点）」に変え、決定の実装で古くなる旨を明記
- flaky-test-filewatcher-investigation.md: `waitUntilWithRetry` の置き場、`BEFOLD_TEST_TIMEOUT_SECONDS` の値（30 秒 → ワークフロー 60 秒・thread-sanitizer 120 秒）
- rules/product-code.md: 「`.js` と `.ts` が混在する（移行の途中）」→ TASK-499 で完了済み、`allowJs: false`

## 別タスク候補（このタスクでは直していない）

**ADR 0003 が Accepted のまま未実装。** `appliedGitStatusGeneration` は今も `SidebarNavigator` にあり、`FileListModel.appliedGitStatusSequence` は存在しない（`rg` で確認）。ADR の決定が実装されていないこと自体は本タスクの範囲外。

**`scripts/check-doc-symbols.sh` の `is_allowlisted` に同型の不具合がある可能性。** `grep -v … | grep -v … | grep -q` のパイプ末尾に `-q` を置いており、`set -o pipefail` 下では `grep -q` の早期終了で上流が SIGPIPE になり、除外が効かない形になりうる（本タスクで同じ書き方をして実際に踏み、`<<<` へ書き換えた）。未検証。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/adr/** と docs/dev/** で `path:行番号` の引用を禁止し、パス + シンボル名で示す規約にした。担保として scripts/check-doc-citations.sh を新設（行番号引用の禁止 + 引用パスの実在、self-test 付き）し pre-commit へ配線。単独シンボル名の実在検査は偽陽性 89%（79 件中 9 件 NOTFOUND のうち 8 件が正しい記述）の実測により不採用。既存のずれは行番号引用 64 件・パス不存在 20 件・記述のずれ十数件をすべて修正した。検証: scripts/check-doc-citations.sh・check-doc-symbols.sh・markdownlint-cli2（78 ファイル 0 issues）が通り、docs/dev に行番号引用を足した commit が pre-commit で実際に拒否されることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
