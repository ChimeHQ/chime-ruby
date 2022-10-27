import Foundation
import os.log

import ConcurrencyPlus
import ChimeKit
import LanguageServerProtocol
import ProcessServiceClient

public class RubyExtension {
    private let host: any HostProtocol
    private var lspServices: [ProjectIdentity: LSPService]
    private let logger: Logger
    private var shouldUpdate: Bool
	public let processHostServiceName: String
	private let taskQueue = TaskQueue()

    init(host: any HostProtocol, processHostServiceName: String) {
        self.host = host
        self.lspServices = [:]
		self.logger = Logger(subsystem: "com.chimehq.Edit.Ruby", category: "RubyExtension")
        self.shouldUpdate = false
		self.processHostServiceName = processHostServiceName
    }

    private func lspService(for docContext: DocumentContext) -> LSPService? {
        return docContext.projectContext.map { lspService(for: $0) }
    }

    private func lspService(for context: ProjectContext) -> LSPService {
        if let service = lspServices[context.id] {
            return service
        }

        let url = context.url
        let options = Solargraph.serverOptions
        let paramProvider: LSPService.ExecutionParamsProvider = { [weak self] in
            guard let self = self else {
				throw LSPServiceError.providerUnavailable
            }

			return try await self.provideParams(rootURL: url)
        }

		let filter: LSPService.ContextFilter = { (projContext, docContext) in
			if docContext?.uti.conforms(to: .rubyScript) == true {
				return true
			}

			return RubyExtension.projectRoot(at: projContext.url)
		}

        let service = LSPService(host: host,
								 serverOptions: options,
								 contextFilter: filter,
								 executionParamsProvider: paramProvider,
								 processHostServiceName: processHostServiceName)

        lspServices[context.id] = service

        return service
    }
}

extension RubyExtension: ExtensionProtocol {
    public func didOpenProject(with context: ProjectContext) async throws {
        try await lspService(for: context).didOpenProject(with: context)
    }

    public func willCloseProject(with context: ProjectContext) async throws {
        try await lspService(for: context).willCloseProject(with: context)
    }

    public func symbolService(for context: ProjectContext) async throws -> SymbolQueryService? {
        return try await lspService(for: context).symbolService(for: context)
    }

    public func didOpenDocument(with context: DocumentContext) async throws -> URL? {
        return try await lspService(for: context)?.didOpenDocument(with: context)
    }

    public func didChangeDocumentContext(from oldContext: DocumentContext, to newContext: DocumentContext) async throws {
        try await willCloseDocument(with: oldContext)
        let _ = try await didOpenDocument(with: newContext)
    }

    public func willCloseDocument(with context: DocumentContext) async throws {
        try await lspService(for: context)?.willCloseDocument(with: context)
    }

    public func documentService(for context: DocumentContext) async throws -> DocumentService? {
        return try await lspService(for: context)?.documentService(for: context)
    }
}

extension RubyExtension {
	static let envKeys = Set(["GEM_HOME", "GEM_PATH", "SOLARGRAPH_CACHE", "SOLARGRAPH_GLOBAL_CONFIG",
							   "PATH", "SHLVL", "TERM_PROGRAM", "PWD", "TERM_PROGRAM_VERSION", "SHELL", "TERM"])

	private func provideParams(rootURL: URL) async throws -> Process.ExecutionParameters {
		let task = taskQueue.addOperation {
			let updateNeeded = self.shouldUpdate

			self.shouldUpdate = false

			return try await self.getSolargraphExecutionParameters(rootURL: rootURL, update: updateNeeded)
		}

		return try await task.value
    }


	private func getSolargraphExecutionParameters(rootURL: URL, update: Bool) async throws -> Process.ExecutionParameters {
		let userEnv = try await HostedProcess.userEnvironment(with: processHostServiceName)

		let printableEnv = userEnv.filter({ RubyExtension.envKeys.contains($0.key) })

		logger.info("Ruby environment: \(printableEnv, privacy: .public)")

		let solargraph = try await Solargraph.findInstance(with: userEnv, in: rootURL, update: update, processHostServiceName: processHostServiceName)

        let params = try await solargraph.startServerParameters()

		do {
			try await solargraph.updateDocumentation()
		} catch {
			logger.error("solargraph failed to update documentation: \(error, privacy: .public)")
		}

		do {
			try await solargraph.indexBundle()
		} catch {
			logger.error("solargraph failed to index bundle: \(error, privacy: .public)")
		}

		let printableServerEnv = params.environment?.filter({ RubyExtension.envKeys.contains($0.key) }) ?? [:]
		let serverPath = params.currentDirectoryURL?.path ?? ""

		logger.info("server path: \(params.path, privacy: .public)")
		logger.info("server arguments: \(params.arguments, privacy: .public)")
		logger.info("server env: \(printableServerEnv, privacy: .public)")
		logger.info("server directory: \(serverPath, privacy: .public)")

		return params
    }
}

extension RubyExtension {
	private static func projectRoot(at url: URL) -> Bool {
		let value = try? FileManager.default
			.contentsOfDirectory(atPath: url.absoluteURL.path)
			.contains { $0 == "Gemfile" }

		return value ?? false
	}
}
