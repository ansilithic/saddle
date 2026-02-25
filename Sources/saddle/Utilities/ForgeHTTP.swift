import Foundation

/// Shared HTTP client for forge API requests.
/// Eliminates duplication between GitHub and GitLab API layers.
struct ForgeHTTP: Sendable {
    let baseURL: String
    let acceptHeader: String

    /// Hosts where TLS certificate validation is relaxed for self-hosted
    /// instances using internal CAs not in the system trust store.
    /// Populated by Forge.fetchAllRepos before any requests are made.
    nonisolated(unsafe) static var selfHostedHosts: Set<String> = []

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        if let proxies = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            config.connectionProxyDictionary = proxies
        }
        return URLSession(configuration: config, delegate: SelfHostedTrustDelegate.shared, delegateQueue: nil)
    }()

    func reachable(timeout: TimeInterval = 2) -> Bool {
        guard let url = URL(string: baseURL + "/version") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        nonisolated(unsafe) var ok = false
        let sem = DispatchSemaphore(value: 0)
        Self.session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                ok = true
            }
            sem.signal()
        }.resume()
        sem.wait()
        return ok
    }

    func get(_ path: String, token: String, params: [(String, String)] = []) -> Data? {
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

        nonisolated(unsafe) var result: Data?
        let sem = DispatchSemaphore(value: 0)
        Self.session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

    func getPaginated<T: Decodable>(
        _ path: String,
        token: String,
        params: [(String, String)] = [],
        perPage: Int = 100,
        maxPages: Int = 50
    ) -> [T] {
        let decoder = JSONDecoder()
        var all: [T] = []
        var page = 1
        while page <= maxPages {
            var pageParams = params
            pageParams.append(("per_page", "\(perPage)"))
            pageParams.append(("page", "\(page)"))
            guard let data = get(path, token: token, params: pageParams),
                  let items = try? decoder.decode([T].self, from: data) else { break }
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.count < perPage { break }
            page += 1
        }
        return all
    }
}

/// Relaxes TLS certificate validation only for self-hosted forge instances
/// detected from the manifest. Public forges (github.com, gitlab.com) and
/// all other hosts use standard system trust evaluation.
private final class SelfHostedTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    static let shared = SelfHostedTrustDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host
        guard ForgeHTTP.selfHostedHosts.contains(host) else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: trust))
    }
}
