import AppKit
import BefoldCLI
import BefoldKit

/// `/usr/local/bin/befold`(CLI シム)の状態チェックと設置、およびその結果案内。
/// 状態を持たないため名前空間として置く。
enum CLIShimCoordinator {
    /// 起動時に一度だけ /usr/local/bin/befold の状態を読み取り専用でチェックし、
    /// 古い実体ファイル/参照先不一致の symlink が残っている場合のみ再インストールを案内する。
    /// 書き込み(再インストール自体)は行わない。
    ///
    /// 状態チェックのファイル I/O はバックグラウンドキューへ逃がし、起動処理(ウィンドウ復元・
    /// メニュー構築)をブロックしない。案内も app-modal な `runModal()` ではなく通知センターの
    /// バナー通知で表示し、表示中も CLI 転送の ACK 応答が main run loop 上で通常どおり
    /// 処理され続けるようにする。
    ///
    /// Debug ビルドでは何もしない。判定は symlink の参照先と「起動中のアプリの bundlePath」の
    /// 文字列一致で行うため、DerivedData や .build 配下から起動する開発ビルドでは、
    /// `/usr/local/bin/befold` が正しくリリース版を指していても必ず staleSymlink に見える。
    /// 開発中に毎回出る誤検知でしかないので、案内自体をリリースビルドに限る。
    @MainActor
    static func notifyIfStale() {
        #if DEBUG
            return
        #else
            let bundlePath = Bundle.main.bundlePath
            // App Translocation 下では bundlePath がランダム化された一時マウントを指すため、
            // 正しく設置済みの symlink でも参照先不一致(staleSymlink)に見えてしまう。
            // ここで案内しても再インストールは translocatedBundle で断られるだけなので黙る。
            guard !CLIInstaller.isTranslocated(bundlePath: bundlePath) else { return }
            DispatchQueue.global(qos: .utility).async {
                let status = CLIShimInspector.status(
                    bundlePath: bundlePath,
                    installPath: CLIInstaller.defaultInstallPath
                )
                guard status == .legacyFile || status == .staleSymlink else { return }
                Task { @MainActor in
                    await CLIInstallUI.presentReinstallRecommended()
                }
            }
        #endif
    }

    /// メニューの「Install 'befold' command in PATH」。/usr/local/bin に CLI コマンドの symlink を設置する。
    ///
    /// 書き込みは管理者認証(AppleScript の `with administrator privileges`)へフォールバックしうる。
    /// 認証ダイアログはユーザーがパスワードを入力し終えるまで戻らないため、メインアクターで待つと
    /// その間 CLI 転送の ACK 応答まで止まる。設置処理そのものをメインアクター外へ逃がし、
    /// 結果の案内だけを戻ってから出す(NSAppleScript の生成・実行はどちらも同じ detached タスク内で
    /// 完結するため、単一スレッドからの利用という前提は保たれる)。
    @MainActor
    static func install() {
        let installPath = CLIInstaller.defaultInstallPath
        let bundlePath = Bundle.main.bundlePath
        Task {
            let result = await withBlockingWork(qos: .userInitiated) {
                CLIInstaller.install(bundlePath: bundlePath, installPath: installPath)
            }
            presentInstallResult(result)
        }
    }

    @MainActor
    private static func presentInstallResult(_ result: Result<Void, CLIInstallError>) {
        switch result {
        case .success:
            CLIInstallUI.presentInstallSucceeded()
        case .failure(.translocatedBundle):
            // 書き込み権限の問題ではないため、再試行を促す汎用の失敗案内では解決に導けない。
            CLIInstallUI.presentInstallBlockedByTranslocation()
        case .failure(.writeFailed):
            CLIInstallUI.presentInstallFailed()
        }
    }
}
