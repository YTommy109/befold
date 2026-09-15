---
id: TASK-619
title: >-
  GitStatusStoreTests.foldsConcurrentRequestsForSameRoot が CI の低速時にゲート予算 60
  秒を超えて失敗する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-13 08:10'
updated_date: '2026-09-15 09:42'
labels:
  - ci
  - test
dependencies: []
priority: medium
type: bug
ordinal: 809000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実測（2026-09-13、PR #658 の build-and-test run 34697491161）: `GitStatusStoreTests.swift:73` の `FakeReader.status: 同期待機が 60.0 秒で上限に達した` が 2 回記録され、テスト自体はその後「129 秒経過後に通過」したがランは失敗になった。同じテストは直前の main の緑ラン（run 34695167155）でも「88 秒経過後に通過」で、予算（BEFOLD_TEST_TIMEOUT_SECONDS=60）に対して余裕が無い。失敗ランは全体が 137 秒（緑ランは 90 秒）と遅く、macOS ランナーの低速化で露出した。手元では 9 テスト 0.016 秒で通る。

構造: 1 本目の要求を `FakeReader.status` の `BlockingGate` で足止めし、2 本目のルート解決（`withBlockingWork` 経由）が完了するのを `AsyncGate` で待ってから解放する。2 本目がルート解決へ到達するには MainActor の順番が必要で、並列に走る GUI 系スイートが MainActor を長く占有すると、1 本目の足止め側（60 秒予算）が先に切れる。**同一ランで他スイートの「passed after」が 111〜137 秒**だったことから、MainActor の輻輳が 60 秒を超えていた。

候補: (a) この足止め側の予算を「ランナーの輻輳」ではなく「畳み込みの検証」に見合う長さへ切り離す（FakeReader の block.wait に別の上限を渡す） (b) 2 本目のルート解決が MainActor を経由しない形に組み替える (c) このスイートを serialized にせず、GUI スイートと同時に走らせない。再現は CI の遅いランでしか起きないため、まず (a) で予算切れの誤検知を止める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じ構造の失敗（FakeReader.status の待機上限）が、MainActor を 60 秒以上塞ぐ他スイートと並走しても起きない（手元で MainActor を意図的に塞ぐテストを並走させて再現 → 対策後に通ることを実測）
- [x] #2 畳み込みの検証（reader が 1 回だけ呼ばれる）は変えない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 原因の再確認(実装済み): GitStatusStoreTests.foldsConcurrentRequestsForSameRoot は
   FakeReader.status を BlockingGate(release)で足止めし、2 本目の Task が
   resolveRepositoryRoot 経由で MainActor に復帰して secondRootResolved を開けるまで
   release.open() を呼ばない。release.wait の予算は BlockingGate.wait 内部の
   testTimeoutSeconds(fallback:) が BEFOLD_TEST_TIMEOUT_SECONDS(CI=60)を優先するため、
   MainActor がフルスイートの他スイートで輻輳して 60 秒を超えると、release.open() が
   呼ばれる前に release.wait 側が先に予算切れで Issue.record してしまう
   (テスト自体はその後 pass するが run は fail のまま)。

2. 単純化の検討: 候補は 3 つ(タスク記載の a/b/c)。
   - (b) ルート解決を MainActor 経由にしない: GitStatusStore の @MainActor 設計
     (WorktreeCatalog に倣ったキャッシュ+in-flight 管理)を崩す必要があり、
     1 テストの同期プリミティブのために本番設計へ手を入れることになる。却下。
   - (c) スイートを GUI 系と同時に走らせない: テストランナーのスケジューリングに
     踏み込む変更で影響範囲が広く、輻輳そのものは解消しない。却下。
   - (a) release.wait の予算を「輻輳への耐性」として BEFOLD_TEST_TIMEOUT_SECONDS
     から切り離す: 本番コードに触れず、待機が MainActor の順番待ちに支配される
     ケースで壁時計予算を env 由来にしない、という設計は
     waitForMainActorDelivery/waitForDeliveryOnMainActor(Waiting.swift)で
     既に採用済みの考え方の延長。BlockingGate.wait に最小限のオプション引数を
     足すだけで済み、他の 4 呼び出し箇所への影響はゼロ。→ (a) を採用(単純化の結果、
     追加の分岐は 1 箇所のオプション引数のみ)。

3. BlockingGate.wait(BlockingWait.swift) に `fixedBudget: Double? = nil` を追加。
   nil なら既存どおり testTimeoutSeconds(fallback:) を使う(他 4 箇所は無変更)。
   非 nil ならその秒数をそのまま上限にし、BEFOLD_TEST_TIMEOUT_SECONDS を無視する。

