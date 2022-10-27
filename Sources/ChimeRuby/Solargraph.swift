import Foundation

import ProcessEnv
import ProcessServiceClient

enum SolargraphError: Error {
	case setupScriptNotFound
}

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
	let processHostServiceName: String

    static func runLocateScript(with userEnv: [String : String], in rootURL: URL, update: Bool, processHostServiceName: String) async throws -> Data {
		guard let locateScriptURL = Bundle.main.url(forResource: "locate_solargraph", withExtension: "sh") else {
			throw SolargraphError.setupScriptNotFound
		}

        let args = [locateScriptURL.path] + (update ? ["-u"] : [])

		let params = Process.ExecutionParameters(path: "/bin/sh", arguments: args, environment: userEnv, currentDirectoryURL: rootURL)

		// this is stupid, but necessary
		let userParams = try await HostedProcess.userShellInvocation(of: params, with: processHostServiceName)

		return try await HostedProcess(named: processHostServiceName, parameters: userParams).runAndReadStdout()
    }

	static func findInstance(with userEnv: [String : String], in rootURL: URL, update: Bool, processHostServiceName: String) async throws -> Solargraph {
		let data = try await runLocateScript(with: userEnv, in: rootURL, update: update, processHostServiceName: processHostServiceName)

		let details = try JSONDecoder().decode(LocatorOutput.self, from: data)

		return Solargraph(details: details, userEnv: userEnv, rootURL: rootURL, processHostServiceName: processHostServiceName)
    }

    var globalConfigExists: Bool {
        let globalConfigPath = ProcessInfo.processInfo.homePath + "/.config/solargraph/config.yml"

        return FileManager.default.fileExists(atPath: globalConfigPath)
    }

    var builtInConfigURL: URL? {
		return Bundle.main.url(forResource: "solargraph", withExtension: "yml")
    }

    var builtInNoRubocopConfigURL: URL? {
		return Bundle.main.url(forResource: "solargraph_no_rubocop", withExtension: "yml")
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

        let params = Process.ExecutionParameters(path: path,
                                                 arguments: args,
                                                 environment: env,
                                                 currentDirectoryURL: rootURL)

		return try await HostedProcess.userShellInvocation(of: params, with: processHostServiceName)
    }

    func startServerParameters() async throws -> Process.ExecutionParameters {
        return try await executionParameters(for: "stdio")
    }

    func updateDocumentation() async throws {
        let params = try await executionParameters(for: "download-core")

		_ = try await HostedProcess(named: processHostServiceName, parameters: params).runAndReadStdout()
    }

    func indexBundle() async throws {
        guard details.command == "bundle" else {
            return
        }

        // This is called "bundle", but actually does YARD work
        let params = try await executionParameters(for: "bundle")

		_ = try await HostedProcess(named: processHostServiceName, parameters: params).runAndReadStdout()
    }
}
