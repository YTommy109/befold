import Foundation

/// git 実行の結果。
///
/// 「git が動いて出した答え」と「git を動かせなかった」を区別するために分けている。
/// 両方を nil に潰すと、呼び出し元は「リポジトリ外」という確定した答えと
/// 「タイムアウトで不明」を取り違え、後者をキャッシュして機能を殺してしまう。
enum GitCommandOutcome: Sendable, Equatable {
    /// 正常終了。標準出力の内容。
    case output(Data)
    /// 実行できたが非 0 終了(リポジトリ外での rev-parse など)。答えとして確定している。
    case rejected
    /// 起動できない・タイムアウトで打ち切った。答えは不明。
    case unavailable
}

/// git コマンド実行を一元化する薄い Process ラッパ。
/// git を呼ぶ全機能(パス解決・将来のブランチ/差分)の共通土台。
struct GitCommandRunner: Sendable {
    /// git 1 回あたりの上限時間。超えたらプロセスを終了させ、他のエラーと同じく nil に倒す。
    /// 応答しないネットワークファイルシステム上のリポジトリなどで git が返ってこないと、
    /// 呼び出し元 (GitCommandFileIndex) は共有ロックを掴んだまま止まり、
    /// 別リポジトリを開いた他ウィンドウのパス解決まで巻き添えで止まるため、必ず打ち切る。
    let timeout: TimeInterval

    init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    /// 全 git 呼び出しに前置する無害化オプション。
    ///
    /// befold は信頼できないソースのファイルを開くことが仕事のアプリであり、git は
    /// 「今開いた文書のディレクトリ」を作業ディレクトリにして実行される。そのツリーに
    /// `core.fsmonitor` を設定した `.git/` が同梱されていると、`git ls-files` がその値を
    /// コマンドとして実行してしまう(`.git/` 入りの zip を展開して中の .md を開くだけで
    /// 任意コマンド実行になる。所有者は展開したユーザー自身なので `safe.directory` は効かない)。
    /// リポジトリ側の設定で上書きできないよう、コマンドラインの `-c` で常に空へ潰す。
    /// `core.hooksPath` は現在使う 2 コマンド(rev-parse / ls-files)では起動しないが、
    /// 将来 git 呼び出しを増やしたときの既定を安全側へ倒すため同時に無効化する。
    /// befold は読み取り専用ビューアなのでフックを必要とする用途は無い。
    /// `--no-pager` も同じ先回りで、ページャという外部プロセスの起動経路自体を塞ぐ
    /// (標準出力が pipe の現在は起動しないが、それは呼び出し形態に依存する性質のため)。
    ///
    /// `core.fsmonitor` を `false` ではなく空文字にするのは、値の解釈が git のバージョンで
    /// 変わるため。2.37 以降は真偽値だが、それ以前は監視フックのパスであり、`false` は
    /// 相対パス扱いになる = リポジトリに同梱された `false` という実行ファイルを起動しうる
    /// (塞ぎたい攻撃そのもの)。空文字はどちらの解釈でも「無効」に落ちる。
    static let hardeningOptions = [
        "--no-pager", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null",
    ]

    /// git へ渡す実引数列。無害化オプションが確実に前置されることを
    /// テストから固定できるよう、組み立てをここへ切り出す。
    static func processArguments(for args: [String]) -> [String] {
        hardeningOptions + args
    }

    /// git へ渡す環境変数。呼び出し元の環境は引き継がない。
    ///
    /// `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_*` や `GIT_DIR` のような GIT_* 変数は
    /// コマンドラインの `-c` と同等以上に効くため、継承したままでは上の無害化を素通しできる。
    /// `PATH` を固定するのも同じ理由(CLI から起動したインスタンスはユーザーのシェルの
    /// PATH を引き継ぐため、書き込み可能なディレクトリが先頭にあると偽の git を掴む)。
    /// `HOME` だけは残す。ユーザー自身の `~/.gitconfig` は信頼できる設定であり、
    /// 落とすと git が意図しない既定へ倒れるため。
    static func processEnvironment() -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            // 資格情報の入力待ちで止まらないようにする(端末を持たないので応答できない)。
            "GIT_TERMINAL_PROMPT": "0",
        ]
    }

    /// git を同期実行して標準出力を返す。標準エラーは捨てる。
    func run(_ args: [String], in workingDirectory: URL? = nil) -> GitCommandOutcome {
        let process = Process()
        // PATH 解決を挟まず実体を直接起動する。GUI 起動時に `/usr/bin/env git` が
        // 解決するのも同じ /usr/bin/git だが、PATH を差し替えられる余地を残さない。
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = Self.processArguments(for: args)
        process.environment = Self.processEnvironment()
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // 標準入力を待って止まらないよう明示的に閉じておく(ビューアは何も送らない)。
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .unavailable }

        // 読み取りは別スレッドで行い、呼び出し元は timeout までしか待たない。
        // readDataToEndOfFile を呼び出しスレッドで回して watchdog から terminate() する形だと、
        // git が孫プロセス(フック/エイリアス経由の子)へ標準出力を渡していた場合に
        // git を殺しても pipe が閉じず、結局 timeout が効かない。
        let output = OutputBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            output.set(status: process.terminationStatus, data: data)
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            // 打ち切りは呼び出し元(索引のロックを持つ)を解放するだけに留め、読み取り端は閉じない。
            // 読み取りスレッドは孫プロセスが標準出力を離すまで残りうるが、閉じる方が危険:
            // read に入る前に閉じると EBADF で `NSFileHandleOperationException` が飛び、
            // Swift からは catch できないのでプロセスごと落ちる。閉じた fd 番号が別の
            // ファイルへ再利用されれば無関係な読み取りまで壊す。しかも read 中の close は
            // Darwin では読み取りを中断しないため、解放したいスレッドは結局残る。
            process.terminate()
            return .unavailable
        }
        return output.outcome()
    }

    /// 読み取りスレッドから呼び出しスレッドへ結果を渡すだけの小箱。
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var data = Data()

        func set(status newStatus: Int32, data newData: Data) {
            lock.lock(); defer { lock.unlock() }
            status = newStatus
            data = newData
        }

        func outcome() -> GitCommandOutcome {
            lock.lock(); defer { lock.unlock() }
            guard let status else { return .unavailable }
            return status == 0 ? .output(data) : .rejected
        }
    }
}
