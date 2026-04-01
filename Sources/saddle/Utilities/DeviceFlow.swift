import CLICore
import Foundation

enum DeviceFlow {
    private static let clientID = "Ov23liJR2hLc4Zg3caFj"
    private static let scope = "repo read:org read:user"

    struct CodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let interval: Int
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case interval
            case expiresIn = "expires_in"
        }
    }

    struct TokenResponse: Decodable {
        let accessToken: String?
        let tokenType: String?
        let scope: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case error
        }
    }

    enum FlowError: Error, CustomStringConvertible {
        case requestFailed
        case expired
        case denied
        case unknownError(String)

        var description: String {
            switch self {
            case .requestFailed: return "Failed to contact GitHub"
            case .expired: return "Authentication timed out"
            case .denied: return "Authentication was denied"
            case .unknownError(let msg): return msg
            }
        }
    }

    static func authenticate() throws -> String {
        let codeBody = "client_id=\(clientID)&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope)"
        guard let codeData = HostHTTP.postSync(
            url: "https://github.com/login/device/code",
            body: codeBody
        ), let code = try? JSONDecoder().decode(CodeResponse.self, from: codeData) else {
            throw FlowError.requestFailed
        }

        print()
        print("  " + styled("Enter code:", .dim) + " " + styled(code.userCode, .bold, .white))
        print()

        #if os(macOS)
        Exec.run("/usr/bin/open", args: [code.verificationUri])
        #else
        Exec.run("/usr/bin/env", args: ["xdg-open", code.verificationUri])
        #endif

        var interval = code.interval
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))

        let spinner = ProgressSpinner()
        spinner.label = styled("Waiting for authorization\u{2026}", .dim)
        spinner.start()

        defer { spinner.stop() }

        while Date() < deadline {
            Thread.sleep(forTimeInterval: TimeInterval(interval))

            let tokenBody = "client_id=\(clientID)&device_code=\(code.deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            guard let tokenData = HostHTTP.postSync(
                url: "https://github.com/login/oauth/access_token",
                body: tokenBody
            ), let response = try? JSONDecoder().decode(TokenResponse.self, from: tokenData) else {
                continue
            }

            if let token = response.accessToken {
                return token
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "expired_token":
                throw FlowError.expired
            case "access_denied":
                throw FlowError.denied
            default:
                if let err = response.error {
                    throw FlowError.unknownError(err)
                }
                continue
            }
        }

        throw FlowError.expired
    }
}
