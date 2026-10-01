import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.hid

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
    // Ask only when Screen off is requested, never at app launch.
    guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        throw NSError(domain: "DarkWork", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Allow Input Monitoring for WattNook/DarkWork in Privacy & Security, then try Screen off again."])
    }
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
        guard loadState()?.caffeinatePID == caffeinate.processIdentifier else {
            throw NSError(domain: "DarkWork", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Physical input monitoring could not start. The display was not switched off."])
        }
        _ = try run("/usr/bin/pmset", ["displaysleepnow"])
    } catch {
        restore()
        throw error
    }
}

private func shouldEndSession(observedSleep: Bool, asleep: Bool, elapsed: TimeInterval,
                             physicalInput: Bool = false) -> Bool {
    return (observedSleep && physicalInput) || (!observedSleep && elapsed > 15)
}

private func isPhysicalActivity(transport: String, page: UInt32, usage: UInt32, value: Int) -> Bool {
    // Normal Quartz/remote-control events and virtual HID devices are not activity.
    guard ["USB", "Bluetooth", "Bluetooth Low Energy", "SPI", "I2C", "FIFO", "ADB"]
        .contains(transport) else { return false }
    switch page {
    case 0x07: return usage >= 4 && usage <= 0xE7 && value > 0 // key down, no key content retained
    case 0x09: return value > 0 // mouse/trackpad button down
    case 0x01: return [0x30, 0x31, 0x38].contains(usage) && value != 0 // X/Y/wheel
    case 0x0D: return usage == 0x42 && value > 0 // trackpad contact
    default: return false // ignore timestamps, sensors and vendor telemetry
    }
}

private final class PhysicalInputMonitor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var armed = false
    var activated = false
    private var scheduled = false

    func start() throws {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            throw NSError(domain: "DarkWork", code: 3)
        }
        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6], // keyboard
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 2], // mouse / built-in trackpad
            [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 1], // pointer
            [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 5], // touchpad
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        // Don't queue unrelated HID reports. Only the activity categories above.
        IOHIDManagerSetInputValueMatchingMultiple(manager, [
            [kIOHIDElementUsagePageKey: 7], [kIOHIDElementUsagePageKey: 9],
            [kIOHIDElementUsagePageKey: 1, kIOHIDElementUsageKey: 0x30],
            [kIOHIDElementUsagePageKey: 1, kIOHIDElementUsageKey: 0x31],
            [kIOHIDElementUsagePageKey: 1, kIOHIDElementUsageKey: 0x38],
            [kIOHIDElementUsagePageKey: 0x0D, kIOHIDElementUsageKey: 0x42],
        ] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, input in
            guard result == kIOReturnSuccess, let context else { return }
            let monitor = Unmanaged<PhysicalInputMonitor>.fromOpaque(context).takeUnretainedValue()
            guard monitor.armed, !monitor.activated else { return }
            let element = IOHIDValueGetElement(input)
            let device = IOHIDElementGetDevice(element)
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            if isPhysicalActivity(transport: transport, page: IOHIDElementGetUsagePage(element),
                usage: IOHIDElementGetUsage(element), value: IOHIDValueGetIntegerValue(input)) {
                monitor.activated = true
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        scheduled = true
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw NSError(domain: "DarkWork", code: 4)
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              devices.contains(where: { device in
                  let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
                  return isPhysicalActivity(transport: transport, page: 7, usage: 4, value: 1)
              }) else { throw NSError(domain: "DarkWork", code: 5) }
    }

    deinit {
        if scheduled {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

private func watchDisplay() throws {
    var observedSleep = false
    guard let sessionPID = loadState()?.caffeinatePID else { return }
    let monitor = PhysicalInputMonitor()
    do { try monitor.start() } catch { restore(expectedPID: sessionPID); throw error }
    let started = ProcessInfo.processInfo.systemUptime
    var nextSessionCheck = started, nextSleepRequest = started
    while true {
        // Run HID callbacks instead of blocking them with usleep. No input history.
        CFRunLoopRunInMode(.defaultMode, 0.25, false)
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextSessionCheck {
            guard loadState()?.caffeinatePID == sessionPID else { return }
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
                restore(expectedPID: sessionPID)
                return
            }
            nextSessionCheck = now + 1
        }
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        if asleep { observedSleep = true; monitor.armed = true }
        if shouldEndSession(observedSleep: observedSleep, asleep: asleep,
                            elapsed: now - started, physicalInput: monitor.activated) {
            restore(expectedPID: sessionPID)
            return
        }
        // Rate-limit retries, including when an automation holds a display assertion.
        if observedSleep && !asleep && now >= nextSleepRequest {
            guard loadState()?.caffeinatePID == sessionPID else { return }
            do {
                let request = try run("/usr/bin/pmset", ["displaysleepnow"])
                request.waitUntilExit()
            } catch {
                restore(expectedPID: sessionPID)
                throw error
            }
            nextSleepRequest = now + 2
        }
    }
}

do {
    if CommandLine.arguments.contains("--self-test") {
        assert(!shouldEndSession(observedSleep: false, asleep: false, elapsed: 1))
        assert(!shouldEndSession(observedSleep: true, asleep: true, elapsed: 20))
        // An automation-only display wake must not end Screen off.
        assert(!shouldEndSession(observedSleep: true, asleep: false, elapsed: 1))
        assert(shouldEndSession(observedSleep: false, asleep: false, elapsed: 16))
        assert(shouldEndSession(observedSleep: true, asleep: false, elapsed: 20, physicalInput: true))
        assert(shouldEndSession(observedSleep: true, asleep: true, elapsed: 20, physicalInput: true))
        assert(!shouldEndSession(observedSleep: false, asleep: false, elapsed: 1, physicalInput: true))
        assert(!isPhysicalActivity(transport: "Virtual", page: 7, usage: 4, value: 1))
        assert(!isPhysicalActivity(transport: "", page: 7, usage: 4, value: 1))
        assert(!isPhysicalActivity(transport: "USB", page: 7, usage: 4, value: 0))
        assert(!isPhysicalActivity(transport: "FIFO", page: 0xFF00, usage: 3, value: 1))
        assert(isPhysicalActivity(transport: "FIFO", page: 7, usage: 4, value: 1))
        assert(isPhysicalActivity(transport: "USB", page: 1, usage: 0x30, value: -2))
        assert(isPhysicalActivity(transport: "Bluetooth", page: 9, usage: 1, value: 1))
        assert(isPhysicalActivity(transport: "SPI", page: 0x0D, usage: 0x42, value: 1))
        print("Dark Work wake policy checks passed")
    } else if CommandLine.arguments.contains("--input-status") {
        // Metadata only: never requests permission, opens devices, or sleeps the screen.
        print("Input Monitoring granted: \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)")
    } else if CommandLine.arguments.contains("--monitor-probe") {
        // Bounded resource/lifecycle check; no screen changes or captured input content.
        let monitor = PhysicalInputMonitor()
        try monitor.start()
        let until = ProcessInfo.processInfo.systemUptime + 10
        while ProcessInfo.processInfo.systemUptime < until {
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }
        print("Physical input monitor lifecycle check passed")
    } else if CommandLine.arguments.contains("--activate") {
        try activate()
    } else if CommandLine.arguments.contains("--restore") {
        restore()
    } else if CommandLine.arguments.contains("--watch") {
        try watchDisplay()
    } else {
        fputs("Use --activate or --restore.\n", stderr)
        exit(EXIT_FAILURE)
    }
} catch {
    fputs("Dark Work: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