4. GitStatusStoreTests.foldsConcurrentRequestsForSameRoot の
   release.wait("FakeReader.status") に fixedBudget を渡す(輻輳の実測値
   111〜137 秒に対して十分な余裕を持たせる値)。GitCommandFileIndexConcurrencyTests
   の同種テストに倣い testTimeLimit() トレイトも付ける(戻らない回帰の最終防波堤)。

5. AC1 の実測: MainActor を意図的に 70 秒程度塞ぐ使い捨てテストを一時的に追加し、
   BEFOLD_TEST_TIMEOUT_SECONDS=60 で GitStatusStoreTests と並走させる。
   - 対策前: release.wait が 60 秒で Issue.record することを確認(再現)
   - 対策後: 同条件で foldsConcurrentRequestsForSameRoot が pass することを確認
   使い捨てテストは検証後に削除する。

6. AC2 の確認: 既存の #expect(reader.callCount == 1) がそのまま畳み込みの検証を
   担保している(変更なし)ことを確認。

7. 通常の swift test(BEFOLD_TEST_TIMEOUT_SECONDS 未設定)で GitStatusStoreTests
   全体を実行し、既存挙動に回帰がないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
進捗(実装は完了、検証が Xcode ライセンス未同意でブロック中):

- 実装: BlockingGate.wait(BlockingWait.swift) に fixedBudget: Double? パラメータを追加
  (nil なら既存どおり testTimeoutSeconds/BEFOLD_TEST_TIMEOUT_SECONDS を使う、非nilなら
  それを無視してそのまま上限にする)。GitStatusStoreTests.foldsConcurrentRequestsForSameRoot
  の release.wait に fixedBudget: 300 を渡し、testTimeLimit() トレイトを追加(TASK-619)。
- スコープを絞った実測(このセッションの前半、xcode ライセンス問題が起きる前):
  `swift test --filter "GitStatusStoreTests|BlockingWaitTests|BlockingWorkTests|GitCommandFileIndexConcurrencyTests"`
  で 16 件全 pass(0.357 秒)。AC2(#expect(reader.callCount == 1))は無変更のまま
  通っている。
- AC1(MainActor を 60 秒以上塞ぐ他スイートと並走させた実測)は未実施。
  検証用の使い捨てハーネス BefoldApp/befoldTests/Task619MainActorCongestionReproTests.swift
  (@MainActor で Thread.sleep(20秒) x4、検証後に削除する前提)を用意済み。
- ブロッカー: セッション中盤から `swift build` / `swift test` が
  `You have not agreed to the Xcode license agreements.`(exit 69)で失敗するようになった。
  `defaults read /Library/Preferences/com.apple.dt.Xcode.plist IDEXcodeVersionForAgreedToGMLicense`
  が 26.3 を返す一方 `xcodebuild -version` は Xcode 27.0 で、ライセンス同意がバージョン
  不一致。`sudo -n xcodebuild -license accept` は非対話シェルのためパスワード要求で失敗。
  ユーザーに `sudo xcodebuild -license` の対話実行を依頼済み、応答待ち。
- 再開時の手順: ライセンス同意後、
  1) BEFOLD_TEST_TIMEOUT_SECONDS=60 で `swift test --filter "GitStatusStoreTests|Task619MainActorCongestionReproTests"`
     を実行し、fixedBudget 付きの現状コードで pass することを確認
  2) 一時的に fixedBudget: 300 を外して(env 由来の予算に戻して)同条件で再現(Issue.record
     で fail)することを確認 → 対策前後の差分を実測として記録
  3) Task619MainActorCongestionReproTests.swift を削除
  4) 通常の swift test(env 変数無し)で GitStatusStoreTests 全体に回帰が無いことを確認

検証ブロッカーの深掘り(このセッションで試行し、すべて不成立と確認済み):

1. `swift build`/`swift test`(既定の Xcode.app トolchain)は exit 69
   「You have not agreed to the Xcode license agreements」でコマンド起動の時点
   (`swift build --help` や `swift --version` すら)で即失敗する。
   `defaults read /Library/Preferences/com.apple.dt.Xcode.plist
   IDEXcodeVersionForAgreedToGMLicense` は 26.3 を返すが `xcodebuild -version` は
   Xcode 27.0 / macOS 27.0(26A428) — セッション中盤で Xcode がこのバージョンへ
   上がり、ライセンス同意が追いついていない状態と判断。`sudo -n xcodebuild -license
   accept` / `sudo -n -v` はいずれも「a password is required」で非対話実行不可。
