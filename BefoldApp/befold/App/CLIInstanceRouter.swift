import BefoldCLI
import Foundation

extension CLIOpenOptions {
    var viewerSortOrder: SortOrder {
        sortOrder == .alphabetical ? .alphabetical : .foldersFirst
    }
}
