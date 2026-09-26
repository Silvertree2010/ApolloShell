enum KDLNumberLiteral {
    static func value(of raw: String) -> Double? {
        switch raw {
        case "#inf":
            return .infinity
        case "#-inf":
            return -.infinity
        case "#nan":
            return .nan
        default:
            break
        }
        var bytes = Array(raw.utf8)
        var negative = false
        if let first = bytes.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
            negative = first == UInt8(ascii: "-")
            bytes.removeFirst()
        }
        guard !bytes.isEmpty else { return nil }
        let magnitude: Double?
        if bytes.count >= 2, bytes[0] == UInt8(ascii: "0"), let radix = radix(for: bytes[1]) {
            magnitude = radixValue(Array(bytes[2...]), radix: radix)
        } else {
            magnitude = decimalValue(bytes)
        }
        guard let magnitude else { return nil }
        return negative ? -magnitude : magnitude
    }

    private static func radix(for marker: UInt8) -> Int? {
        switch marker {
        case UInt8(ascii: "x"):
            return 16
        case UInt8(ascii: "o"):
            return 8
        case UInt8(ascii: "b"):
            return 2
        default:
            return nil
        }
    }

    private static func digitValue(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return Int(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return Int(byte - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }

    private static func radixValue(_ digits: [UInt8], radix: Int) -> Double? {
        guard let first = digits.first, let firstValue = digitValue(first), firstValue < radix else {
            return nil
        }
        let limbBase: UInt64 = 1_000_000_000
        var limbs: [UInt64] = [0]
        for byte in digits {
            if byte == UInt8(ascii: "_") { continue }
            guard let digit = digitValue(byte), digit < radix else { return nil }
            guard limbs.count <= 35 else { continue }
            var carry = UInt64(digit)
            for index in limbs.indices {
                let product = limbs[index] * UInt64(radix) + carry
                limbs[index] = product % limbBase
                carry = product / limbBase
            }
            while carry > 0 {
                limbs.append(carry % limbBase)
                carry /= limbBase
            }
        }
        guard limbs.count <= 35 else { return .infinity }
        var text = String(limbs[limbs.count - 1])
        for limb in limbs.dropLast().reversed() {
            let part = String(limb)
            text += String(repeating: "0", count: 9 - part.count) + part
        }
        return Double(text)
    }

    private static func decimalValue(_ bytes: [UInt8]) -> Double? {
        var index = 0
        var cleaned = ""
        func isDigit(_ byte: UInt8) -> Bool {
            byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
        }
        func readInteger() -> Bool {
            guard index < bytes.count, isDigit(bytes[index]) else { return false }
            while index < bytes.count, isDigit(bytes[index]) || bytes[index] == UInt8(ascii: "_") {
                if bytes[index] != UInt8(ascii: "_") {
                    cleaned.unicodeScalars.append(Unicode.Scalar(bytes[index]))
                }
                index += 1
            }
            return true
        }
        guard readInteger() else { return nil }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            cleaned += "."
            index += 1
            guard readInteger() else { return nil }
        }
        var exponentNegative = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            cleaned += "e"
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                exponentNegative = bytes[index] == UInt8(ascii: "-")
                cleaned.unicodeScalars.append(Unicode.Scalar(bytes[index]))
                index += 1
            }
            guard readInteger() else { return nil }
        }
        guard index == bytes.count else { return nil }
        return Double(cleaned) ?? (exponentNegative ? 0 : .infinity)
    }
}
