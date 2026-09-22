import Foundation
@testable import Prizm

/// Demo content for the design screenshots.
///
/// Deliberately rich rather than minimal: the point of the shots is to see the layout under load —
/// long names, org badges, a nested folder, every item type, a trashed item, a re-prompt-flagged
/// item. A fixture with three tidy logins would show a layout that never occurs.
@MainActor
enum DesignFixtures {

    static let orgId = "org-acme"
    static let orgId2 = "org-personal-co"

    static let folders: [Folder] = [
        Folder(id: "f-work", name: "Work"),
        Folder(id: "f-personal", name: "Personal"),
        Folder(id: "f-social", name: "Social"),
        Folder(id: "f-social-forums", name: "Social/Forums"),
        Folder(id: "f-finance", name: "Finance")
    ]

    static let organizations: [Organization] = [
        Organization(id: orgId, name: "Acme Inc", role: .owner),
        Organization(id: orgId2, name: "Side Project", role: .user)
    ]

    static let collections: [OrgCollection] = [
        OrgCollection(id: "c-eng", organizationId: orgId, name: "Engineering"),
        OrgCollection(id: "c-marketing", organizationId: orgId, name: "Marketing"),
        OrgCollection(id: "c-shared", organizationId: orgId, name: "Shared"),
        OrgCollection(id: "c-side", organizationId: orgId2, name: "Side Projects")
    ]

    static let items: [VaultItem] = [
        login(
            id: "i-github", name: "GitHub", username: "alice@acme.dev",
            uri: "https://github.com/login", folder: "f-work",
            totp: "JBSWY3DPEHPK3PXP", favorite: true,
            notes: "Recovery codes are in the attachment. Hardware key registered.",
            custom: [CustomField(name: "Team", value: "Platform", type: .text, linkedId: nil)],
            attachments: [
                Attachment(id: "a-1", fileName: "github-recovery-codes.txt",
                           encryptedKey: "2.abc", size: 1024, sizeName: "1 KB",
                           url: "https://example.invalid/a-1", isUploadIncomplete: false),
                Attachment(id: "a-2", fileName: "ssh-config-backup.tar.gz",
                           encryptedKey: "2.def", size: 2_400_000, sizeName: "2.4 MB",
                           url: nil, isUploadIncomplete: true)
            ]
        ),
        login(id: "i-google", name: "Google", username: "alice.chen@gmail.com",
              uri: "https://accounts.google.com", folder: "f-personal",
              totp: "GEZDGNBVGY3TQOJQ", favorite: true),
        login(id: "i-aws", name: "AWS Console", username: "alice.ops",
              uri: "https://acme.signin.aws.amazon.com/console",
              org: orgId, collections: ["c-eng"], totp: "MFRGGZDFMZTWQ2LK"),
        login(id: "i-stripe", name: "Stripe Dashboard", username: "billing@acme.dev",
              uri: "https://dashboard.stripe.com/login",
              org: orgId, collections: ["c-eng", "c-shared"],
              notes: "Production keys are under Developers → API keys."),
        login(id: "i-bank", name: "Bank of America", username: "alicechen1988",
              uri: "https://www.bankofamerica.com", folder: "f-finance", reprompt: 1,
              notes: "Security questions are in the vault note."),
        login(id: "i-proton", name: "ProtonMail", username: "alice@proton.me",
              uri: "https://mail.proton.me", totp: "JBSWY3DPEHPK3PXP"),
        login(id: "i-netflix", name: "Netflix", username: "alice.chen@gmail.com",
              uri: "https://www.netflix.com/login", folder: "f-personal"),
        login(id: "i-forum", name: "Hacker News", username: "achen",
              uri: "https://news.ycombinator.com/login", folder: "f-social-forums"),
        login(id: "i-old-twitter", name: "Twitter (old)", username: "achen_old",
              uri: "https://twitter.com/login", deleted: true),
        card(id: "i-visa", name: "Visa Personal", cardholder: "Alice Chen",
             brand: "Visa", number: "4111111111114242", month: "07", year: "2029",
             code: "123", favorite: true),
        card(id: "i-mc", name: "Mastercard — Acme", cardholder: "Acme Inc",
             brand: "Mastercard", number: "5555555555554444", month: "11", year: "2027",
             org: orgId, collections: ["c-eng"]),
        identity(id: "i-identity", name: "Alice Chen — Personal", first: "Alice",
                 last: "Chen", email: "alice.chen@gmail.com", phone: "+1 415 555 0134",
                 company: "Acme Inc", address: "1 Market St", city: "San Francisco",
                 state: "CA", postal: "94105", country: "United States", folder: "f-personal"),
        secureNote(id: "i-wifi", name: "Cafe WiFi", subtype: .wifi,
                   notes: "SSID: CafeGuest\nPassword: flat-white-2026\nRotates monthly."),
        secureNote(id: "i-passport", name: "Passport", subtype: .passport,
                   notes: "Number, issue and expiry dates."),
        sshKey(id: "i-ssh", name: "deploy-key-prod",
               fingerprint: "SHA256:9f3Kq2mZ8vLpQ1rT7wXyB4nH6jC0dE5gA2sU8iO3kM",
               publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDeployKeyProdAcme deploy@acme")
    ]

    /// Sidebar badge counts derived from the fixtures, so a count can never disagree with the list
    /// the shots show.
    static var itemCounts: [SidebarSelection: Int] {
        var counts: [SidebarSelection: Int] = [:]
        let live = items.filter { !$0.isDeleted }
        counts[.allItems] = live.count
        counts[.favorites] = live.filter(\.isFavorite).count
        counts[.trash] = items.filter(\.isDeleted).count
        for type in ItemType.allCases {
            counts[.type(type)] = live.filter { matches($0, type) }.count
        }
        for folder in folders {
            counts[.folder(folder.id)] = live.filter { $0.folderId == folder.id }.count
        }
        for org in organizations {
            counts[.organization(org.id)] = live.filter { $0.organizationId == org.id }.count
        }
        for col in collections {
            counts[.collection(col.id)] = live.filter { $0.collectionIds.contains(col.id) }.count
        }
        return counts
    }

    static func matches(_ item: VaultItem, _ type: ItemType) -> Bool {
        switch (item.content, type) {
        case (.login, .login), (.card, .card), (.identity, .identity),
             (.secureNote, .secureNote), (.sshKey, .sshKey):
            return true
        default:
            return false
        }
    }

    // MARK: - Builders

    static func login(
        id: String, name: String, username: String?, uri: String?, folder: String? = nil,
        org: String? = nil, collections: [String] = [], totp: String? = nil,
        favorite: Bool = false, deleted: Bool = false, reprompt: Int = 0,
        notes: String? = nil, custom: [CustomField] = [], attachments: [Attachment] = []
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: favorite, isDeleted: deleted,
            creationDate: date(2024, 3, 12), revisionDate: date(2026, 9, 18),
            content: .login(LoginContent(
                username: username, password: "correct-horse-battery-staple",
                uris: uri.map { [LoginURI(uri: $0, matchType: .defaultMatch)] } ?? [],
                totp: totp, notes: notes, customFields: custom)),
            reprompt: reprompt, attachments: attachments,
            folderId: folder, organizationId: org, collectionIds: collections
        )
    }

