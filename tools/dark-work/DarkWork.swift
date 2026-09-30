import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit

// Bundled auxiliary executable. There is deliberately no second menu-bar app.
private struct SavedState: Codable {
    var brightness: [UInt32: Float]?
    var caffeinatePID: Int32?
}

private let stateURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/DarkWork/state.json")

private func loadState() -> SavedState? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(SavedState.self, from: data)
}

private func restoreLegacyBrightness(_ values: [UInt32: Float]?) {
    guard let values, !values.isEmpty,
          let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let getSymbol = dlsym(framework, "DisplayServicesGetBrightness"),
          let setSymbol = dlsym(framework, "DisplayServicesSetBrightness") else { return }
    defer { dlclose(framework) }
    typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    let getBrightness = unsafeBitCast(getSymbol, to: Getter.self)
    let setBrightness = unsafeBitCast(setSymbol, to: Setter.self)
    for (display, brightness) in values {
        var current: Float = 0
        if getBrightness(CGDirectDisplayID(display), &current) == 0 && current < 0.01 {
            _ = setBrightness(CGDirectDisplayID(display), brightness)
        }
    }
}

private func restore(expectedPID: Int32? = nil) {
    guard let state = loadState() else { return }
    if let expectedPID, state.caffeinatePID != expectedPID { return }
    restoreLegacyBrightness(state.brightness)
    if let pid = state.caffeinatePID, pid > 0 {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        if length > 0 && String(cString: path) == "/usr/bin/caffeinate" {
            _ = kill(pid, SIGTERM)
        }
    }
    try? FileManager.default.removeItem(at: stateURL)
}

private func run(_ path: String, _ arguments: [String]) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
}

private func activate() throws {
    if loadState() != nil { restore() }
    let caffeinate = try run("/usr/bin/caffeinate", ["-i"])
    do {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(SavedState(brightness: nil,
                                                      caffeinatePID: caffeinate.processIdentifier))
        try data.write(to: stateURL, options: .atomic)
        _ = try run(CommandLine.arguments[0], ["--watch"])
        // Give the watcher time to observe the sleep edge before requesting it.
        usleep(400_000)
        _ = try run("/usr/bin/pmset", ["displaysleepnow"])
    } catch {
        restore()
        throw error
    }
}

private func shouldEndSession(observedSleep: Bool, asleep: Bool, elapsed: TimeInterval) -> Bool {
    return (observedSleep && !asleep) || (!observedSleep && elapsed > 15)
}

private func watchDisplay() {
    var observedSleep = false
    guard let sessionPID = loadState()?.caffeinatePID else { return }
    let started = Date()
    while loadState()?.caffeinatePID == sessionPID {
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        if asleep { observedSleep = true }
        // Any display wake ends this session, even if the HID reset fell between polls.
        // Never re-sleep a display the user has already restored.
        if shouldEndSession(observedSleep: observedSleep, asleep: asleep,
                            elapsed: Date().timeIntervalSince(started)) {
            restore(expectedPID: sessionPID)
            return
        }
        usleep(250_000)
    }
}

do {
    if CommandLine.arguments.contains("--self-test") {
        assert(!shouldEndSession(observedSleep: false, asleep: false, elapsed: 1))
        assert(!shouldEndSession(observedSleep: true, asleep: true, elapsed: 20))
        assert(shouldEndSession(observedSleep: true, asleep: false, elapsed: 1))
        assert(shouldEndSession(observedSleep: false, asleep: false, elapsed: 16))
        print("Dark Work wake policy checks passed")
    } else if CommandLine.arguments.contains("--activate") {
        try activate()
    } else if CommandLine.arguments.contains("--restore") {
        restore()
    } else if CommandLine.arguments.contains("--watch") {
        watchDisplay()
    } else {
        fputs("Use --activate or --restore.\n", stderr)
        exit(EXIT_FAILURE)
    }
} catch {
    fputs("Dark Work: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
