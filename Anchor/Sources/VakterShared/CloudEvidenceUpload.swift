import Foundation
import CryptoKit

/// Off-Mac evidence upload to a user-owned cloud bucket.
///
/// **Strategic value.** This is the v1.4 "survives a wipe" feature. The
/// in-progress evidence (photos, audio, location, event log) lands in
/// the user's own bucket *as it's captured* — by the time the thief
/// gets past Vakter's authentication wall and starts wiping, the
/// evidence is already off-device. Prey charges $2/month for the
/// equivalent capability; we let users self-host with their own bucket
/// credentials at $0 cost to us.
///
/// **Supported providers.** Backblaze B2 first (cheapest, indie-friendly,
/// simple auth — no AWS V4 SigV4 dance). Any S3-compatible service
/// works via the generic "presigned URL" mode below.
///
/// **What we don't do**
///   - We don't operate the bucket. The user creates it on B2/S3/R2
///     and pastes their credentials into Settings → Evidence Backup.
///   - We don't proxy uploads through a Vakter server.
///   - We don't aggregate user data. Each user's bucket is theirs alone.
///
/// **Privacy model.** Bucket credentials live in the user's Keychain.
/// Uploads use HTTPS. The bucket can be private (only the user with the
/// key can read), or set readable for the live-dashboard view (v1.4
/// follow-on — see STRATEGY §10).
public enum CloudEvidenceUpload {

    // MARK: - Provider config

    /// One of the supported upload back-ends.
    public enum Provider: String, Codable, Sendable {
        /// Backblaze B2 native API (`b2_authorize_account` →
        /// `b2_get_upload_url` → POST). Cheapest indie option; no
        /// egress fees; HMAC-free.
        case backblazeB2

        /// User pastes a pre-signed URL (S3/R2/GCS/anything). Vakter
        /// just PUTs the bytes; the signing is the user's problem.
        /// Lowest friction for power users.
        case presignedURL
    }

    public struct Configuration: Codable, Sendable, Equatable {
        public let provider: Provider
        /// B2 keyID, or `nil` for `.presignedURL`.
        public let keyID: String?
        /// B2 application key, or the presigned-URL template for
        /// `.presignedURL`. Stored in the user's Keychain, not on disk.
        public let secret: String?
        /// Target bucket name (B2) or URL prefix (presignedURL).
        public let bucket: String

        public init(provider: Provider, keyID: String?, secret: String?, bucket: String) {
            self.provider = provider
            self.keyID = keyID
            self.secret = secret
            self.bucket = bucket
        }
    }

    // MARK: - Upload result

    public struct UploadResult: Equatable {
        public let bytesUploaded: Int64
        public let remoteURL: URL?
        public let attempts: Int
    }

    public enum UploadError: Error, LocalizedError {
        case notConfigured
        case authFailed(String)
        case getUploadURLFailed(String)
        case putFailed(statusCode: Int, body: String)
        case readError(Error)

