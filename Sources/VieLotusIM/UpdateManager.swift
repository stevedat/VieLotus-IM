import AppKit
import CryptoKit
import Foundation
import VieLotusCore

/// Cấu trúc thông tin bản phát hành mới từ GitHub Releases (`stevedat/VieLotus-IM`)
public struct ReleaseManifest: Codable, Sendable, Equatable {
    public let version: String
    public let pkgURL: String
    public let checksumsURL: String?
    public let sha256: String
    public let releaseNotes: String?
    public let releasePageURL: String?

    public init(
        version: String,
        pkgURL: String,
        checksumsURL: String? = nil,
        sha256: String = "",
        releaseNotes: String? = nil,
        releasePageURL: String? = nil
    ) {
        self.version = version
        self.pkgURL = pkgURL
        self.checksumsURL = checksumsURL
        self.sha256 = sha256
        self.releaseNotes = releaseNotes
        self.releasePageURL = releasePageURL
    }
}

/// Trạng thái kiểm tra & cập nhật phần mềm (On-Demand — chỉ chạy khi mở Cài đặt)
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(ReleaseManifest)
    case downloading(progress: Double)
    case installing
    case error(message: String)
}

/// Quản lý kiểm tra và cập nhật tự động xác thực SHA-256 cho Sen Việt (VieLotusIM).
/// Tuân thủ kiến trúc "Pure Apple Native": KHÔNG chạy timer ngầm trong tiến trình gõ phím,
/// chỉ kiểm tra khi người dùng mở cửa sổ Cài đặt hoặc bấm nút "Kiểm tra cập nhật".
@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var lastCheckedAt: Date?

    public let githubRepoSlug = "stevedat/VieLotus-IM"

    public var currentVersion: String {
        Self.normalizeVersion(AppInfo.appVersion)
    }

    public var releasesWebURL: URL {
        URL(string: "https://github.com/\(githubRepoSlug)/releases/latest")!
    }

    private var githubLatestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepoSlug)/releases/latest")!
    }

    private init() {}

    // MARK: - Public Actions

    /// Tự động kiểm tra nhẹ nhàng khi mở cửa sổ Cài đặt (tối đa 1 lần mỗi 30 phút)
    public func checkIfNeededOnSettingsOpen() async {
        if case .downloading = status { return }
        if case .installing = status { return }
        if case .checking = status { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < 1800 {
            return
        }
        await checkForUpdates(userInitiated: false)
    }

    /// Kiểm tra bản cập nhật mới từ GitHub Releases
    public func checkForUpdates(userInitiated: Bool = true) async {
        if case .checking = status { return }
        if case .downloading = status { return }
        if case .installing = status { return }

        status = .checking

        do {
            let manifest = try await fetchLatestManifest()
            lastCheckedAt = Date()

            if Self.isVersion(manifest.version, newerThan: currentVersion) {
                status = .updateAvailable(manifest)
            } else {
                status = .upToDate(version: currentVersion)
            }
        } catch {
            if userInitiated {
                status = .error(message: "Không thể kết nối máy chủ cập nhật GitHub.")
            } else {
                status = .idle
            }
        }
    }

    /// Tải về gói `VieLotusIM.pkg`, đối chiếu mã băm SHA-256 từ `checksums.sha256` và cài đặt 1 chạm
    public func downloadAndInstallUpdate() async {
        guard case .updateAvailable(let manifest) = status else { return }
        guard let pkgDownloadURL = URL(string: manifest.pkgURL),
              pkgDownloadURL.scheme?.lowercased() == "https" else {
            status = .error(message: "Đường dẫn gói cập nhật không hợp lệ.")
            return
        }

        status = .downloading(progress: 0.08)

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(
            "VieLotusIM-Update-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 1. Resolve expected SHA-256 from manifest or checksums.sha256
            var expectedSha = Self.extractHexSha256(from: manifest.sha256)
            if expectedSha.count != 64,
               let csURLStr = manifest.checksumsURL,
               let csURL = URL(string: csURLStr),
               csURL.scheme?.lowercased() == "https" {
                status = .downloading(progress: 0.18)
                if let csText = try? await downloadText(from: csURL) {
                    expectedSha = Self.parseSha256ForAsset(named: "VieLotusIM.pkg", inChecksumsText: csText)
                }
            }

            status = .downloading(progress: 0.30)

            // 2. Download VieLotusIM.pkg
            var request = URLRequest(url: pkgDownloadURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 180
            request.setValue(
                "VieLotusIM/\(currentVersion) (macOS; AutoUpdater)",
                forHTTPHeaderField: "User-Agent"
            )

            let (downloadedURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            status = .downloading(progress: 0.82)

            let targetPkgURL = tempDir.appendingPathComponent("VieLotusIM-\(manifest.version).pkg")
            if fm.fileExists(atPath: targetPkgURL.path) {
                try fm.removeItem(at: targetPkgURL)
            }
            try fm.moveItem(at: downloadedURL, to: targetPkgURL)

            // 3. Verify SHA-256 integrity
            let pkgData = try Data(contentsOf: targetPkgURL, options: .mappedIfSafe)
            let actualHash = SHA256.hash(data: pkgData)
            let actualHex = actualHash.compactMap { String(format: "%02x", $0) }.joined()

            guard expectedSha.count == 64 else {
                try? fm.removeItem(at: tempDir)
                status = .error(message: "Không tìm thấy mã kiểm tra SHA-256 chính thức.")
                return
            }

            guard actualHex.lowercased() == expectedSha.lowercased() else {
                try? fm.removeItem(at: tempDir)
                status = .error(message: "Mã băm SHA-256 không khớp. Đã huỷ cài đặt để bảo vệ an toàn.")
                return
            }

            status = .downloading(progress: 1.0)
            status = .installing

            // 4. Install VieLotusIM.pkg via macOS administrator prompt (or open standard Installer on cancel)
            let installResult = await Self.runPrivilegedPkgInstaller(pkgURL: targetPkgURL)
            switch installResult {
            case .installed:
                try? fm.removeItem(at: tempDir)
                status = .upToDate(version: manifest.version)
            case .cancelledByUser:
                // Open the verified .pkg in standard macOS Installer GUI as a friendly fallback
                NSWorkspace.shared.open(targetPkgURL)
                status = .updateAvailable(manifest)
            case .failed(let reason):
                NSWorkspace.shared.open(targetPkgURL)
                status = .error(message: reason)
            }
        } catch {
            try? fm.removeItem(at: tempDir)
            status = .error(message: "Tải bản cập nhật thất bại. Vui lòng thử lại.")
        }
    }

    public func openReleaseDownloadPage() {
        if case .updateAvailable(let manifest) = status,
           let pageStr = manifest.releasePageURL,
           let url = URL(string: pageStr) {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(releasesWebURL)
    }

    // MARK: - GitHub Releases Manifest Fetching

    private struct GitHubReleaseAssetDTO: Decodable {
        let name: String
        let browser_download_url: String
        let digest: String?
    }

    private struct GitHubReleaseDTO: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String?
        let assets: [GitHubReleaseAssetDTO]
    }

    private func fetchLatestManifest() async throws -> ReleaseManifest {
        var req = URLRequest(url: githubLatestReleaseAPIURL)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VieLotusIM/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        let cleanVer = Self.normalizeVersion(release.tag_name)

        guard let pkgAsset = release.assets.first(where: { $0.name == "VieLotusIM.pkg" })
                ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) else {
            throw URLError(.fileDoesNotExist)
        }

        let checksumsAsset = release.assets.first(where: { $0.name == "checksums.sha256" })
        let digestHex = Self.extractHexSha256(from: pkgAsset.digest ?? "")

        return ReleaseManifest(
            version: cleanVer,
            pkgURL: pkgAsset.browser_download_url,
            checksumsURL: checksumsAsset?.browser_download_url,
            sha256: digestHex,
            releaseNotes: release.body,
            releasePageURL: release.html_url
        )
    }

    private func downloadText(from url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15
        req.setValue("VieLotusIM/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    // MARK: - Helpers (Pure & Testable)

    public static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        if let dashIdx = s.firstIndex(of: "-") {
            s = String(s[..<dashIdx])
        }
        return s
    }

    public static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let rParts = normalizeVersion(remote).split(separator: ".").compactMap { Int($0) }
        let lParts = normalizeVersion(local).split(separator: ".").compactMap { Int($0) }
        let maxCount = max(rParts.count, lParts.count)
        for i in 0..<maxCount {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r != l {
                return r > l
            }
        }
        return false
    }

    public static func extractHexSha256(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexCandidate: String
        if trimmed.hasPrefix("sha256:") {
            hexCandidate = String(trimmed.dropFirst("sha256:".count))
        } else {
            hexCandidate = trimmed
        }
        guard hexCandidate.count == 64,
              hexCandidate.allSatisfy({ $0.isHexDigit }) else {
            return ""
        }
        return hexCandidate
    }

    public static func parseSha256ForAsset(named assetName: String, inChecksumsText text: String) -> String {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let hashCandidate = String(parts[0]).lowercased()
            var fileCandidate = String(parts.last!)
            if fileCandidate.hasPrefix("*") || fileCandidate.hasPrefix("./") {
                fileCandidate = fileCandidate.trimmingCharacters(in: CharacterSet(charactersIn: "*./"))
            }
            let baseName = (fileCandidate as NSString).lastPathComponent
            if baseName == assetName, hashCandidate.count == 64, hashCandidate.allSatisfy({ $0.isHexDigit }) {
                return hashCandidate
            }
        }
        return ""
    }

    private enum PkgInstallOutcome: Sendable {
        case installed
        case cancelledByUser
        case failed(String)
    }

    private static func runPrivilegedPkgInstaller(pkgURL: URL) async -> PkgInstallOutcome {
        await Task.detached(priority: .userInitiated) {
            let pkgPath = pkgURL.path
            let escapedForShell = pkgPath.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"/usr/sbin/installer -pkg \\\"\(escapedForShell)\\\" -target /\" with administrator privileges"

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", appleScript]

            let errPipe = Pipe()
            proc.standardOutput = Pipe()
            proc.standardError = errPipe

            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    return .installed
                }
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                if errStr.contains("-128") || errStr.localizedCaseInsensitiveContains("canceled") || errStr.localizedCaseInsensitiveContains("cancelled") {
                    return .cancelledByUser
                }
                return .failed("Đã mở bộ cài Sen Việt để hoàn tất cập nhật.")
            } catch {
                return .failed("Đã mở bộ cài Sen Việt để hoàn tất cập nhật.")
            }
        }.value
    }
}
