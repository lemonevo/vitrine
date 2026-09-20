import XCTest
@testable import Prizm

// MARK: - CertificateImporterTests

/// Parsing, against a real self-signed certificate generated for this suite.
///
/// The fixtures are a genuine X.509 certificate rather than invented bytes, because
/// `SecCertificateCreateWithData` is the only way to know a file is a certificate and a fake would
/// be rejected for being a fake. It carries no key material that matters — it was generated for
/// these tests and is embedded in plain sight.
final class CertificateImporterTests: XCTestCase {

    /// PEM, as `openssl req -x509` writes it: base64 wrapped at 64 characters between BEGIN/END.
    private static let pem = 
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIDGTCCAgGgAwIBAgIUHMrNOQpAY4NLYq7/RfHL5m7EVmowDQYJKoZIhvcNAQEL\n" +
        "BQAwHDEaMBgGA1UEAwwRdmF1bHQuZXhhbXBsZS5jb20wHhcNMjYwOTIwMTMyMTA1\n" +
        "WhcNMzYwOTE3MTMyMTA1WjAcMRowGAYDVQQDDBF2YXVsdC5leGFtcGxlLmNvbTCC\n" +
        "ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALh4tpMpeB7C1AfBa3KcR0Ow\n" +
        "gZh+57a/9lPt08Sv3ZY2n+f6QD3PXn5+nSy8h1YXKKUex5pshusdc+dCE+IF5kZk\n" +
        "JwwiJy44R314mm2uV7TbRfUm+S3bDl78KZn9kpf5x6FKbNVO0h2BjkkDYN9umfId\n" +
        "jS+xo5RRQCAIqy95N/XoxBiFqkmo0vbTh3CRKxGvbaJRgtFa9oZDcK6VGF7KtEPs\n" +
        "DqFWkBR5Ubo8UOGEt5QEsX28Lv+8NuzPYWNiPPfQ1FC+1dIYRk1K2Iz4HwfEAIr3\n" +
        "FydyTHhqAQlSM0sPr2GAJrZLMBMcUuHm9N7Eja4G1lc/7rZ5coX+fDQZ7PfyG0EC\n" +
        "AwEAAaNTMFEwHQYDVR0OBBYEFH/XOTe7i0LkAkZqF1RSZ/i8EhPQMB8GA1UdIwQY\n" +
        "MBaAFH/XOTe7i0LkAkZqF1RSZ/i8EhPQMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZI\n" +
        "hvcNAQELBQADggEBACf83eAMn3JFyM89R6Mz24y7dPeWCNLw848ZLtuxRlNmlUZJ\n" +
        "UQA3OBKvKeUg1Ec1I1qzGKxRHY0PQoh78q2lsHZCQEJ2I+3Bqe7kNzSIOrk4hLab\n" +
        "7HBIo5GlnpEWLsowPmYkynyDeG76Mn9IenRmHSvUpINPlf34PuBvMZsExhxJGGj3\n" +
        "On8TXJ2dleqfdKLcIa33UxxadyhIHy005mWwFM4s5qeVwz5W+qSo7n3gkN6y0ASt\n" +
        "LtnKfhmT6WYjxA1nrY8aNCFcHe8dzlKvZoBK4Kb0MbvNkPSTVQ2mcvdvsJcYUwsy\n" +
        "j+FS78mngy+cIh3u5D491KYjc/Dvf8QJrnt7WFI=\n" +
        "-----END CERTIFICATE-----\n"