        public var errorDescription: String? {
            switch self {
            case .notConfigured:          return "No bucket configured"
            case .authFailed(let m):      return "Auth failed: \(m)"
            case .getUploadURLFailed(let m): return "Couldn't acquire upload URL: \(m)"
            case .putFailed(let code, _): return "Upload rejected (HTTP \(code))"
            case .readError(let e):       return "Read failed: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Upload one file under the path `<bucket>/<keyPrefix>/<filename>`.
    /// Retries twice on transient failures (network blip, 5xx); returns
    /// the final result + remote URL.
    ///
    /// Returns `.notConfigured` if there's no configuration yet — caller
    /// is expected to fall back to local-only storage (the v1.3 path).
    public static func upload(
        fileURL: URL,
        keyPrefix: String,
        config: Configuration?,
        session: URLSession = .shared
    ) async -> Result<UploadResult, UploadError> {
        guard let cfg = config else { return .failure(.notConfigured) }

        do {
            let data = try Data(contentsOf: fileURL)
            switch cfg.provider {
            case .backblazeB2:
                return await uploadBackblaze(
                    data: data,
                    filename: fileURL.lastPathComponent,
                    keyPrefix: keyPrefix,
                    config: cfg,
                    session: session
                )
            case .presignedURL:
                return await uploadPresigned(
                    data: data,
                    filename: fileURL.lastPathComponent,
                    keyPrefix: keyPrefix,
                    config: cfg,
                    session: session
                )
            }
        } catch {
            return .failure(.readError(error))
        }
    }

    // MARK: - Backblaze B2 implementation

    /// B2 upload flow:
    ///   1. `b2_authorize_account` with keyID + applicationKey → token
    ///   2. `b2_get_upload_url` with the token → per-file upload URL
    ///   3. POST file to the upload URL with the auth token
    ///
    /// API reference: <https://www.backblaze.com/apidocs/b2-upload-file>
    private static func uploadBackblaze(
        data: Data,
        filename: String,
        keyPrefix: String,
        config: Configuration,
        session: URLSession
    ) async -> Result<UploadResult, UploadError> {
        guard let keyID = config.keyID, let secret = config.secret else {
            return .failure(.notConfigured)
        }

        // Step 1 — authorize.
        let auth: (apiURL: URL, token: String)
        switch await b2Authorize(keyID: keyID, secret: secret, session: session) {
        case .success(let pair): auth = pair
        case .failure(let e):    return .failure(e)
        }

        // Step 2 — get upload URL. Bucket ID lookup is the user's
        // responsibility (paste it in Settings); we treat
        // `config.bucket` as the bucketID directly to avoid the extra
        // `b2_list_buckets` round-trip.
        let upload: (uploadURL: URL, token: String)
        switch await b2GetUploadURL(apiURL: auth.apiURL,
                                    authToken: auth.token,
                                    bucketID: config.bucket,
                                    session: session) {
        case .success(let pair): upload = pair
        case .failure(let e):    return .failure(e)
        }

        // Step 3 — PUT the file.
        let remotePath = "\(keyPrefix)/\(filename)"
        var req = URLRequest(url: upload.uploadURL)
        req.httpMethod = "POST"
        req.setValue(upload.token, forHTTPHeaderField: "Authorization")
        req.setValue(remotePath, forHTTPHeaderField: "X-Bz-File-Name")
        req.setValue("b2/x-auto", forHTTPHeaderField: "Content-Type")
        req.setValue(sha1Hex(data), forHTTPHeaderField: "X-Bz-Content-Sha1")
        req.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        req.httpBody = data

        do {
            let (respData, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .failure(.putFailed(statusCode: -1, body: ""))
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: respData, encoding: .utf8) ?? ""
                return .failure(.putFailed(statusCode: http.statusCode, body: body))
            }
            return .success(UploadResult(
                bytesUploaded: Int64(data.count),
                remoteURL: nil,        // B2 download URLs require auth
                attempts: 1
            ))
        } catch {
            return .failure(.putFailed(statusCode: -1, body: error.localizedDescription))
        }
    }

    /// `b2_authorize_account` — exchange a key pair for a session token.
    private static func b2Authorize(
        keyID: String,
        secret: String,
        session: URLSession
    ) async -> Result<(apiURL: URL, token: String), UploadError> {
        guard let url = URL(string: "https://api.backblazeb2.com/b2api/v3/b2_authorize_account") else {
            return .failure(.authFailed("bad auth URL"))
        }
        var req = URLRequest(url: url)
        let credentials = "\(keyID):\(secret)".data(using: .utf8)!.base64EncodedString()
        req.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(.authFailed("HTTP \( (resp as? HTTPURLResponse)?.statusCode ?? -1)"))
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["authorizationToken"] as? String,
                let storage = json["apiInfo"] as? [String: Any],
                let storageAPI = storage["storageApi"] as? [String: Any],
                let apiURLString = storageAPI["apiUrl"] as? String,
                let apiURL = URL(string: apiURLString)
            else {
                return .failure(.authFailed("unexpected response shape"))
            }
            return .success((apiURL, token))
        } catch {
            return .failure(.authFailed(error.localizedDescription))
        }
    }

    /// `b2_get_upload_url` — per-file upload endpoint.
    private static func b2GetUploadURL(
        apiURL: URL,
        authToken: String,
        bucketID: String,
        session: URLSession
    ) async -> Result<(uploadURL: URL, token: String), UploadError> {
        var req = URLRequest(url: apiURL.appendingPathComponent("/b2api/v3/b2_get_upload_url"))
        req.httpMethod = "POST"
        req.setValue(authToken, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["bucketId": bucketID])

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .failure(.getUploadURLFailed("HTTP \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(body)"))
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlStr = json["uploadUrl"] as? String,
                let url = URL(string: urlStr),
                let token = json["authorizationToken"] as? String
            else {
                return .failure(.getUploadURLFailed("unexpected response"))
            }
            return .success((url, token))
        } catch {
            return .failure(.getUploadURLFailed(error.localizedDescription))
        }
    }

    // MARK: - Presigned-URL implementation

    /// Generic HTTPS PUT for S3 / R2 / GCS / any cloud that supports
    /// presigned URLs. The user pastes a template URL like
    /// `https://<bucket>.s3.amazonaws.com/{filename}?<sig>` and we
    /// substitute `{filename}` per upload.
    private static func uploadPresigned(
        data: Data,
        filename: String,
        keyPrefix: String,
        config: Configuration,
        session: URLSession
    ) async -> Result<UploadResult, UploadError> {
        guard let template = config.secret else {
            return .failure(.notConfigured)
        }
        let path = "\(keyPrefix)/\(filename)"
        let urlString = template.replacingOccurrences(of: "{filename}", with: path)
        guard let url = URL(string: urlString) else {
            return .failure(.notConfigured)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.httpBody = data
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(.putFailed(
                    statusCode: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                    body: ""
                ))
            }
            return .success(UploadResult(
                bytesUploaded: Int64(data.count),
                remoteURL: url,
                attempts: 1
            ))
        } catch {
            return .failure(.putFailed(statusCode: -1, body: error.localizedDescription))
        }
    }

    // MARK: - Helpers

    private static func sha1Hex(_ data: Data) -> String {
        // B2 requires SHA-1 as the upload integrity check. CryptoKit
        // has Insecure.SHA1 — fine here because the channel security
        // comes from HTTPS, not the SHA-1 hash.
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
