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

struct GitLabUser: Decodable {
    let username: String
}

struct GitLabProject: Decodable {
    let pathWithNamespace: String
    let visibility: String?
    let defaultBranch: String?
    let lastActivityAt: String?
    let description: String?
    let starCount: Int?
    let archived: Bool?
    let forkedFromProject: ForkedRef?

    enum CodingKeys: String, CodingKey {
        case pathWithNamespace = "path_with_namespace"
        case visibility
        case defaultBranch = "default_branch"
        case lastActivityAt = "last_activity_at"
        case description
        case starCount = "star_count"
        case archived
        case forkedFromProject = "forked_from_project"
    }

    struct ForkedRef: Decodable {
        let id: Int?
    }
}
