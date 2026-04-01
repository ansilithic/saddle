#if canImport(os)
import os
#endif
import Foundation

struct HostHTTP: Sendable {
    let baseURL: String
    let acceptHeader: String

    private static let session: URLSession = {
        URLSession(configuration: .default)
    }()

    func reachable(timeout: TimeInterval = 2) async -> Bool {
        guard let url = URL(string: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        guard let (_, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode < 500
    }

    func get(_ path: String, token: String, params: [(String, String)] = []) async -> Data? {
        var urlString = baseURL + path
        if !params.isEmpty {
            let query = params.map {
                let key = $0.0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.0
                let val = $0.1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.1
                return "\(key)=\(val)"
            }.joined(separator: "&")
            urlString += "?\(query)"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 200 {
            return data
        } else if http.statusCode == 403 || http.statusCode == 429 {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "?"
            #if canImport(os)
            let logger = Logger(subsystem: "com.ansilithic.saddle", category: "http")
            logger.warning("Rate limited (\(http.statusCode)) on \(path, privacy: .public) — remaining: \(remaining, privacy: .public), reset: \(reset, privacy: .public)")
            #else
            fputs("warning: Rate limited (\(http.statusCode)) on \(path) — remaining: \(remaining), reset: \(reset)\n", stderr)
            #endif
        }
        return nil
    }

    func getPaginated<T: Decodable>(
        _ path: String,
        token: String,
        params: [(String, String)] = [],
        perPage: Int = 100,
        maxPages: Int = 50
    ) async -> [T] {
        let decoder = JSONDecoder()
        var all: [T] = []
        var page = 1
        while page <= maxPages {
            var pageParams = params
            pageParams.append(("per_page", "\(perPage)"))
            pageParams.append(("page", "\(page)"))
            guard let data = await get(path, token: token, params: pageParams),
                  let items = try? decoder.decode([T].self, from: data) else { break }
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.count < perPage { break }
            page += 1
        }
        return all
    }

    /// Synchronous form-encoded POST (for OAuth endpoints).
    static func postSync(url urlString: String, body: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        nonisolated(unsafe) var result: Data?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

    /// Synchronous GET for simple one-off calls (auth validation).
    func getSync(_ path: String, token: String, params: [(String, String)] = []) -> Data? {
        nonisolated(unsafe) var result: Data?
        let sem = DispatchSemaphore(value: 0)
        let capturedPath = path
        let capturedToken = token
        let capturedParams = params
        let capturedHTTP = self
        Task { @Sendable in
            result = await capturedHTTP.get(capturedPath, token: capturedToken, params: capturedParams)
            sem.signal()
        }
        sem.wait()
        return result
    }
}
