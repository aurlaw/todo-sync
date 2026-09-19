import Foundation

/// Talks to the Cloudflare Worker. The token and base URL are read from the `SecretStore` on
/// every call (never cached), so a value saved in Settings applies on the very next sync.
public struct URLSessionSyncClient: SyncClient {
    private let session: URLSession
    private let secrets: any SecretStore

    public init(session: URLSession = .shared, secrets: any SecretStore) {
        self.session = session
        self.secrets = secrets
    }

    public func baseURL() async throws -> URL {
        let raw = try secret(.workerBaseURL)
        guard !raw.isEmpty else { throw SyncError.notConfigured }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { throw SyncError.invalidURL(raw) }
        return url
    }

    public func push(_ items: [TodoWireDto]) async throws -> PushResponse {
        var request = try await makeRequest(path: "push", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PushRequest(items: items))
        return try await send(request, as: PushResponse.self)
    }

    public func changes(since: Int64, limit: Int) async throws -> ChangesResponse {
        let request = try await makeRequest(
            path: "changes",
            method: "GET",
            query: [URLQueryItem(name: "since", value: String(since)), URLQueryItem(name: "limit", value: String(limit))]
        )
        return try await send(request, as: ChangesResponse.self)
    }

    private func secret(_ key: SecretKey) throws -> String {
        do {
            return try secrets.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            throw SyncError.secretStore(String(describing: error))
        }
    }

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        let token = try secret(.apiToken)
        guard !token.isEmpty else { throw SyncError.notConfigured }

        let base = try await baseURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidURL(base.absoluteString)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw SyncError.invalidURL(base.absoluteString) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SyncError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.transport("non-HTTP response")
        }
        if http.statusCode == 401 { throw SyncError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SyncError.http(http.statusCode) }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SyncError.decoding(String(describing: error))
        }
    }
}
