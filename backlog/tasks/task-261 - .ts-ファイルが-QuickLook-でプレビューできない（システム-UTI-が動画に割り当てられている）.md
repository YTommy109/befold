---
id: TASK-261
title: .ts ファイルが QuickLook でプレビューできない（システム UTI が動画に割り当てられている）
status: To Do
assignee: []
created_date: '2026-08-02 15:07'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 455000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finder のスペースキー（QuickLook）で .ts ファイルをプレビューしても befold の QuickLook 拡張が担当せず、ソースコードとして表示されない。アプリ本体で開く経路は拡張子ベース（FileType）のため正常に表示される。

原因: macOS は .ts を public.mpeg-2-transport-stream（MPEG-2 トランスポートストリーム＝動画）に分類する。

    $ mdls -name kMDItemContentType site/src/lib/visitor.ts
    kMDItemContentType = "public.mpeg-2-transport-stream"
    → 継承ツリーは public.movie / public.audiovisual-content 配下

befold/Info.plist は com.degino.befold.source-code の UTTypeTagSpecification に "ts" を宣言しているが、システム宣言の UTI が優先されるため上書きできない。QuickLook 拡張の QLSupportedContentTypes は public.source-code 系のみを列挙しており、public.movie 配下の UTI には適合しないため拡張が呼ばれない。

宣言済み拡張子を総当たりで確認したところ、システム UTI が public.source-code 系に適合しないのは .ts のみ（.tsx は com.microsoft.typescript、.bash は public.bash-script、.zsh は public.zsh-script などでいずれも適合する）。

QLSupportedContentTypes に public.mpeg-2-transport-stream を追加すれば .ts は拾えるが、本物の .ts 動画ファイル（トランスポートストリーム）まで befold が担当してしまうトレードオフがある。拡張子と内容の両面から判断する必要があるため、対応方針は着手時に検討する（対応しないという結論も可）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .ts ファイルを Finder のスペースキーでプレビューしたときの挙動が決定され、方針が Implementation Notes に記録されている
- [ ] #2 対応する場合: TypeScript の .ts が befold の QuickLook でソースコードとして表示される
- [ ] #3 対応する場合: 実際の MPEG-2 トランスポートストリーム動画を befold が壊れた形で奪わない
- [ ] #4 見送る場合: 理由（動画 UTI との衝突）が記録され、アプリ本体では表示できることが判明する形で閉じられる
<!-- AC:END -->
