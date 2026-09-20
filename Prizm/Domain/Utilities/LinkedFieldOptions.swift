import Foundation

// MARK: - Linked field options per item type

// `nonisolated` because the project builds with `-default-isolation MainActor`, which an extension
// does not inherit from the type it extends.
nonisolated extension LinkedFieldId {

    /// The native fields a linked custom field may point at for the given item type, in the order
    /// they should be offered.
    ///
    /// **Why this is per-type.** `LinkedFieldId` is a single flat enum covering all five item types,
    /// but a login has no "Passport Number" and a secure note has no fields at all. Offering the
    /// whole enum would let a user link a login's custom field to a card field, which the server
    /// would accept and no client would resolve.
    static func options(for type: ItemType) -> [LinkedFieldId] {
        switch type {
        case .login:
            return [.loginUsername, .loginPassword]

        case .card:
            return [.cardCardholderName, .cardBrand, .cardNumber,
                    .cardExpMonth, .cardExpYear, .cardCode]

        case .identity:
            return [.identityTitle, .identityFirstName, .identityMiddleName,
                    .identityLastName, .identityFullName,
                    .identityUsername, .identityEmail, .identityPhone,
                    .identityCompany,
                    .identityAddress1, .identityAddress2, .identityAddress3,
                    .identityCity, .identityState, .identityPostalCode, .identityCountry,
                    .identitySsn, .identityPassportNumber, .identityLicenseNumber]

        case .secureNote, .sshKey:
            // Nothing to point at. The type picker must therefore not offer `.linked`.
            return []
        }
    }

    /// Whether `.linked` is a selectable custom-field type for the given item type.
    static func supportsLinking(_ type: ItemType) -> Bool {
        !options(for: type).isEmpty
    }

    /// The custom-field types offered for the given item type.
    ///
    /// Identical to `CustomFieldType.allCases` except for item types with no linkable fields, where
    /// `.linked` is removed rather than shown and rejected later.
    static func availableFieldTypes(for type: ItemType) -> [CustomFieldType] {
        supportsLinking(type) ? CustomFieldType.allCases
                              : CustomFieldType.allCases.filter { $0 != .linked }
    }
}
