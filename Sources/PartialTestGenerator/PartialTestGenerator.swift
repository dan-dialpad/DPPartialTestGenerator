import Foundation
import ArgumentParser

/// Runs XCTests skipping packages that are not needed
@main
struct Generate: ParsableCommand {
    @Argument(help: "The root directory for the project")
    var rootDirectory: String

    @Argument(help: "The root package for the project")
    var rootPackage: String

    @Argument(help: "The test plan file")
    var testPlan: String

    @Argument(help: "The files that changed in the pull request")
    var changedFiles: [String]

    private var testPlanFile: String = ""

    /// The generated JSON with the packages and their dependencies
    private var dependencyJSON: String = ""

    /// The generated list of packages that changed in the commit hash
    private var packageChanges: [String] = []

    mutating func run() throws {
        setup()
        try computeDependencyJSON()
        try computePackageChanges()
        let impact = try computeImpact()
        try removeTestTargets(keeping: impact)
    }

    private mutating func setup() {
        testPlanFile = rootDirectory + testPlan + ".xctestplan"
        dependencyJSON = rootDirectory + "dep.json"
        rootPackage = rootDirectory + rootPackage
    }

    /// Generates a JSON file with all the packages and their dependencies, starting with the root package
    private func computeDependencyJSON() throws {
        try shell("swift package show-dependencies --package-path \(rootPackage) --format json > \(dependencyJSON)")
    }

    /// Get the packages that changed in a specific commit hash
    private mutating func computePackageChanges() throws {
        packageChanges = changedFiles
            .compactMap { match(for: "Packages/(\\w+?)", in: $0) }
    }

    /// Navigate the dependency tree recursively, to figure out the packages that were impacted
    /// by the change in the commit hash. It should include:
    /// 1. The packages listed on **packageChanges**
    /// 2. Any parent packages that relies directly or indirectly on a package listed on **packageChanges**
    private func computeImpact() throws -> Set<Dependency> {
        let jsonStr = try String(contentsOfFile: dependencyJSON, encoding: .utf8)
        let data = jsonStr.data(using: .utf8) ?? Data()
        let rootDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
        return Set(packageChanges)
            .map { computeImpact(dict: rootDict, for: $0) }
            .reduce(Set()) { $0.union($1) }
    }

    private func computeImpact(dict: [String: Any], for name: String) -> Set<Dependency> {
        let currentName = dict["name"] as? String ?? ""
        let currentAbsolutePath = (dict["path"] as? String ?? "")
        let currentPath = String(
            currentAbsolutePath.dropFirst(rootDirectory.count)
        )

        let currentDependency = Dependency(name: currentName, path: currentPath)
        guard currentDependency.name != name else {
            return [currentDependency]
        }
        let dependencies = dict["dependencies"] as? [[String: Any]] ?? []
        let computedDependencies = dependencies
            .map { computeImpact(dict: $0, for: name) }
            .reduce(Set()) { $0.union($1) }
        if computedDependencies.isEmpty {
            return []
        } else {
            let output = [[currentDependency], computedDependencies]
                .flatMap { $0 }
            return Set(output)
        }
    }

    /// Starts with the test plan with all tests included and then removes the test targets, that were not impacted
    /// by the change in the commit hash
    private func removeTestTargets(keeping impactedDependencies: Set<Dependency>) throws {
        let jsonStr = try String(contentsOfFile: testPlanFile, encoding: .utf8)
        let data = jsonStr.data(using: .utf8) ?? Data()
        var testPlanDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
        var testTargets = testPlanDict["testTargets"] as? [[String: [String: String]]] ?? []
        testTargets.removeAll { targetObj in
            let target = targetObj["target"] ?? [:]
            let containerPath = target["containerPath"] ?? ""
            return !impactedDependencies
                .contains { "container:\($0.path)" == containerPath }
        }
        testPlanDict["testTargets"] = testTargets
        let updatedData = try JSONSerialization.data(
            withJSONObject: testPlanDict,
            options: []
        )
        let updatedStr = String(data: updatedData, encoding: .utf8) ?? ""
        try updatedStr.write(to: URL(string: "file://\(testPlanFile)")!, atomically: false, encoding: .utf8)
    }

    private func match(for regex: String, in text: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            var captures: [String] = []
            for match in matches {
                for rangeIndex in 0..<match.numberOfRanges {
                    let matchRange = match.range(at: rangeIndex)
                    if let substringRange = Range(matchRange, in: text) {
                        let capture = String(text[substringRange])
                        captures.append(capture)
                    }
                }
            }
            return captures.last ?? ""
        } catch {
            return ""
        }
    }
}

