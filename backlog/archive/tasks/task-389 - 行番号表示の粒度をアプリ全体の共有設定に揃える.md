---
id: TASK-389
title: 行番号表示の粒度をアプリ全体の共有設定に揃える
status: To Do
assignee: []
created_date: '2026-08-09 10:12'
updated_date: '2026-08-09 10:31'
labels: []
dependencies:
  - TASK-382
priority: medium
type: bug
ordinal: 516000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002 の「状態の所在」の基準（TASK-382 で追加）を当てた結果の逸脱。

行番号表示は ViewerStore.showLineNumbers（BefoldApp/befold/Viewer/ViewerStore.swift:177-188）が窓ごとのライブ値として持ちつつ、didSet でアプリ全体キー ShowLineNumbers へ永続化している。粒度が 2 つに割れている。

基準では「利用者の好みに属する状態」（どのファイルかに依らない見え方の設定）であり、SidebarDisplayPreference / DiffDisplayPreference / CodeFontPreference / FindOptionsPreference と同じく **アプリ全体で 1 インスタンスを注入して共有する** 形になるはず。実際には各ウィンドウが自分の Bool を持つため、窓 A で切り替えても窓 B は変わらず、B の再生成時に defaults を読み直して初めて揃う。

参考実装: DiffDisplayPreference.swift（イニシャライザに既定値を持たせず、渡し忘れが静かに窓ごとインスタンスへ落ちないようにしている。同型の不具合が TASK-319）。

設計で決めること:
- LineNumberPreference 相当の共有クラスへ移すか、既存の SidebarDisplayPreference のような preference へ相乗りさせるか
- CLI のパス無し起動オプション（ViewerWindowManager.applyDisplayOverrides の applyShowLineNumbersOverride）が全窓へ適用している経路との整合
- 既存の UserDefaults キー ShowLineNumbers はそのまま使えるため移行は不要と見込まれるが、CLAUDE.md「UserDefaults キーの廃止・改名」の節に照らして確認する

着手前に /review-design を回すこと（値の持ち方を変える変更のため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 行番号表示を 1 つのウィンドウで切り替えると、他のウィンドウにも即座に反映される
- [ ] #2 アプリ全体で 1 インスタンスという粒度が破れたら落ちるテストがある（窓ごとに別インスタンスが生成されたら失敗する）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
取り下げ（2026-08-09）。起票の前提だった「行番号表示は利用者の好みだから全窓で共有されるべき」という分類が、TASK-382 の再検討で置き換わった。新しい原則『窓が生きている間はその窓のライブ値が有効で、閉じると保存値（次に開くときの既定）に戻る』では、現状の実装（ViewerStore.showLineNumbers が窓ごとのライブ値、didSet でアプリ全体キー ShowLineNumbers へ既定値として保存）がまさにその形であり、逸脱ではなく模範例にあたる。修正すべきものは無い。
<!-- SECTION:NOTES:END -->
