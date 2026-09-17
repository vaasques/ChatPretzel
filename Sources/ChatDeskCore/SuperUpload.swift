import Foundation

public enum SuperUploadLanguage: String, Sendable {
    case english = "en"
    case swedish = "sv"
}

public struct SuperUploadBatchPlan: Equatable, Sendable {
    public let number: Int
    public let totalBatches: Int
    public let start: Int
    public let end: Int
    public let totalFiles: Int

    public init(number: Int, totalBatches: Int, start: Int, end: Int, totalFiles: Int) {
        self.number = number; self.totalBatches = totalBatches
        self.start = start; self.end = end; self.totalFiles = totalFiles
    }

    public var count: Int { end - start + 1 }
    public var sentAfterBatch: Int { end }
    public var remainingAfterBatch: Int { totalFiles - end }
    public var isFirst: Bool { number == 1 }
    public var isLast: Bool { number == totalBatches }
}

public struct SuperUploadPlan: Equatable, Sendable {
    public static let defaultBatchSize = 10
    public let totalFiles: Int
    public let batchSize: Int
    public let batches: [SuperUploadBatchPlan]

    public init?(totalFiles: Int, batchSize: Int = defaultBatchSize) {
        guard totalFiles > 0, batchSize > 0 else { return nil }
        self.totalFiles = totalFiles
        self.batchSize = batchSize
        let totalBatches = ((totalFiles - 1) / batchSize) + 1
        self.batches = (0..<totalBatches).map { index in
            let start = index * batchSize + 1
            return SuperUploadBatchPlan(number: index + 1, totalBatches: totalBatches,
                                        start: start, end: min(totalFiles, start + batchSize - 1),
                                        totalFiles: totalFiles)
        }
    }
}

public enum SuperUploadMessageBuilder {
    /// Filenames are basenames only and are bounded by the caller before crossing into the web page.
    public static func message(for batch: SuperUploadBatchPlan, language: SuperUploadLanguage,
                               selectedCount: Int, skippedCount: Int? = nil, skipped: [String]) -> String {
        let count = skippedCount ?? skipped.count
        switch language {
        case .english: return english(batch, selectedCount: selectedCount, skippedCount: count, skipped: skipped)
        case .swedish: return swedish(batch, selectedCount: selectedCount, skippedCount: count, skipped: skipped)
        }
    }

    private static func english(_ batch: SuperUploadBatchPlan, selectedCount: Int, skippedCount: Int, skipped: [String]) -> String {
        var parts: [String] = []
        if batch.count == 0 {
            parts.append("Super Upload complete: no additional files could be attached in this batch. The \(batch.totalFiles) files confirmed in earlier messages are the complete available set.")
            parts.append("Please now use those files together with the instruction in the first message.")
        } else if batch.isLast {
            parts.append("Super Upload complete: files \(batch.start)–\(batch.end) of \(batch.totalFiles) are attached.")
            parts.append("All \(batch.totalFiles) supported files have now been sent.")
            parts.append("Please now use the complete file set together with any instruction in the first message.")
        } else if batch.isFirst {
            parts.append("Super Upload: files \(batch.start)–\(batch.end) of \(batch.totalFiles) are attached.")
            parts.append("\(batch.remainingAfterBatch) more files will follow in \(batch.totalBatches - batch.number) additional batches.")
            parts.append("Please wait until the final batch arrives before analysing or answering.")
        } else {
            parts.append("Super Upload: files \(batch.start)–\(batch.end) of \(batch.totalFiles) are attached.")
            parts.append("\(batch.sentAfterBatch) of \(batch.totalFiles) files have now been sent; \(batch.remainingAfterBatch) more will follow.")
            parts.append("Please continue waiting for the final batch.")
        }
        if skippedCount > 0, !skipped.isEmpty {
            parts.append("Of \(selectedCount) selected items, \(skippedCount) have been skipped; totals above exclude them: \(skipped.joined(separator: "; ")).")
        }
        return parts.joined(separator: " ")
    }

    private static func swedish(_ batch: SuperUploadBatchPlan, selectedCount: Int, skippedCount: Int, skipped: [String]) -> String {
        var parts: [String] = []
        if batch.count == 0 {
            parts.append("Superuppladdningen är klar: inga ytterligare filer kunde bifogas i denna omgång. De \(batch.totalFiles) filer som bekräftats i tidigare meddelanden är hela den tillgängliga uppsättningen.")
            parts.append("Använd nu dessa filer tillsammans med instruktionen i det första meddelandet.")
        } else if batch.isLast {
            parts.append("Superuppladdningen är klar: filer \(batch.start)–\(batch.end) av \(batch.totalFiles) är bifogade.")
            parts.append("Alla \(batch.totalFiles) filer som stöds har nu skickats.")
            parts.append("Använd nu hela filuppsättningen tillsammans med en eventuell instruktion i det första meddelandet.")
        } else if batch.isFirst {
            parts.append("Superuppladdning: filer \(batch.start)–\(batch.end) av \(batch.totalFiles) är bifogade.")
            parts.append("Ytterligare \(batch.remainingAfterBatch) filer kommer i \(batch.totalBatches - batch.number) omgångar.")
            parts.append("Vänta tills den sista omgången har kommit innan du analyserar eller svarar.")
        } else {
            parts.append("Superuppladdning: filer \(batch.start)–\(batch.end) av \(batch.totalFiles) är bifogade.")
            parts.append("\(batch.sentAfterBatch) av \(batch.totalFiles) filer har nu skickats; ytterligare \(batch.remainingAfterBatch) kommer.")
            parts.append("Fortsätt vänta på den sista omgången.")
        }
        if skippedCount > 0, !skipped.isEmpty {
            parts.append("Av \(selectedCount) valda objekt har \(skippedCount) utelämnats; totalsiffrorna ovan räknar inte med dem: \(skipped.joined(separator: "; ")).")
        }
        return parts.joined(separator: " ")
    }
}
