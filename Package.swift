// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Halo", targets: ["Halo"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0"))
    ],
    targets: [
        .executableTarget(
            name: "Halo",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/Halo"
        )
    ]
)