2. `DEVELOPER_DIR=/Library/Developer/CommandLineTools`(別途インストール済みの単体
   Command Line Tools)へ切替えるとライセンス連動は回避できる(`swift --version` は
   通る)が、`swift build`(既定の swiftbuild/XCBuild)は
   `Could not initialize build system ... Unknown error parsing property list`
   で失敗。`--build-system native` に切り替えると先へ進むが、今度は
   SwiftLintBuildToolPlugin の PrebuildCommand が
   `SourceKittenFramework/library_wrapper.swift:58: Fatal error: Loading
   sourcekitdInProc.framework/Versions/A/sourcekitdInProc failed`(SIGTRAP)で
   落ちる。ベンダリング済み SwiftLintBinary(0.65.0)を単体実行しても
   (`swiftlint lint` を直接叩いても)同じクラッシュを再現、`~/Library/Logs/
   DiagnosticReports/swiftlint-*.ips` にも記録あり。グローバルキャッシュの
   SwiftLintBinary.artifactbundle.zip は 2026-06-29 時点のもので今回のセッションの
   影響ではない(=このマシンの Xcode 27.0 と同梱 SwiftLintBinary の組み合わせが
   壊れている可能性)。
3. Package.swift から SwiftLintBuildToolPlugin の参照を一時的に全ターゲットから
   外して(検証後に原状復帰済み、コミット差分ゼロを確認済み)同条件で再ビルドすると
   sourcekit のクラッシュは回避できるが、CLT トolchain では befold(本体アプリ、
   SwiftUI)側で `external macro implementation type 'SwiftUIMacros.StateMacro'
   could not be found` が多数出て止まる(CLT には SwiftUI のマクロプラグインが
   無い)。befoldTests は "befold" に依存するため、この経路でも
   GitStatusStoreTests まで到達できない。
4. 以上で「ライセンス未同意を Xcode.app 側で解消する」以外に取れる非対話の回避策が
   無いことを確認した。`sudo xcodebuild -license`(対話実行、パスワード入力)を
   ユーザーに依頼中。応答待ち。

このブロッカーは TASK-619 のコード変更(BlockingGate.wait への fixedBudget 追加、
GitStatusStoreTests への適用)とは無関係な、セッション環境側の状態変化
(Xcode バージョンとライセンス同意のずれ)によるもの。

AC1 実測完了(環境ブロッカーの回避策として、独立パッケージでの等価再現による):

本体の `swift test`(befoldTests)は引き続き Xcode ライセンス未同意(exit 69)で
実行不可(CLT トolchain は SwiftUI マクロプラグイン未解決で befold 本体をビルドできず、
befoldTests は befold に依存するため経路が無い)。ユーザーの sudo 対応待ちを継続する一方、
BlockingGate.wait/AsyncGate の実装をそのまま(1 行も変えず)コピーし、
GitStatusStoreTests.foldsConcurrentRequestsForSameRoot と同一の配線
(release で足止めされた別スレッドの wait ⇔ MainActor の順番待ちを経て
secondRootResolved を開く 2 本目)を再現する独立 SPM パッケージを
BefoldApp 外(スクラッチパッド)に作り、CLT toolchain(SwiftUI/SwiftLint 依存が
無いため building 可能)で実行した。

実測(BEFOLD_TEST_TIMEOUT_SECONDS=60、MainActor を 4 本のホグで計 70.0 秒塞ぐ):
- 対策前(fixedBudget 無し、env 由来の 60 秒予算): secondRootResolved が開くまでに
  70.0 秒かかり、release.wait は 60.0 秒で先に timeout(TIMED OUT) → FAIL
  (実際の CI 障害と同じ「MainActor 輻輳 > 予算」の構造を再現)
- 対策後(fixedBudget: 300): 同じ 70.0 秒の輻輳でも release.wait は timeout せず
  正常に開いた → PASS

ログは .tmp/task619-ac1-repro.log(gitignore 済み、コミットしない)。独立パッケージの
ソースはスクラッチパッド配下(BefoldApp/リポジトリ本体には一切変更なし)。
本体コード(BlockingWait.swift 側の実装)とテスト(GitStatusStoreTests.swift)は
このコピー元と完全一致していることを diff で確認済み。

使い捨てハーネス Task619MainActorCongestionReproTests.swift は上記の独立再現で
代替できたため削除済み(git status で追跡外を確認)。

AC2(畳み込みの検証・reader.callCount==1)は変更前から実装済みの
#expect(reader.callCount == 1) がそのまま担保しており、今回のセッション前半の
スコープ限定実行(GitStatusStoreTests 全 10 件 pass、0.002 秒)でも確認済み。

