@testable import befold
import BefoldKit
import Foundation
import Testing

/// ヘルプ系パネルが表示するバンドル同梱リソースの所在を固定する。
///
/// どちらの画面もリソースが引けなければ失敗文言に縮退するだけで、画面自体は開いてしまう。
/// リソース定義（Package.swift / project.yml）の取りこぼしが手動で開くまで気付けないため、
/// 「引けること」をテストで押さえる。描画そのものは自動テスト対象外（手動チェック）。
struct HelpPanelResourceTests {
    @Test("OSS 謝辞の Markdown がバンドルから引ける")
    func licensesMarkdownIsBundled() throws {
        let url = try #require(
            Bundle.befoldKitResources.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md")
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.isEmpty)
        // レンダリング経路は拡張子で種別を決めるため、Markdown として扱われることも確かめる。
        #expect(FileType(url: url) == .markdown)
    }

    @Test("AI 連携画面の skill ファイルがバンドルから引ける")
    func reviewSkillIsBundled() throws {
        let url = try #require(
            Bundle.appResources.url(forResource: "befold-review-skill", withExtension: "md")
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        // コピーボタンが載せる内容。skill として成立する最低限（front matter の name）を確認する。
        #expect(text.contains("name: befold-review"))
    }

    /// コピーボタンが載せるのは skill ファイル本体であって、画面の説明文や
    /// 保存先パスの手順ではない。クリップボードの中身そのものは GUI 操作を伴うため
    /// 手動チェックに委ね、ここでは「何をコピー対象に選んでいるか」を固定する。
    @MainActor
    @Test("AI 連携画面が保持するコピー対象は skill ファイル本体そのもの")
    func copyTargetIsTheSkillFileItself() throws {
        let url = try #require(
            Bundle.appResources.url(forResource: "befold-review-skill", withExtension: "md")
        )
        let expected = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(AIIntegrationView().exampleSkill == expected)
    }
}
