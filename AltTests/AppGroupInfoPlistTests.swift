import Foundation

@main
enum AppGroupInfoPlistTests
{
    static func main() throws
    {
        let original = "group.ru.yandex.mobile.music"
        let adjusted = original + ".TESTTEAM"
        let remote = "group.ru.yandex.remote.sdk"
        let info: [String: Any] = [
            "CFBundleIdentifier": "ru.yandex.mobile.music.TESTTEAM",
            "AMAApplicationGroupIdentifier": original,
            "ExtensionAppGroup": original,
            "NSExtension": ["NSExtensionFileProviderDocumentGroup": original],
            "Nested": [original, ["OtherGroup": remote], 42] as [Any],
            "URL": "https://example.com/" + original,
            "LongerGroup": original + ".unrelated",
            original: "dictionary key stays unchanged",
            "Enabled": true
        ]
        let result = AppGroupInfoPlist.remappingReferences(in: info, originalGroups: [original, remote], authorizedGroups: [adjusted, remote], teamIdentifier: "TESTTEAM")
        precondition(result["AMAApplicationGroupIdentifier"] as? String == adjusted)
        precondition(result["ExtensionAppGroup"] as? String == adjusted)
        precondition((result["NSExtension"] as? [String: String])?["NSExtensionFileProviderDocumentGroup"] == adjusted)
        let nested = result["Nested"] as! [Any]
        precondition(nested[0] as? String == adjusted)
        precondition((nested[1] as? [String: String])?["OtherGroup"] == remote)
        precondition(nested[2] as? Int == 42)
        precondition(result["CFBundleIdentifier"] as? String == "ru.yandex.mobile.music.TESTTEAM")
        precondition(result["URL"] as? String == info["URL"] as? String)
        precondition(result["LongerGroup"] as? String == original + ".unrelated")
        precondition(result[original] as? String == "dictionary key stays unchanged")
        precondition(result["Enabled"] as? Bool == true)

        let unchanged = AppGroupInfoPlist.remappingReferences(in: info, originalGroups: [original], authorizedGroups: [], teamIdentifier: "TESTTEAM")
        precondition(unchanged["AMAApplicationGroupIdentifier"] as? String == original)
        let repeated = AppGroupInfoPlist.remappingReferences(in: result, originalGroups: [adjusted], authorizedGroups: [adjusted], teamIdentifier: "TESTTEAM")
        precondition(repeated["AMAApplicationGroupIdentifier"] as? String == adjusted)

        // Optionally exercise the actual input application's Info.plist.
        if CommandLine.arguments.count > 1
        {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let actual = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            let rewritten = AppGroupInfoPlist.remappingReferences(in: actual, originalGroups: [original, remote], authorizedGroups: [adjusted, remote + ".TESTTEAM"], teamIdentifier: "TESTTEAM")
            precondition(rewritten["AMAApplicationGroupIdentifier"] as? String == adjusted)
            precondition(rewritten["ExtensionAppGroup"] as? String == adjusted)
            precondition(rewritten["CFBundleIdentifier"] as? String == actual["CFBundleIdentifier"] as? String)
            _ = try PropertyListSerialization.data(fromPropertyList: rewritten, format: .binary, options: 0)
        }
        print("PASS: App Group plist references, nested values, authorized mappings and real input fixture")
    }
}
