import AppKit
import Foundation

/// Keeps MXMenu up to date from the repo's GitHub Releases (built by .github/workflows/build.yml).
@MainActor
final class Updater: ObservableObject {
    static let repo = "alexgallacher/MXMenu"
    static let assetName = "MXMenu.zip"

    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var autoInstall: Bool {
        get { UserDefaults.standard.object(forKey: "autoInstallUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoInstallUpdates"); objectWillChange.send() }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var latest: (version: String, url: URL)?
    private var loop: Task<Void, Never>?

    /// Only a real .app bundle can replace itself (not `swift run`).
    private var canSelfUpdate: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func start() {
        guard loop == nil, canSelfUpdate else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.check(userInitiated: false)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check(userInitiated: Bool = true) async {
        if case .installing = state { return }
        state = .checking
        do {
            if let release = try await fetchLatest(), Self.isNewer(release.version, than: currentVersion) {
                latest = release
                state = .available(version: release.version)
                if autoInstall && !userInitiated { await install() }
            } else {
                state = userInitiated ? .upToDate : .idle
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func install() async {
        guard let latest, canSelfUpdate else { return }
        state = .installing(version: latest.version)
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("MXMenuUpdate-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            let (download, response) = try await URLSession.shared.download(for: request(latest.url, accept: "application/octet-stream"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed") }
            let zip = work.appendingPathComponent(Self.assetName)
            try fm.moveItem(at: download, to: zip)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

            let newApp = work.appendingPathComponent("MXMenu.app")
            guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download isn't an MXMenu app")
            }

            // Swap the bundle after this process quits, then relaunch.
            let target = Bundle.main.bundleURL.path
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(target)" && mv "\(newApp.path)" "\(target)" && xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
            open "\(target)"
            rm -rf "\(work.path)"
            """
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", script]
            try shell.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private func fetchLatest() async throws -> (version: String, url: URL)? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        let (data, response) = try await URLSession.shared.data(for: request(url, accept: "application/vnd.github+json"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }  // no releases yet
        guard status == 200 else { throw UpdateError("GitHub returned HTTP \(status)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
              let assetURL = (asset["url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, assetURL)
    }

    private func request(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("MXMenu/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\(tool) failed") }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
