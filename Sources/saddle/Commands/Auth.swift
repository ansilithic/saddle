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

            let http = HostHTTP(baseURL: GitHub.apiBaseURL, acceptHeader: GitHub.apiAccept)
            guard let data = http.getSync("/user", token: token),
                  let user = try? JSONDecoder().decode(GitHubUser.self, from: data) else {
                Output.error("Got a token but could not verify it.")
                throw ExitCode.failure
            }

            try CredentialStore.platform.set(account: GitHub.hostname, token: token)
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

            if let token = CredentialStore.platform.get(account: GitHub.hostname) {
                let http = HostHTTP(baseURL: GitHub.apiBaseURL, acceptHeader: GitHub.apiAccept)
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
            try CredentialStore.platform.delete(account: GitHub.hostname)
            print()
            print("  " + styled("Credentials removed.", .yellow))
        }
    }
}
