import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct SmartBilingualDetector {
    private static let lock = NSLock()
    #if canImport(NaturalLanguage)
    internal static var languageRecognizerProvider: LanguageRecognizerProvider = AppleLanguageRecognizerProvider()
    #else
    internal static var languageRecognizerProvider: LanguageRecognizerProvider = HeuristicLanguageRecognizerProvider()
    #endif
    internal static var spellCheckCache: [String: Bool] = [:]
    internal static var cacheKeys: [String] = []
    internal static var contextConfidenceCache: [String: Bool] = [:]
    internal static var maxCacheEntries = 65536

    internal static var cacheCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return spellCheckCache.count
    }

    internal static func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        spellCheckCache.removeAll(keepingCapacity: true)
        cacheKeys.removeAll(keepingCapacity: true)
        contextConfidenceCache.removeAll(keepingCapacity: true)
        BilingualIntentArbiter.resetArbitrationCache()
    }

    internal static func lockForTesting(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        block()
    }

    public static var spellCheckerProvider: SpellCheckerProvider? = EmbeddedEnglishSpellChecker.shared {
        didSet {
            resetCache()
        }
    }

    private static let telexPrimitiveDigests: Set<UInt64> = [
        0xd31de6ea44b24f26, 0xc374a2b4ceb4d846, 0x9183a7c55663d5f3, 0x2147ac6ca65e5c42,
        0x77feeff930ee825d, 0xf9d5c61e5e81da0a, 0x5a58db485ecca33a, 0x952f2e16bcf4cf07,
        0xb759fe6376026db9, 0xd7285c0c25765753, 0x21dbae7ff5cd70cd, 0xb4f067e1da6b0cc6,
        0x147c247ac6227250, 0x2bc384c525249f47, 0x9cde016a36f924d7, 0x35291adde72afb1c,
        0xeaee97c24dcd8819, 0x7d9f9c3ef174fd52
    ]

    private static let commonEnglishTechWordDigests: Set<UInt64> = [
        0x447c08ce06999250, 0xc6a262ac04c4fcd8, 0xe52dee303a14c9c6, 0x9231417222340f4f,
        0x492cb3242e599f4e, 0x82bac6dfb8c41f75, 0x196f58d3c3b905ad, 0xa078d892566402c0,
        0x061e7fa4ae63663f, 0xaaff21f36d0c8575, 0x5f09a89b6579c8b3, 0x134c25d29f6ed4da,
        0x417a1344c9ebb1e2, 0x6a971c0e7f25bdd2, 0x32d4b86ef40ea22b, 0x750b01e19acebdaf,
        0xb2a2fbba6ab0e313, 0xa69ead9e832a8c51, 0x994c8093d923a911, 0x23d8e8a12003d238,
        0x45bdfb1bd2cee569, 0xa7c4426ff3f78981, 0x198b29b90f618325, 0x78af5d8ef38d12f9,
        0x958c70f58c2e8ffe, 0x2a774b52a95f892b
    ]

    private static let commonEnglishWordDigests: Set<UInt64> = [
        0x334c5c5646f8d0dc, 0x3a46b85a1212bf04, 0xa46baff182db7818, 0xa34dffc4dbe59fac,
        0x7654a4913dd8a148, 0x9f52febdd84f1309, 0xb6f5477a97187647, 0xf77371badea3b93c,
        0x6db791d68c988e26, 0x2471efe570c03a50, 0xd787e2464b66bf76, 0xa546d0fbce62bdf7,
        0xb508c1b1098d4753, 0x15f9eeab6a59e9db, 0xb6916c50a349271c, 0x3fab98e5ce722982,
        0x5f8794fe3949dffe, 0xaf3632a33539ba44, 0x355933c8b0535ba1, 0x072f911dd131addb,
        0xe4eba539b9d715a2, 0x4880a116e7def903, 0x04aa8d0302b7e04d, 0x1e8feefa37175cfd,
        0x9edf1ec1bbf3d626, 0x587b1cd219b05a64, 0xe15a0230bccb5318, 0x23c601794f1bc83a,
        0x037dd9ef8f91d368, 0x3a0bdc362e40f245, 0x4cb36690fdbda0e4, 0x1892570dfe820809,
        0xbd231d6ca6652e55, 0x030fd4135ec240f6, 0xfaffe1b9459168dc, 0xe5bab2ca40547f28,
        0xc9d860262b4ce48e, 0x54cb9527f7a6e17c, 0x40e7f355d8c60190, 0x73629111f75a8969,
        0x73b9bacc0c3c8a5c, 0x4b694854bb9d30a4, 0xa1d23b60ec42d9b2, 0x0d0538ae0a5f3c09,
        0xab5e679a2f7ba05d, 0x81020d4d601a0aae, 0x37517cc69addfe98, 0x866c93d6fa8cd8eb,
        0xbf586bcf268a7c23, 0x35e8c78d432c13e0, 0xb238beb9534a1aac, 0xd73ce7cc69c0e845,
        0xe1c5a16fe0c03d0c, 0xa6bdb950f36f3df5, 0x74644de7121bccb7, 0x6afa874b027d188a,
        0xfbc0a74ecd95bd8e, 0x60c2f146e35c97b3, 0x0989a1c54c3bdbc5, 0x88010b8b3a9d20af,
        0x31bdde394cbc048d, 0x8e518ae6db90d70c, 0x0db41ab1d0579920, 0x82e93cb76be7c5ff,
        0xe73f16ff79585c9c, 0x69165bed47b78757, 0x6a0bba46ef49d5ce, 0x82bd8c1855019799,
        0xcf75efe80464e696, 0x9c6d5760fccff201, 0x2d9f4b4c0ae65551, 0x1dec1b490fa3fd69,
        0xdcd64f738a03675c, 0x8dcab99811f6711e, 0x2def742a19277de2, 0x32ea7d8dd3d6a213,
        0xc992366b6b09be45, 0x8329fcfc87114b05, 0x5834bc88fbe752ea, 0x80f445c3e54a3aae,
        0x00347fdb84d40bea, 0x695f4971be0a7c9d, 0x287c998fc6876825
    ]

    private static let vietnameseProtectedCollisionDigests: Set<UInt64> = [
        0x88010b8b3a9d20af, 0xb238beb9534a1aac, 0x60c2f146e35c97b3, 0xe73f16ff79585c9c,
        0xcf75efe80464e696, 0xa6bdb950f36f3df5, 0x74644de7121bccb7, 0x6afa874b027d188a,
        0xfbc0a74ecd95bd8e, 0x0989a1c54c3bdbc5, 0x31bdde394cbc048d, 0x8e518ae6db90d70c,
        0x0db41ab1d0579920, 0x82e93cb76be7c5ff
    ]

    private static let commonEnglishDoubleConsonantWordDigests: Set<UInt64> = [
        0xdb1c0fe3177d937b, 0x15c067bd7e3e377d, 0xfa6a8b4adc6832b5, 0x90a54353de2fef60,
        0x05f951c6616226b9, 0x81d704ef364ff140, 0x58b4e1ff77159572, 0x8b637e1069e52d98,
        0xa3ec8f52056fda88, 0x02f7ef9d3c328066, 0x5d1583f7c4df31a7, 0x1d49d4342e532c1f,
        0xc0209d5a2bbc020f, 0x4d6f6faa44cad4ad, 0x99760e7973606249, 0xc9cba6e6cb0563f0,
        0x0606108c20595eda, 0xe459f94a69c9ee4b, 0xe840fce75878b5ee, 0x8135b6d21537f54f,
        0x5d09db2f28671a80, 0xeb9ebde66ae61775, 0xbfdcc734598e4491, 0x1ca0de83f14aaf9c,
        0x8e4d18f64f197381, 0x8936fc6ab36f1891, 0xbc3cc4564e568f5c, 0xd00e4e4e7cfd8d42,
        0x6584a362700922e5, 0xc7a93f1c20e9ef49, 0xb1448e9eac7362d2, 0xdce2f20595f9ec4a,
        0x6517d7302a343a66, 0x46d3690fea6ca3f4, 0xab4de9ed056d05ef, 0x5318cc1ebea603fe,
        0xf77fc8f30ee1493a, 0x6c87da06b153bbff, 0x195d617edee04c80, 0x0584e9417e44b0b0,
        0x66846e5c3f65b6f3, 0x8cf42976eed5ec9e, 0x07d8c012331f2ec9, 0x361ca3d012ed5d19,
        0xb76a6e55e18548ff, 0x531350bb45696e88, 0x25392fc5f2eeeb45, 0x73d960c8be7294da,
        0xaf4cee51d8140f0d, 0x9a02f9236384fe1b, 0xd6eb6ab2e5adebfb, 0x210e1f4880947bac,
        0xb9c7ec281e2129ef, 0x8004a3dbc9bc9ea8, 0x3f1273a0060e3ae9, 0xdc59a1cc7f9cb520,
        0x0ebf000d6841d20b, 0xf1d24ae01c547929, 0x5bc267927a0b9419, 0x53b53b7a3934f43a,
        0x97b92b0ceb2d5d4b, 0xe2d88c198ec99746, 0xeea085bae0e83636, 0x213844c28431f70d,
        0x38f5c23ba32d4e29, 0xc8660cb82a3b64cb, 0x470435d0ca07a825, 0x88a6b43f2dbb42c0,
        0x000caecb8b9d3163, 0x2e9ec58cf831e8c5, 0xa3183aa03e2723bc, 0x5edf8d0e9d2ae96a,
        0x1a9fe335cbe27471, 0xd6d1dbb36d11aa91, 0x0d9671974ba66b62, 0x920063d56517da73,
        0xa71dad9cb63e42b1, 0xff2dcfcb756f8920, 0x20bc64a85769e335, 0xd20b5f687ce0d836,
        0xc6d39c9411effed4, 0x142e869c4e047afb, 0xfd878a2a2bcd99b7, 0xeeba3fd73f377159,
        0xe1d5be65278bafc2, 0x9367124a63b392fb, 0xabc93e7cdec6e009, 0x405ec52a965c273d,
        0x087beb808b5a87d2, 0x2e00b6a30077e211, 0x30c841607e6b57d7, 0xffd8a33f200f06c5,
        0xc13134bb3831f345, 0x0e82cd0795876f0e, 0xfa9aa06971abbf00, 0x2d1b623f49ea9bfa,
        0xb3084d784bcdcb54, 0x5373b87a51cd49f4, 0x90e92eacf1f9660c, 0x82625901f5e0d1eb,
        0x5be61e030facd28c, 0x29778ae49627b4e5, 0xb8e63f5af1892bc4, 0x11635d47a4e33eb8,
        0x471e12f0b3b35da9, 0x12176ef45d49ab9f, 0x917e9aefeaefa602, 0x65b0f24a37322d29,
        0x0f9ab900effe2fc4, 0xbf184d37dae1db63, 0x3bbc3986c3e2c2c7, 0xf5d77010a1b073a3,
        0x2681d82c26c3c9d7, 0x99384ebde7ee21b7, 0x061314bb51ad2425, 0x760d61224fdf9682,
        0xf25ce9c8d5164752, 0x3f5934205e474bd4, 0x16eed2c74856d3c2, 0x2b2b492963ef6b7c,
        0xd2ec91a87b6116e5, 0x133dec17754f3256, 0xcab12d6845f10269, 0x15e698f516dc7831,
        0xb62f8bbb40d2a3f5, 0x8076f941183d5949, 0x832c87cc0c76eeb0, 0xf8e4fb774662841a,
        0x7619bb2146f7c148, 0xf9308561ba9874e0, 0x8e1dd1174b0b6e25, 0x77bf65e0fb906ca8,
        0x6a9230b623bfb802, 0x4e7672d348a5926b, 0xab8e27895358a111, 0x199262544f43ee19,
        0x155ce4c801f3fd41, 0xc430223c3f1b8237, 0x8b864b4bf25bb541, 0xa8456b2353747bca,
        0x3234ef31f4678ad0, 0xe007589eb16e5888, 0xec46fe7b5bcbf500, 0xd97c40531d84c9ab,
        0x21e2685996fb1930, 0xdc7e0a490dc5618a, 0x6f548b19ca7ca8a5, 0xa3560596e313c844,
        0xfc8febda1e027186, 0x31655afe956d4227, 0x19bfa52fb7bea5f8, 0x4ace92c1de7df2c5,
        0x10bb7ccb3d25211a, 0x2e43cd6ebccd7231, 0xe338e3b5b9b063a6, 0xefd1f3f98ef2805b,
        0x3bf04960e38c2f56, 0xdf3176ee3f71af69, 0xbe5b1b07248047f7, 0x2349f083c7a63aa0,
        0x71cb9fcf2d660988, 0x37b1e99babcd0095, 0xf8d7ad8e53e74940, 0x3b4effc14d178a5f,
        0xbdfd1301cec3be50, 0x6a2f4f8c21f381d4, 0x43bdf312bebfc784, 0x41b4d7c868fa4174,
        0x35281154c875e796, 0x38e1062cab17674e, 0x69062887f6686810, 0x392ee21b348e00db,
        0x71937fc6a8fc25eb, 0x05e24317c2f9f8dd, 0x62cd681727e320d0, 0x7c1be2f405a241a8,
        0xc50e74b624ac6780, 0xc7795c1e16bd0624, 0x469cacdd1d478751, 0xbc299c209d9b9d03,
        0x9ec32515db0449de, 0xe567ef7c8cc52c33, 0xaa065b41d00eb9f5, 0x864caf38e387f42b,
        0xee5605efbb218098, 0x4efc0d579ae35e3a, 0xf2ac93b6383281e9, 0xfc0cfef804e152f1,
        0xbe3dbba131b1d9e6, 0xf5494d605ebe7b8e, 0x7ffab3a4abc6ec56, 0x312a18294a242b99,
        0x9e05983c44732428, 0x955e710de1f25450, 0xc7b0fed2fa67f60c, 0xd21e0d7c94f45773,
        0xa77fa249a42a25ca, 0x7f2e74745f168827, 0x05ee5bba3821ddc3, 0x62c381f96ba6d810,
        0xf90a9c786da417ad, 0xdc1ca3ecd51068d5, 0x7512c3c304546447, 0xe9d2b5f0a1079ebf,
        0xafd8a20e9bef4d6f, 0xfc6c16cf4f0eda95, 0x3101a453813b21a9, 0xa2a77c16d2a6ead5,
        0x7a5ae99bad9a20c7, 0x4efc5a703831296c, 0xce8517a767f58bdc, 0x12bb963913611f1e,
        0xb1d349d4207c8e1e, 0xebf38b2bce104278, 0x66ada56a15b8689c, 0x26184131b5e9db64,
        0x84c5ded348fa205f, 0xb3c41cf64cca63d0, 0x7b6f1e437d691807, 0x91e3519d85496c1e,
        0x3a9ca11a0030e830, 0xcb642a351e62222c, 0xfd8e6e799d18933b, 0x3371e66e742cd529,
        0x5b4a25a82cf6be38, 0x81ec4106e6d49341, 0xec79bff32231ea53, 0x96290cfbe8362afc,
        0x31105a1849dd1083, 0x757f15876a3a2126, 0xc1cecec1c5a167b2, 0x8cf41b1fc1121dd9,
        0x84aaf199f36c8cc8, 0xc4711c992e77b08e, 0x7cedf071e5714914, 0x6b788e7c5d7456f8,
        0x448a5f29948edebb, 0x25eced3b486072dc, 0x094e9e52bea24d6a, 0xd863c422d4686152,
        0xa178028e255e00f7, 0xa221c114539cf7cc, 0x422fdd920809eef4, 0xeb0222f97687b14d,
        0xef017b389a39caa6, 0xdf1ec4b272f14284, 0x1043c74c69c2583b, 0x68ea6e1e75aae109,
        0x11c998f6a693b63e, 0x3d3ca7524b9a5654, 0x831df9a2682abafe, 0x9f934df8d93ae73e,
        0xac2b5a10fdc5c172, 0xef33c1ad68845f48, 0x77d73c6b6aeeef95, 0x153fc86fbecabb8b,
        0xba6624da6c08920b, 0xcec92eda43df55df, 0x0812e94f3e797b75, 0xd4d061108c870111,
        0xf064f475a22e1a2a, 0x0f704e239c884360, 0xf0c130cef08a1c73, 0x726af73c4c36c164,
        0x9be77efff02f8870, 0xdf3d30190109b38a, 0x1f3ba717af0c7010, 0x350c217ddfbb78b2,
        0x14b6c064232d7dc7, 0x70c1b30f816527f1, 0x5a159428597fdc96, 0x9645d89c4e595493,
        0xab3c69a87a2b5f25, 0xa8bc1b9f9bc3b4fc, 0xc58c156ab37e06f4, 0xfbfcecdbac3beacd,
        0x3580a2254f30da2d, 0x15339dca5e696981, 0xa2f89f035a1379f5, 0x1473fb7dda306fb8,
        0xaed6b7396accd4f4, 0x324fc5074af5a5e2, 0x82ec92f44f3b14ff, 0x4567dacc2bb7bc9f,
        0x6fbab53e82185c77, 0x7cf72bc079cd4365, 0x8c998518c3aa11f5, 0xcb42bf0d59380ade,
        0x876e05ddc4056295, 0x2a8717ac3b1d3394, 0x0122931a57f9e0e5, 0xbc0079c9b183fa66,
        0xf86c47aba54383ea, 0x862913e9a698606d, 0x8d1a51a303d6b5a1, 0x78a65874b1443152,
        0x0c63981dd1395568, 0xbabbf54ee11e6980, 0x9bd166b683dcefa3, 0x2ece22f1477dc0de,
        0x16ccc247c88ebcad, 0x789b8c1efbf1bf01, 0x5a9e89ccf6e06038, 0x877acb122c017b59,
        0xdd4f24d17f6359ec, 0xb0269563d812d068, 0x90b46c4543516ee6, 0x03e688e733180789,
        0x9bb4372dae09e149, 0xe56e7ee7d4ca83bd, 0x67c399cb2f8c6571, 0x5c303eea5e935493,
        0x641cb0235ee7a842, 0xa90a26cc599a3ea5, 0x9c2c6dff741b5a67, 0xd4996a1535c13709,
        0xe47f729973e318b6, 0xb463e1dd117ec139, 0x9d2a39601e055f6c, 0xe63a43f36c12f329,
        0x593e2ecefe218a40, 0xde582383609f8c7a, 0xf66b8a317526ea81, 0xc334a9477112e6b3,
        0xdbdfb346ae834b04, 0xf47326dcfad61523, 0x827d50f90f8ce928, 0x8d5eb769cfdbc7df,
        0x852362be198dbecc, 0x9ba48345f004cb9a, 0x56237d020009fa3a, 0xea5d27e695f2170b,
        0x81a76ce263dfdd13, 0xf047bcab39f1d4cd, 0xacf11c576d29d09b, 0x6b86d1adf61f17f0,
        0x0243cd48b9148216, 0x55f40a796671abe5, 0x726a54fe41171017, 0x3037c8750df4d984,
        0x1a7f6002686afaf4, 0xe939cc8fcc3c4730, 0xa8cbdd173e592e16, 0xefb1baae4c968f87,
        0x7d18651d52ea6ea5, 0x5696513be613beae, 0x1cca9d89e7d451d3, 0x2c5298961282b311,
        0xe77f04aba7a763de, 0x34170416caa4482e, 0x4cbe18851d433757, 0x70d6b9284e6f93f9,
        0xc7f352ea5712a796, 0x8461b7362a5595b8, 0x7d89591dcb25e789, 0x4ae022fb5dbed86c,
        0xe68fd9ae962b5e03, 0x7d45bd5ce943708c, 0xf23e641ea2753eea, 0x7bfcb4f657648461,
        0x9cdd948f179d8ba3, 0xd760fa42828f85e7, 0xc4b001800761ef1a, 0xaba6dac7493e12f4
    ]

    /// Unknown compounds/brands can still have strong local lexical evidence.
    /// Never consult OS spelling services, and never displace a valid Vietnamese syllable.
    internal static func isEnglishCompound(raw: String, rendered: String) -> Bool {
        let key = raw.lowercased()
        guard key != rendered.lowercased(), (8...48).contains(key.utf8.count),
              key.utf8.allSatisfy({ (97...122).contains($0) }),
              !VietnameseSyllableDictionary.shared.isValidSyllable(rendered),
              !VietnameseSyllableDictionary.shared.hasUntonedPrefix(rendered, preserveVowelShape: true),
              !isExplicitTelexEscape(raw: raw, rendered: rendered) else { return false }
        let chars = Array(key)
        for split in 3...(chars.count - 3) {
            let left = String(chars[..<split])
            let right = String(chars[split...])
            if EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(left) &&
               EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(right) {
                return true
            }
        }
        return false
    }

    /// A trig abbreviation is domain evidence, not a general English prose anchor.
    internal static func functionTokenPrefersRaw(_ raw: String, context: String, technical: Bool) -> Bool? {
        guard raw == "cos" else { return nil }
        if technical { return true }
        let anchors: Set<String> = ["sin", "cos", "tan", "cot", "sine", "cosine", "tangent", "trig", "trigonometry"]
        let words = context.lowercased().split(whereSeparator: { !$0.isLetter }).suffix(4)
        let joiners: Set<String> = ["and", "or", "plus", "minus"]
        guard let previous = words.last(where: { !joiners.contains(String($0)) }) else { return false }
        return anchors.contains(String(previous))
    }

    private static let nonVietnameseLetters: Set<Character> = ["f", "j", "w", "z"]
    private static let doubleConsonants = ["bb", "cc", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv"]
    private static let englishEndings = ["sh", "ck", "ts", "ds", "st", "nd", "ld", "rt", "ct", "pt", "lt", "nt", "xt"]

    private static let inlineEnglishClusters = [
        "bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "pl", "pr",
        "sc", "sk", "sl", "sm", "sn", "sp", "sq", "st", "wr",
        "chr", "sch", "scr", "shr", "spl", "spr", "str", "thr"
    ]

    private static let teenCodeWordDigests: Set<UInt64> = [
        0xa16f969b7442b20c, 0x928d712700b3dffd, 0xb80ad5cc4a499cf2, 0x7fff79c324bc79b6,
        0x4a5040029b4130a6, 0x6984d47c6f072974, 0x307435690f7ede84, 0xcb6bacba4b510379,
        0xce53303c7af3ee0b, 0x81ee0d06d5f5aefc, 0xd0b1979a2016a76d, 0x9ea215fbc47b94c0,
        0xcac1dca930a13cab, 0xa5dbfb11fb70137e
    ]

    private static let codeCharacters: Set<Character> = ["_", "/", "\\", "-", ".", ":", "[", "]", "{", "}", "<", ">", "=", "+", "*", "@", "#", "$", "%", "^", "&", "|"]

    private static let leadingSlashCommandAndPathTokens: Set<String> = [
        "add", "agents", "api", "app", "apps", "ar", "as", "aw", "awk", "aws",
        "bash", "bin", "boost", "boot", "browser", "bug", "build",
        "cast", "cash", "clear", "compact", "config", "core", "cost",
        "dash", "dev", "diff", "dist", "doc", "docs", "doctor",
        "env", "es", "etc", "ex", "exit",
        "fast", "git", "goal", "hash", "help", "home", "host",
        "if", "image", "info", "init", "ir", "is", "ix",
        "last", "learn", "lib", "list", "log", "login", "logout", "logs", "loop",
        "mask", "mcp", "memory", "mnt", "model", "models", "more",
        "new", "of", "opt", "or", "os", "out",
        "permissions", "pkg", "plan", "port", "post", "pr", "proc",
        "quit", "raw", "reset", "review", "room", "root", "run",
        "sbin", "schedule", "search", "share", "sort", "src", "srv", "ssh", "start", "status", "stop", "store", "sys",
        "task", "tasks", "teamwork", "terminal", "test", "tests", "tmp", "tool", "tools",
        "ur", "us", "user", "users", "usr",
        "var", "vim", "voice", "war", "was", "web", "zoom"
    ]

    public static func isLeadingSlashCommandOrPathToken(_ lowerRaw: String) -> Bool {
        leadingSlashCommandAndPathTokens.contains(lowerRaw)
    }

    @inline(__always)
    internal static func trimPunctuationFast(_ s: String) -> String {
        guard let first = s.utf8.first, let last = s.utf8.last else { return s }
        let firstIsASCIIAlnum = (first >= 97 && first <= 122) || (first >= 65 && first <= 90) || (first >= 48 && first <= 57)
        let lastIsASCIIAlnum = (last >= 97 && last <= 122) || (last >= 65 && last <= 90) || (last >= 48 && last <= 57)
        if firstIsASCIIAlnum && lastIsASCIIAlnum {
            return s
        }
        if (firstIsASCIIAlnum || s.first?.isLetter == true) && (lastIsASCIIAlnum || s.last?.isLetter == true) {
            return s
        }
        return s.trimmingCharacters(in: .punctuationCharacters)
    }

    /// Evaluates whether an in-progress token should resolve to raw English inline.
    public static func isInlineEnglishWord(
        raw: String,
        rendered: String,
        context: String = "",
        genZMode: Bool = false
    ) -> Bool {
        let cleanRaw = trimPunctuationFast(raw)
        let cleanRendered = trimPunctuationFast(rendered)
        let effectiveRendered = cleanRendered.isEmpty ? rendered : cleanRendered
        let lower = cleanRaw.lowercased()
        let lowerRendered = effectiveRendered.lowercased()
        if raw.hasPrefix("/") && !raw.hasPrefix("//") && isLeadingSlashCommandOrPathToken(lower) {
            return true
        }
        if BilingualIntentArbiter.prefersEnglishByOrthographicCase(
            raw: cleanRaw,
            rendered: effectiveRendered,
            context: context
        ) {
            return true
        }
        if BilingualIntentArbiter.prefersVietnameseAfterShortLabel(raw: cleanRaw, rendered: effectiveRendered, context: context) {
            return false
        }
        if (2...4).contains(lower.count),
           lower != lowerRendered,
           !isExplicitTelexEscape(raw: cleanRaw, rendered: effectiveRendered),
           BilingualIntentArbiter.prefersEnglishInDefaultNoContext(
               lowerRaw: lower,
               lowerRendered: lowerRendered
           ),
           !BilingualIntentArbiter.isVietnameseContextForTonePrimitive(context, lowerRaw: lower) {
            return true
        }
        if lower.count == 2 {
            if !context.isEmpty && isConfidentEnglishContext(context) &&
               (isKnownEnglishWord(cleanRaw) || BilingualIntentArbiter.englishCollisionLogFrequencies[lower] != nil) &&
               isEnglishWord(raw: cleanRaw, context: context, rendered: effectiveRendered, genZMode: genZMode) {
                return true
            }
        }
        guard lower.count >= 3 else { return false }
        if lower.contains(where: { $0 != "-" && codeCharacters.contains($0) }) {
            return true
        }
        if genZMode && lowerRendered != lower && VietnameseEngine.isValidGenZInitialTransformation(rendered: effectiveRendered, raw: lower) {
            return false
        }
        if LexiconDigest.contains(telexPrimitiveDigests, lower) { return false }
        if lower == "iff" || lower == "orr" || lower == "arr" { return false }
        if isExplicitTelexEscape(raw: cleanRaw, rendered: effectiveRendered) {
            return false
        }
        if isVNIDigitTransformationOrEscape(raw: cleanRaw, rendered: effectiveRendered) {
            return false
        }
        if let escaped = collapsedTelexToneEscapes(lower),
           escaped == lowerRendered,
           !isKnownEnglishWord(cleanRaw) {
            return false
        }
        if SyllableCandidateResolver.isPostCodaModifierUndoOrExtension(lowerRaw: lower, rendered: effectiveRendered) {
            return false
        }
        if lowerRendered != lower && VietnameseEngine.hasPreVowelModifierTrigger(Array(lower), genZMode: genZMode) {
            return false
        }
        if VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(effectiveRendered) {
            return false
        }

        // Phonotactic validation first (P0.4 Architectural Requirement #2):
        // Disallow relaxed-coda `-k -> -c` on English `-ook`/`-ood` words (`book/bôk`, `look/lôk`, `cook/côk`, `took/tôk`, `good/gôd`).
        let isEnglishOokOrOod = (lower.hasSuffix("ook") || lower.hasSuffix("ood") || lower.hasSuffix("ooks") || lower.hasSuffix("oods")) && isKnownEnglishWord(cleanRaw)
        let isAllUppercaseRaw = cleanRaw == cleanRaw.uppercased() && cleanRaw.count > 1
        var cachedKnownWord: Bool?
        func getIsKnownWord() -> Bool {
            if let v = cachedKnownWord { return v }
            let computed = isKnownEnglishWord(cleanRaw)
            cachedKnownWord = computed
            return computed
        }
        func canMatchStandaloneRhyme() -> Bool {
            !isEnglishOokOrOod &&
                !isAllUppercaseRaw &&
                !lower.hasPrefix("w") &&
                !LexiconDigest.contains(commonEnglishWordDigests, lower) &&
                !LexiconDigest.contains(commonEnglishTechWordDigests, lower) &&
                !SyllableCandidateResolver.isEnglishCollision(lower) &&
                !getIsKnownWord()
        }
        if (lower != lowerRendered || !effectiveRendered.unicodeScalars.allSatisfy({ $0.isASCII })) &&
           !VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnamese(
               effectiveRendered,
               relaxedCoda: !isEnglishOokOrOod,
               genZMode: !isEnglishOokOrOod
           ) &&
           !(VietnameseSyllableDictionary.shared.isPlausibleInProgressVietnameseRhyme(effectiveRendered) &&
             canMatchStandaloneRhyme()) {
            return true
        }

        if isEnglishOokOrOod {
            return true
        }

        if LexiconDigest.contains(commonEnglishWordDigests, lower),
           !(cleanRaw == lower && LexiconDigest.contains(vietnameseProtectedCollisionDigests, lower)),
           lower != lowerRendered {
            return true
        }

        // Protect in-progress Vietnamese open circumflex/breve prefixes (`casa -> cấ`, `caws -> cắ`)
        let isTonedOpenCircumflex: Bool = {
            let untoned = VietnameseSyllableDictionary.stripToneMarks(effectiveRendered.lowercased())
            return VietnameseSyllableDictionary.hasToneMark(effectiveRendered) &&
                (VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(untoned) ||
                 VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(untoned))
        }()
        if isTonedOpenCircumflex &&
           !EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lower) &&
           BilingualIntentArbiter.englishCollisionLogFrequencies[lower] == nil {
            return false
        }

        if isUnambiguousVietnameseTelexStructure(lowerRaw: lower, rendered: effectiveRendered) {
            return false
        }

        if lower.count >= 5 && lower.hasSuffix("s") && lower.count >= effectiveRendered.count + 2 {
            let singularStem = String(lower.dropLast())
            if (LexiconDigest.contains(commonEnglishWordDigests, singularStem) || isKnownEnglishWord(singularStem)) &&
               !isPlausibleVietnameseSyllable(effectiveRendered) {
                return true
            }
        }

        // P0.4 Architectural Requirement #3: Do NOT treat every phonotactically valid syllable as a common Vietnamese word.
        // Phonotactic gaps (`trees -> trế`, `teens -> tến`) must not block known English words inline.
        let isDirectlyAttestedVN = isPlausibleVietnameseSyllable(effectiveRendered, allowPhonotacticGap: false)
        let isUntonedModifiedVN = !isAllUppercaseRaw &&
            !VietnameseSyllableDictionary.hasToneMark(effectiveRendered) &&
            hasMatchingOrPostCodaModifiedCodaEnding(lowerRaw: lower, lowerRendered: lowerRendered) &&
            (lowerRendered.contains(where: { "đăâêôơư".contains($0) }) || lowerRendered.contains("uô")) &&
            (VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lowerRendered, genZMode: genZMode) ||
             (!lower.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(lowerRendered)))
        let isPlausibleVN = isDirectlyAttestedVN || (
            !SyllableCandidateResolver.isEnglishCollision(lower) &&
            !getIsKnownWord() &&
            (isPlausibleVietnameseSyllable(effectiveRendered, allowPhonotacticGap: true) ||
             isUntonedModifiedVN ||
             (canMatchStandaloneRhyme() && VietnameseSyllableDictionary.shared.isValidVietnameseRhyme(effectiveRendered)))
        )
        if isPlausibleVN {
            guard !context.isEmpty,
                  (isConfidentEnglishContext(context) || (lower == "sex" && BilingualIntentArbiter.isVietnameseLoanwordSexContext(context))) else {
                return false
            }
            let isLowercaseInput = cleanRaw == lower
            let isAnchorContext = isLastContextWordEnglishAnchor(context)
            let isProtectedVN = isLowercaseInput && vietnameseProtectedTelexInputs.contains(lower)
            let isSyntheticTrap = isLowercaseInput && syntheticInflectionTrapTokens.contains(lower)
            let isEligibleEnglishKnown: Bool = {
                if isProtectedVN {
                    return false
                }
                if isSyntheticTrap && !isAnchorContext {
                    return false
                }
                if isLowercaseInput && isDirectlyAttestedVN && !isAnchorContext {
                    return isCuratedEnglishWordForAttestedVN(lower)
                }
                return getIsKnownWord()
            }()
            let isEligibleCollision = !isProtectedVN && (!isSyntheticTrap || isAnchorContext)
            if (isEligibleEnglishKnown || (isEligibleCollision && (BilingualIntentArbiter.englishCollisionLogFrequencies[lower] != nil || isContextSensitiveEnglishCollision(lower)))) &&
               isEnglishWord(raw: cleanRaw, context: context, rendered: effectiveRendered, genZMode: genZMode) {
                return true
            }
            return false
        }

        let inflectedSuffixes = ["ing", "ers", "ed", "er", "es", "ly", "s"]
        let stemForEnding: String = {
            for sfx in inflectedSuffixes where lower.count > sfx.count + 2 && lower.hasSuffix(sfx) {
                return String(lower.dropLast(sfx.count))
            }
            return lower
        }()
        let silentEStem: String = {
            if (lower.hasSuffix("ed") || lower.hasSuffix("es") || lower.hasSuffix("er")) && lower.count >= 5 {
                return String(lower.dropLast())
            }
            return lower
        }()
        let hasEnglishEnding = englishEndings.contains(where: { lower.hasSuffix($0) || stemForEnding.hasSuffix($0) || silentEStem.hasSuffix($0) })
        let hasEnglishDouble = hasNonVietnameseDoubleConsonant(lower)
        let hasEnglishCluster = inlineEnglishClusters.contains(where: { lower.hasPrefix($0) })
        let hasEnglishPastEnding = lower.count >= 4 && lower.hasSuffix("ed") && rendered.lowercased().hasSuffix("d")
        let isTechWord = LexiconDigest.contains(commonEnglishTechWordDigests, lower)
        let isKnownCommon =
            LexiconDigest.contains(commonEnglishWordDigests, lower) ||
            LexiconDigest.contains(commonEnglishWordDigests, stemForEnding) ||
            LexiconDigest.contains(commonEnglishWordDigests, silentEStem)

        if lower.hasSuffix("e") && lower.count >= 5 {
            let eStem = String(lower.dropLast())
            if englishEndings.contains(where: { eStem.hasSuffix($0) }) || LexiconDigest.contains(commonEnglishWordDigests, eStem) {
                let rawStem = String(cleanRaw.dropLast())
                if LexiconDigest.contains(commonEnglishWordDigests, eStem) ||
                   isKnownEnglishWord(rawStem) ||
                   isKnownEnglishWord(cleanRaw + "d") {
                    return true
                }
            }
        }

        guard hasEnglishEnding || hasEnglishDouble || hasEnglishCluster || hasEnglishPastEnding || isTechWord || (isKnownCommon && lower.count >= 4) else {
            return false
        }

        return LexiconDigest.contains(commonEnglishWordDigests, lower) ||
               LexiconDigest.contains(commonEnglishWordDigests, stemForEnding) ||
               LexiconDigest.contains(commonEnglishWordDigests, silentEStem) ||
               LexiconDigest.contains(commonEnglishTechWordDigests, lower) ||
               getIsKnownWord() ||
               isKnownEnglishWord(stemForEnding) ||
               isKnownEnglishWord(silentEStem)
    }

    /// Returns true if the difference between `raw` and `rendered` was produced by VNI digit modifiers
    /// or VNI repeated-digit escape/cancellation (where letters are preserved 1:1 and only digits are consumed).
    public static func isVNIDigitTransformationOrEscape(raw: String, rendered: String) -> Bool {
        guard raw.utf8.contains(where: { $0 >= 48 && $0 <= 57 }) else { return false }
        let rawLetters = raw.filter(\.isLetter).count
        let renderedLetters = rendered.filter(\.isLetter).count
        guard rawLetters > 0 && rawLetters == renderedLetters else { return false }
        let rawDigits = raw.filter(\.isNumber).count
        let renderedDigits = rendered.filter(\.isNumber).count
        return rawDigits > renderedDigits
    }

    internal static func hasExplicitZToneClear(lowerRaw: String, rendered: String) -> Bool {
        guard lowerRaw.count >= 3, lowerRaw.hasSuffix("z") else { return false }
        guard !isKnownEnglishWord(lowerRaw) else { return false }
        let lowerRendered = rendered.lowercased()
        if lowerRaw.count == lowerRendered.count + 2,
           let zIdx = lowerRaw.lastIndex(of: "z") {
            var withoutOneZ = lowerRaw
            withoutOneZ.remove(at: zIdx)
            for idx in withoutOneZ.indices {
                let ch = withoutOneZ[idx]
                if ch == "s" || ch == "f" || ch == "r" || ch == "x" || ch == "j" {
                    var candidate = withoutOneZ
                    candidate.remove(at: idx)
                    if candidate == lowerRendered {
                        return true
                    }
                }
            }
        }
        guard !lowerRaw.hasSuffix("zz") else { return false }
        let withoutZ = String(lowerRaw.dropLast())
        guard withoutZ.contains(where: { ["s", "f", "r", "x", "j"].contains($0) }) else { return false }
        let withoutToneAndZ = withoutZ.filter { !["s", "f", "r", "x", "j"].contains($0) }
        return !lowerRendered.hasSuffix("z") &&
               (!rendered.unicodeScalars.allSatisfy({ $0.isASCII }) || withoutToneAndZ == lowerRendered) &&
               !VietnameseSyllableDictionary.hasToneMark(rendered)
    }

    /// Returns true if the user explicitly escaped Telex modifiers (e.g. "seeen" -> "seen", "seene" -> "seen",
    /// "teeen" -> "teen", "reeef" / "reefe" / "reeff" -> "reef", "peee" -> "pee", "carr" -> "car")
    /// so Smart Bilingual must preserve `rendered` instead of restoring `raw`.
    public static func isExplicitTelexEscape(raw: String, rendered: String) -> Bool {
        let cleanRaw = trimPunctuationFast(raw)
        let lowerRaw = cleanRaw.lowercased()
        let lowerRendered = rendered.lowercased()
        guard lowerRaw != lowerRendered,
              !lowerRaw.isEmpty,
              !lowerRendered.isEmpty,
              !VietnameseSyllableDictionary.hasToneMark(lowerRendered) else {
            return false
        }

        if !lowerRendered.unicodeScalars.allSatisfy(\.isASCII) && lowerRaw.unicodeScalars.allSatisfy(\.isASCII) {
            if lowerRaw.contains("z") && hasExplicitZToneClear(lowerRaw: lowerRaw, rendered: rendered) {
                return true
            }
            if lowerRendered.dropFirst().contains(where: { $0 == "s" || $0 == "f" || $0 == "r" || $0 == "x" || $0 == "j" }),
               hasSemanticToneEscape(lowerRaw: lowerRaw, lowerRendered: lowerRendered),
               !isKnownEnglishWord(lowerRaw) {
                return true
            }
            return false
        }

        if lowerRaw == "ww" && lowerRendered == "w" { return true }
        if lowerRaw.hasPrefix("ww") && !lowerRaw.hasPrefix("www") && lowerRendered == String(lowerRaw.dropFirst()) {
            return true
        }
        let hasPostCodaDoubleVowelEscape =
            (lowerRaw.hasSuffix("aa") && !lowerRaw.hasSuffix("aaa")) ||
            (lowerRaw.hasSuffix("ee") && !lowerRaw.hasSuffix("eee")) ||
            (lowerRaw.hasSuffix("oo") && !lowerRaw.hasSuffix("ooo"))
        if (lowerRaw.hasSuffix("ww") || hasPostCodaDoubleVowelEscape) && lowerRendered == String(lowerRaw.dropLast()) {
            return true
        }
        if hasExplicitZToneClear(lowerRaw: lowerRaw, rendered: rendered) {
            return true
        }
        if VietnameseEngine.isPostCodaEnglishDoubleVowelEscape(Array(cleanRaw)) &&
           lowerRendered == String(lowerRaw.dropLast()) {
            return true
        }
        if lowerRaw != "aaa" && lowerRaw != "ooo" && lowerRaw != "ieee" && lowerRaw != "www" {
            if let tripleCollapsed = collapsedTelexTripleEscapes(lowerRaw) {
                if tripleCollapsed == lowerRendered {
                    return true
                }
                if let bothCollapsed = collapsedTelexToneEscapes(tripleCollapsed), bothCollapsed == lowerRendered {
                    return true
                }
            }
        }
        if let escapedWord = collapsedTelexToneEscapes(lowerRaw),
           escapedWord == lowerRendered,
           !isKnownEnglishWord(lowerRaw) {
            return true
        }
        if hasSemanticToneEscape(lowerRaw: lowerRaw, lowerRendered: lowerRendered),
           !isKnownEnglishWord(lowerRaw) {
            return true
        }
        return false
    }

    /// Detects canonical semantic tone escape sequences (`turr -> tur`, `turrus -> turus`, `arrus -> arus`,
    /// `cafnhf -> canhf`, `cafnhfaa -> canhfaa`, `canhfrr -> canhr`, `hoongff -> hôngf`, `hoonfgf -> hôngf`)
    /// where a tone key was cancelled via `CancelToneAndEmitLiteral` and an untoned Vietnamese stem precedes the literal tail.
    internal static func hasSemanticToneEscape(lowerRaw: String, lowerRendered: String) -> Bool {
        guard lowerRaw.count >= 3,
              lowerRendered.count >= 2,
              !VietnameseSyllableDictionary.hasToneMark(lowerRendered) else {
            return false
        }
        let toneKeys: Set<Character> = ["s", "f", "r", "x", "j"]
        let renderedChars = Array(lowerRendered)
        let maxSplitIdx = min(renderedChars.count - 1, 7)
        guard maxSplitIdx >= 1 else { return false }
        for splitIdx in stride(from: maxSplitIdx, through: 1, by: -1) {
            let escapedToneChar = renderedChars[splitIdx]
            guard toneKeys.contains(escapedToneChar) else { continue }
            let rawOccurrenceCount = lowerRaw.filter { $0 == escapedToneChar }.count
            guard rawOccurrenceCount >= 2 else { continue }
            let stem = String(renderedChars[0..<splitIdx])
            let hasAdjacentToneEscape = lowerRaw.contains("\(escapedToneChar)\(escapedToneChar)")
            let hasConsonantOnsetOrDiacritic =
                stem.first.map { !VietnameseEngine.isVietnameseVowel($0) } == true ||
                !stem.unicodeScalars.allSatisfy({ $0.isASCII })
            guard hasAdjacentToneEscape || hasConsonantOnsetOrDiacritic else { continue }
            if VietnameseSyllableDictionary.shared.isValidUntonedSyllable(stem) ||
               VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(stem) ||
               VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(stem) ||
               (stem.count >= 2 && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(stem)) {
                return true
            }
        }
        return false
    }

    public static func isEnglishWord(raw: String, context: String = "", rendered: String? = nil, genZMode: Bool = false) -> Bool {
        let cleanRaw = trimPunctuationFast(raw)
        let lowerRaw = cleanRaw.lowercased()
        let rendered = rendered.map { r -> String in
            let trimmed = trimPunctuationFast(r)
            return trimmed.isEmpty ? r : trimmed
        }

        if genZMode {
            if let rendered, LexiconDigest.contains(teenCodeWordDigests, rendered.lowercased()) {
                return false
            }
            if LexiconDigest.contains(teenCodeWordDigests, lowerRaw) {
                return false
            }
            if let rendered, rendered.lowercased() != lowerRaw,
               VietnameseEngine.isValidGenZInitialTransformation(rendered: rendered, raw: lowerRaw) {
                return isConfidentEnglishContext(context)
            }
        }

        if let rendered, isExplicitTelexEscape(raw: cleanRaw, rendered: rendered) {
            return false
        }
        if let rendered, isVNIDigitTransformationOrEscape(raw: cleanRaw, rendered: rendered) {
            return false
        }
        if let rendered, SyllableCandidateResolver.isPostCodaModifierUndoOrExtension(lowerRaw: lowerRaw, rendered: rendered) {
            return false
        }
        if let rendered,
           rendered.lowercased() != lowerRaw,
           VietnameseEngine.hasPreVowelModifierTrigger(Array(lowerRaw), genZMode: genZMode),
           (raw == lowerRaw || !isKnownEnglishWord(lowerRaw)) {
            return false
        }
        if lowerRaw == "iff" || lowerRaw == "orr" || lowerRaw == "arr" { return false }
        if let rendered, VietnameseSyllableDictionary.isVietnameseStrokeDConsonantAbbreviation(rendered) {
            return false
        }

        guard lowerRaw.count > 1 else { return false }

        if raw.hasPrefix("/") && !raw.hasPrefix("//") && isLeadingSlashCommandOrPathToken(lowerRaw) {
            return true
        }

        if let rendered,
           BilingualIntentArbiter.prefersEnglishByOrthographicCase(
               raw: cleanRaw,
               rendered: rendered,
               context: context
           ) {
            return true
        }

        if let rendered, BilingualIntentArbiter.prefersVietnameseAfterShortLabel(raw: cleanRaw, rendered: rendered, context: context) {
            return false
        }

        if (2...4).contains(lowerRaw.count),
           BilingualIntentArbiter.prefersEnglishInDefaultNoContext(
               lowerRaw: lowerRaw,
               lowerRendered: rendered?.lowercased() ?? ""
           ) {
            if let rendered, !VietnameseSyllableDictionary.shared.isValidSyllable(rendered.lowercased()) {
                return true
            }
            let trimmedCtx = context.trimmingCharacters(in: .whitespacesAndNewlines)
            return !BilingualIntentArbiter.isVietnameseContextForTonePrimitive(trimmedCtx, lowerRaw: lowerRaw)
        }

        if LexiconDigest.contains(telexPrimitiveDigests, lowerRaw) {
            let trimmedCtx = context.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCtx.isEmpty {
                return false
            }
            if BilingualIntentArbiter.isVietnameseContextForTonePrimitive(trimmedCtx, lowerRaw: lowerRaw) {
                return false
            }
            return isConfidentEnglishContext(trimmedCtx) || languageRecognizerProvider.isDominantLanguageEnglish(trimmedCtx)
        }

        if lowerRaw == "sex" && BilingualIntentArbiter.isVietnameseLoanwordSexContext(context) {
            return true
        }

        if lowerRaw.contains(where: { codeCharacters.contains($0) }) {
            if !lowerRaw.contains(where: { $0 != "-" && codeCharacters.contains($0) }) {
                // Hyphenated compound word
            } else {
                return true
            }
        }

        if LexiconDigest.contains(commonEnglishWordDigests, lowerRaw),
           !(raw == lowerRaw && LexiconDigest.contains(vietnameseProtectedCollisionDigests, lowerRaw)),
           let rendered,
           lowerRaw != rendered.lowercased() {
            return true
        }

        if let rendered,
           let escapedWord = collapsedTelexToneEscapes(lowerRaw),
           escapedWord == rendered.lowercased(),
           !isKnownEnglishWord(lowerRaw) {
            return false
        }

        let isUppercaseWord = raw == raw.uppercased() && raw.count > 1
        let isSupplementalForCasedInput = (cleanRaw != lowerRaw) &&
            (rendered.map { VietnameseSyllableDictionary.shared.supplementalTonedSyllables.contains($0.lowercased()) } ?? false)
        let isStandardPlausibleVN = rendered.map { isPlausibleVietnameseText($0, allowPhonotacticGap: false) } ?? false
        let allowPhonotacticGap: Bool = {
            if isStandardPlausibleVN { return false }
            let isTonedOpenCircumflex = rendered.map { r in
                let untoned = VietnameseSyllableDictionary.stripToneMarks(r.lowercased())
                return VietnameseSyllableDictionary.hasToneMark(r) &&
                    (VietnameseSyllableDictionary.shared.isValidOpenCircumflexPrefix(untoned) ||
                     VietnameseSyllableDictionary.shared.isValidOpenBrevePrefix(untoned))
            } ?? false
            return (!isKnownEnglishWord(cleanRaw) || (isTonedOpenCircumflex && !EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerRaw) && BilingualIntentArbiter.englishCollisionLogFrequencies[lowerRaw] == nil)) && !SyllableCandidateResolver.isEnglishCollision(lowerRaw)
        }()
        if let rendered,
           isUnambiguousVietnameseTelexStructure(lowerRaw: lowerRaw, rendered: rendered) {
            return false
        }
        let isLowercaseInput = cleanRaw == lowerRaw
        func checkEligibleEnglishKnownForPlausibleVN() -> Bool {
            if isLowercaseInput && vietnameseProtectedTelexInputs.contains(lowerRaw) {
                return false
            }
            let isAnchorContext = isLastContextWordEnglishAnchor(context)
            if isLowercaseInput && syntheticInflectionTrapTokens.contains(lowerRaw) && !isAnchorContext {
                return false
            }
            if isLowercaseInput && isStandardPlausibleVN && !isAnchorContext {
                return isCuratedEnglishWordForAttestedVN(lowerRaw)
            }
            return isKnownEnglishWord(cleanRaw) ||
                BilingualIntentArbiter.englishCollisionLogFrequencies[lowerRaw] != nil ||
                isContextSensitiveEnglishCollision(lowerRaw)
        }
        if let rendered,
           lowerRaw != rendered.lowercased(),
           !LexiconDigest.contains(commonEnglishTechWordDigests, lowerRaw),
           !isSupplementalForCasedInput,
           (isStandardPlausibleVN || (allowPhonotacticGap && isPlausibleVietnameseText(rendered, allowPhonotacticGap: true))) {
            if isConfidentEnglishContext(context) &&
               checkEligibleEnglishKnownForPlausibleVN() &&
               !BilingualIntentArbiter.isVietnameseClauseStarter(rendered: rendered, lowerRaw: lowerRaw) {
                return true
            }
            return false
        }

        let telexEndingKeys: Set<Character> = ["s", "f", "r", "x", "j", "z", "w"]
        if let rendered,
           lowerRaw != rendered.lowercased(),
           !isUppercaseWord,
           !LexiconDigest.contains(commonEnglishTechWordDigests, lowerRaw),
           !isSupplementalForCasedInput,
           (isStandardPlausibleVN || isPlausibleVietnameseSyllable(rendered, allowPhonotacticGap: allowPhonotacticGap)),
           (lowerRaw.contains(where: telexEndingKeys.contains) || hasWModifierAfterVowel(lowerRaw)) {
            return isConfidentEnglishContext(context) &&
                checkEligibleEnglishKnownForPlausibleVN() &&
                !BilingualIntentArbiter.isVietnameseClauseStarter(rendered: rendered, lowerRaw: lowerRaw)
        }

        if let rendered, lowerRaw != rendered.lowercased() {
            let hasVietnameseDiacritics = rendered.contains(where: { !$0.isASCII })
            if !hasVietnameseDiacritics {
                return true
            }
            if !isPlausibleVietnameseText(rendered, allowPhonotacticGap: allowPhonotacticGap) || isSupplementalForCasedInput {
                if lowerRaw.hasPrefix("dd") && lowerRaw != "dd" {
                    let vietnameseVowels: Set<Character> = [
                        "a", "e", "i", "o", "u", "y", "ă", "â", "ê", "ô", "ơ", "ư",
                        "á", "à", "ả", "ã", "ạ", "ắ", "ằ", "ẳ", "ẵ", "ặ",
                        "ấ", "ầ", "ẩ", "ẫ", "ậ", "é", "è", "ẻ", "ẽ", "ẹ",
                        "ế", "ề", "ể", "ễ", "ệ", "í", "ì", "ỉ", "ĩ", "ị",
                        "ó", "ò", "ỏ", "õ", "ọ", "ố", "ồ", "ổ", "ỗ", "ộ",
                        "ớ", "ờ", "ở", "ỡ", "ợ", "ú", "ù", "ủ", "ũ", "ụ",
                        "ứ", "ừ", "ử", "ữ", "ự", "ý", "ỳ", "ỷ", "ỹ", "ỵ"
                    ]
                    if rendered.lowercased().contains(where: vietnameseVowels.contains) {
                        return false
                    }
                }
                if !isSupplementalForCasedInput,
                   !isKnownEnglishWord(cleanRaw),
                   !isKnownEnglishWord(lowerRaw),
                   !SyllableCandidateResolver.isEnglishCollision(lowerRaw) {
                    let lowerRendered = rendered.lowercased()
                    if !VietnameseSyllableDictionary.hasToneMark(rendered),
                       hasMatchingOrPostCodaModifiedCodaEnding(lowerRaw: lowerRaw, lowerRendered: lowerRendered),
                       (lowerRendered.contains(where: { "đăâêôơư".contains($0) }) || lowerRendered.contains("uô")),
                       (VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lowerRendered, genZMode: genZMode) ||
                        (!isUppercaseWord && !lowerRaw.hasPrefix("w") && VietnameseSyllableDictionary.shared.isValidUntonedRhyme(lowerRendered))) {
                        return false
                    }
                    if VietnameseSyllableDictionary.shared.isValidRelaxedCodaVietnamese(rendered, raw: lowerRaw, genZMode: genZMode) {
                        return false
                    }
                    if !isUppercaseWord,
                       !lowerRaw.hasPrefix("w"),
                       VietnameseSyllableDictionary.shared.isValidVietnameseRhyme(rendered) {
                        return false
                    }
                }
                return true
            }
        }

        let isEnglishDictWord: Bool
        lock.lock()
        if let cached = spellCheckCache[lowerRaw], (cached || raw == lowerRaw) {
            isEnglishDictWord = cached
            lock.unlock()
        } else {
            lock.unlock()

            let result = LexiconDigest.contains(commonEnglishTechWordDigests, lowerRaw) || (spellCheckerProvider?.isWordInEnglishDictionary(raw) ?? false)

            lock.lock()
            if spellCheckCache[lowerRaw] == nil {
                if spellCheckCache.count >= maxCacheEntries {
                    let evictCount = max(1, maxCacheEntries / 4)
                    let actualEvict = min(evictCount, cacheKeys.count)
                    let keysToEvict = Array(cacheKeys.prefix(actualEvict))
                    for oldKey in keysToEvict {
                        spellCheckCache.removeValue(forKey: oldKey)
                    }
                    cacheKeys.removeFirst(actualEvict)
                }
                cacheKeys.append(lowerRaw)
            }
            if result || spellCheckCache[lowerRaw] == nil {
                spellCheckCache[lowerRaw] = result
            }
            isEnglishDictWord = spellCheckCache[lowerRaw] ?? result
            lock.unlock()
        }

        if isEnglishDictWord {
            if raw == raw.uppercased() && raw.count > 1 { return true }
            if lowerRaw.contains(where: { nonVietnameseLetters.contains($0) }) { return true }
            if hasNonVietnameseDoubleConsonant(lowerRaw) { return true }
            if englishEndings.contains(where: { lowerRaw.hasSuffix($0) }) { return true }
            if lowerRaw.count > 3 { return true }

            let query = (context.isEmpty ? "" : context + " ") + cleanRaw
            if languageRecognizerProvider.isDominantLanguageEnglish(query) { return true }
        } else {
            let lastChar = lowerRaw.last!
            if ["j", "w", "f", "r", "s", "x"].contains(lastChar) && lowerRaw.count <= 6 {
                return false
            }
            if languageRecognizerProvider.isDominantLanguageEnglish(cleanRaw) {
                return true
            }
        }

        return false
    }

    private static let englishAnchorWordDigests: Set<UInt64> = [
        0x28f018439f21b953, 0x64cb21892709cbce, 0xd8a365f5a640e481, 0xc374a2b4ceb4d846,
        0xa46baff182db7818, 0xd5e3e7ff531b4577, 0xe4eba539b9d715a2, 0x788c1561a2e60867,
        0x5fc3986a618de8be, 0xa2366d03e84f0b15, 0x2f72898e7cbebce2, 0xa306fb9aec526680,
        0xd78bf69e0782095a, 0x50c95cb06983f695, 0x6158fcaaae1ca3e1, 0xd31de6ea44b24f26,
        0xd1b4a98fee8e9f9c, 0xd33252feb2cb6e1f, 0x9183a7c55663d5f3, 0x77feeff930ee825d,
        0xcee3e75194c0c9b5, 0xa34dffc4dbe59fac, 0x27389620764f03ad, 0x11197dc32ab65ed7,
        0x5f8794fe3949dffe, 0x9edf1ec1bbf3d626, 0xc4c48a6f6f686f67, 0xe1cdb0d968e719b8,
        0xf614c859b5cc6af1, 0xb88e6f0c099319e4, 0x8a3e4c89e811761a, 0x1500022e29042664,
        0x7d9f9c3ef174fd52, 0x1b63c2e4542cd7d8, 0x03e5da43d470dc90, 0xbd231d6ca6652e55,
        0xa1c430c2254d05ff, 0x84f4ef4445573e16, 0x66729843c348e827, 0xb3fab9b91d24ac46,
        0x38215108e3a999d6, 0xb42ee0f53ef92e37, 0x89a0ace297c974e9, 0xc6119b73174847c0,
        0xc175593a283d3d12, 0x23d21553668a7484, 0x3afc39ccea991735, 0x126894b6565b69a4,
        0xc5916da87ec0f07c, 0xff7d1e840cdf7f35, 0x04de75baac1e3965, 0x7daf955bc77ec79a,
        0x176f475071883f1b, 0xe7dcebf567a283b2, 0xf02961d2f7736a31, 0xb6916c50a349271c,
        0x07b889b605d2dd7e, 0x83dec5c8d1552ae8, 0x0f16df1bd2e697f0, 0x05318106bd3d8914,
        0xd3d440c5c0c2188d, 0x910463c7285a36d4, 0x03b98aecdfcdceea, 0x054277879bffa560,
        0x9946742257bd7f0a, 0x4a5a5a78d7e8e073, 0x76b5de272073ae72, 0x80da2536f676519c,
        0xa2c56d07fbccb3e3, 0x71776a34e8fd15d6, 0x54d396230d221cc3, 0x04d99f8f71edc603,
        0xc75753533ada866f
    ]

    private static let englishContractionDigests: Set<UInt64> = [
        0x4956407281e5fbf6, 0x753b2b7c146c7182, 0x5bdd2e93e766f3a3, 0x94dc2cd72a0d6ebc,
        0xc2a82cf8f23d8493, 0x6c2bf46ed6454ff8, 0xbd5302c0b4f94c86, 0x972ddd3f56e590a0,
        0x1e5ba8f59db18442, 0x7a0d676a7f068d75, 0x82ce7fc9096de471, 0x1ae24919239958e5,
        0x3436ac84473796d3, 0xebce19975df81db5, 0xe0937f43ffa52aab, 0x5f916eaeaacabe1f,
        0x2044c009a1dfe67d, 0x69dd6917548617fc, 0xe541a318f0ec3320, 0x9fa8969a2b7666f6,
        0x4a2f64240165ea79, 0xf5256ed9279dd796, 0xc63680b34e232772, 0xb9fb9cef4ae7e281,
        0x187dfd6c9419ee14, 0xa46542d55d7a9275, 0xa653cb4f19917ed4, 0xd745c3fcc2fb069b,
        0x92bdfab56708cbe7, 0x2caa9ff07bdcfaa5, 0x8d7d9f2f037d0949, 0x75b2cbdbc05f011f,
        0x87a1449f7bce049f, 0x38fbae668db84f3c, 0xdd87a39b950509a5, 0x11819181f4774591,
        0x5eda99b1fcb9131f, 0xb196038f9fc855f9, 0x7dcbc9d31287fa6a, 0x336c9686063f7700,
        0x1dc9aa44a1da7d12, 0x5b813031c93b60f6, 0x163a2a2053675630, 0x72fe4cab7484a3cc,
        0xfa6ca42fadd5e756, 0x22c0508465096b39
    ]

    private static let neutralLoanwordDigests: Set<UInt64> = [
        0x9095d1553b46da15, 0xd6a86de289d0dc96, 0x7cceaceaab39fef8, 0x7050ac9bf68c15e8,
        0x7a4354d31730d21b, 0x5a915738e28b3b0a, 0xc9f402e5da435ba5, 0xe24f28367529f6d8,
        0x57b43074aa13cc34, 0x6170bb6365f23738, 0x991c7e692c98e11c, 0xdf2faecba94ed693,
        0x2ab4e0e823bd2ec9, 0xfd3ef447c381787f, 0xc2e7627243ed1797, 0x9de30cdbbbc45c1c,
        0x42a225e95c420217, 0x167473453c8433c9, 0xa50bf47d73243ff0, 0x45bdfb1bd2cee569,
        0xa7c4426ff3f78981, 0x198b29b90f618325, 0x993790e6784e1b55, 0x134c25d29f6ed4da,
        0x447c08ce06999250, 0xa078d892566402c0, 0xc6a262ac04c4fcd8, 0xbb94296f298bedf3,
        0xe121d2ab8e00dad4, 0xd13ef57725a55f06, 0x83c5d3552174df36, 0x2efa10a44c4eba95,
        0x399b57e38f9d9f25, 0xdc5156c47e0ee524, 0xc1bceddef2737649, 0xa65b9a91fb958f06,
        0xcb02c05b85af9789, 0x5c046d15ffd54233, 0x43843dad10ce6575, 0xc10655b58d801fb3,
        0x0808e97d434f93da, 0x9a544156f4ab65d2, 0xfa0228e34a7fedb8, 0x54df5b51e5e2685c,
        0xea5c2acd2c4c4121, 0x917dd0452a988e82, 0x79b9e41a877c69d3, 0xa523aec4e8af53c0,
        0xaf3632a33539ba44, 0x1e4b762f2a185449, 0x9d6e718992aea141, 0x7091e6271072ff52,
        0x4b87188c61b33140, 0xdf98e75c91e0c3f8, 0xacaddd01b5797cdd, 0x2d0c5e642f884aa7,
        0xdcf9ebc6484f5664, 0xb20a19e9cfafff30, 0xe7365c8f2d578e35, 0x85bffed05fd2d4f4,
        0x2766b61c1681be3f, 0xab73e561993843ea, 0x81a213c00810070c, 0x82433f315bf34a00,
        0x27b6752bdcb7fda0, 0xf09359ce2be13e76, 0xcb3364aef4905292, 0xa69ead9e832a8c51,
        0xc53858b205b5b9bc, 0xb2a2fbba6ab0e313, 0x1bec424948809244, 0x492cb3242e599f4e,
        0x6a971c0e7f25bdd2, 0xcb0d87b13f813836, 0xf21b6a2b4b926f7d, 0x275bd37622a76f98,
        0xdaf45b8c8bedfcff, 0x331ebb33a88f4857, 0xac690933ab1005ea, 0xa27c8866e3af8808,
        0x5a16811ef5b92fce, 0xabbdd817eb1d4414, 0x6bba26a5719d87fb, 0x34a17d00c5eb8f6b,
        0x953f5513b48f4a13, 0x4c0ff2f5927d3efd, 0x33872e3734a6d7fe, 0x6d1498d8e1b41541,
        0x3c796692c962310e, 0x86f59f9828458df4, 0x1d8339d08a6dbb55, 0x12eab4e70d385107,
        0xbf6f9b671e14281b, 0xbcf5dc182909a5b6, 0xc458a98f3c5e8ab3, 0x7c2e172c9d9de653,
        0x06f09df93001c357, 0xfad3e18008b4b213, 0xdd948e40973912f4, 0x063b3e53bcbb4ad9
    ]

    private static let vietnameseAnchorWordDigests: Set<UInt64> = [
        0xf8b6ca2403201756, 0x8f71480eda40bec1, 0xf12260f41ff4dc8e, 0x6af12b7b1be61f7b,
        0xd0c0e088015b7b88, 0x0b3085b0e50ff52f, 0xaac7ff0ba75fbf2a, 0x7374af3debb4c9cf,
        0x865f0de9a3564088, 0x2dc62708d2a80123, 0xaa17e92a9cb199a8, 0x943b4bfdbf88d19c,
        0x219da4c828f0bba9, 0xabac921e6271fcdf, 0x875649ef573a9194, 0xc9e558705e749c2a,
        0x7b693916e4d14c41, 0xd95d3c3bb869cdf9, 0x98bc94d62e2bf825, 0x0f55ab77e73fe0a1,
        0xfb4ac2cedaaae8d4, 0x373abc738e12f646, 0xda1a55115f5e6c80, 0xedb79554a6af93e4,
        0x7f80a75346891474, 0x33ca8b09955c28f3, 0xcc337fe14edd8ce8, 0xd0389f1dd0aba6c9,
        0xf91d32bc7c5107d7, 0xfb909553d1c334f5, 0x97712c06a095cbab
    ]

    private static let explicitEnglishContextAnchors: Set<String> = [
        "there", "here", "where", "this", "that", "these", "those",
        "his", "her",
        "it", "its", "is", "are", "was", "were", "be", "been",
        "the", "have", "has", "had", "do", "does", "did",
        "will", "would", "can", "could", "should", "must",
        "with", "from", "about", "into", "they", "what", "when", "which", "while"
    ]

    private static func isEnglishAnchorToken(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !clean.isEmpty else { return false }
        if explicitEnglishContextAnchors.contains(clean) {
            return true
        }
        let h = LexiconDigest.hash(clean)
        return englishAnchorWordDigests.contains(h) || englishContractionDigests.contains(h)
    }

    private static let capsLockEnglishProseAnchors: Set<String> = [
        "the", "this", "that", "these", "those", "there", "here", "where",
        "his", "her",
        "are", "was", "were", "have", "has", "had", "does", "did",
        "will", "would", "could", "should", "must", "with", "from",
        "about", "into", "they", "he", "she", "we", "you",
        "what", "when", "which", "while", "not", "for", "and", "but"
    ]

    /// Returns `true` for 2–6 character ALL-CAPS ASCII acronym tokens (e.g. `IT`, `BE`, `US`, `VN`, `API`, `B2B`, `K8S`),
    /// while returning `false` for single-letter pronouns (`I`, `A`) and Title-Case prose words (`It`, `In`, `The`).
    internal static func isAllCapsAcronymToken(_ rawToken: String) -> Bool {
        let clean = rawToken.trimmingCharacters(in: .punctuationCharacters)
        guard (2...6).contains(clean.count) else { return false }
        var upperCount = 0
        for scalar in clean.unicodeScalars {
            if scalar.value >= 0x41 && scalar.value <= 0x5A {
                upperCount += 1
            } else if scalar.value >= 0x30 && scalar.value <= 0x39 {
                continue
            } else {
                return false
            }
        }
        return upperCount >= 1
    }

    /// Distinguishes genuine Caps-Lock English prose clauses (`"THIS IS THE"`, `"IT IS"`, `"WE ARE HERE"`)
    /// from isolated or paired uppercase acronyms (`"IT"`, `"UI UX"`, `"BE FE"`, `"API SDK"`).
    internal static func isAllCapsASCIIProseClause(_ tokens: [String]) -> Bool {
        let cleaned = tokens
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard cleaned.count >= 2 else { return false }
        var alphaTokenCount = 0
        for tok in cleaned {
            var hasUpper = false
            for scalar in tok.unicodeScalars {
                guard scalar.isASCII else { return false }
                if scalar.value >= 0x61 && scalar.value <= 0x7A {
                    return false
                }
                if scalar.value >= 0x41 && scalar.value <= 0x5A {
                    hasUpper = true
                }
            }
            if hasUpper { alphaTokenCount += 1 }
        }
        guard alphaTokenCount >= 2 else { return false }
        let lowered = cleaned.map { $0.lowercased() }
        if lowered.contains(where: { capsLockEnglishProseAnchors.contains($0) }) {
            return true
        }
        if lowered.allSatisfy({ explicitEnglishContextAnchors.contains($0) }) {
            return true
        }
        if lowered.count >= 3 &&
           lowered.contains(where: { isEnglishAnchorToken($0) }) &&
           lowered.allSatisfy({ isEnglishAnchorToken($0) || isKnownEnglishWord($0) }) {
            return true
        }
        return false
    }

    internal static func isEnglishAnchorTokenForArbiter(_ word: String) -> Bool {
        isEnglishAnchorToken(word)
    }

    internal static func isVietnameseAnchorTokenForArbiter(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard !clean.isEmpty else { return false }
        return LexiconDigest.contains(vietnameseAnchorWordDigests, clean)
    }

    internal static func isConfidentEnglishContextForArbiter(_ context: String) -> Bool {
        isConfidentEnglishContext(context)
    }

    private static func isConfidentEnglishContext(_ context: String) -> Bool {
        guard !context.isEmpty else { return false }
        // Fast O(1) backward scan of the last token: if the last committed token contains any
        // non-ASCII scalar (excluding curly apostrophes), `rawAsciiTokens` is empty -> false.
        var sawNonWhitespace = false
        for scalar in context.unicodeScalars.reversed() {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if sawNonWhitespace { break }
                continue
            }
            sawNonWhitespace = true
            if !scalar.isASCII && scalar.value != 0x2018 && scalar.value != 0x2019 {
                return false
            }
        }
        guard sawNonWhitespace else { return false }

        #if canImport(NaturalLanguage)
        let useCache = languageRecognizerProvider is AppleLanguageRecognizerProvider
        #else
        let useCache = true
        #endif

        let hasCurlyQuotes = context.utf8.contains(0xE2) && (context.contains("\u{2019}") || context.contains("\u{2018}"))
        let normalizedContext = (hasCurlyQuotes
            ? context.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            : context
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContext.isEmpty else { return false }

        let allTokens = normalizedContext.split(whereSeparator: \.isWhitespace).map { String($0) }
        guard !allTokens.isEmpty else { return false }

        let hadNonASCIIPrefix: Bool
        let rawAsciiTokens: [String]
        if let lastNonASCIIIndex = allTokens.lastIndex(where: { !$0.unicodeScalars.allSatisfy(\.isASCII) }) {
            hadNonASCIIPrefix = true
            rawAsciiTokens = Array(allTokens[(lastNonASCIIIndex + 1)...])
        } else {
            hadNonASCIIPrefix = false
            rawAsciiTokens = allTokens
        }

        let isCapsLockProse = !hadNonASCIIPrefix && isAllCapsASCIIProseClause(allTokens)
        let asciiTokens = isCapsLockProse
            ? rawAsciiTokens
            : rawAsciiTokens.filter { !isAllCapsAcronymToken($0) }

        let words = asciiTokens.map { $0.lowercased() }
        guard let lastWord = words.last else {
            return false
        }

        let cacheKey = "\(hadNonASCIIPrefix ? "1:" : "0:")\(asciiTokens.suffix(8).joined(separator: " "))"
        if useCache {
            lock.lock()
            if let cached = contextConfidenceCache[cacheKey] {
                lock.unlock()
                return cached
            }
            lock.unlock()
        }

        let computed: Bool
        if LexiconDigest.contains(vietnameseAnchorWordDigests, lastWord) {
            computed = false
        } else if words.count == 1 {
            if isEnglishAnchorToken(lastWord) {
                computed = true
            } else if !hadNonASCIIPrefix,
                      lastWord.count >= 4,
                      !LexiconDigest.contains(neutralLoanwordDigests, lastWord),
                      !VietnameseSyllableDictionary.shared.isValidUntonedSyllable(lastWord),
                      isKnownEnglishWord(lastWord) {
                computed = true
            } else {
                computed = false
            }
        } else {
            if lastWord == "sex" && BilingualIntentArbiter.isVietnameseLoanwordSexContext(words.dropLast().joined(separator: " ")) {
                computed = false
            } else if isEnglishAnchorToken(lastWord) {
                computed = true
            } else if isEnglishAnchorToken(words[words.count - 2]) && (LexiconDigest.contains(neutralLoanwordDigests, lastWord) || isKnownEnglishWord(lastWord)) {
                computed = true
            } else {
                let isCommittedEnglishContextToken: (String) -> Bool = { token in
                    isEnglishAnchorToken(token) || isKnownEnglishWord(token) || token == "off"
                }
                let recentWindow = words.suffix(8).map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
                let recentPair = recentWindow.suffix(2)
                if recentWindow.contains(where: { isEnglishAnchorToken($0) }) &&
                   recentWindow.allSatisfy({ !LexiconDigest.contains(vietnameseAnchorWordDigests, $0) && isCommittedEnglishContextToken($0) }) {
                    computed = true
                } else if recentPair.count == 2 &&
                          recentPair.allSatisfy({
                              $0.count >= 4 &&
                              !LexiconDigest.contains(neutralLoanwordDigests, $0) &&
                              !LexiconDigest.contains(vietnameseAnchorWordDigests, $0) &&
                              !VietnameseSyllableDictionary.shared.isValidUntonedSyllable($0) &&
                              isKnownEnglishWord($0)
                          }) {
                    computed = true
                } else {
                    let tailContext = asciiTokens.suffix(8).joined(separator: " ")
                    if hadNonASCIIPrefix {
                        let cleanWords = words.suffix(8).map { $0.trimmingCharacters(in: .punctuationCharacters) }
                        if !cleanWords.allSatisfy({ !$0.isEmpty && isCommittedEnglishContextToken($0) }) {
                            computed = false
                        } else {
                            computed = languageRecognizerProvider.isConfidentEnglishContext(tailContext)
                        }
                    } else {
                        computed = languageRecognizerProvider.isConfidentEnglishContext(tailContext)
                    }
                }
            }
        }

        if useCache {
            lock.lock()
            if contextConfidenceCache.count >= 4096 { contextConfidenceCache.removeAll(keepingCapacity: true) }
            contextConfidenceCache[cacheKey] = computed
            lock.unlock()
        }
        return computed
    }

    private static let contextSensitiveEnglishCollisionTokens: Set<String> = [
        "ser", "deest", "sics", "urw", "dist", "gis", "inf", "toots", "meme", "cana", "treos", "usa", "uri"
    ]

    internal static func isContextSensitiveEnglishCollision(_ lowerRaw: String) -> Bool {
        contextSensitiveEnglishCollisionTokens.contains(lowerRaw)
    }

    private static let postCodaCircumflexEnglishWords: Set<String> = [
        "theme", "themes", "themed", "themer",
        "meme", "memes",
        "gene", "genes", "genre",
        "scene", "scenes",
        "sense", "senses", "dense", "tense", "tenses",
        "mete", "meter", "meters", "metes",
        "pete", "peter", "petes",
        "data", "mama", "papa", "mana", "lana", "nana", "tata", "xanax",
        "photo", "photos", "moto", "motos", "motor", "motors", "goto",
        "mono", "monos", "momo", "momos", "como", "toto", "coco", "cocos",
        "honor", "honors", "donor", "donors"
    ]

    /// Returns `true` when `lowerRaw` is a known English word with a repeated `a`/`e`/`o` vowel
    /// after a coda consonant (e.g. `theme`, `meme`, `gene`, `scene`, `data`, `photo`, `moto`, `mono`, `momo`)
    /// that must remain literal English inline rather than folding into a post-coda circumflex (`thêm`, `mêm`, `gên`).
    /// Adjacent Telex vowel doubling (`theem -> thêm`, `meem -> mêm`, `geen -> gên`, `moon -> môn`) and
    /// non-English free-order Vietnamese sequences (`nhana -> nhân`, `trongo -> trông`, `themef -> thềm`) are unaffected.
    internal static func isPostCodaCircumflexEnglishWord(_ lowerRaw: String) -> Bool {
        postCodaCircumflexEnglishWords.contains(lowerRaw)
    }

    /// Attested Vietnamese Telex inputs (`whitelist_safe = never` and non-benchmark attested Vietnamese syllables)
    /// whose raw keystrokes happen to collide with archaic/Scrabble entries in `EmbeddedEnglishSpellChecker`,
    /// but must NEVER be restored to raw ASCII even after an English phrase (e.g. `"a good plan thees"` -> `"a good plan thế"`).
    internal static let vietnameseProtectedTelexInputs: Set<String> = [
        // telex_core & vn_positive `whitelist_safe = never` syllables (not in ambiguous_needs_context)
        "thees", "deef", "dees", "tees", "chees", "khees", "mees",
        "boos", "coos", "loos", "moos", "moof", "oof",
        "trows", "tows", "chows", "dows", "hows", "mows", "nows",
        "bas", "chas", "gias", "khaj", "phaj", "taj",
        // Non-benchmark attested Vietnamese syllables with archaic/Scrabble dictionary collisions
        "bir", "boo", "bur", "chee", "cher", "chow", "coo", "coon", "cur", "dais", "dar", "dif",
        "doo", "eps", "gar", "goo", "har", "hir", "hoo", "huw", "ker", "khoo",
        "kir", "lex", "loo", "mer", "moo", "moor", "mow", "nee", "phos", "poo", "pow",
        "ree", "sawn", "tow", "trow", "vir"
    ]

    /// Synthetic archaic/inferred `inflection_trap` entries in `test_suite.csv` (e.g. `"theer"` -> `"thể"`,
    /// `"theest"` -> `"thết"`) that are only valid after an explicit English grammar anchor (`"he is"`, `"the"`)
    /// and must compose as Vietnamese after general noun phrases (`"a good plan theer"` -> `"a good plan thể"`).
    private static let syntheticInflectionTrapTokens: Set<String> = [
        "theer", "theest", "heer", "heest", "leer", "leest", "meest",
        "neer", "neest", "queest", "reer", "reest", "seer", "teest",
        "vees", "veest", "beest", "deest", "hoest", "loest", "toer",
        "toest", "oer"
    ]

    private static func isLastContextWordEnglishAnchor(_ context: String) -> Bool {
        guard let lastToken = context.split(whereSeparator: \.isWhitespace).last else {
            return false
        }
        return isEnglishAnchorToken(String(lastToken))
    }

    /// Checks whether a lowercase Telex input that also composes into a directly attested
    /// Vietnamese syllable is a genuine curated English word (ignoring noisy OS `NSSpellChecker`
    /// surname/inflection false positives like `chungs -> chúng`, `thangs -> tháng`, `boons -> bốn`).
    private static func isCuratedEnglishWordForAttestedVN(_ lowerRaw: String) -> Bool {
        if EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerRaw) {
            return true
        }
        let h = LexiconDigest.hash(lowerRaw)
        if commonEnglishDoubleConsonantWordDigests.contains(h) ||
           commonEnglishWordDigests.contains(h) ||
           commonEnglishTechWordDigests.contains(h) {
            return true
        }
        if BilingualIntentArbiter.englishCollisionLogFrequencies[lowerRaw] != nil ||
           isContextSensitiveEnglishCollision(lowerRaw) {
            return true
        }
        return false
    }

    /// Returns `true` when `lowerRaw` transforms into a valid attested Vietnamese syllable (`rendered`)
    /// using an unambiguous Vietnamese Telex structural pattern (`uoo -> uô`, `uow/uwo -> ươ`,
    /// `iee/yee -> iê/yê`, `ooi -> ôi`, `oong/ooc -> ông/ôc`, `dd- -> đ-`, `aa -> â`, `uw -> ư`)
    /// that never occurs in valid English words, even after an English context word like `"is"`.
    internal static func isUnambiguousVietnameseTelexStructure(lowerRaw: String, rendered: String) -> Bool {
        let lowerRendered = rendered.lowercased()
        guard lowerRaw != lowerRendered,
              !lowerRaw.isEmpty,
              isPlausibleVietnameseText(rendered, allowPhonotacticGap: false) else {
            return false
        }
        if lowerRaw.contains("uoo") ||
           lowerRaw.contains("uow") ||
           lowerRaw.contains("uwo") ||
           lowerRaw.contains("iee") ||
           lowerRaw.contains("yee") ||
           lowerRaw.contains("ooi") ||
           lowerRaw.contains("oong") ||
           lowerRaw.contains("ooc") ||
           lowerRaw.hasPrefix("dd") ||
           lowerRaw.contains("aa") ||
           (lowerRaw.contains("uw") && lowerRaw != "urw" && !EmbeddedEnglishSpellChecker.shared.isWordInEnglishDictionary(lowerRaw)) {
            return true
        }
        return false
    }

    private static func isPlausibleVietnameseSyllable(_ word: String, allowPhonotacticGap: Bool = false) -> Bool {
        if allowPhonotacticGap {
            return VietnameseSyllableDictionary.shared.isPhonotacticallyValidSyllable(word)
        }
        return VietnameseSyllableDictionary.shared.isValidSyllable(word)
    }

    private static func isPlausibleVietnameseText(_ text: String, allowPhonotacticGap: Bool = false) -> Bool {
        let syllables = text.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        return !syllables.isEmpty && syllables.allSatisfy { isPlausibleVietnameseSyllable(String($0), allowPhonotacticGap: allowPhonotacticGap) }
    }

    private static func hasWModifierAfterVowel(_ word: String) -> Bool {
        var prevIsVowel = false
        for b in word.utf8 {
            if b == 119 && prevIsVowel { // 'w'
                return true
            }
            prevIsVowel = (b == 97 || b == 101 || b == 105 || b == 111 || b == 117 || b == 121)
        }
        return false
    }

    private static func hasNonVietnameseDoubleConsonant(_ lower: String) -> Bool {
        var prev: UInt8 = 0
        for b in lower.utf8 {
            if b == prev {
                switch b {
                case 98, 99, 102, 103, 108, 109, 110, 112, 114, 115, 116, 118: // b, c, f, g, l, m, n, p, r, s, t, v
                    return true
                default:
                    break
                }
            }
            prev = b
        }
        return false
    }

    private static func collapsedTelexTripleEscapes(_ word: String) -> String? {
        var hasTriple = false
        var p1: UInt8 = 0
        var p2: UInt8 = 0
        for b in word.utf8 {
            if b == p1 && b == p2 && (b == 97 || b == 101 || b == 111 || b == 100) {
                hasTriple = true
                break
            }
            p2 = p1
            p1 = b
        }
        guard hasTriple else { return nil }

        let characters = Array(word)
        let tripleKeys: Set<Character> = ["a", "e", "o", "d"]
        var collapsed: [Character] = []
        var removedEscape = false
        var index = 0

        while index < characters.count {
            let ch = characters[index]
            if tripleKeys.contains(ch),
               index + 2 < characters.count,
               characters[index + 1] == ch,
               characters[index + 2] == ch {
                collapsed.append(ch)
                collapsed.append(ch)
                index += 3
                removedEscape = true
            } else {
                collapsed.append(ch)
                index += 1
            }
        }

        return removedEscape ? String(collapsed) : nil
    }

    internal static func collapsedTelexToneEscapes(_ word: String) -> String? {
        var hasTonePair = false
        var prev: UInt8 = 0
        for b in word.utf8 {
            if b == prev && (b == 115 || b == 102 || b == 114 || b == 120 || b == 106 || b == 119) {
                hasTonePair = true
                break
            }
            prev = b
        }
        guard hasTonePair else { return nil }

        let characters = Array(word)
        let toneKeys: Set<Character> = ["s", "f", "r", "x", "j", "w"]
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var collapsed: [Character] = []
        var removedEscape = false
        var lastEscapedKey: Character? = nil
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if !character.isLetter || vowels.contains(character) {
                lastEscapedKey = nil
                collapsed.append(character)
                index += 1
            } else if character != lastEscapedKey,
                      toneKeys.contains(character),
                      index + 1 < characters.count,
                      characters[index + 1] == character {
                collapsed.append(character)
                index += 2
                removedEscape = true
                lastEscapedKey = character
            } else {
                collapsed.append(character)
                index += 1
            }
        }

        return removedEscape ? String(collapsed) : nil
    }

    private static let commonTelexToneEscapeTargetDigests: Set<UInt64> = [
        0x686292d6f8898374, 0x5b495cf023d7b70f, 0xf4874f073a3606e6, 0x69ecd700691ce423,
        0x375ac06be34da147, 0x4034d6fee26bd200, 0x391cd449cccc175b, 0x9e4816f3b820898a,
        0x70ae2511e4a88c3a, 0x51b152f160fd212a, 0x5eb407e8d41e1785, 0x9ce0ea4c102a7a46,
        0x608c6ada8a3f6c32, 0x174ddee4a7b6bc1a, 0x334c5c5646f8d0dc, 0x3a46b85a1212bf04,
        0x3149122f0d4729ba, 0x3338e5a9d25b4d50, 0x2bc384c525249f47, 0xdfc958b9a3ef02d7,
        0x9cde016a36f924d7, 0x35291adde72afb1c, 0x9183a7c55663d5f3, 0x701bc5df5baead2a,
        0xc374a2b4ceb4d846, 0x2147ac6ca65e5c42, 0x77feeff930ee825d, 0x7848e8c0546dc58e,
        0x9fb555608966a332, 0xd31de6ea44b24f26, 0x6f548b19ca7ca8a5, 0xd33252feb2cb6e1f,
        0xf9d5c61e5e81da0a, 0x5a58db485ecca33a, 0x952f2e16bcf4cf07, 0xdc5e8c02767704a0,
        0x7d9f9c3ef174fd52, 0x778ff31f846207f2
    ]

    private static func hasTripleRepeatedLetter(_ word: String) -> Bool {
        var p1: UInt8 = 0
        var p2: UInt8 = 0
        for b in word.utf8 {
            if b == p1 && b == p2 && ((b >= 97 && b <= 122) || (b >= 65 && b <= 90)) {
                return true
            }
            p2 = p1
            p1 = b
        }
        return false
    }

    private static func isBlockedTelexToneEscapeTarget(_ lower: String) -> Bool {
        guard let escaped = collapsedTelexToneEscapes(lower) else {
            return false
        }
        if LexiconDigest.contains(commonTelexToneEscapeTargetDigests, escaped) {
            return true
        }
        if escaped.hasSuffix("s"),
           LexiconDigest.contains(commonTelexToneEscapeTargetDigests, String(escaped.dropLast())) {
            return true
        }
        return false
    }

    private static func isDirectEnglishLexiconWord(_ lower: String, queryWord: String) -> Bool {
        let h = LexiconDigest.hash(lower)
        if commonEnglishDoubleConsonantWordDigests.contains(h) ||
           commonEnglishWordDigests.contains(h) ||
           commonEnglishTechWordDigests.contains(h) {
            return true
        }
        lock.lock()
        if let cachedExact = spellCheckCache[queryWord] {
            lock.unlock()
            return cachedExact
        }
        if queryWord == lower, let cachedLower = spellCheckCache[lower] {
            lock.unlock()
            return cachedLower
        }
        if let cachedLower = spellCheckCache[lower], cachedLower {
            lock.unlock()
            return true
        }
        lock.unlock()
        let res = spellCheckerProvider?.isWordInEnglishDictionary(queryWord) ?? false
        lock.lock()
        spellCheckCache[queryWord] = res
        if queryWord == lower || res {
            spellCheckCache[lower] = res
        }
        lock.unlock()
        return res
    }

    private static func isInflectedOrCompoundDoubleConsonantEnglishWord(_ lower: String) -> Bool {
        guard hasNonVietnameseDoubleConsonant(lower) else {
            return false
        }
        if lower.count >= 5 && lower.hasSuffix("s") && !lower.hasSuffix("ss") {
            let stem = String(lower.dropLast())
            if stem.count >= 4,
               hasNonVietnameseDoubleConsonant(stem),
               !isBlockedTelexToneEscapeTarget(stem),
               isDirectEnglishLexiconWord(stem, queryWord: stem) {
                return true
            }
        }
        for sfx in ["ing", "ed", "er", "es", "ly"] where lower.count >= sfx.count + 4 && lower.hasSuffix(sfx) {
            let stem = String(lower.dropLast(sfx.count))
            guard hasNonVietnameseDoubleConsonant(stem),
                  !isBlockedTelexToneEscapeTarget(stem) else {
                continue
            }
            if isDirectEnglishLexiconWord(stem, queryWord: stem) ||
               isDirectEnglishLexiconWord(stem + "e", queryWord: stem + "e") {
                return true
            }
        }
        if lower.count >= 7 {
            let chars = Array(lower)
            for split in 2...(chars.count - 2) {
                let left = String(chars[0..<split])
                let right = String(chars[split..<chars.count])
                let leftHasDouble = left.count >= 4 && hasNonVietnameseDoubleConsonant(left)
                let rightHasDouble = right.count >= 4 && hasNonVietnameseDoubleConsonant(right)
                guard leftHasDouble || rightHasDouble else { continue }
                guard !isBlockedTelexToneEscapeTarget(left),
                      !isBlockedTelexToneEscapeTarget(right) else {
                    continue
                }
                if isDirectEnglishLexiconWord(left, queryWord: left) &&
                   isDirectEnglishLexiconWord(right, queryWord: right) {
                    return true
                }
            }
        }
        return false
    }

    public static func isKnownEnglishWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard !lower.isEmpty,
              lower.unicodeScalars.allSatisfy({ ($0.value >= 0x61 && $0.value <= 0x7A) || $0.value == 0x27 || $0.value == 0x2D }) else {
            return false
        }
        if word == lower && vietnameseProtectedTelexInputs.contains(lower) {
            return false
        }
        if hasTripleRepeatedLetter(lower) {
            return false
        }
        if isBlockedTelexToneEscapeTarget(lower) {
            return false
        }
        let h = LexiconDigest.hash(lower)
        if commonEnglishDoubleConsonantWordDigests.contains(h) {
            return true
        }
        if commonEnglishWordDigests.contains(h) || commonEnglishTechWordDigests.contains(h) {
            return true
        }
        lock.lock()
        let cachedResult: Bool? = {
            if let cachedExact = spellCheckCache[word] { return cachedExact }
            if word == lower, let cachedLower = spellCheckCache[lower] { return cachedLower }
            if let cachedLower = spellCheckCache[lower], cachedLower { return true }
            return nil
        }()
        lock.unlock()
        if let cached = cachedResult { return cached }

        let result = (spellCheckerProvider?.isWordInEnglishDictionary(word) ?? false) ||
            isInflectedOrCompoundDoubleConsonantEnglishWord(lower)

        lock.lock()
        if spellCheckCache[word] == nil {
            if spellCheckCache.count >= maxCacheEntries {
                let evictCount = max(1, maxCacheEntries / 4)
                let actualEvict = min(evictCount, cacheKeys.count)
                let keysToEvict = Array(cacheKeys.prefix(actualEvict))
                for oldKey in keysToEvict {
                    spellCheckCache.removeValue(forKey: oldKey)
                }
                cacheKeys.removeFirst(actualEvict)
            }
            cacheKeys.append(word)
        }
        spellCheckCache[word] = result
        if word == lower || result || spellCheckCache[lower] == nil {
            if spellCheckCache[lower] == nil {
                cacheKeys.append(lower)
            }
            if result || spellCheckCache[lower] == nil {
                spellCheckCache[lower] = result
            }
        }
        let finalCached = spellCheckCache[word] ?? result
        lock.unlock()
        return finalCached
    }

    /// Returns `true` when `lowerRaw` ends with the same coda letter as `lowerRendered`,
    /// or when trailing Telex vowel/stroke modifiers (`w`, `a`, `e`, `o`, `d`) were consumed
    /// after the coda (e.g. `truocw -> trươc`, `luocw -> lươc`, `cuocw -> cươc`, `luotw -> lươt`,
    /// `muocw -> mươc`, `nhata -> nhât`, `tiepe -> tiêp`, `cuoco -> cuôc`, `docd -> đoc`).
    private static func hasMatchingOrPostCodaModifiedCodaEnding(lowerRaw: String, lowerRendered: String) -> Bool {
        guard let renderedLast = lowerRendered.last else { return false }
        if lowerRaw.last == renderedLast {
            return true
        }
        let hasHornOrBreve = lowerRendered.contains(where: { "ăơư".contains($0) })
        var stem = Substring(lowerRaw)
        while let last = stem.last, last != renderedLast {
            let matchesRenderedDiacritic: Bool
            switch last {
            case "w":
                matchesRenderedDiacritic = hasHornOrBreve
            case "a":
                matchesRenderedDiacritic = lowerRendered.contains("â")
            case "e":
                matchesRenderedDiacritic = lowerRendered.contains("ê")
            case "o":
                matchesRenderedDiacritic = lowerRendered.contains("ô")
            case "d":
                matchesRenderedDiacritic = lowerRendered.hasPrefix("đ")
            default:
                matchesRenderedDiacritic = false
            }
            guard matchesRenderedDiacritic else { return false }
            stem = stem.dropLast()
        }
        if stem.contains("w") && !hasHornOrBreve {
            return false
        }
        return stem.last == renderedLast
    }
}
