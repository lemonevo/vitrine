import Foundation

/// Display names for `SecureNoteSubtype`.
///
/// Separate from the enum so the domain entity carries no UI strings, and testable on its own —
/// the `.unknown` case is the one that matters, because its label is the only place the user can see
/// that this build does not recognise a note's subtype.
enum SecureNoteSubtypeLabel {

    static func name(for subtype: SecureNoteSubtype) -> String {
        switch subtype {
        case .generic:         return L("Generic")
        case .bankAccount:     return L("Bank Account")
        case .driversLicense:  return L("Driver's Licence")
        case .passport:        return L("Passport")
        case .medicalRecord:   return L("Medical Record")
        case .membership:      return L("Membership")
        case .socialSecurity:  return L("Social Security Number")
        case .wifi:            return L("WiFi")
        case .softwareLicense: return L("Software Licence")
        // The raw number, not "Unknown". A bare "Unknown" tells the user nothing and hides that the
        // value came from somewhere; the number is at least something they can report, and it makes
        // visible that nothing was silently discarded.
        case .unknown(let raw): return L("Unrecognised type (%d)", raw)
        }
    }
}
