import Carbon.HIToolbox
import Foundation

final class HotKeyCenter {
    private let hotKeyID = EventHotKeyID(signature: OSType(0x41545950), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let keyCode: UInt32
    private let modifiers: UInt32
    private(set) var isRegistered = false

    var onHotKey: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    deinit {
        unregister()
    }

    func register() throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.installHandlerFailed(handlerStatus)
        }

        var registeredHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        guard registerStatus == noErr else {
            throw HotKeyError.registerFailed(registerStatus)
        }

        hotKeyRef = registeredHotKey
        isRegistered = true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        isRegistered = false
    }

    func handleHotKey() {
        DispatchQueue.main.async { [weak self] in
            self?.onHotKey?()
        }
    }
}

enum HotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            return "Could not install hotkey handler. OSStatus: \(status)"
        case .registerFailed(let status):
            return "Could not register global hotkey. OSStatus: \(status)"
        }
    }
}

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
        return noErr
    }

    var receivedHotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &receivedHotKeyID
    )

    guard status == noErr else {
        return status
    }

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.handleHotKey()
    return noErr
}
