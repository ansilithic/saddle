import ArgumentParser
import CLICore
import Foundation

struct Auth: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage authentication.",
        subcommands: [Login.self, AuthStatus.self, Remove.self],
        defaultSubcommand: Login.self
    )

    struct Login: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Authenticate with GitHub."
        )

        func run() throws {
            let token = try DeviceFlow.authenticate()

            // Validate
            let http = HostHTTP(baseURL: "https://api.github.com", acceptHeader: "application/vnd.github+json")
            guard let data = http.getSync("/user", token: token),
                  let user = try? JSONDecoder().decode(GitHubUser.self, from: data) else {
                Output.error("Got a token but could not verify it.")
                throw ExitCode.failure
            }

            try CredentialStore.platform.set(account: "github.com", token: token)
            print("  " + styled("Authenticated as", .green) + " " + styled(user.login, .bold))
        }
    }

    struct AuthStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show authentication status."
        )

        func run() {
            print()

            if let envToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !envToken.isEmpty {
                let http = HostHTTP(baseURL: "https://api.github.com", acceptHeader: "application/vnd.github+json")
                if let data = http.getSync("/user", token: envToken),
                   let user = try? JSONDecoder().decode(GitHubUser.self, from: data) {
                    print("  " + styled("Authenticated via GITHUB_TOKEN as", .green) + " " + styled(user.login, .bold))
                } else {
                    print("  " + styled("GITHUB_TOKEN is set but invalid.", .yellow))
                }
                return
            }

            if let token = CredentialStore.platform.get(account: "github.com") {
                let http = HostHTTP(baseURL: "https://api.github.com", acceptHeader: "application/vnd.github+json")
                if let data = http.getSync("/user", token: token),
                   let user = try? JSONDecoder().decode(GitHubUser.self, from: data) {
                    print("  " + styled("Authenticated as", .green) + " " + styled(user.login, .bold))
                } else {
                    print("  " + styled("Stored token is invalid. Run", .yellow) + " " + styled("saddle auth", .bold) + " " + styled("to re-authenticate.", .yellow))
                }
                return
            }

            print("  " + styled("Not authenticated.", .dim) + " Run " + styled("saddle auth", .bold) + " to log in.")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove stored credentials."
        )

        func run() throws {
            try CredentialStore.platform.delete(account: "github.com")
            print()
            print("  " + styled("Credentials removed.", .yellow))
        }
    }
}
