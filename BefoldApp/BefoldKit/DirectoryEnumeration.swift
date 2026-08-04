import Foundation

/// ディレクトリ列挙・分類・ソートと「先頭の対応ファイル」判定の単一の実装元。
///
/// GUI サイドバー(`DirectoryLister`)と CLI/オープン経路(`SupportedFileResolver`)が
/// それぞれ FileManager を直接叩くと、隠しファイルの扱い・ソート順・
/// 「フォルダを開いたとき最初に開くファイル」の判定がドリフトする。
/// 列挙まわりはここに集約し、双方はここへ委譲すること。
public enum DirectoryEnumeration {
    /// ディレクトリ直下のエントリを列挙し、フォルダーとファイルに分類して
    /// それぞれファイル名の localizedStandardCompare 昇順で返す。
    /// 実体が存在しないダングリングシンボリックリンク等の非通常エントリも files に算入する
    /// (サイレントに一覧から消さず、開こうとした時点で既存のオープン/エラー表示フローに委譲する)。
    /// 列挙に失敗した場合は空の組を返す。
    public static func sortedContents(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> (folders: [URL], files: [URL]) {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: options
        ) else {
            return ([], [])
        }

        var folders: [URL] = []
        var files: [URL] = []
        // ここでは裏打ち(nativeBackedFileURL)を揃えない。この列挙は
        // containsSupportedFile / firstSupportedFile など「1 件だけ見て残りを捨てる」
        // 経路の入口でもあり、フォルダー行ごとに全件ぶんの URL 再構築を払うことになる。
        // 揃えるのは実際に URL をハッシュキーにする消費側(サイドバー一覧は
        // FileListEntry.init と DirectoryLister.allEntriesSorted、開く対象は
        // ViewerStore が文書 URL を保持するところ)に置く(TASK-273 / TASK-279)。
        for url in contents {
            if fileReader.isDirectory(at: url) {
                folders.append(url)
            } else {
                files.append(url)
            }
        }
        return (folders.sortedByFileName(), files.sortedByFileName())
    }

    /// ディレクトリ直下の非ディレクトリエントリを、ファイル名の自然順でソートして返す。
    public static func sortedFiles(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> [URL] {
        sortedContents(in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader).files
    }

    /// ディレクトリ直下の最初の対応形式(`FileType.isSupported`)ファイル。無ければ nil。
    public static func firstSupportedFile(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> URL? {
        sortedFiles(in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader).firstSupported()
    }

    /// 「フォルダを開いたとき最初に開くファイル」の選択規則の単一の実装元。
    /// 対応形式を優先し、無ければ先頭のファイルにフォールバックする。
    static func fileToOpen(from files: [URL]) -> URL? {
        files.firstSupported() ?? files.first
    }
}

public extension Array {
    /// ファイル名順にソート済みの 2 列を、順序を保ったままひと続きにする。
    ///
    /// `sortedContents` は既にフォルダー・ファイルそれぞれをソートして返す。
    /// 連結してソートし直すと、ロケール依存で重い localizedStandardCompare を
    /// O(n log n) 回払い直すことになるため、比較 O(n) のマージで済ませる。
    ///
    /// - Parameter name: 比較に使うファイル名(URL なら lastPathComponent)。
    static func mergedByFileName(
        _ lhs: [Element], _ rhs: [Element], name: (Element) -> String
    ) -> [Element] {
        var merged: [Element] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var left = lhs.makeIterator()
        var right = rhs.makeIterator()
        var pendingLeft = left.next()
        var pendingRight = right.next()
        while let leftElement = pendingLeft, let rightElement = pendingRight {
            // 同順(orderedSame)のときは左を先に出し、連結の前後関係を保つ。
            if name(rightElement).localizedStandardCompare(name(leftElement)) == .orderedAscending {
                merged.append(rightElement)
                pendingRight = right.next()
            } else {
                merged.append(leftElement)
                pendingLeft = left.next()
            }
        }
        while let leftElement = pendingLeft {
            merged.append(leftElement)
            pendingLeft = left.next()
        }
        while let rightElement = pendingRight {
            merged.append(rightElement)
            pendingRight = right.next()
        }
        return merged
    }
}

extension [URL] {
    /// ファイル名(lastPathComponent)の localizedStandardCompare 昇順ソート。
    /// 列挙結果の並びを一箇所に固定するため、呼び出し側で個別に sorted を書かない。
    public func sortedByFileName() -> [URL] {
        sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    fileprivate func firstSupported() -> URL? {
        first(where: FileType.isSupported)
    }
}
