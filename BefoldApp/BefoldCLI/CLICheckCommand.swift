import BefoldKit
import Foundation

/// `befold --check <path>` — 既存の FileType・サイズ上限定数を再利用し、befold が開けるファイルかどうかを判定する。
public enum CLICheckCommand {
    /// ディレクトリが渡された場合、対応形式優先で中のファイルを解決する。ファイルならそのまま返す。
    /// 実体は BefoldKit.SupportedFileResolver(GUI・CLI 双方の単一の実装元)に委譲する。
    public static func defaultResolveFileToOpen(at url: URL, fileReader: any FileReading) -> URL? {
        SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader)
    }

    public static func run(
        _ path: String,
        fileReader: any FileReading = DefaultFileReader(),
        resolveFileToOpen: (URL, any FileReading) -> URL? = defaultResolveFileToOpen
    ) async -> CLICommandResult {
        let url = URL(fileURLWithPath: path)
        guard fileReader.fileExists(at: url) else {
            return CLICommandResult(message: "No such path: \(path)", exitCode: 1)
        }

        guard let target = resolveFileToOpen(url, fileReader) else {
            return CLICommandResult(message: "No file found in folder: \(path)", exitCode: 1)
        }

        guard fileReader.isExistingFile(at: target) else {
            return CLICommandResult(
                message: "Cannot open: \(target.path)\nReason: "
                    + "The file's target could not be found (it may be a broken symbolic link).",
                exitCode: 1
            )
        }

        let fileType = FileType(url: target)
        let size = fileReader.fileSize(at: target).map { "\($0) bytes" } ?? "unknown"
        let detail = "Size: \(size)\nType: \(fileType.jsValue) (extension: .\(target.pathExtension))"

        switch await rejectReason(for: fileType, target: target, fileReader: fileReader) {
        case .none:
            return CLICommandResult(message: "Can open: \(target.path)\n\(detail)", exitCode: 0)
        case let .some(reason):
            return CLICommandResult(
                message: "Cannot open: \(target.path)\nReason: \(reason.cliMessage)\n\(detail)", exitCode: 1
            )
        }
    }

    /// GUI が実際に使う読み込み経路をそのまま実行し、その拒否理由を答えとする。
    ///
    /// --check は「GUI で開けるか」を予測するコマンドなので、判定を独自に持つと必ず GUI と
    /// ドリフトする(サイズ不明ファイルの誤 openable 報告、非 UTF-8 のデコード後膨張の見落とし、
    /// 内容起因の拒否の予測不能はいずれもそのドリフトだった)。ここで ViewerLoadPipeline へ
    /// 委譲することで、判定の実装元を GUI と 1 つに保つ。
    ///
    /// 代償としてファイルを全量読む。--check は 1 パスあたり 1 回の実行なので許容し、
    /// ライブリロード用の dataHash 計算(oneShotLoad)と画像埋め込み(embedLocalImages)は
    /// 判定に不要なため省く。
    private static func rejectReason(
        for fileType: FileType, target: URL, fileReader: any FileReading
    ) async -> RejectReason? {
        let outcome = await ViewerLoadPipeline.load(
            resolved: target,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: { cache, fileType in
                StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
            },
            oneShotLoad: true,
            embedLocalImages: false
        )
        switch outcome {
        case .missing:
            // 段階 1・3 の存在確認を通った後に消えた場合(TOCTOU)。開けないことに変わりはない。
            return .unsupportedFormat
        case .chunked:
            // 行指向ファイルの先頭チャンクを読めた = GUI も開ける。
            return nil
        case let .full(content, _):
            return content.rejectReason
        }
    }
}
