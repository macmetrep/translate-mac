import ProjectDescription

let project = Project(
  name: "TranslateComics",
  targets: [
    .target(
      name: "TranslateComics",
      destinations: .macOS,
      product: .app,
      bundleId: "io.tuist.TranslateComics",
      deploymentTargets: .macOS("15.0"),
      sources: ["translate-mac/Sources/**"],
      resources: ["translate-mac/Resources/**"],
      dependencies: []
    ),
    .target(
      name: "TranslateComicsTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "io.tuist.TranslateComicsTests",
      deploymentTargets: .macOS("15.0"),
      infoPlist: .default,
      sources: ["translate-mac/Tests/**"],
      resources: [],
      dependencies: [.target(name: "TranslateComics")]
    ),
  ]
)
