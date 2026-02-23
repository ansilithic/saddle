import Foundation

/// Shared HTTP client for forge API requests.
/// Eliminates duplication between GitHub and GitLab API layers.
struct ForgeHTTP: Sendable {
    let baseURL: String
    let acceptHeader: String

    func get(_ path: String, token: String, params: [(String, String)] = []) -> Data? {
        var urlString = baseURL + path
        if !params.isEmpty {
            let query = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
            urlString += "?\(query)"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        nonisolated(unsafe) var result: Data?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
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
