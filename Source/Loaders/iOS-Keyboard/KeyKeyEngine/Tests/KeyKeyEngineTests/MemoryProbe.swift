import Foundation
import Testing

@testable import KeyKeyEngine

/// Not an assertion about the extension sandbox -- a proxy measurement of the
/// data layer's resident cost, to compare against the ~60 MB extension budget.
private func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / (1024 * 1024)
}

@Suite("Memory probe", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["KEYKEY_IOS_MEMORY_PROBE"] == "1"))
struct MemoryProbe {
    @Test("footprint after ten thousand lookups")
    func footprint() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Distributions/Takao/CookedDatabase/KeyKey.db")
        try #require(FileManager.default.fileExists(atPath: url.path))

        let before = footprintMB()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidates = try GuanyinmaInputEngine(modelURL: url,
            userDatabaseURL: directory.appendingPathComponent("user.db"), method: .traditional)
        let phrases = try GuanyinmaAssociatedPhraseStore(modelURL: url, enabledSources: { ["McBopomofo"] })
        let afterOpen = footprintMB()

        var total = 0
        for _ in 0..<10_000 {
            // UIKit drains temporary Foundation JSON objects between input
            // events. Match that lifecycle rather than one test-long pool.
            total += autoreleasepool {
                candidates.reset()
                for key in "su3" { _ = candidates.handleSoftKey(String(key)) }
                return candidates.displayedCandidates.count
                    + phrases.phrases(forHeadCharacter: "一").count
            }
        }
        let afterQueries = footprintMB()

        print(String(
            format: "[memory] baseline %.1f MB -> open %.1f MB -> after 10k lookups %.1f MB (rows %d)",
            before, afterOpen, afterQueries, total))
        #expect(total > 0)
        #expect(afterQueries - before < 40, "data layer footprint should stay well under the extension budget")
    }
}
