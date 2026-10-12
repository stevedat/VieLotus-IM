#if !SWIFT_PACKAGE
import Foundation

private class BundleFinder {}

extension Bundle {
    /// Compatibility fallback for `Bundle.module` when compiling as an Xcode target / framework.
    static var module: Bundle {
        let bundleName = "VieLotusCore_VieLotusCore"
        let candidates = [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,
            // Bundle should be present here when the package is linked into a framework.
            Bundle(for: BundleFinder.self).resourceURL,
            // For command-line tools.
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        return Bundle(for: BundleFinder.self)
    }
}
#endif
