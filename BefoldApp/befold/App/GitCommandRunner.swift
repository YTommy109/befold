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

    /// 打ち切りを試みてから、読み取りスレッドが EOF を諦めるまでの猶予(秒)。
    ///
    /// 予算切れの直後にプロセスグループを消しているので、通常はこの猶予に入る前に EOF が来る。
    /// 猶予が実際に使われるのは、書き込み端を握る全員を殺し切れない場合(プロセスグループを
    /// 特定できないフォールバック経路で、孫プロセスが SIGTERM を伏せているとき)だけ。
    /// そこで無期限に待たないことが、スレッドと fd を必ず返す保証になっている。
    /// SIGKILL の配送と数十 KB のパイプの吸い出しには桁違いに余裕のある幅を採り、
    /// 負荷の高い環境で正常な巻き取りを取りこぼさないようにする。
    ///
    /// テストでは「猶予切れで確実に資源が返る」こと自体を検証するために猶予の満了を
    /// 待つ必要があり、既定の 5 秒だとテストが構造的に遅くなる。差し替え可能かつ
    /// 呼び出しごとに閉じた値(状態を共有しない)のため、デフォルト引数での注入を許容する。
    private let terminationGrace: TimeInterval

    init(timeout: TimeInterval = 10, terminationGrace: TimeInterval = 5) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
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
        // 打ち切り用のプロセスグループは、子が確実に生きているこの時点で控える。
        // 打ち切り時に採り直すと、その頃には子が終了して Foundation に reap 済みかもしれず、
        // 空いた pid を別プロセスが再利用していると無関係なグループを殺しうる。
        let processGroup = terminableProcessGroup(of: process)

        // 読み取りは別スレッドで行い、呼び出し元は timeout までしか待たない。
        // 読み取りを呼び出しスレッドで回して watchdog から terminate() する形だと、
        // git が孫プロセス(フック/エイリアス経由の子)へ標準出力を渡していた場合に
        // git を殺しても pipe が閉じず、結局 timeout が効かない。
        //
        // 読み取り先は `DispatchQueue.global` ではなく専用スレッドにする。global は
        // 非 overcommit の共有ワーカープールで、その本数は `kern.wq_max_constrained_threads`
        // (実測 64)が上限。これはコア数ではなくプロセス全体・全 QoS 共通の枠なので、
        // どこか他所がブロッキング処理で 64 本を埋めれば何コアあっても詰まる。
        // そこへブロックする処理(ここでは EOF 待ちの read)を投げると、読み取りブロック
        // 自体が起動できず、git はとっくに終わっているのに毎回 timeout まで待って
        // `.unavailable` になる。CI(数百テスト並行)で実際にこれが起き、パス参照リンクが
        // 丸ごと死ぬ形の赤になった。予算を延ばしても直らない種類の詰まりのため、
        // 共有プールに依存しない専用スレッドで確実に読み始める。
        //
        // このスレッドは EOF を無期限には待たず、自分の期限を持つ(`readUntilEOF` を参照)。
        // 期限は呼び出し元の予算に `terminationGrace` を足したもの。呼び出し元は予算切れで
        // プロセスグループを消しに行くので、殺せていれば猶予の中で EOF が来て通常どおり
        // 巻き取れる。殺し切れない場合(グループを特定できないフォールバック経路で孫が
        // SIGTERM を伏せているとき)だけ猶予切れで読み取りを諦める。こうしてスレッドと
        // Pipe の解放が「書き込み端を握る全員を殺せたか」に依存しなくなる。
        // スレッドを抜ければ最後の参照が切れて Pipe が deinit し、両端の fd が閉じる。
        //
        // stackSize は既定(512KB)のまま触らない。このスレッドでは `waitUntilExit()` の
        // ラン・ループも走るため、切り詰めても仮想アドレス空間しか節約できない一方で
        // 溢れたときは診断しにくい SIGSEGV に化ける。
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout + terminationGrace))
        let output = OutputBox()
        let done = DispatchSemaphore(value: 0)
        let reader = Thread {
            guard let data = readUntilEOF(pipe.fileHandleForReading, deadline: deadline) else {
                // 期限切れ。標準出力は不完全なので結果は採らない。`done` も signal しない:
                // 呼び出し元を待機解除してしまうと、下の `terminate` を通らずに git を
                // 野放しにする。呼び出し元は自分の期限で抜け、打ち切り処理へ進む。
                return
            }
            process.waitUntilExit()
            output.set(status: process.terminationStatus, data: data)
            done.signal()
        }
        reader.name = "GitCommandRunner.read"
        reader.start()
        guard done.wait(timeout: .now() + timeout) == .success else {
            // 読み取り端は決して閉じない。read に入る前に閉じると EBADF で
            // `NSFileHandleOperationException` が飛び、Swift からは catch できないので
            // プロセスごと落ちる。閉じた fd 番号が別のファイルへ再利用されれば無関係な
            // 読み取りまで壊す。しかも read 中の close は Darwin では読み取りを中断しない
            // ため、解放したいスレッドは結局残る。fd を閉じるのは読み取りスレッド自身に任せる。
            //
            // ここでやるのは、放置すると居座る子孫の始末。git 単体への SIGTERM だと、
            // git が孫プロセス(フック/エイリアス経由の子)へ標準出力を渡していて、その孫が
            // SIGTERM に応じないときに git・シェル・孫の全員が生き残る(実測)。索引の warm は
            // ファイルを開くたび・タブを切り替えるたびに走るので、応答しないリポジトリでは
            // 居座るプロセスが積み上がる。プロセスグループごと消せば全員まとめて始末できる。
            terminate(processGroup, fallingBackTo: process)
            return .unavailable
        }
        return output.outcome()
    }

    /// 期限まで pipe を読み、EOF に達したら読み取った全量を返す。期限切れなら nil。
    ///
    /// `readDataToEndOfFile` を使わないのは、EOF が来ない限り戻らないため。書き込み端を
    /// 握った孫プロセスを殺し切れない状況(プロセスグループを特定できないフォールバック
    /// 経路)では EOF が永遠に来ず、スレッドと Pipe の fd が孫の終了まで残留してしまう。
    /// 期限を読み取り側にも持たせて、打ち切りの成否と資源の解放を切り離す。
    ///
    /// `poll` で読める状態を確かめてから `read` するので、単一の読み手であるこのスレッドが
    /// ブロックすることはない。`FileHandle` の API を経由しないため、fd が壊れていても
    /// catch 不能な `NSFileHandleOperationException` ではなく戻り値のエラーとして現れる。
    private func readUntilEOF(_ handle: FileHandle, deadline: ContinuousClock.Instant) -> Data? {
        let descriptor = handle.fileDescriptor
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return nil }
            var fds = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fds, 1, Self.pollMilliseconds(remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { return nil }
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer[0 ..< count])
        }
    }

    /// 残り時間を `poll` の待機ミリ秒へ丸める。0 に潰れて空回りしないよう最低 1ms を与え、
    /// Int32 を溢れさせないよう上限で切る(このランナーの予算では実際には届かない)。
    private static func pollMilliseconds(_ remaining: Duration) -> Int32 {
        let components = remaining.components
        let millis = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        return Int32(min(max(millis, 1), Int64(Int32.max)))
    }

    /// 打ち切り時にまとめて消してよいプロセスグループ ID を返す。判断できなければ nil。
    ///
    /// macOS の `Process` は子を「子自身をリーダーとする新しいプロセスグループ」へ置く。
    /// その前提が成り立つこと(pgid == pid)を確かめてから使う。前提が崩れた環境で
    /// 素朴にグループを殺すと、子が呼び出し元と同じグループに居た場合に befold 自身を
    /// 巻き込んで落とすため、確認できないときは何も返さない。
    private func terminableProcessGroup(of process: Process) -> pid_t? {
        let pid = process.processIdentifier
        guard pid > 0 else { return nil }
        let group = getpgid(pid)
        guard group == pid, group != getpgid(0) else { return nil }
        return group
    }

    /// プロセスグループごと打ち切る。グループを特定できていなければ git 単体を終了させる。
    ///
    /// SIGTERM ではなく SIGKILL を使うのは、無視できない signal であることが
    /// 「必ず書き込み端が閉じる」保証そのものだから。猶予を与えて後始末させる必要も無い:
    /// このランナーが実行するのは読み取り専用のクエリ(rev-parse / ls-files)だけで、
    /// フックは `hardeningOptions` で無効化済みのため、中断で壊れる書きかけの状態が無い。
    /// フォールバック(グループ不明)では git 単体へ SIGTERM を送るに留める。この経路では
    /// 孫プロセスが SIGTERM を伏せていると生き残るが、読み取りは自前の期限で打ち切られるため
    /// befold 側のスレッドと fd は残らない。
    private func terminate(_ processGroup: pid_t?, fallingBackTo process: Process) {
        guard let processGroup else {
            process.terminate()
            return
        }
        // pgid は起動直後に控えた値なので、既に git が終わって Foundation が reap していれば
        // その番号は別のプロセスグループへ再利用されうる。無関係なグループを SIGKILL しないよう、
        // 送る直前に子がまだ生きていることを確かめる。
        // (確認と kill の間にも理屈の上では窓が残るが、Foundation の reap は
        // `waitpid` を回すスレッドが起きてからなので、この幅は縮められる限界まで縮む。)
        guard process.isRunning else { return }
        kill(-processGroup, SIGKILL)
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
