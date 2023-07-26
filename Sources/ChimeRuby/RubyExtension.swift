import Foundation
import OSLog

import ChimeKit
import LanguageServerProtocol

@MainActor
public final class RubyExtension {
    private let host: any HostProtocol
    private var lspServices = [ProjectIdentity: LSPService]()
    private let logger = Logger(subsystem: "com.chimehq.Edit.Ruby", category: "RubyExtension")
    private var shouldUpdate = false

    init(host: any HostProtocol) {
        self.host = host
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

        let service = LSPService(host: host,
								 serverOptions: options,
								 executionParamsProvider: paramProvider,
								 runInUserShell: true)

        lspServices[context.id] = service

        return service
    }
}

extension RubyExtension: ExtensionProtocol {
	public var configuration: ExtensionConfiguration {
		get throws {
			ExtensionConfiguration(documentFilter: [.uti(.rubyScript)],
								   directoryContentFilter: [.uti(.rubyScript), .fileName("Gemfile")])
		}
	}
	
	public var applicationService: ApplicationService {
		return self
	}
}

extension RubyExtension: ApplicationService {
    public func didOpenProject(with context: ProjectContext) throws {
        try lspService(for: context).didOpenProject(with: context)
    }

    public func willCloseProject(with context: ProjectContext) throws {
        try lspService(for: context).willCloseProject(with: context)
    }

    public func symbolService(for context: ProjectContext) throws -> SymbolQueryService? {
        try lspService(for: context).symbolService(for: context)
    }

    public func didOpenDocument(with context: DocumentContext) throws {
        try lspService(for: context)?.didOpenDocument(with: context)
    }

    public func didChangeDocumentContext(from oldContext: DocumentContext, to newContext: DocumentContext) throws {
        try willCloseDocument(with: oldContext)
        try didOpenDocument(with: newContext)
    }

    public func willCloseDocument(with context: DocumentContext) throws {
        try lspService(for: context)?.willCloseDocument(with: context)
    }

    public func documentService(for context: DocumentContext) throws -> DocumentService? {
         try lspService(for: context)?.documentService(for: context)
    }
}

extension RubyExtension {
	static let bundle: Bundle? = {
		// Determine if we are executing within the main application or an extension
		let mainBundle = Bundle.main

		if mainBundle.bundleURL.pathExtension == "appex" {
			return mainBundle
		}

		let bundleURL = mainBundle.bundleURL.appendingPathComponent("Contents/Extensions/RubyExtension.appex", isDirectory: true)

		return Bundle(url: bundleURL)
	}()

	static let envKeys = Set(["GEM_HOME", "GEM_PATH", "SOLARGRAPH_CACHE", "SOLARGRAPH_GLOBAL_CONFIG",
							   "PATH", "SHLVL", "TERM_PROGRAM", "PWD", "TERM_PROGRAM_VERSION", "SHELL", "TERM"])

	private func provideParams(rootURL: URL) async throws -> Process.ExecutionParameters {
		let updateNeeded = self.shouldUpdate

		self.shouldUpdate = false

		return try await self.getSolargraphExecutionParameters(rootURL: rootURL, update: updateNeeded)
    }


	private func getSolargraphExecutionParameters(rootURL: URL, update: Bool) async throws -> Process.ExecutionParameters {
		let userEnv = try await host.captureUserEnvironment()

		let printableEnv = userEnv.filter({ RubyExtension.envKeys.contains($0.key) })

		logger.info("Ruby environment: \(printableEnv, privacy: .public)")

		let solargraph = try await Solargraph.findInstance(with: userEnv, in: rootURL, update: update, host: host)

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
