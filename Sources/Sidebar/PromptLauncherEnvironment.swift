/// Keeps a forwarded socket paired with the CLI and identity of the hosting app.
struct PromptLauncherEnvironment {
    let inherited: [String: String]
    let bundledCLIPath: String?
    let bundleIdentifier: String?
    let bundleTag: String?

    func merging(_ configured: [String: String], forwardedSocketPath: String?) -> [String: String] {
        var result = inherited.merging(configured) { _, configuredValue in configuredValue }
        guard let forwardedSocketPath else { return result }

        result["CMUX_SOCKET_PATH"] = forwardedSocketPath
        result.removeValue(forKey: "CMUX_SOCKET")
        result["CMUX_BUNDLED_CLI_PATH"] = bundledCLIPath
        result["CMUX_BUNDLE_ID"] = bundleIdentifier
        result["CMUX_TAG"] = bundleTag
        return result
    }
}
