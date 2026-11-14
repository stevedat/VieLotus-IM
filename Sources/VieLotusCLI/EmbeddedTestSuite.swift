import Foundation

enum EmbeddedTestSuite {
    static func loadCSV() -> String? {
        #if SWIFT_PACKAGE
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "test_suite", withExtension: "csv"),
            Bundle.module.url(forResource: "test_suite", withExtension: "csv", subdirectory: "Resources")
        ]
        for case let url? in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        #endif
        if let url = Bundle.main.url(forResource: "test_suite", withExtension: "csv"),
           let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            return text
        }
        return nil
    }
}
