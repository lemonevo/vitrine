import AppKit
import os.log

// MARK: - FaviconLoader

/// Loads favicon images from an icon service.
///
/// URL format: `{iconsBase}/{domain}/icon.png`
///
/// **Where `iconsBase` comes from.** The account's own server: `ServerEnvironment.iconsURL`, which
/// is `{base}/icons` unless the account overrides it. Both Bitwarden and Vaultwarden serve
/// `/icons/{domain}/icon.png`, so a self-hosted user's item domains never leave their own
/// infrastructure. There is deliberately **no default**: the loader starts with no base and fetches
/// nothing until `configure(iconsBase:)` is called with the signed-in account's value, so a domain
/// can never be requested before the account's server is known.
///
/// Earlier versions defaulted to `https://icons.bitwarden.net`, which leaked every login item's
/// domain to a third party.
///
/// **Caching.** `URLCache` provides HTTP-level caching (`returnCacheDataElseLoad`); the in-memory
/// table below provides session-level deduplication. The table is dropped when the icon base changes
/// so images from a previous server are not shown for the next one.
///
/// **Why the in-memory table is not an `NSCache`.** `NSCache` discards entries whenever it likes —
/// that is its documented behaviour, and the reason it was chosen: it bounds its own memory. But it
/// bounds nothing this loader needs, because an `actor` already serialises access to it, and it makes
/// the one property callers rely on ("a domain is fetched once per session") unassertable: a test
/// that counts network requests for a repeated fetch passes or fails depending on how much memory
/// the rest of the process is using. The replacement is explicit about its bound instead.
///
/// **Failures are silent** — callers fall back to the appropriate SF Symbol (FR-009). A password
/// manager must not surface an alert because an icon host is unreachable.
///
/// **Thread safety.** `actor` isolation makes the in-memory cache mutation-safe.
actor FaviconLoader {

    // MARK: - Dependencies

    private let session: URLSession
    /// `UserDefaults` is documented by Apple as thread-safe; `nonisolated(unsafe)` matches the
    /// treatment in `SyncTimestampRepositoryImpl`.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.lemonevo.vitrine", category: "FaviconLoader")

    /// Base URL of the icon service. `nil` means "do not fetch" — either no account has signed in
    /// yet, or the user turned website icons off.
    private var iconsBase: URL?

    // MARK: - In-memory cache

    /// Domains fetched this session, oldest first.
    ///
    /// Kept alongside `cachedImages` so eviction is a decision with a stated rule — drop the oldest
    /// fetched domain — rather than something a library does silently. Only a domain that is new to
    /// the table extends the order, so the two can never disagree about what is cached.
    private var fetchedOrder: [String] = []
    private var cachedImages: [String: NSImage] = [:]

    /// Domains retained before the oldest is dropped.
    ///
    /// Icons are small — a 32×32 PNG is single-digit kilobytes — but the loader lives as long as the
    /// signed-in session, so an unbounded table would retain one image per domain a user has ever
    /// looked at. 512 is well past any realistic vault and a few megabytes at worst.
    nonisolated static let memoryCacheLimit = 512

    // MARK: - Init

    /// - Parameters:
    ///   - iconsBase: Icon service base URL. Defaults to `nil` — nothing is fetched until
    ///                `configure(iconsBase:)` supplies the signed-in account's value.
    ///   - session:   The URLSession to fetch with. **Required, with no default.**
    ///
    /// **Why there is no default for `session`.** The icon service lives on the same host as the API,
    /// and that host is frequently a self-hosted Vaultwarden whose certificate only works because of
    /// `ServerTrustDelegate`. `URLSession.shared` has no such delegate, so a loader built on it fails
    /// TLS against a server the rest of the app reaches fine — and because failures here are silent by
    /// design, the only symptom is that every login row quietly shows the fallback glyph. This was the
    /// behaviour until it was fixed; a defaulted parameter is what let the wrong value compile.
    ///   - defaults:  Preference store for `WebsiteIconsPreference`. Injectable for tests.
    init(
        iconsBase: URL? = nil,
        session: URLSession,
        defaults: UserDefaults = .standard
    ) {
        self.iconsBase = iconsBase
        self.session   = session
        self.defaults  = defaults
    }

    // MARK: - Configuration

    /// Points the loader at an icon service, or disables fetching entirely with `nil`.
    ///
    /// The in-memory cache is cleared on every change: after switching servers (or switching icons
    /// off and back on) a stale image from the previous configuration must not be served.
    func configure(iconsBase: URL?) {
        guard iconsBase != self.iconsBase else { return }
        self.iconsBase = iconsBase
        clearCache()
        logger.info("Favicon source updated — fetching \(iconsBase == nil ? "disabled" : "enabled", privacy: .public)")
    }

    // MARK: - Public API

    /// Returns the favicon for `domain`, or `nil` on any failure (FR-009).
    ///
    /// - Parameter domain: Bare domain (e.g. `"github.com"`), no scheme or path.
    func favicon(for domain: String) async -> NSImage? {
        // Checked before the cache, not after: turning website icons off must stop images being
        // shown immediately, not only once the cache happens to expire.
        guard WebsiteIconsPreference.isEnabled(in: defaults) else {
            return nil
        }
        guard let iconsBase else {
            return nil
        }

        if let cached = cachedImages[domain] {
            return cached
        }

        let url = iconsBase
            .appendingPathComponent(domain)
            .appendingPathComponent("icon.png")

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let image = NSImage(data: data) else {
                return nil
            }
            remember(image, for: domain)
            return image
        } catch {
            logger.debug("Favicon fetch failed for \(domain, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Cache maintenance

    private func remember(_ image: NSImage, for domain: String) {
        // `favicon(for:)` awaits inside this actor, so two calls for the same domain can both miss
        // and both arrive here. Only a genuinely new domain may extend the eviction order, or the
        // order and the table would disagree about how many domains are cached.
        let isNewDomain = cachedImages[domain] == nil
        cachedImages[domain] = image
        guard isNewDomain else { return }
        fetchedOrder.append(domain)

        if fetchedOrder.count > Self.memoryCacheLimit {
            let overflow = fetchedOrder.count - Self.memoryCacheLimit
            for evicted in fetchedOrder.prefix(overflow) {
                cachedImages[evicted] = nil
            }
            fetchedOrder.removeFirst(overflow)
        }
    }

    private func clearCache() {
        cachedImages.removeAll()
        fetchedOrder.removeAll()
    }
}
