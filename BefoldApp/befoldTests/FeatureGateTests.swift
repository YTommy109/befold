@testable import befold
import Testing

/// 開発中機能のゲート判定（dev/DEBUG のみ ON）を検証する。
@Suite
struct FeatureGateTests {
    @Test("dev バージョンなら有効（DEBUG でなくても）")
    func enabledForDevVersion() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10-dev.1", isDebugBuild: false) == true)
    }

    @Test("stable バージョンかつ非 DEBUG なら無効")
    func disabledForStableRelease() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10", isDebugBuild: false) == false)
    }

    @Test("DEBUG ビルドなら stable バージョンでも有効")
    func enabledInDebugBuild() {
        #expect(FeatureGate.inProgressFeaturesEnabled(version: "1.4.10", isDebugBuild: true) == true)
    }
}

/// 機能ごとの名前付きプロパティが、共通の判定と同じ値を返すことを確かめる。
/// 露出点を足すときにこのプロパティ経由であることを崩さないための歯止め。
@Suite
struct FeatureGateNamedPropertyTests {
    @Test("文書内ジャンプのゲートは共通判定と一致する")
    func documentJumpMatchesCommonGate() {
        #expect(FeatureGate.isDocumentJumpEnabled == FeatureGate.inProgressFeaturesEnabled)
    }
}
