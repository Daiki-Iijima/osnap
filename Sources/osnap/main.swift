import ArgumentParser
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Window model

struct WindowInfo {
    let id: CGWindowID
    let owner: String
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
    let layer: Int
}

enum WindowQuery {
    static func list(onScreenOnly: Bool = true) -> [WindowInfo] {
        let opts: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            guard
                let id = entry[kCGWindowNumber as String] as? CGWindowID,
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            let title = entry[kCGWindowName as String] as? String ?? ""
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            return WindowInfo(id: id, owner: owner, ownerPID: pid, title: title, bounds: bounds, layer: layer)
        }
    }

    static func matching(app: String, includeMenuLayer: Bool = false) -> [WindowInfo] {
        list().filter { w in
            let appMatches = w.owner.localizedCaseInsensitiveContains(app)
            let menuLayerOK = includeMenuLayer || w.layer < 100
            return appMatches && menuLayerOK
        }
    }
}

// MARK: - Capture

enum Capture {
    /// Write a CGImage to disk as PNG.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SnapError.encodeFailed
        }
        try data.write(to: url)
    }

    static func screenshotRegion(_ rect: CGRect) throws -> CGImage {
        // Use external screencapture for region — guaranteed and respects scaling.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("osnap-\(UUID().uuidString).png")
        let r = "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))"
        let proc = Process()
        proc.launchPath = "/usr/sbin/screencapture"
        proc.arguments = ["-x", "-R", r, tmp.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw SnapError.captureFailed("screencapture exit \(proc.terminationStatus)")
        }
        guard let img = NSImage(contentsOf: tmp), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SnapError.captureFailed("could not decode \(tmp.path)")
        }
        try? FileManager.default.removeItem(at: tmp)
        return cg
    }

    static func screenshotWindow(_ id: CGWindowID) throws -> CGImage {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("osnap-\(UUID().uuidString).png")
        let proc = Process()
        proc.launchPath = "/usr/sbin/screencapture"
        proc.arguments = ["-x", "-l", String(id), "-o", tmp.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw SnapError.captureFailed("screencapture exit \(proc.terminationStatus) for window \(id)")
        }
        guard FileManager.default.fileExists(atPath: tmp.path),
              let img = NSImage(contentsOf: tmp),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SnapError.captureFailed("no image for window \(id)")
        }
        try? FileManager.default.removeItem(at: tmp)
        return cg
    }
}

enum SnapError: LocalizedError {
    case captureFailed(String)
    case encodeFailed
    case windowNotFound(String)
    case axNotPermitted
    case axFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let s): return "capture failed: \(s)"
        case .encodeFailed: return "PNG encode failed"
        case .windowNotFound(let s): return "window not found: \(s)"
        case .axNotPermitted: return "Accessibility permission required. System Settings → Privacy & Security → Accessibility → enable for the binary running osnap."
        case .axFailed(let s): return "AX call failed: \(s)"
        }
    }
}

// MARK: - Accessibility helpers

enum AX {
    static func ensureTrusted() throws {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            throw SnapError.axNotPermitted
        }
    }

    static func pressFirstMenuBarItem(pid: pid_t) throws {
        let app = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        var which = "AXExtrasMenuBar"
        var rc = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &menuBarRef)
        if rc != .success {
            which = "AXMenuBar"
            rc = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef)
        }
        guard rc == .success, let mb = menuBarRef else {
            throw SnapError.axFailed("no AXMenuBar / AXExtrasMenuBar on pid \(pid)")
        }
        let menuBar = mb as! AXUIElement

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else {
            throw SnapError.axFailed("\(which) has no children")
        }

        var lastErr: AXError = .failure
        for item in children {
            for action in ["AXShowMenu", kAXPressAction as String, "AXOpen", kAXPickAction as String] {
                let err = AXUIElementPerformAction(item, action as CFString)
                if err == .success { return }
                lastErr = err
            }
        }
        throw SnapError.axFailed("no actionable item under \(which); last AX error \(lastErr.rawValue)")
    }
}

// MARK: - Subcommands

struct ListCmd: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "list", abstract: "List capturable on-screen windows.")
    @Option(name: .long, help: "Filter by app name (substring, case-insensitive).") var app: String?
    @Flag(name: .long, help: "Include menu-layer windows (popups, menus).") var includeMenu: Bool = false

    func run() throws {
        let wins = WindowQuery.list().filter { w in
            (app == nil || w.owner.localizedCaseInsensitiveContains(app!))
                && (includeMenu || w.layer < 100)
        }
        for w in wins {
            let b = w.bounds
            let id = String(w.id).padding(toLength: 9, withPad: " ", startingAt: 0)
            let layer = "L\(w.layer)".padding(toLength: 5, withPad: " ", startingAt: 0)
            let owner = w.owner.padding(toLength: 28, withPad: " ", startingAt: 0)
            let title = w.title.padding(toLength: 28, withPad: " ", startingAt: 0)
            let size = String(format: "%4.0fx%-4.0f", b.width, b.height)
            let pos = String(format: "%4.0f,%-4.0f", b.origin.x, b.origin.y)
            print("\(id) \(layer) \(owner) \(title) \(size) @ \(pos)")
        }
    }
}

struct RegionCmd: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "region", abstract: "Capture an explicit screen rectangle (no other UI exposed).")
    @Argument(help: "Rect as X,Y,W,H (logical points, top-left origin).") var rect: String
    @Option(name: [.short, .long]) var out: String

    func run() throws {
        let parts = rect.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { throw ValidationError("rect must be X,Y,W,H") }
        let r = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        let img = try Capture.screenshotRegion(r)
        try Capture.writePNG(img, to: URL(fileURLWithPath: out))
        print("wrote \(out)  \(Int(r.width))x\(Int(r.height))")
    }
}

