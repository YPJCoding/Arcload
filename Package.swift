// swift-tools-version: 6.2

import PackageDescription

let modernSwiftSettings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Arcload",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "AppCore", targets: ["AppCore"]),
    .executable(name: "Arcload", targets: ["ArcloadApp"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
      name: "AppCore",
      dependencies: ["CSQLite"],
      path: "Sources/AppCore",
      swiftSettings: modernSwiftSettings,
    ),
    .executableTarget(
      name: "ArcloadApp",
      dependencies: ["AppCore"],
      path: "Sources/Application",
      swiftSettings: modernSwiftSettings,
    ),
    .testTarget(
      name: "AppCoreTests",
      dependencies: ["AppCore", "CSQLite"],
      path: "Tests/AppCoreTests",
      swiftSettings: modernSwiftSettings,
    ),
    .executableTarget(
      name: "SmokeTests",
      dependencies: ["AppCore"],
      path: "Tests/SmokeTests",
      swiftSettings: modernSwiftSettings,
    ),
  ],
  swiftLanguageModes: [.v6],
)
