import Foundation

import ChimeKit
import ProcessEnv

enum SolargraphError: Error {
	case setupScriptNotFound
}

@MainActor
struct Solargraph {
	static let serverOptions: [String: Bool] = [
		"autoformat": false,
		"completion": true,
		"definitions": false,
		"diagnostics": true,
		"folding": false,
		"formatting": false,
		"hover": true,
		"references": false,
		"rename": false,
		"symbols": false,
	]

    struct LocatorOutput: Hashable, Codable {
        let command: String
        let environment: [String : String]?
        let version: String
        let arguments: [String]?
    }

    let details: LocatorOutput
    let userEnv: [String : String]
    let rootURL: URL
	let host: HostProtocol

    static func runLocateScript(with userEnv: [String : String], in rootURL: URL, update: Bool, host: HostProtocol) async throws -> Data {
		guard let locateScriptURL = RubyExtension.bundle?.url(forResource: "locate_solargraph", withExtension: "sh") else {
			throw SolargraphError.setupScriptNotFound
		}

        let args = [locateScriptURL.path] + (update ? ["-u"] : [])

		let params = Process.ExecutionParameters(path: "/bin/sh", arguments: args, environment: userEnv, currentDirectoryURL: rootURL)

		return try await host.launchProcess(with: params, inUserShell: true).readStdout()
    }

	static func findInstance(with userEnv: [String : String], in rootURL: URL, update: Bool, host: HostProtocol) async throws -> Solargraph {
		let data = try await runLocateScript(with: userEnv, in: rootURL, update: update, host: host)

		let details = try JSONDecoder().decode(LocatorOutput.self, from: data)

		return Solargraph(details: details, userEnv: userEnv, rootURL: rootURL, host: host)
    }

    var globalConfigExists: Bool {
        let globalConfigPath = ProcessInfo.processInfo.homePath + "/.config/solargraph/config.yml"

        return FileManager.default.fileExists(atPath: globalConfigPath)
    }

    var builtInConfigURL: URL? {
		return RubyExtension.bundle?.url(forResource: "solargraph", withExtension: "yml")
    }

    var builtInNoRubocopConfigURL: URL? {
		return RubyExtension.bundle?.url(forResource: "solargraph_no_rubocop", withExtension: "yml")
    }

    func executionParameters(for command: String, arguments: [String] = []) async throws -> Process.ExecutionParameters {
        var env = details.environment ?? [:]

        let rubocopPath = rootURL.appendingPathComponent(".rubocop.yml").path
        let configPath = rootURL.appendingPathComponent(".solargraph.yml").path

        let rubocopPresent = FileManager.default.fileExists(atPath: rubocopPath)
        let configPresent = FileManager.default.fileExists(atPath: configPath)
        let globalEnvDefined = env["SOLARGRAPH_GLOBAL_CONFIG"] != nil
        let globalConfigDefined = globalConfigExists || globalEnvDefined

        switch (configPresent, globalConfigDefined, rubocopPresent) {
        case (true, _, _):
            break
        case (false, true, _):
            break
        case (false, false, true):
            if let url = builtInConfigURL {
                env["SOLARGRAPH_GLOBAL_CONFIG"] = url.path
            }
        case (false, false, false):
            if let url = builtInNoRubocopConfigURL {
                env["SOLARGRAPH_GLOBAL_CONFIG"] = url.path
            }
        }

        let envArgs = env.map({ "\($0)=\($1)" }) + [details.command]
        let path = envArgs.joined(separator: " ")

        let args = (details.arguments ?? []) + [command] + arguments

		return Process.ExecutionParameters(path: path,
										   arguments: args,
										   environment: env,
										   currentDirectoryURL: rootURL)
    }

    func startServerParameters() async throws -> Process.ExecutionParameters {
        return try await executionParameters(for: "stdio")
    }

    func updateDocumentation() async throws {
        let params = try await executionParameters(for: "download-core")

		_ = try await host.launchProcess(with: params, inUserShell: true).readStdout()
    }

    func indexBundle() async throws {
        guard details.command == "bundle" else {
            return
        }

        // This is called "bundle", but actually does YARD work
        let params = try await executionParameters(for: "bundle")

		_ = try await host.launchProcess(with: params, inUserShell: true).readStdout()
    }
}