struct WindowCmd: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "window", abstract: "Capture a single window by its CGWindowID.")
    @Argument var windowID: CGWindowID
    @Option(name: [.short, .long]) var out: String

    func run() throws {
        let img = try Capture.screenshotWindow(windowID)
        try Capture.writePNG(img, to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}

struct AppCmd: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "app", abstract: "Capture every on-screen window of an app.")
    @Argument(help: "App name (substring of CGWindowOwnerName).") var app: String
    @Option(name: [.short, .long], help: "Output prefix; files become <prefix>-1.png, -2.png, ...") var out: String
    @Flag(name: .long) var includeMenu: Bool = false

    func run() throws {
        let wins = WindowQuery.matching(app: app, includeMenuLayer: includeMenu)
        if wins.isEmpty {
            FileHandle.standardError.write(Data("no windows match '\(app)'\n".utf8))
            throw ExitCode.failure
        }
        for (i, w) in wins.enumerated() {
            let img = try Capture.screenshotWindow(w.id)
            let path = "\(out)-\(i + 1).png"
            try Capture.writePNG(img, to: URL(fileURLWithPath: path))
            print("wrote \(path)  (win \(w.id), \(Int(w.bounds.width))x\(Int(w.bounds.height)))")
        }
    }
}

struct MenubarPopupCmd: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "menubar-popup",
        abstract: "Open a menu-bar-extra of an app and capture just the popup window. Requires Accessibility permission."
    )
    @Argument(help: "App name (substring of NSRunningApplication.localizedName).") var app: String
    @Option(name: [.short, .long]) var out: String
    @Option(name: .long, help: "Wait ms after triggering the menu before capturing.") var settleMs: Int = 250

    func run() throws {
        try AX.ensureTrusted()
        guard let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains(app)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(app)
        }) else {
            throw SnapError.windowNotFound("no running app matches '\(app)'")
        }
        let allBefore = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let beforeIDs = Set(allBefore.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })

        try AX.pressFirstMenuBarItem(pid: running.processIdentifier)
        usleep(useconds_t(settleMs * 1000))

        let after = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let popup = after.compactMap { e -> WindowInfo? in
            guard let id = e[kCGWindowNumber as String] as? CGWindowID,
                  let owner = e[kCGWindowOwnerName as String] as? String,
                  let pid = e[kCGWindowOwnerPID as String] as? pid_t,
                  let bd = e[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary)
            else { return nil }
            let layer = e[kCGWindowLayer as String] as? Int ?? 0
            return WindowInfo(id: id, owner: owner, ownerPID: pid, title: "", bounds: b, layer: layer)
        }.first(where: { w in
            !beforeIDs.contains(w.id) && w.layer >= 100 && w.bounds.height > 20
        })

        guard let popup else {
            throw SnapError.windowNotFound("no new popup window appeared for \(running.localizedName ?? app)")
        }

        let img = try Capture.screenshotWindow(popup.id)
        try Capture.writePNG(img, to: URL(fileURLWithPath: out))
        print("wrote \(out)  (window \(popup.id), \(Int(popup.bounds.width))x\(Int(popup.bounds.height)))")
    }
}

struct PopupWaitCmd: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "popup-wait",
        abstract: "Snapshot current windows, then wait until a new high-layer (menu/popup) window appears and capture only that. No AX permission needed; user opens the menu manually."
    )
    @Option(name: [.short, .long]) var out: String
    @Option(name: .long, help: "Timeout seconds.") var timeout: Int = 30
    @Option(name: .long, help: "Min window height to qualify as a popup (px).") var minHeight: Double = 40
    @Option(name: .long, help: "Settle ms after detection before capture (lets the popup finish animating).") var settleMs: Int = 150
    @Option(name: .long, help: "Optional substring filter on owner name.") var owner: String?

    func run() throws {
        let allBefore = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let beforeIDs = Set(allBefore.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })

        FileHandle.standardError.write(Data("waiting for new popup window (timeout \(timeout)s)…\n".utf8))

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        var popup: WindowInfo?
        while Date() < deadline {
            let snap = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
            for e in snap {
                guard
                    let id = e[kCGWindowNumber as String] as? CGWindowID,
                    !beforeIDs.contains(id),
                    let ownerName = e[kCGWindowOwnerName as String] as? String,
                    let pid = e[kCGWindowOwnerPID as String] as? pid_t,
                    let bd = e[kCGWindowBounds as String] as? [String: Any],
                    let b = CGRect(dictionaryRepresentation: bd as CFDictionary)
                else { continue }
                let layer = e[kCGWindowLayer as String] as? Int ?? 0
                if layer < 100 { continue }
                if b.height < minHeight { continue }
                if let need = owner, !ownerName.localizedCaseInsensitiveContains(need) { continue }
                popup = WindowInfo(id: id, owner: ownerName, ownerPID: pid, title: "", bounds: b, layer: layer)
                break
            }
            if popup != nil { break }
            usleep(80_000)
        }

        guard let popup else {
            throw SnapError.windowNotFound("no new popup window appeared within \(timeout)s")
        }
        usleep(useconds_t(settleMs * 1000))
        let img = try Capture.screenshotWindow(popup.id)
        try Capture.writePNG(img, to: URL(fileURLWithPath: out))
        print("wrote \(out)  (window \(popup.id), owner=\(popup.owner), \(Int(popup.bounds.width))x\(Int(popup.bounds.height)))")
    }
}

struct Osnap: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "osnap",
        abstract: "Targeted macOS screenshot CLI — region, window, app, menu-bar popup. Never captures more than asked.",
        subcommands: [ListCmd.self, RegionCmd.self, WindowCmd.self, AppCmd.self, MenubarPopupCmd.self, PopupWaitCmd.self]
    )
}

Osnap.main()
