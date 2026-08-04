import Foundation

/// 「ファイルシステム表現から file URL を作り直すと、文字列の裏打ちが native な
/// 連続 UTF-8 に変わるか」を、OS のバージョンではなく実際の挙動で観測する。
///
/// macOS 14 では URL の実装が異なり、作り直しても裏打ちは揃わない(no-op になる)。
/// ただしそこでは URL のハッシュに遅い経路自体が存在せず実害はない。TASK-269 で
/// macos-14 / macos-26 の CI ランナー実測により確認済み。バージョン境界を書かないのは、
/// 実測したのが 14 と 26 の 2 点だけで、その間のどこで実装が変わったかを確かめていないため。
///
/// **ここは本番の `URL.nativeBackedFileURL` を呼んではならない。** 観測が本番 API に
/// 依存すると、本番が壊れたときに観測値も一緒に動いてアサートが素通りする(裏打ちを
/// 差し替えなくなった実装に対して「差し替わらない環境だ」と観測してしまう)。
/// 観測は Foundation の振る舞いだけを直接測り、本番 API がそのとおりに働けているかは
/// テスト側で突き合わせる。作り直しの引数は本番と揃える(TASK-280)。
public enum URLBackingSupport {
    /// この環境で実測した、Foundation 側の裏打ちの振る舞い。
    public struct Observation: Sendable {
        /// ファイルシステム表現から作り直した file URL のパスが連続 UTF-8 になるか。
        /// `URL.nativeBackedFileURL` の結果を突き合わせる相手。
        public let rebuiltPathIsContiguousUTF8: Bool
        /// 作り直した URL から `resolvingSymlinksInPath().path` を採ったものが連続 UTF-8 になるか。
        /// `FileListEntry.pathKey`(= `URL.normalizedPathKey`)の結果を突き合わせる相手。
        /// 作り直しとは別の API を通るため、上と同じ値になるとは限らない。
        public let resolvedPathIsContiguousUTF8: Bool
    }

    /// 観測そのものができなかった。裏打ちの回帰とは別の失敗であることを名前で示す。
    ///
    /// 「測れないので通す」も「測れないので落とす」も、失敗の理由が裏打ちの回帰に
    /// 見えてしまう。測れなかったことをエラーとして返し、テスト側の `try` で
    /// プローブを名指しして落ちるようにする。
    public struct ProbeFailed: Error, CustomStringConvertible {
        public let description = "URL の裏打ちを観測できなかった(一時ディレクトリの作成・列挙に失敗)。"
            + "裏打ちの回帰ではなく、プローブ自身が動かせなかったことを意味する。"
    }

    /// 観測は 1 度だけ行い、以後は同じ結果を返す。
    public static func observed() throws -> Observation {
        try cached.get()
    }

    private static let cached: Result<Observation, ProbeFailed> = probe()

    private static func probe() -> Result<Observation, ProbeFailed> {
        guard let directory = try? TempDir(prefix: "url-backing-probe"),
              let source = probeURLFromFileManager(in: directory)
        else {
            return .failure(ProbeFailed())
        }
        defer { withExtendedLifetime(directory) {} }
        let rebuilt = source.withUnsafeFileSystemRepresentation { pointer -> URL? in
            guard let pointer else { return nil }
            return URL(
                fileURLWithFileSystemRepresentation: pointer,
                isDirectory: source.hasDirectoryPath,
                relativeTo: nil
            )
        }
        guard let rebuilt else { return .failure(ProbeFailed()) }
        return .success(
            Observation(
                rebuiltPathIsContiguousUTF8: rebuilt.path.isContiguousUTF8,
                resolvedPathIsContiguousUTF8: rebuilt.resolvingSymlinksInPath().path.isContiguousUTF8
            )
        )
    }

    /// 本番と同じ経路(FileManager の列挙)で、非 ASCII 名の URL を 1 つ得る。
    /// NSString 裏打ちになるのはこの経路だけなので、合成した URL では観測にならない。
    private static func probeURLFromFileManager(in directory: TempDir) -> URL? {
        guard (try? directory.file(named: "裏打ち判定.md", contents: "")) != nil else { return nil }
        let listed = try? FileManager.default.contentsOfDirectory(
            at: directory.url, includingPropertiesForKeys: nil
        )
        return listed?.first { $0.pathExtension == "md" }
    }
}
