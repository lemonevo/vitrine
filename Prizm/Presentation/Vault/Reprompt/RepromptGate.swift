import Foundation

// MARK: - RepromptGating

/// Decides whether an item's secrets still require the master password, and records that they have
/// been given.
///
/// `RootViewModel` is the only conformer, and that is the point. A grant is permission to show
/// material the key caches protect, so it has to be revoked by the same teardown that destroys
/// those caches — `lockVault()` and `signOut()` — and not by a second, parallel rule. Holding the
/// set anywhere else would create a second answer to "how long does a grant last", and it would be
/// the copy that survives a lock (design D7, Constitution §III).
///
/// `VaultBrowserViewModel` asks this rather than owning the set. It presents the sheet and holds
/// the reveal state, and it must be able to *request* a grant without being able to *issue* one.
protocol RepromptGating: AnyObject {
    func needsReprompt(for item: VaultItem) -> Bool
    func grantReprompt(for itemId: String)
}

// MARK: - PendingReprompt

/// The re-prompt request currently on screen.
///
/// The continuation — what to do once the password checks out — is deliberately **not** part of
/// this value. Keeping it out leaves a plain equatable pair a test can assert on, and keeps the
/// action out of published state where it would outlive the request if the sheet were dismissed
/// another way.
struct PendingReprompt: Equatable {
    let itemId: String
    let itemName: String
}

// MARK: - RevealGateBinding

/// What a view needs in order to render one gated field.
///
/// A single value rather than three parameters because it travels through five type-specific
/// detail views on its way to `CustomFieldsSection` and `FieldRowView`. Three parameters would be
/// three chances per view to drop one on the floor — and a dropped `isGated` is silent: the field
/// simply reveals, which looks like the gate not existing.
struct RevealGateBinding {

    /// Whether the field is gated at all. False for the fields the gate does not cover.
    var isGated: Bool
    /// The gate's answer, consulted only when `isGated`.
    var isRevealed: Bool
    /// Asks the gate. Toggles: hiding is always allowed, and re-revealing does not re-prompt
    /// because the grant outlives the reveal.
    var request: () -> Void
    /// Whether asking will actually prompt. False when the item is protected but already granted
    /// this session, so a view can say "reveal" rather than promising a prompt that never comes.
    var requiresPrompt: Bool
    /// Copies a value through the gate. Nil falls back to the caller's ordinary copy — which is
    /// correct for a field the gate does not cover, and only for one.
    var copyGated: ((String) -> Void)?

    /// The binding for a field the gate does not cover.
    static let none = RevealGateBinding(isGated: false, isRevealed: false, request: {},
                                        requiresPrompt: false, copyGated: nil)

    /// The binding for a field the gate covers.
    ///
    /// `copyGated` is required rather than optional. A gated row that fell back to the ordinary
    /// copy would be a gate you can walk around by clicking the value instead of using the menu —
    /// and a silently missing closure is exactly how that happens.
    static func gated(isRevealed:     Bool,
                      request:        @escaping () -> Void,
                      requiresPrompt: Bool = true,
                      copyGated:      @escaping (String) -> Void) -> RevealGateBinding {
        RevealGateBinding(isGated: true, isRevealed: isRevealed, request: request,
                          requiresPrompt: requiresPrompt, copyGated: copyGated)
    }

    private init(isGated: Bool, isRevealed: Bool, request: @escaping () -> Void,
                 requiresPrompt: Bool, copyGated: ((String) -> Void)? = nil) {
        self.isGated        = isGated
        self.isRevealed     = isRevealed
        self.request        = request
        self.requiresPrompt = requiresPrompt
        self.copyGated      = copyGated
    }
}
