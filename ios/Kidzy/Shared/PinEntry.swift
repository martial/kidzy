import Foundation

/// The parent keypad buffer: 4 to 6 digits; the view submits each time the
/// count reaches a valid length, so a wrong 4-digit guess can grow to 5 or 6.
public struct PinEntry: Sendable, Equatable {
    public static let minLength = 4
    public static let maxLength = 6
    public private(set) var digits = ""

    public init() {}

    /// Appends a digit; returns true when the buffer should be submitted.
    @discardableResult
    public mutating func append(_ digit: Character) -> Bool {
        guard digit.isNumber, digits.count < Self.maxLength else { return false }
        digits.append(digit)
        return digits.count >= Self.minLength
    }

    public mutating func deleteLast() {
        if !digits.isEmpty { digits.removeLast() }
    }

    public mutating func clear() { digits = "" }

    public var count: Int { digits.count }
    public var isFull: Bool { digits.count == Self.maxLength }
}
