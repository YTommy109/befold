---
id: TASK-550
title: 'ADR の file:line 引用がコード変更で静かにずれる問題に手を打つ'
status: To Do
assignee: []
created_date: '2026-08-24 15:19'
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
- [ ] #1 docs/adr/0007 の DOWNLOAD_URL 3 箇所（53・58・172 行）が実態と合っている
- [ ] #2 行番号引用を今後どう扱うかの方針が決まり、ADR かルール文書に記録されている
- [ ] #3 決めた方針が破れたときに気づける手段がある（検査スクリプトの拡張、または引用形式そのものを壊れない形にする）
- [ ] #4 0007 以外の文書（0004 / 0005 / 0006 / docs/dev/flaky-test-filewatcher-investigation.md）の同型のずれを実測し、このタスクで直すか別タスクにするかを Notes に記録している
<!-- AC:END -->
