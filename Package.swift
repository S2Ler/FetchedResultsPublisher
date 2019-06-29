// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "FetchedResultsPublisher",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .tvOS(.v13),
  ],
  products: [
    .library(
      name: "FetchedResultsPublisher",
      targets: ["FetchedResultsPublisher"]),
  ],
  targets: [
    .target(
      name: "FetchedResultsPublisher",
      dependencies: []),
    .testTarget(
      name: "FetchedResultsPublisherTests",
      dependencies: ["FetchedResultsPublisher"]),
  ]
)
