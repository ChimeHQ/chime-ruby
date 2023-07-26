// swift-tools-version: 5.5

import PackageDescription

let package = Package(
	name: "ChimeRuby",
	platforms: [.macOS(.v11)],
	products: [
		.library(name: "ChimeRuby", targets: ["ChimeRuby"]),
	],
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/ChimeKit", from: "0.3.0"),
	],
	targets: [
		.target(name: "ChimeRuby", dependencies: ["ChimeKit"]),
		.testTarget(name: "ChimeRubyTests", dependencies: ["ChimeRuby"]),
	]
)
