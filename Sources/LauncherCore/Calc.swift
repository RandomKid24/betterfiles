import Foundation

/// Typed-in answers: arithmetic ("12*(3+4)") and unit conversion ("5 km to mi").
public enum Calc {
    /// A display string like "84", or nil when `text` isn't a calculation worth showing.
    public static func answer(_ text: String) -> String? {
        if let c = convert(text) { return c }
        let t = text.trimmingCharacters(in: .whitespaces)
        // Needs an operator after the first character, so plain numbers and "-5" stay quiet.
        guard t.dropFirst().contains(where: { "+-*/^%×÷".contains($0) }), let v = eval(t) else { return nil }
        return format(v)
    }

    // MARK: arithmetic: + - * / % ^ and parentheses, with × ÷ accepted

    public static func eval(_ text: String) -> Double? {
        var p = Parser(Array(text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "").filter { !$0.isWhitespace }))
        guard let v = p.expression(), p.done, v.isFinite else { return nil }
        return v
    }

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }
        var done: Bool { i == c.count }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" {
                let op = c[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < c.count, c[i] == "*" || c[i] == "/" || c[i] == "%" {
                let op = c[i]; i += 1
                guard let r = power() else { return nil }
                switch op {
                case "*": v *= r
                case "/": v /= r
                default: v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if i < c.count, c[i] == "^" {
                i += 1
                guard let e = power() else { return nil }   // right-associative
                return pow(base, e)
            }
            return base
        }

        mutating func unary() -> Double? {
            if i < c.count, c[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < c.count, c[i] == "(" {
                i += 1
                guard let v = expression(), i < c.count, c[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < c.count, c[i].isNumber || c[i] == "." { i += 1 }
            return Double(String(c[start..<i]))
        }
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 8
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    // MARK: unit conversion

    private static let units: [String: Dimension] = {
        var u: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { names.forEach { u[$0] = unit } }
        add(UnitLength.meters, "m", "meter", "meters", "metre", "metres")
        add(UnitLength.kilometers, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(UnitLength.centimeters, "cm", "centimeter", "centimeters")
        add(UnitLength.millimeters, "mm", "millimeter", "millimeters")
        add(UnitLength.miles, "mi", "mile", "miles")
        add(UnitLength.feet, "ft", "foot", "feet")
        add(UnitLength.inches, "inch", "inches")
        add(UnitLength.yards, "yd", "yard", "yards")
        add(UnitMass.kilograms, "kg", "kilo", "kilos", "kilogram", "kilograms")
        add(UnitMass.grams, "g", "gram", "grams")
        add(UnitMass.milligrams, "mg")
        add(UnitMass.pounds, "lb", "lbs", "pound", "pounds")
        add(UnitMass.ounces, "oz", "ounce", "ounces")
        add(UnitTemperature.celsius, "c", "celsius", "°c")
        add(UnitTemperature.fahrenheit, "f", "fahrenheit", "°f")
        add(UnitTemperature.kelvin, "k", "kelvin")
        add(UnitVolume.liters, "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.milliliters, "ml")
        add(UnitVolume.gallons, "gal", "gallon", "gallons")
        add(UnitVolume.cups, "cup", "cups")
        add(UnitDuration.seconds, "s", "sec", "second", "seconds")
        add(UnitDuration.minutes, "min", "minute", "minutes")
        add(UnitDuration.hours, "h", "hr", "hour", "hours")
        add(UnitSpeed.kilometersPerHour, "kph", "kmh", "km/h")
        add(UnitSpeed.milesPerHour, "mph", "mi/h")
        add(UnitInformationStorage.bytes, "b", "byte", "bytes")
        add(UnitInformationStorage.kilobytes, "kb")
        add(UnitInformationStorage.megabytes, "mb")
        add(UnitInformationStorage.gigabytes, "gb")
        add(UnitInformationStorage.terabytes, "tb")
        return u
    }()

    /// "5 km to mi" -> "5 km = 3.10685596 mi"
    static func convert(_ text: String) -> String? {
        let parts = text.lowercased().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // value unit (to|in) unit, or the glued form "5km to mi"
        var tokens = parts
        if tokens.count == 3, let split = splitGlued(tokens[0]) { tokens = [split.0, split.1] + tokens.dropFirst() }
        guard tokens.count == 4, ["to", "in", "into", "->"].contains(tokens[2]),
              let value = Double(tokens[0]), let from = units[tokens[1]], let to = units[tokens[3]],
              type(of: from) == type(of: to) else { return nil }
        let result = Measurement(value: value, unit: from).converted(to: to).value
        return "\(format(value)) \(tokens[1]) = \(format((result * 1e6).rounded() / 1e6)) \(tokens[3])"
    }

    private static func splitGlued(_ s: String) -> (String, String)? {
        guard let idx = s.firstIndex(where: { $0.isLetter || $0 == "°" }), idx != s.startIndex,
              Double(s[..<idx]) != nil else { return nil }
        return (String(s[..<idx]), String(s[idx...]))
    }
}
