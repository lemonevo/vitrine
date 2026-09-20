import Foundation

// MARK: - TwoFactorProvider

/// A two-factor method, by the number the identity service reports it under.
///
/// The numbers were verified against Vaultwarden's `TwoFactorType`
/// (`src/db/models/two_factor.rs`, main branch) rather than taken from a table in a client:
///
/// ```
/// Authenticator = 0, Email = 1, Duo = 2, YubiKey = 3, U2f = 4,
/// Remember = 5, OrganizationDuo = 6, Webauthn = 7, RecoveryCode = 8
/// ```
///
/// `8` is in here although the task for this work listed only `0...7`: `is_twofactor_provider_usable`
/// returns true for it, so the server can offer it, and an offered method that this type calls
/// unknown is exactly the case the spec asks to report honestly.
///
/// `recoveryCode` is deliberately **not** completable. Vaultwarden accepts it at the token
/// endpoint and, on success, deletes every two-factor method the account has
/// (`src/api/identity.rs`, `TwoFactorType::RecoveryCode` → `TwoFactor::delete_all_by_user`). A
/// generic "enter your code" prompt must not carry that side effect — it belongs behind a
/// control that says what it is going to do.
nonisolated enum TwoFactorProvider: Int, Sendable, CaseIterable {

    case authenticatorApp = 0
    case email            = 1
    case duo              = 2
    case yubiKeyOTP       = 3
    case u2f              = 4
    case remember         = 5
    case organizationDuo  = 6
    case webAuthn         = 7
    case recoveryCode     = 8

    // MARK: - Selection

    /// The methods Prizm can complete, in the order one is chosen when the server offers several.
    static let supportedOrder: [TwoFactorProvider] = [.authenticatorApp, .yubiKeyOTP, .email]

    var isSupported: Bool { Self.supportedOrder.contains(self) }

    /// The first method the server offered that Prizm can complete, or `nil` when the server
    /// offered none of them.
    ///
    /// Ordering matters once and only once — at selection. Everything downstream takes the chosen
    /// provider as a value, so nothing else can re-decide and disagree with what the user was
    /// shown.
    static func select(from numbers: [Int]) -> TwoFactorProvider? {
        for provider in supportedOrder where numbers.contains(provider.rawValue) {
            return provider
        }
        return nil
    }

    /// Names every number the server offered, so an error can say which method it cannot complete.
    ///
    /// A number with no name is named as a number. Guessing at it would produce a sentence that
    /// reads as knowledge the app does not have.
    static func names(from numbers: [Int]) -> [String] {
        numbers.map { number in
            guard let provider = TwoFactorProvider(rawValue: number) else {
                return L("method %lld", number)
            }
            return provider.displayName
        }
    }

    // MARK: - Text

    /// The name of the method, for a prompt or an error.
    var displayName: String {
        switch self {
        case .authenticatorApp: return L("Authenticator app")
        case .email:            return L("Email")
        case .duo:              return L("Duo")
        case .yubiKeyOTP:       return L("YubiKey")
        case .u2f:              return L("U2F security key")
        case .remember:         return L("Remember this device")
        case .organizationDuo:  return L("Duo (organization)")
        case .webAuthn:         return L("WebAuthn")
        case .recoveryCode:     return L("Recovery code")
        }
    }

    /// The instruction shown above the code field.
    ///
    /// `nil` for a method Prizm cannot complete. Those never reach the prompt, and a string here
    /// would be one nobody can see — which is how a stale sentence survives a change elsewhere.
    /// The prompt is built with a supported provider and unwraps once.
    var promptText: String? {
        switch self {
        case .authenticatorApp: return L("Enter the 6-digit code from your authenticator app.")
        case .yubiKeyOTP:
            return L("Put the cursor in the field below, then tap the metal contact on your YubiKey. The key types the code for you.")
        case .email:            return L("Enter the code that was emailed to you.")
        default:                return nil
        }
    }

    // MARK: - The code field

    /// What the code field accepts and how much of it.
    struct CodeField {
        /// Characters kept as the user types. Anything else is rejected rather than silently
        /// trimmed on submit — a YubiKey code is letters, so the old digits-only filter would
        /// have reduced a tap to an empty string and left the user staring at a dead field.
        let allowed:        CharacterSet
        let maximumLength:  Int
        let placeholder:    String
    }

    var codeField: CodeField? {
        switch self {
        case .authenticatorApp:
            // Six is the standard; authenticator apps can be configured for eight.
            return CodeField(allowed: .decimalDigits, maximumLength: 8, placeholder: L("000000"))
        case .email:
            // Vaultwarden's EMAIL_TOKEN_SIZE defaults to 6 and has a floor of 6, but it is
            // configurable upwards — so this is a ceiling, not the expected length.
            return CodeField(allowed: .decimalDigits, maximumLength: 12, placeholder: L("000000"))
        case .yubiKeyOTP:
            // A Yubico OTP is 44 modhex characters; the field is focused and the key types into
            // it, so its placeholder is an instruction rather than a shape.
            return CodeField(allowed: CharacterSet(charactersIn: "cbdefghijklnrtuv"),
                             maximumLength: 48,
                             placeholder: L("Tap your YubiKey"))
        default:
            return nil
        }
    }

    /// Whether a new code can be asked for.
    ///
    /// Only email has anything to resend: an authenticator app generates continuously and a
    /// YubiKey generates on contact, so a button there would be a control with nothing behind it.
    var offersResend: Bool { self == .email }
}