    static func card(
        id: String, name: String, cardholder: String?, brand: String?, number: String?,
        month: String?, year: String?, code: String? = nil, folder: String? = nil,
        org: String? = nil, collections: [String] = [], favorite: Bool = false
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: favorite, isDeleted: false,
            creationDate: date(2024, 6, 2), revisionDate: date(2026, 8, 30),
            content: .card(CardContent(
                cardholderName: cardholder, brand: brand, number: number,
                expMonth: month, expYear: year, code: code, notes: nil, customFields: [])),
            folderId: folder, organizationId: org, collectionIds: collections
        )
    }

    static func identity(
        id: String, name: String, first: String?, last: String?, email: String?,
        phone: String?, company: String?, address: String?, city: String?,
        state: String?, postal: String?, country: String?, folder: String? = nil
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: date(2024, 1, 20), revisionDate: date(2026, 5, 4),
            content: .identity(IdentityContent(
                title: nil, firstName: first, middleName: nil, lastName: last,
                address1: address, address2: nil, address3: nil, city: city,
                state: state, postalCode: postal, country: country, company: company,
                email: email, phone: phone, ssn: nil, username: nil,
                passportNumber: nil, licenseNumber: nil, notes: nil, customFields: [])),
            folderId: folder
        )
    }

    static func secureNote(
        id: String, name: String, subtype: SecureNoteSubtype, notes: String?
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: date(2024, 9, 9), revisionDate: date(2026, 2, 14),
            content: .secureNote(SecureNoteContent(
                notes: notes, customFields: [], subtype: subtype))
        )
    }

    static func sshKey(
        id: String, name: String, fingerprint: String?, publicKey: String?
    ) -> VaultItem {
        VaultItem(
            id: id, name: name, isFavorite: false, isDeleted: false,
            creationDate: date(2025, 2, 1), revisionDate: date(2026, 7, 21),
            content: .sshKey(SSHKeyContent(
                privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\n…\n-----END OPENSSH PRIVATE KEY-----",
                publicKey: publicKey, keyFingerprint: fingerprint,
                notes: "Deploy key for the production cluster.", customFields: []))
        )
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 10
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }
}

/// A save that never runs.
///
/// `ItemDetailView` requires an edit-view-model factory; the shots never press Edit, so the use case
/// only has to exist. Returning the draft unchanged is the honest no-op.
@MainActor
final class NoopEditVaultItemUseCase: EditVaultItemUseCase {
    func execute(draft: DraftVaultItem) async throws -> VaultItem {
        throw VaultError.itemNotFound(draft.id)
    }
}