残タスク: Xcode ライセンス同意が得られ次第、本体の
`swift test --filter GitStatusStoreTests` で最終確認し、通常の全体テストにも
回帰が無いことを見る(念のための二重確認。AC1/AC2 の実測自体は上記で成立済み)。

ユーザー判断: ライセンス対応(sudo xcodebuild -license)を待ってから本体の swift test で最終確認し、その後 Done にする方針を確認済み(2026-09-15)。それまでは In Progress のまま保留。

ライセンスはユーザー対応後に解消した(IDEXcodeVersionForAgreedToGMLicense が 27.0 に更新)。
しかし本体の `swift test --filter GitStatusStoreTests` は別の理由で依然実行不可と判明:

このセッション中に(ライセンス再同意を要求されたのと同じタイミングで)ローカル環境の
Xcode が Swift 6.3.3(Target macosx28.0)から Swift 6.4(Target macosx27.0.0)へ
入れ替わっていた(`xcodebuild -version` は終始 Xcode 27.0 build 27A266a だが、
内部の swift ツールチェーンのバージョン表示が変わった)。この新しいコンパイラは
`nonisolated static func main()` に対して「main() must be '@MainActor'」を要求するように
なっており、`befold/App/AppDelegate.swift:73`(TASK-619 と無関係な既存コード、
`nonisolated static func main()`)でビルドが失敗する。befoldTests は "befold" に
依存するため、これが解消しない限り GitStatusStoreTests も実行できない。

CI(.github/workflows/ci.yml)は `xcode-version: '26.5'` / `runs-on: macos-26` に
固定されており、このローカルサンドボックスの Xcode 27.0(未固定・恐らく自動更新)とは
別バージョン。CI は現行 main(a2a6f830)で green(run 34947568166)であることを確認済み
なので、ここで踏んだ主要因はローカル環境が CI のピン留めバージョンより新しい未検証の
Xcode に上がってしまったことであり、TASK-619 のコード変更にもこのセッションの他の
作業にも起因しない。AppDelegate.swift の修正は明確にスコープ外(TASK-619 は
GitStatusStoreTests の flaky 修正であり main() の @MainActor 化は無関係な別件)なので
行わない。

結論: このローカルサンドボックスでは CI 相当の環境が再現できず、実機での
`swift test --filter GitStatusStoreTests` 実行は継続困難。AC1 の実測は独立パッケージでの
等価再現(対策前 FAIL・対策後 PASS、.tmp/task619-ac1-repro.log)を正とする。
ユーザーに最終判断を確認する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BlockingGate.wait(BefoldTestSupport/BlockingWait.swift)に fixedBudget: Double? を追加し、
GitStatusStoreTests.foldsConcurrentRequestsForSameRoot の release.wait(FakeReader.status)
に fixedBudget: 300 を指定(+ testTimeLimit() トレイト)。この待機は「git 実行の模した
遅さ」ではなく「2 本目の要求が MainActor の順番待ちを経て secondRootResolved を開くまで」
に支配されるため、CI 輻輳に連動する BEFOLD_TEST_TIMEOUT_SECONDS から切り離した
(waitForMainActorDelivery が同種の待機で壁時計予算を env に持たせない設計を踏襲)。
BlockingGate の他 4 呼び出し箇所は fixedBudget 省略で無変更。

検証:
- AC2(畳み込み: reader.callCount==1)はセッション前半にローカル swift test
  (GitStatusStoreTests 全 10 件・BlockingGate 系含め 16 件)で実測 pass。
- AC1(MainActor を 60 秒超塞ぐ輻輳下でも誤検知しない)は、ローカル環境が途中で
  Xcode 27.0/Swift 6.4 へ変わり CI 固定版(Xcode 26.5)と食い違い、無関係な既存コード
  (AppDelegate.swift の main())でビルド不能になったため、本体の swift test では
  最終実測できなかった。代わりに BlockingGate/AsyncGate の実装をそのままコピーした
  独立 SPM パッケージで同一配線を再現し、BEFOLD_TEST_TIMEOUT_SECONDS=60・MainActor を
  70.0 秒塞ぐ条件で実測: 対策前(env 由来予算)は 60.0 秒で timeout(FAIL、CI 障害と
  同型)、対策後(fixedBudget: 300)は timeout せず正常終了(PASS)。ログは
  .tmp/task619-ac1-repro.log(gitignore 済み)。
- CI(main, a2a6f830, run 34947568166)は green を確認済みで、ローカルのビルド不能は
  TASK-619 の変更と無関係(サンドボックス側の Xcode バージョンずれ)と判断。
<!-- SECTION:FINAL_SUMMARY:END -->
