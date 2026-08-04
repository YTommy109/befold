import Foundation

/// `URL.nativeBackedFileURL` が「文字列の裏打ちを native な連続 UTF-8 へ差し替える」
/// 働きを持てる環境かどうかを、OS のバージョンではなく実際の挙動で判定する。
///
/// macOS 14 では URL の実装が異なり、ファイルシステム表現から作り直しても裏打ちは
/// 揃わない(no-op になる)。ただしそこでは URL のハッシュに遅い経路自体が存在せず
/// 実害はない。TASK-269 で macos-14 / macos-26 の CI ランナー実測により確認済み。
///
/// 裏打ちを見るアサートはこの差し替えが効く環境でだけ意味を持つため、
/// 対応 OS 全体で成り立つ不変条件(バイト列の保存・等値・ハッシュ一致)と分けて扱う。
/// バージョン境界を書かないのは、実測したのが 14 と 26 の 2 点だけで、
/// その間のどこで実装が変わったかを確かめていないため。
public enum URLBackingSupport {
    /// ファイルシステム表現から作り直した file URL のパスが連続 UTF-8 になるか。
    /// 判定は 1 度だけ行い、以後は同じ結果を返す。
    public static let rebuildYieldsContiguousUTF8: Bool = probe()

    private static func probe() -> Bool {
        // 判定できない場合は true を返す。アサートを走らせたうえで落とすほうが、
        // 黙って検証を飛ばすより問題が見える。
        guard let source = probeURLFromFileManager() else { return true }
        // 元から連続 UTF-8 なら、差し替えは不要で結果も連続 UTF-8 になる。
        guard !source.path.isContiguousUTF8 else { return true }
        return source.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return true }
            let rebuilt = URL(
                fileURLWithFileSystemRepresentation: pointer, isDirectory: false, relativeTo: nil
            )
            return rebuilt.path.isContiguousUTF8
        }
    }

    /// 本番と同じ経路(FileManager の列挙)で、非 ASCII 名の URL を 1 つ得る。
    /// NSString 裏打ちになるのはこの経路だけなので、合成した URL では判定にならない。
    private static func probeURLFromFileManager() -> URL? {
        guard let directory = try? TempDir(prefix: "url-backing-probe") else { return nil }
        defer { withExtendedLifetime(directory) {} }
        guard (try? directory.file(named: "裏打ち判定.md", contents: "")) != nil else { return nil }
        let listed = try? FileManager.default.contentsOfDirectory(
            at: directory.url, includingPropertiesForKeys: nil
        )
        return listed?.first { $0.pathExtension == "md" }
    }
}
