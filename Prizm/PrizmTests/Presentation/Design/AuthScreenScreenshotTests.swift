import AppKit
import SwiftUI
import XCTest
@testable import Prizm

/// Renders the two authentication screens — first-run login, and the unlock screen every later
/// launch reaches — so the redesign can be looked at rather than imagined.
///
/// Uses the same real-window capture as `VaultScreenshotTests`; see that file for why
/// `ImageRenderer` alone is not enough.
@MainActor
final class AuthScreenScreenshotTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        useLanguage("en")
    }

    /// Points string lookup at one `.lproj`.
    ///
    /// `ActiveLocalization.languageCode` alone does **not** change what `L()` returns — it only feeds
    /// date and number formatting. Strings resolve through `LocalizedBundle.overrideBundle`, so a
    /// capture that wants Chinese has to set both, or it silently photographs English and looks fine.
    ///
    /// Resolving from `Bundle.main` only is the point: this is the guard that the app bundle actually
    /// carries the strings. It used to fall back to `Prizm/Resources` in the checkout, which let the
    /// capture succeed while the shipped bundle had no `.lproj` at all — see
    /// `openspec/changes/xcode-localisation-resources/`.
    private func useLanguage(_ code: String) {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            XCTFail("Prizm.app carries no \(code).lproj — the localisation files are not in the build")
            return
        }
        LocalizedBundle.overrideBundle = bundle
        ActiveLocalization.languageCode = code
        ActiveLocalization.locale       = Locale(identifier: code)
    }

    private func snapshot<V: View>(_ name: String, size: CGSize,
                                   appearance: NSAppearance.Name = .aqua,
                                   @ViewBuilder _ view: () -> V) throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSHostingView(
            rootView: AnyView(
                view().frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            XCTFail("could not prepare \(name)"); return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("could not encode \(name)"); return
        }
        let url = URL(fileURLWithPath: "/tmp/prizm-design/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    /// `roomy` is a comfortable window. `small` is the *minimum* each screen now declares, which
    /// `.windowResizability(.contentSize)` turns into the smallest window the app can be shrunk to —
    /// so these two captures are the clipping check, not a stylistic one.
    private let small = CGSize(width: 480, height: 520)
    private let unlockMinimum = CGSize(width: 480, height: 560)
    private let roomy = CGSize(width: 620, height: 640)

    private func loginVM(filled: Bool = false, error: String? = nil) -> LoginViewModel {
        let vm = LoginViewModel(loginUseCase: MockLoginUseCase())
        if filled {
            vm.serverURL = "https://vault.example.com"
            vm.email     = "alice@example.com"
        }
        vm.errorMessage = error
        return vm
    }

    private var account: Account {
        Account(
            userId: "user-guid-001",
            email: "alice@example.com",
            name: "apple",
            serverEnvironment: ServerEnvironment(
                base: URL(string: "https://vault.example.com")!, overrides: nil
            )
        )
    }

    private func unlockVM(biometrics: Bool = false,
                          pin: Bool = false,
                          pinAttemptsLeft: Int = 5,
                          error: String? = nil) -> UnlockViewModel {
        let auth = MockAuthRepository()
        auth.stubbedBiometricUnlockAvailable = biometrics
        auth.stubbedPinUnlockAvailable = pin
        auth.stubbedPinUnlockRemainingAttempts = pinAttemptsLeft
        let vm = UnlockViewModel(auth: auth, sync: MockSyncUseCase(), account: account)
        vm.errorMessage = error
        return vm
    }

    // MARK: - Login

    func testLoginEmpty() throws {
        try snapshot("auth-login-empty", size: roomy) { LoginView(viewModel: loginVM()) }
    }

    func testLoginFilledWithError() throws {
        try snapshot("auth-login-error", size: roomy) {
            LoginView(viewModel: loginVM(
                filled: true,
                error: "The server could not be reached. Check the URL and your network connection."
            ))
        }
    }

    func testLoginAtMinimumSize() throws {
        try snapshot("auth-login-min", size: small) { LoginView(viewModel: loginVM()) }
        // The banner is the element that grows the card, so it is the one that has to fit.
        try snapshot("auth-login-min-error", size: small) {
            LoginView(viewModel: loginVM(filled: true, error: "Master password incorrect."))
        }
    }

    func testLoginDark() throws {
        try snapshot("auth-login-dark", size: roomy, appearance: .darkAqua) {
            LoginView(viewModel: loginVM(filled: true))
        }
    }

    // MARK: - Unlock

    func testUnlock() throws {
        try snapshot("auth-unlock", size: roomy) { UnlockView(viewModel: unlockVM()) }
    }

    /// The path most returning users see: the button that raises the system prompt, and the subtitle
    /// that names the same sensor.
    func testUnlockWithBiometrics() throws {
        try snapshot("auth-unlock-biometric", size: roomy) {
            UnlockView(viewModel: unlockVM(biometrics: true))
        }
    }

    /// PIN offered, one wrong try already spent, so the remaining-attempt line is visible.
    func testUnlockWithPIN() throws {
        try snapshot("auth-unlock-pin", size: roomy) {
            UnlockView(viewModel: unlockVM(pin: true, pinAttemptsLeft: 4))
        }
    }

    func testUnlockWithError() throws {
        try snapshot("auth-unlock-error", size: roomy) {
            UnlockView(viewModel: unlockVM(error: "Master password incorrect."))
        }
    }

    /// Every optional element at once, in the smallest window the screen allows. If this fits,
    /// nothing else can clip.
    func testUnlockWorstCaseAtMinimumSize() throws {
        try snapshot("auth-unlock-min", size: unlockMinimum) {
            UnlockView(viewModel: unlockVM(biometrics: true, pin: true, pinAttemptsLeft: 4,
                                           error: "Master password incorrect."))
        }
    }

    func testUnlockDark() throws {
        try snapshot("auth-unlock-dark", size: roomy, appearance: .darkAqua) {
            UnlockView(viewModel: unlockVM())
        }
    }

    // MARK: - Chinese

    /// The layout this app is actually used in. A 400 pt card is only proven at the width of the
    /// copy it has to hold, and the shipped strings are English.
    ///
    /// `ActiveLocalization` is a process global and the scheme is `parallelizable`, so this flips the
    /// language for the whole test process for about two seconds. Every other capture here sets the
    /// language in `setUp`, so the only cost is a hypothetical vault screenshot landing inside that
    /// window — which is why this class is run on its own, not as part of a full-suite pass.
    func testBothScreensInChinese() throws {
        defer { useLanguage("en") }
        useLanguage("zh-Hans")

        // Assert the switch actually happened. Without this the capture quietly renders English —
        // which is exactly how a broken language switch first shows up: as a screenshot that looks fine.
        let heading = L("Sign in to your self-hosted vault")
        XCTAssertNotEqual(heading, "Sign in to your self-hosted vault",
                          "zh-Hans lookup returned the English key, so the capture would be meaningless")

        try snapshot("auth-login-zh", size: small) { LoginView(viewModel: loginVM()) }
        try snapshot("auth-unlock-zh", size: unlockMinimum) {
            UnlockView(viewModel: unlockVM(biometrics: true, pin: true))
        }
    }
}
