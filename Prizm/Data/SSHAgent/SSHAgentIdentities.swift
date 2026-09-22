import Foundation

// MARK: - SSHAgentIdentity

/// One SSH key the agent will serve.
///
/// **Public material only.** The blob is the SSH wire encoding of the *public* key, which is what
/// the protocol puts in `IDENTITIES_ANSWER` and what a client sends back to name a key it wants a
/// signature from. Nothing here can produce a signature, which is what makes it safe to keep in
/// memory while the agent is idle.
nonisolated struct SSHAgentIdentity: Hashable, Sendable {
    /// The vault item the key came from. The agent's own identifier for the key: a client names a
    /// key by its blob, and the vault is asked by item id.
    let itemId: String
    let blob:    Data
    /// The item's name, not the comment stored inside the key file. See `SSHAgentKeyStore.load`.
    let comment: String
}

// MARK: - SSHAgentUnusableKey

/// A key the agent cannot use, with the reason it cannot.
///
/// The reason is part of the type because the spec asks for the omission to be **stated**, in
/// Settings, rather than left to be inferred from a key that never appears in `ssh-add -l`. A
/// reason computed at listing time and thrown away would be exactly the kind of explanation that
/// is unavailable when someone actually looks.
nonisolated struct SSHAgentUnusableKey: Hashable, Sendable {
    let itemId: String
    let name:   String
    let reason: String
}

// MARK: - SSHAgentKeyStore

/// Turns vault items into keys the agent can serve, and says why the others are left out.
///
/// Parsing here is for **classification only**: the private key is read, the public blob is taken
/// from it, and the key material is discarded before `load` returns. It is parsed again when a
/// signature is actually requested, which is the behaviour the spec asks for — no parsed private
/// key is held while the agent sits idle — at the cost of reading the item twice per signature.
/// The alternative, holding the parsed key, is the one thing this file must not do.
nonisolated enum SSHAgentKeyStore {

    /// Classifies every SSH key item in the vault.
    ///
    /// - Parameter items: The vault's items. Non-SSH items are ignored rather than reported, since
    ///   "a login item is not an SSH key" is not a failure of anything.
    static func load(items: [VaultItem]) -> (usable: [SSHAgentIdentity], unusable: [SSHAgentUnusableKey]) {
        var usable:   [SSHAgentIdentity]     = []
        var unusable: [SSHAgentUnusableKey]  = []

        for item in items {
            guard case .sshKey(let content) = item.content else { continue }
            guard let text = content.privateKey,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                unusable.append(SSHAgentUnusableKey(
                    itemId: item.id,
                    name:   item.name,
                    reason: L("This item holds no private key.")
                ))
                continue
            }

            do {
                let parsed = try OpenSSHPrivateKey.parse(text)
                usable.append(SSHAgentIdentity(
                    itemId:  item.id,
                    blob:    parsed.publicBlob,
                    // The item's name, deliberately not `parsed.comment`. `ssh-add -l` prints the
                    // comment, and the user's own name for the key is the one that tells them which
                    // key it is; the comment inside the file is whatever the machine that generated
                    // the key happened to write.
                    comment: item.name
                ))
            } catch let error as OpenSSHKeyError {
                unusable.append(SSHAgentUnusableKey(itemId: item.id, name: item.name,
                                                    reason: Self.reason(for: error)))
            } catch {
                unusable.append(SSHAgentUnusableKey(
                    itemId: item.id,
                    name:   item.name,
                    reason: L("This key could not be read: %@", error.localizedDescription)
                ))
            }
        }

        return (usable, unusable)
    }

    /// Parses one item's key at the moment a signature is requested.
    ///
    /// Separate from `load` on purpose: this is the only path that produces key material, and it is
    /// called per signature so the material's lifetime is the signature's lifetime.
    static func key(for item: VaultItem) throws -> SSHParsedKey {
        guard case .sshKey(let content) = item.content else {
            throw OpenSSHKeyError.notOpenSSHFormat(markerFound: nil)
        }
        guard let text = content.privateKey else {
            throw OpenSSHKeyError.malformed("no private key")
        }
        return try OpenSSHPrivateKey.parse(text)
    }

    /// Why a key cannot be served, in the user's language and naming the specific obstruction.
    ///
    /// These are written to be actionable where an action exists. "Passphrase-protected" is not
    /// actionable inside Prizm — Prizm stores no passphrase for a key — but it is still the answer,
    /// and saying it keeps the user from concluding the feature is broken.
    private static func reason(for error: OpenSSHKeyError) -> String {
        switch error {
        case .encrypted(let cipher):
            return L("Passphrase-protected (%@). Vitrine stores no passphrase for a key, so it cannot be used.", cipher)
        case .unsupportedAlgorithm(let algorithm):
            return L("The key type “%@” is not supported. Vitrine can use ed25519 and RSA keys.", algorithm)
        case .notOpenSSHFormat:
            return L("Not an OpenSSH private key. Vitrine needs the openssh-key-v1 format ssh-keygen writes.")
        case .malformed:
            return L("This key could not be read: %@", error.localizedDescription)
        }
    }
}
