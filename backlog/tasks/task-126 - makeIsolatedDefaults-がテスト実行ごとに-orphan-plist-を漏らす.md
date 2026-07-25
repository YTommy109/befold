---
id: TASK-126
title: makeIsolatedDefaults がテスト実行ごとに orphan plist を漏らす
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-24 22:22'
updated_date: '2026-07-25 03:36'
labels:
  - test
  - bug
dependencies: []
priority: medium
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。BefoldTestSupport/IsolatedDefaults.swift:9 の makeIsolatedDefaults は呼び出しごとに一意な永続 UserDefaults ドメイン("<prefix>-<UUID>")を作るが、テスト後に削除しない。removePersistentDomain は作成時にのみ呼ばれ、新規ランダム名に対しては no-op。
swift test 1 回ごとに数十個の orphan plist(例: CLIBookmarkCommandTests-3F2A...plist)が ~/Library/Preferences に堆積し、開発を続けるほど cfprefsd を劣化させる。クリーンアップ経路がない。既に 8 万個以上の堆積が確認されている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テスト終了時に作成した UserDefaults ドメインの plist が削除される(deinit/teardown 等の仕組み)
- [x] #2 既存の堆積 plist を掃除する手段(スクリプトまたは初回実行時掃除)を提供する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
【当初計画から変更あり。実測に基づき方針を差し替えた】

現状確認: ~/Library/Preferences に UUID 付き plist が 189,656 個(約 750MB)堆積。makeIsolatedDefaults の呼び出しは 110 箇所以上。

0. 単純化検討と実測:
   (a) 返り値をラッパー型にして deinit で削除 / withIsolatedDefaults のクロージャ形 → 呼び出し 110 箇所以上の書き換えが必要。不採用。
   (b) 呼び出しごとに以前のスイートを削除 → swift-testing の並行実行で使用中のスイートを壊す。不採用。
   (c) 登録簿 + atexit でプロセス終了時に一括削除 → 実装して実測したところ不安定(1 回目 delta 166、2 回目 delta 2)。原因を切り分けるため 50 スイートを作って atexit で削除する検証を行い、t=0 で 50/50 削除できるが t=+2s で 50/50 復活することを確認した。cfprefsd がプロセス終了後に永続ドメインを書き戻すため、ディスク上のドメインを使う限りこの競合には勝てない。不採用。
   (d) 採用: 永続ドメインを作ること自体をやめ、UserDefaults のサブクラス(メモリ上の辞書)を返す。plist が生成されないため後始末が不要になり、競合も起きない。makeIsolatedDefaults のシグネチャは変えないため呼び出し箇所の変更はゼロ。

1. BefoldTestSupport/IsolatedDefaults.swift の makeIsolatedDefaults を InMemoryUserDefaults を返す実装にする。Apple の規約どおりプリミティブメソッド(object(forKey:) / set(_:forKey:) / removeObject(forKey:) / dictionaryRepresentation())を上書きし、型付きセッター(Bool/Int/Double/Float/URL)も明示的に塞ぐ(setObject:forKey: を経由する保証がなく、取りこぼすと利用者の実際の設定を汚しうるため)。
2. befoldTests/IsolatedDefaultsTests.swift を追加し、独立性・型付きの往復・既定値・削除・plist を作らないこと・共有スイートへ漏れないことを検証する。
3. AC#2: scripts/clean-test-defaults.sh を追加する。~/Library/Preferences 直下の「<接頭辞>-<正準形式の UUID>.plist」のみを対象とし(実在のドメインは逆 DNS 形式で UUID 接尾辞を持たない)、既定は dry-run、--force で実削除。数万件でも実用的な速度で動くよう走査は 1 回に限定する。
4. 検証: swift test 前後の plist 件数が増えないことを連続実行で確認する。既存堆積はスクリプトで掃除する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
- BefoldTestSupport/IsolatedDefaults.swift: makeIsolatedDefaults が UserDefaults のサブクラス InMemoryUserDefaults(NSLock 保護の辞書)を返すようにした。永続スイートを作らないため plist が生成されない。シグネチャは据え置きのため呼び出し 110 箇所以上は無変更。prefix 引数は呼び出し箇所の可読性のために残し、格納先には影響しない。
- 上書きしたメソッド: object(forKey:) / set(_:forKey:) / removeObject(forKey:) / dictionaryRepresentation() / synchronize() に加え、型付きセッター set(Bool/Int/Double/Float/URL?)。型付きセッターが setObject:forKey: を経由する保証がなく、取りこぼすと利用者の実際の設定ドメインを汚しうるため明示的に塞いだ。
- befoldTests/IsolatedDefaultsTests.swift を追加(7 件)。
- scripts/clean-test-defaults.sh を追加(dry-run 既定、--force で実削除)。

AC#1 の達成方法について: 受け入れ基準の文面は「テスト終了時に削除する(deinit/teardown 等)」だが、この方式は OS の挙動により成立しないことを実測で確認したため、「そもそも作らない」方式で満たしている。根拠として、50 スイートを作って atexit で removePersistentDomain + ファイル削除を行う検証を実施し、t=0 では 50/50 削除できるが t=+2s には 50/50 が復活することを確認した(cfprefsd がプロセス終了後に永続ドメインを書き戻す)。実際に atexit 方式を実装して swift test を回した際も delta が 166 → 2 → 141 → 176 と不安定だった。

検証:
- swift test を連続 2 回実行し、いずれも plist の増加数 delta 0(189,656 個のまま変化なし)。従来は 1 回あたり約 150〜170 個増えていた。
- swift test: 622 tests / 87 suites passed(IsolatedDefaultsTests 7 件を含む)。
- swiftformat --lint: 全ターゲット 0 files require formatting。
- scripts/clean-test-defaults.sh の dry-run が 189,656 個を検出し、接頭辞ごとの内訳を表示することを確認(実行時間 約 6 秒)。
<!-- SECTION:NOTES:END -->
