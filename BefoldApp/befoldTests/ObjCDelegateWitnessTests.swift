import AppKit
@testable import befold
@testable import BefoldRenderKit
import Testing

/// optional なデリゲートメソッドの selector が Objective-C へ公開されていること。
///
/// 署名が SDK の宣言とずれると(例: closure の actor 注釈)、コンパイラは `nearly matches` の警告を
/// 出すだけでビルドは通り、呼ばれなくなる。警告は SDK ごとに違うため、CI の Xcode では出ないことがある
/// (実測: `decisionHandler` は SDK 26.5 では公開され、SDK 27.2 では公開されなかった)。
/// Swift から直接呼ぶテストはこの状態でも通るので、公開の事実そのものを測る。
///
/// デリゲートのメソッドを足したらここへ足す。`override` と required は、ずれるとビルドが落ちるので対象外。
@Suite
struct ObjCDelegateWitnessTests {
    /// `decidePolicy` は `WebKitSurfaceEventBridgeMappingTests` が測る。
    @Test(
        "WebKit のデリゲート",
        arguments: [
            "webView:didFinishNavigation:",
            "webView:didFailNavigation:withError:",
            "webView:didFailProvisionalNavigation:withError:",
            "webViewWebContentProcessDidTerminate:",
        ]
    )
    func webKitNavigationDelegate(selector: String) {
        #expect(WebKitSurfaceEventBridge.instancesRespond(to: NSSelectorFromString(selector)))
    }

    @Test("通知センターのデリゲート")
    func notificationCenterDelegate() {
        #expect(AppDelegate.instancesRespond(
            to: NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
        ))
    }

    @Test("Sparkle のデリゲート")
    func updaterDelegate() {
        #expect(AppUpdaterController.instancesRespond(to: NSSelectorFromString("feedURLStringForUpdater:")))
    }
}