    /// The same certificate in DER, base64-encoded.
    private static let derBase64 = "MIIDGTCCAgGgAwIBAgIUHMrNOQpAY4NLYq7/RfHL5m7EVmowDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRdmF1bHQuZXhhbXBsZS5jb20wHhcNMjYwOTIwMTMyMTA1WhcNMzYwOTE3MTMyMTA1WjAcMRowGAYDVQQDDBF2YXVsdC5leGFtcGxlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALh4tpMpeB7C1AfBa3KcR0OwgZh+57a/9lPt08Sv3ZY2n+f6QD3PXn5+nSy8h1YXKKUex5pshusdc+dCE+IF5kZkJwwiJy44R314mm2uV7TbRfUm+S3bDl78KZn9kpf5x6FKbNVO0h2BjkkDYN9umfIdjS+xo5RRQCAIqy95N/XoxBiFqkmo0vbTh3CRKxGvbaJRgtFa9oZDcK6VGF7KtEPsDqFWkBR5Ubo8UOGEt5QEsX28Lv+8NuzPYWNiPPfQ1FC+1dIYRk1K2Iz4HwfEAIr3FydyTHhqAQlSM0sPr2GAJrZLMBMcUuHm9N7Eja4G1lc/7rZ5coX+fDQZ7PfyG0ECAwEAAaNTMFEwHQYDVR0OBBYEFH/XOTe7i0LkAkZqF1RSZ/i8EhPQMB8GA1UdIwQYMBaAFH/XOTe7i0LkAkZqF1RSZ/i8EhPQMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBACf83eAMn3JFyM89R6Mz24y7dPeWCNLw848ZLtuxRlNmlUZJUQA3OBKvKeUg1Ec1I1qzGKxRHY0PQoh78q2lsHZCQEJ2I+3Bqe7kNzSIOrk4hLab7HBIo5GlnpEWLsowPmYkynyDeG76Mn9IenRmHSvUpINPlf34PuBvMZsExhxJGGj3On8TXJ2dleqfdKLcIa33UxxadyhIHy005mWwFM4s5qeVwz5W+qSo7n3gkN6y0AStLtnKfhmT6WYjxA1nrY8aNCFcHe8dzlKvZoBK4Kb0MbvNkPSTVQ2mcvdvsJcYUwsyj+FS78mngy+cIh3u5D491KYjc/Dvf8QJrnt7WFI="

    // MARK: - Accepted forms

    func testPEM_yieldsTheCertificate() throws {
        let certificates = try CertificateImporter.certificates(in: Data(Self.pem.utf8))
        XCTAssertEqual(certificates.count, 1)
        XCTAssertEqual(certificates.first, Data(base64Encoded: Self.derBase64),
                       "the PEM body must decode to the same DER the file would carry")
    }

    func testDER_yieldsTheCertificate() throws {
        let der = try XCTUnwrap(Data(base64Encoded: Self.derBase64))
        let certificates = try CertificateImporter.certificates(in: der)
        XCTAssertEqual(certificates.count, 1)
        XCTAssertEqual(certificates.first, der)
    }

    func testPEMWithTwoBlocks_yieldsBoth() throws {
        let two = Self.pem + Self.pem
        let certificates = try CertificateImporter.certificates(in: Data(two.utf8))
        XCTAssertEqual(certificates.count, 2,
                       "a chain the user trusts is usually more than one certificate")
    }

    // MARK: - Rejected forms

    func testBytesThatAreNotACertificate_areRejected() {
        XCTAssertThrowsError(try CertificateImporter.certificates(in: Data("hello".utf8)))
    }

    func testPEMHeadersAroundSomethingThatIsNotBase64_areRejected() {
        let text = "-----BEGIN CERTIFICATE-----\nnot base64 at all\n-----END CERTIFICATE-----\n"
        XCTAssertThrowsError(try CertificateImporter.certificates(in: Data(text.utf8))) { error in
            XCTAssertTrue(error is CertificateImportError)
        }
    }

    func testPEMHeadersWithNoCertificate_areRejectedRatherThanTrusted() {
        // Storing an empty anchor set would read as "no private authority" in the delegate, which
        // means the system's own — so this has to be an error, not an empty success.
        let text = "-----BEGIN CERTIFICATE-----\n"
        XCTAssertThrowsError(try CertificateImporter.certificates(in: Data(text.utf8)))
    }

    func testTheRejectionHasAMessageThatSaysWhatToDo() {
        let error = CertificateImportError.notACertificate
        let text  = error.errorDescription ?? ""
        XCTAssertTrue(text.contains(".pem"), "the message should name the kinds of file that work")
    }
}
