import BefoldKit
import Foundation

public enum CLICheckCommand {
    public static func defaultResolveFileToOpen(at url: URL, fileReader: any FileReading) -> URL? {
        guard fileReader.isDirectory(at: url) else { return url }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first { !fileReader.isDirectory(at: $0) }
    }

    public static func run(
        _ path: String,
        fileReader: any FileReading = DefaultFileReader(),
        resolveFileToOpen: (URL, any FileReading) -> URL? = defaultResolveFileToOpen
    ) -> CLICommandResult {
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
        let size = fileReader.fileSize(at: target) ?? 0
        let detail = "Size: \(size) bytes\nType: \(fileType.jsValue) (extension: .\(target.pathExtension))"

        if let reason = rejectReason(for: fileType, size: size, target: target, fileReader: fileReader) {
            return CLICommandResult(
                message: "Cannot open: \(target.path)\nReason: \(reason.cliMessage)\n\(detail)", exitCode: 1
            )
        }
        return CLICommandResult(message: "Can open: \(target.path)\n\(detail)", exitCode: 0)
    }

    private static func rejectReason(
        for fileType: FileType, size: Int, target: URL, fileReader: any FileReading
    ) -> RejectReason? {
        if fileType.isBinaryContent {
            return size > ContentLoader.maxFileSizeBytes ? .fileTooLarge : nil
        }
        if fileReader.isBinary(at: target) {
            return .unsupportedFormat
        }
        let sizeLimit = fileType.isLineOriented
            ? NormalizedTextCache.maxFileSizeBytes
            : ContentLoader.maxTextFileSizeBytes
        return size > sizeLimit ? .fileTooLarge : nil
    }
}
