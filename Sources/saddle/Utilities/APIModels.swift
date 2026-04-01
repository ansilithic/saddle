import Foundation

struct GitHubRepo: Decodable {
    let fullName: String
    let visibility: String?
    let fork: Bool?
    let defaultBranch: String?
    let pushedAt: String?
    let language: String?
    let description: String?
    let stargazersCount: Int?
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case visibility
        case fork
        case defaultBranch = "default_branch"
        case pushedAt = "pushed_at"
        case language
        case description
        case stargazersCount = "stargazers_count"
        case archived
    }
}

struct GitHubOrg: Decodable {
    let login: String
}

struct GitHubUser: Decodable {
    let login: String
}
