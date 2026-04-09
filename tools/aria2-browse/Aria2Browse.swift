import AppKit
import Carbon
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger()
    private var handledURL = false

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logger.log("launch argv=\(CommandLine.arguments)")

        if let argURL = CommandLine.arguments.dropFirst().first, argURL.contains("://") {
            logger.log("handling argv url=\(argURL)")
            handleURL(argURL)
            terminateSoon()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            if !self.handledURL {
                self.logger.log("no URL received before timeout, terminating")
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            logger.log("received URL event with empty payload")
            terminateSoon()
            return
        }

        logger.log("received apple event url=\(url)")
        handleURL(url)
        terminateSoon()
    }

    private func handleURL(_ urlString: String) {
        handledURL = true

        do {
            let targetURL = try URLResolver.resolve(urlString: urlString)
            logger.log("resolved target=\(targetURL.path)")
            try reveal(targetURL)
        } catch {
            logger.log("error=\(error.localizedDescription)")
            showError(error.localizedDescription)
        }
    }

    private func reveal(_ targetURL: URL) throws {
        var isDirectory: ObjCBool = false
        let path = targetURL.path
        let fm = FileManager.default

        if fm.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                logger.log("opening directory=\(path)")
                NSWorkspace.shared.open(targetURL)
            } else {
                logger.log("revealing file=\(path)")
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            }
            return
        }

        let parent = targetURL.deletingLastPathComponent()
        logger.log("target missing, opening parent=\(parent.path)")
        NSWorkspace.shared.open(parent)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Aria2Browse error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func terminateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}

enum URLResolver {
    static func resolve(urlString: String) throws -> URL {
        guard let components = URLComponents(string: urlString) else {
            throw BrowseError.invalidURL(urlString)
        }

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { item in
            (item.name, item.value ?? "")
        })

        let path: String
        if let directPath = items["path"], !directPath.isEmpty {
            path = directPath
        } else if let dir = items["dir"], !dir.isEmpty {
            if let name = items["name"], !name.isEmpty {
                path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            } else {
                path = dir
            }
        } else {
            throw BrowseError.missingPath
        }

        guard path.hasPrefix("/") else {
            throw BrowseError.nonAbsolutePath(path)
        }

        return URL(fileURLWithPath: path)
    }
}

enum BrowseError: LocalizedError {
    case invalidURL(String)
    case missingPath
    case nonAbsolutePath(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .missingPath:
            return "Missing query parameter: path or dir"
        case .nonAbsolutePath(let value):
            return "Only absolute local paths are supported: \(value)"
        }
    }
}

final class Logger {
    private let fileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/Aria2Browse.log")
    }()

    func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
