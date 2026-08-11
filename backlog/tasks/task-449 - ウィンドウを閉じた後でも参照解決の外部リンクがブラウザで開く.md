---
id: TASK-449
title: ウィンドウを閉じた後でも参照解決の外部リンクがブラウザで開く
status: To Do
assignee: []
created_date: '2026-08-11 13:38'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 100610
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #483 で ReferenceResolutionCoordinator の `host` プロトコル参照をクロージャ注入へ置き換えた際、await 後の生存確認 `guard let host = self.host else { return }` が削除された（BefoldApp/befold/App/ReferenceResolutionCoordinator.swift:69-90）。

`.resolved` / `.unresolved` のクロージャは controller を weak で捕捉しているため従来どおり抑止されるが、`.external` だけは `NSWorkspace.shared.open(url)` を直接呼ぶため生存確認を通らない。結果、リンク種別で挙動が食い違う。

再現経路: Markdown 上の `https://...` リンクを cmd+click →`resolver.resolve` の detached な git 参照解決が走っている間にウィンドウを閉じる（cmd+W）→ 解決完了後に既定ブラウザが起動して前面に出る。閉じたはずのウィンドウの操作が後から効く。

同じ削除が handleContextMenu 側（同ファイル :78 付近）にもある。

/code-review high の finder 2 本が独立に検出し、verifier は PLAUSIBLE（削除自体はコード参照で確定。実機での再現は未実施）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 await 後にウィンドウ（host）の生存を確認し、失われていれば `.external` を含むすべての分岐で処理を中断する
- [ ] #2 handleOpenReference と handleContextMenu の両方が同じ扱いになっている
- [ ] #3 host が失われた状態で解決が完了しても NSWorkspace が呼ばれないことをユニットテストで担保している
<!-- AC:END -->
