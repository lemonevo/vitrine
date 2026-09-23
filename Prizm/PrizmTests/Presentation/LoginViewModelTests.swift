import XCTest
import Combine
@testable import Prizm

@MainActor
final class LoginViewModelTests: XCTestCase {

    private var sut:          LoginViewModel!
    private var mockUseCase:  MockLoginUseCase!
    private var cancellables: Set<AnyCancellable> = []

    private func makeAccount() -> Account {
        Account(
            userId:            "user-001",
            email:             "alice@example.com",
            name:              nil,
            serverEnvironment: ServerEnvironment(
                base:      URL(string: "https://vault.example.com")!,
                overrides: nil
            )
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        mockUseCase = MockLoginUseCase()
        sut         = LoginViewModel(loginUseCase: mockUseCase)
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - signIn: password cleared on success

    /// signIn() clears the password field after a successful login.
    func testSignIn_success_clearsPasswordField() async throws {
        mockUseCase.stubbedResult = .signedIn(account: makeAccount(), sync: nil)
        sut.serverURL = "https://vault.example.com"
        sut.email     = "alice@example.com"
        sut.password  = "SuperSecret1!"

        let exp = expectation(description: "password cleared after sign-in")
        sut.$password
            .dropFirst()
            .filter { $0.isEmpty }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.signIn()

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(sut.password, "", "Password field must be cleared after successful login")
    }

    /// signIn() clears the password field when the server returns .requiresTwoFactor.
    func testSignIn_requiresTwoFactor_clearsPasswordField() async throws {
        mockUseCase.stubbedResult = .requiresTwoFactor(.challenge(.authenticatorApp))
        sut.serverURL = "https://vault.example.com"
        sut.email     = "alice@example.com"
        sut.password  = "SuperSecret1!"

        let exp = expectation(description: "flow transitions to 2FA prompt")
        sut.$flowState
            .dropFirst()
            .filter { if case .twoFactorPrompt = $0 { return true }; return false }
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.signIn()

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(sut.password, "", "Password field must be cleared on 2FA prompt transition")
    }

    /// signIn() does not call the use case when password is empty (matches UI disabled-button guard).
    func testSignIn_emptyPassword_doesNotCallUseCase() {
        sut.serverURL = "https://vault.example.com"
        sut.email     = "alice@example.com"
        sut.password  = ""   // empty — guarded before Task is spawned

        sut.signIn()

        XCTAssertEqual(mockUseCase.executeCallCount, 0,
                       "execute must not be called when password is empty")
    }

    // MARK: - cancelTwoFactor

    /// cancelTwoFactor() delegates to the use case and resets flow state to .login.
    func testCancelTwoFactor_callsUseCaseAndResetsState() {
        sut.cancelTwoFactor()

        XCTAssertTrue(mockUseCase.cancelTwoFactorCalled,
                      "cancelTwoFactor must forward to loginUseCase.cancelTwoFactor()")
        XCTAssertEqual(sut.flowState, .login,
                       "flowState must return to .login after cancelling the challenge")
    }

    // MARK: - Incomplete submissions are answered, not prevented

    /// The submit button no longer disables itself until every field is filled — a form whose one
    /// action looks inert while it is being filled teaches the user that it is not for them. So the
    /// emptiness has to be answered here, naming the field and pointing the focus at it.

    func testSignIn_withNothingFilled_namesTheServerFirst() {
        sut.signIn()

        XCTAssertEqual(sut.errorMessage, "Enter the address of your server.")
        XCTAssertEqual(sut.fieldRequiringAttention, .serverURL,
                       "The message and the insertion point have to name the same field")
        XCTAssertEqual(mockUseCase.executeCallCount, 0)
    }

    func testSignIn_withOnlyTheServer_namesTheEmail() {
        sut.serverURL = "https://vault.example.com"
        sut.signIn()

        XCTAssertEqual(sut.errorMessage, "Enter your email address.")
        XCTAssertEqual(sut.fieldRequiringAttention, .email)
    }

    func testSignIn_whitespaceIsNotAnAnswer() {
        sut.serverURL = "   "
        sut.signIn()

        XCTAssertEqual(sut.fieldRequiringAttention, .serverURL,
                       "A field holding only spaces is still empty, and the server would reject it just the same")
    }

    func testSignIn_aCompleteSubmissionClearsThePreviousComplaint() {
        sut.signIn()
        XCTAssertEqual(sut.fieldRequiringAttention, .serverURL)

        mockUseCase.stubbedResult = .signedIn(account: makeAccount(), sync: nil)
        sut.serverURL = "https://vault.example.com"
        sut.email     = "alice@example.com"
        sut.password  = "SuperSecret1!"
        sut.signIn()

        XCTAssertNil(sut.fieldRequiringAttention,
                     "A submission that passes validation must not leave the focus pointer set")
        XCTAssertNil(sut.errorMessage)
    }
}
