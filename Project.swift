import ProjectDescription

let project = Project(
  name: "translate-mac",
  targets: [
    .target(
      name: "translate-mac",
      destinations: .macOS,
      product: .app,
      bundleId: "io.tuist.translate-mac",
      deploymentTargets: .macOS("15.0"),
      sources: ["translate-mac/Sources/**"],
      resources: ["translate-mac/Resources/**"],
      dependencies: []
    ),
    .target(
      name: "translate-macTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "io.tuist.translate-macTests",
      deploymentTargets: .macOS("15.0"),
      infoPlist: .default,
      sources: ["translate-mac/Tests/**"],
      resources: [],
      dependencies: [.target(name: "translate-mac")]
    ),
  ]
)
