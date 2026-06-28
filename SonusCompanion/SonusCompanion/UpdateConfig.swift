import Foundation

enum UpdateConfig {
    static let repoOwner = "XinchaoGou"
    static let repoName = "Sonus"
    static let assetFileName = "Sonus-macos.zip"
    static let appBundleName = "Sonus.app"
    static let installPath = "/Applications/Sonus.app"
    static let executableName = "Sonus"

    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    static var isRunningFromInstallLocation: Bool {
        let installed = URL(fileURLWithPath: installPath).resolvingSymlinksInPath().path
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return installed == current
    }
}
