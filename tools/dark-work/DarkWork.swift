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

private func restore() {
    guard let state = loadState() else { return }
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

private func secondsSinceUserInput() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else {
        return nil
    }
    return value.doubleValue / 1_000_000_000
}

private func watchDisplay() {
    var observedSleep = false
    var previousIdle = secondsSinceUserInput()
    var lastSleepRequest = Date.distantPast
    let started = Date()
    while loadState() != nil {
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        let idle = secondsSinceUserInput()
        if asleep { observedSleep = true }
        if observedSleep && !asleep {
            // Automation can wake the display without the user returning.
            // Only a fresh HID idle reset ends Dark Work.
            if let idle, let previousIdle, idle < 0.8 && idle + 0.1 < previousIdle {
                restore()
                return
            }
            if Date().timeIntervalSince(lastSleepRequest) > 1 {
                _ = try? run("/usr/bin/pmset", ["displaysleepnow"])
                lastSleepRequest = Date()
            }
        }
        // If macOS refuses to sleep the display, do not leave an assertion or stale UI.
        if !observedSleep && Date().timeIntervalSince(started) > 15 {
            restore()
            return
        }
        previousIdle = idle
        usleep(250_000)
    }
}

do {
    if CommandLine.arguments.contains("--activate") {
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
