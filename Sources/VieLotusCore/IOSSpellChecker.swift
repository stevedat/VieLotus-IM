#if !VIELOTUS_OPEN_CORE_MACOS
import Foundation
#if DEBUG
import os.log
#endif

/// The live keyboard must never wait for UIKit spelling services or their IPC.
public final class IOSSpellChecker: SpellCheckerProvider, Sendable {
    private let lexicon: LocalEnglishLexicon

    public init() {
        // Load before the first key, when the controller installs its provider.
#if DEBUG
        let startedAt = DispatchTime.now().uptimeNanoseconds
#endif
        lexicon = .shared
        // These lazy tables used to initialize during the first character callback.
        _ = EmbeddedEnglishSpellChecker.shared
        _ = VietnameseSyllableDictionary.shared
#if DEBUG
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        os_log("local_english_provider_ready loaded=%{public}d elapsed_ms=%{public}.3f",
               log: OSLog(subsystem: "org.vielotus.keyboard", category: "InputLatency"),
               type: .info, lexicon.isLoaded ? 1 : 0, elapsed)
#endif
    }

    public func isWordInEnglishDictionary(_ word: String) -> Bool {
        guard (1...48).contains(word.utf8.count), word.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return false }
        // Preserve explicit Vietnamese collision policy before consulting the larger list.
        if word == word.lowercased(), SmartBilingualDetector.vietnameseProtectedTelexInputs.contains(word) {
            return false
        }
        return EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(word) || lexicon.contains(word)
    }
}

#if !VIELOTUS_OPEN_CORE_MACOS
public final class IOSEnglishWordSuggestions: Sendable {
    public init() {}
    public func candidates(for word: String) -> [SuggestionCandidate] {
        LocalEnglishLexicon.shared.candidates(for: word)
    }
    public static func isEnglishWordShape(_ word: String) -> Bool {
        LocalEnglishLexicon.isEligible(word)
    }
}
#endif
#endif
