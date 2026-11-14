import Foundation

/// Constant-time 64-bit salted FNV-1a + MurmurHash3 finalizer digest for zero-allocation lexical table lookups.
internal enum LexiconDigest {
    @inline(__always)
    internal static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325 ^ 0x5649454c4f545553
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h &*= 0x00000100000001b3
        }
        h ^= h >> 33
        h &*= 0xff51afd7ed558ccd
        h ^= h >> 33
        h &*= 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return h
    }

    @inline(__always)
    internal static func contains(_ set: Set<UInt64>, _ word: String) -> Bool {
        return set.contains(hash(word))
    }
}
