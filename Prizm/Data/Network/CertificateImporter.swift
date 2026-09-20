import Foundation
import Security

// MARK: - CertificateImporter

/// Reads DER-encoded certificates out of a file the user picked.
///
/// Accepts both PEM and DER. Asking the user to know which one they have would reject valid files
/// for a reason that means nothing to them, and PEM is what `openssl` and nearly every
/// self-signed-server guide produces — so "the file is fine, you just named it wrong" is a common
/// outcome worth avoiding. A PEM file may carry several blocks; all of them are returned, because
/// a chain the user trusts is usually more than one certificate.
nonisolated enum CertificateImporter {

    static func certificates(at url: URL) throws -> [Data] {
        try certificates(in: Data(contentsOf: url))
    }

    static func certificates(in data: Data) throws -> [Data] {
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("BEGIN CERTIFICATE") else { return [try validated(data)] }
        return try pemCertificates(in: text)
    }

    // MARK: - PEM

    private static func pemCertificates(in text: String) throws -> [Data] {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end   = "-----END CERTIFICATE-----"

        var certificates: [Data] = []
        var rest = text[text.startIndex...]

        while let start = rest.range(of: begin),
              let stop = rest.range(of: end, range: start.upperBound..<rest.endIndex) {
            // PEM line-wraps the base64 at 64 characters; the decoder wants none of that.
            let body   = rest[start.upperBound..<stop.lowerBound]
            let base64 = String(body.filter { !$0.isWhitespace })
            guard let der = Data(base64Encoded: base64) else { throw CertificateImportError.notACertificate }
            certificates.append(try validated(der))
            rest = rest[stop.upperBound...]
        }

        // A file that says BEGIN but yields nothing is how a truncated or hand-edited file shows
        // up. Reporting it as "trusted" would store an empty anchor set — which the delegate reads
        // as "no private authority", i.e. silently the system's own.
        guard !certificates.isEmpty else { throw CertificateImportError.notACertificate }
        return certificates
    }

    // MARK: - Validation

    /// Parsing is the only way to know a file is a certificate: the extension is a convention and
    /// the header is a comment.
    private static func validated(_ der: Data) throws -> Data {
        guard SecCertificateCreateWithData(nil, der as CFData) != nil else {
            throw CertificateImportError.notACertificate
        }
        return der
    }
}

// MARK: - CertificateImportError

nonisolated enum CertificateImportError: Error, LocalizedError, Equatable {
    /// The file held no parseable certificate.
    case notACertificate

    var errorDescription: String? {
        switch self {
        case .notACertificate:
            return L("That file does not contain a certificate. Choose a .pem, .crt or .cer file exported from your server.")
        }
    }
}
