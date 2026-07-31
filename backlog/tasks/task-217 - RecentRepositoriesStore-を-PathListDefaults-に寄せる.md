---
id: TASK-217
title: RecentRepositoriesStore を PathListDefaults に寄せる
status: Done
assignee: []
created_date: '2026-07-31 07:43'
updated_date: '2026-07-31 08:22'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/RecentRepositoriesStore.swift
  - BefoldApp/BefoldKit/PathListDefaults.swift
priority: low
ordinal: 297000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-210 で SessionStore / BookmarkStore / RecentDocumentsStore の UserDefaults パス配列ボイラープレートを BefoldKit の PathListDefaults に共通化したが、RecentRepositoriesStore は当時のスコープ外だったため旧来の「stringArray(forKey:) ?? [] → normalizedPathKey で操作 → set(_:forKey:)」を自前で持ったまま残っている。共通基盤が既にあるのに 1 ストアだけ外れている状態は、TASK-210 が防ごうとした「新ストア追加時の rename 反映漏れ」の余地をそのまま残す。PathListDefaults に寄せて 4 ストアすべてを同じプリミティブの合成に揃える。着手前に PR #356 (TASK-210) がマージ済みであることを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RecentRepositoriesStore が PathListDefaults を合成する形になり、パス配列の load/save/追加/rename の自前実装が消える
- [ ] #2 既存のドメイン API と挙動が変わらない（既存テストが通る）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
【対応不要と判断・実装なし】タスク登録時の前提が実コードと一致しないことが確認できたため、コード変更・コミットともに行っていない。RecentRepositoriesStore の永続化は [RecentRepositoryEntry]（Codable: rootPath / label / lastTabGroup）を JSONEncoder で encode し defaults.set(data:forKey:) する形式であり、TASK-210 が共通化した stringArray(forKey:) ?? [] 系とは保存フォーマットが別物。プロダクトコードで stringArray(forKey:) を使うのは PathListDefaults.swift:28 のみで、取り残された自前実装は存在しない。rename 反映 API も持たない（ルートはディレクトリのため rename 追従対象外）ので、本タスクの動機だった rename 反映漏れリスクも当てはまらない。寄せる方法は (1) 保存フォーマットを文字列配列へ変更（既存ユーザーの lastTabGroup が失われ挙動不変に反する）(2) Codable 版プリミティブを新設（利用者 1 ストアの抽象が増えるだけで単純化にならない）の 2 案しかなく、いずれも AC を満たさない。バックログ登録時に TASK-210 の報告を実コードで検証しなかったことが原因。
<!-- SECTION:NOTES:END -->
