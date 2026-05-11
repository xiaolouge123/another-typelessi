import AppKit
import Foundation

final class FunctionHotKeyCenter {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let queue = DispatchQueue(label: "com.local.another-typeless.function-hotkey")
    private var isFunctionDown = false
    private(set) var isRegistered = false

    var onHotKey: (() -> Void)?

    deinit {
        unregister()
    }

    func register() throws {
        unregister()

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }

        guard global != nil || local != nil else {
            throw FunctionHotKeyError.monitorRegistrationFailed
        }

        globalMonitor = global
        localMonitor = local
        isRegistered = true
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        queue.sync {
            isFunctionDown = false
        }

        isRegistered = false
    }

    private func handle(_ event: NSEvent) {
        queue.sync {
            let functionDown = Self.isFunctionDown(in: event)
            let shouldTrigger = functionDown && !isFunctionDown
            isFunctionDown = functionDown

            guard shouldTrigger else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.onHotKey?()
            }
        }
    }

    private static func isFunctionDown(in event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.function) {
            return true
        }

        return event.cgEvent?.flags.contains(.maskSecondaryFn) ?? false
    }
}

enum FunctionHotKeyError: LocalizedError {
    case monitorRegistrationFailed

    var errorDescription: String? {
        switch self {
        case .monitorRegistrationFailed:
            return "Could not register Fn hotkey monitor."
        }
    }
}
