import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Call only from an explicit user action.
    @discardableResult
    public static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// One bounded pass over Accessibility. Every call checks a shared deadline so
/// an unresponsive app can never stall the monitor.
struct AXRead {
    enum Failure: Error {
        case timedOut
        case unavailable
    }

    let deadline: ContinuousClock.Instant

    init(budget: Duration) {
        deadline = ContinuousClock.now.advanced(by: budget)
    }

    var hasTimeLeft: Bool { ContinuousClock.now < deadline }

    func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        guard hasTimeLeft else { throw Failure.timedOut }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success: return value
        case .attributeUnsupported, .noValue, .notImplemented: return nil
        case .cannotComplete: throw Failure.timedOut
        default: throw Failure.unavailable
        }
    }

    func string(_ element: AXUIElement, _ name: String) throws -> String? {
        guard let value = try attribute(element, name) else { return nil }
        return Self.string(from: value)
    }

    func element(_ element: AXUIElement, _ name: String) throws -> AXUIElement? {
        guard let value = try attribute(element, name) else { return nil }
        return Self.element(from: value)
    }

    func children(_ element: AXUIElement, limit: Int) throws -> [AXUIElement] {
        guard hasTimeLeft else { throw Failure.timedOut }
        var count: CFIndex = 0
        let status = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
        if status == .attributeUnsupported || status == .noValue { return [] }
        guard status == .success else { throw Failure.unavailable }
        guard count > 0 else { return [] }
        var values: CFArray?
        guard
            AXUIElementCopyAttributeValues(
                element, kAXChildrenAttribute as CFString, 0, min(count, limit), &values) == .success,
            let children = values as? [AXUIElement]
        else { throw Failure.unavailable }
        return children
    }

    /// Batched read; missing or errored attributes come back as nil.
    func multiple(_ element: AXUIElement, _ names: [String]) throws -> [CFTypeRef?] {
        guard hasTimeLeft else { throw Failure.timedOut }
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard status == .success, let array = values as? [Any] else {
            if status == .cannotComplete { throw Failure.timedOut }
            throw Failure.unavailable
        }
        return names.indices.map { index in
            guard index < array.count else { return nil }
            let value = array[index]
            if value is NSNull { return nil }
            let cf = value as CFTypeRef
            if CFGetTypeID(cf) == AXValueGetTypeID(),
                AXValueGetType(unsafeBitCast(cf, to: AXValue.self)) == .axError
            {
                return nil
            }
            return cf
        }
    }

    func frame(_ element: AXUIElement) throws -> CGRect? {
        guard let position = try attribute(element, kAXPositionAttribute as String),
            let size = try attribute(element, kAXSizeAttribute as String),
            let point = Self.point(from: position),
            let extent = Self.size(from: size),
            point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
            extent.width > 0, extent.height > 0
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    static func string(from value: CFTypeRef) -> String? {
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }

    static func element(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func point(from value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(from value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
