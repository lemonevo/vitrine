import Foundation

/// A user-defined or linked extra field attached to a vault item.
nonisolated struct CustomField: Equatable, Hashable {
    let name: String
    let value: String?
    let type: CustomFieldType
    /// Non-nil only when `type == .linked`.
    let linkedId: LinkedFieldId?
}

/// Discriminates how a custom field's value is stored and displayed.
///
/// `CaseIterable` drives the type picker in the edit sheet. Not every case is offered for every
/// item type — `.linked` needs native fields to point at, so it is filtered out for secure notes
/// and SSH keys via `LinkedFieldId.supportsLinking(_:)`.
nonisolated enum CustomFieldType: Int, Equatable, Hashable, CaseIterable {
    case text = 0
    case hidden = 1
    case boolean = 2
    case linked = 3

    /// Label shown in the type picker. Resolved through `L(…)` at call time.
    var displayName: String {
        switch self {
        case .text:    return L("Text")
        case .hidden:  return L("Hidden")
        case .boolean: return L("Boolean")
        case .linked:  return L("Linked")
        }
    }
}

/// Identifies a native vault-item field that a linked custom field mirrors.
/// Raw values match the Bitwarden API schema.
nonisolated enum LinkedFieldId: Int, Equatable, Hashable {
    // MARK: - Login fields
    case loginUsername = 100
    case loginPassword = 101

    // MARK: - Card fields
    case cardCardholderName = 300
    case cardExpMonth = 301
    case cardExpYear = 302
    case cardCode = 303
    case cardBrand = 304
    case cardNumber = 305

    // MARK: - Identity fields
    case identityTitle = 400
    case identityMiddleName = 401
    case identityAddress1 = 402
    case identityAddress2 = 403
    case identityAddress3 = 404
    case identityCity = 405
    case identityState = 406
    case identityPostalCode = 407
    case identityCountry = 408
    case identityCompany = 409
    case identityEmail = 410
    case identityPhone = 411
    case identitySsn = 412
    case identityUsername = 413
    case identityPassportNumber = 414
    case identityLicenseNumber = 415
    case identityFirstName = 416
    case identityLastName = 417
    case identityFullName = 418

    /// Human-readable label shown in the linked field row (e.g. "Username").
    ///
    /// Resolved through `L(…)` at call time rather than being a compile-time constant,
    /// so the label follows the interface language when it changes.
    var displayName: String {
        switch self {
        case .loginUsername:        return L("Username")
        case .loginPassword:        return L("Password")
        case .cardCardholderName:   return L("Cardholder Name")
        case .cardExpMonth:         return L("Expiration Month")
        case .cardExpYear:          return L("Expiration Year")
        case .cardCode:             return L("Security Code")
        case .cardBrand:            return L("Brand")
        case .cardNumber:           return L("Number")
        case .identityTitle:        return L("Title")
        case .identityMiddleName:   return L("Middle Name")
        case .identityAddress1:     return L("Address 1")
        case .identityAddress2:     return L("Address 2")
        case .identityAddress3:     return L("Address 3")
        case .identityCity:         return L("City")
        case .identityState:        return L("State")
        case .identityPostalCode:   return L("Postal Code")
        case .identityCountry:      return L("Country")
        case .identityCompany:      return L("Company")
        case .identityEmail:        return L("Email")
        case .identityPhone:        return L("Phone")
        case .identitySsn:          return L("SSN")
        case .identityUsername:     return L("Username")
        case .identityPassportNumber: return L("Passport Number")
        case .identityLicenseNumber:  return L("License Number")
        case .identityFirstName:    return L("First Name")
        case .identityLastName:     return L("Last Name")
        case .identityFullName:     return L("Full Name")
        }
    }
}
