import Foundation

/// The values the card form offers, and the rule for one it does not.
///
/// The card fields are strings on the wire (`RawCardData.brand` / `expMonth` / `expYear`), and they
/// already round-trip. So this is presentation only — but a picker is a place where data goes missing,
/// so the lists live here with the rule rather than inline in a view.
enum CardFieldOptions {

    /// Bitwarden's brand list.
    ///
    /// Not exhaustive and not meant to be: a card whose brand is absent — a regional one, or a value
    /// another client wrote — keeps what it has. See `isRecognised(brand:)`.
    static let brands = [
        "Visa",
        "Mastercard",
        "American Express",
        "Discover",
        "Diners Club",
        "JCB",
        "Maestro",
        "UnionPay",
        "RuPay",
        "Other"
    ]

    /// `"01"`–`"12"`. Zero-padded because that is what Bitwarden stores, and a picker that produced
    /// `"9"` would change the value every time the form was opened.
    static let months = (1...12).map { String(format: "%02d", $0) }

    /// This year onward. A card that expired last year should not be offered as the default for a new
    /// one, and a year outside this range that arrives from the server is preserved regardless.
    static var years: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (current...(current + 20)).map(String.init)
    }

    /// Whether the picker offers `brand`.
    ///
    /// The form shows a "Custom" row for a value this returns `false` for, holding the original text.
    /// A closed picker would silently rewrite the brand the moment the form opened — the same class of
    /// loss this codebase has already had twice, only harder to notice because the user never touched
    /// the field.
    static func isRecognised(brand: String?) -> Bool {
        guard let brand, !brand.isEmpty else { return true }
        return brands.contains(brand)
    }

    static func isRecognised(month: String?) -> Bool {
        guard let month, !month.isEmpty else { return true }
        return months.contains(month)
    }

    static func isRecognised(year: String?) -> Bool {
        guard let year, !year.isEmpty else { return true }
        return years.contains(year)
    }
}
