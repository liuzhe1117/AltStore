import Foundation

enum AppGroupInfoPlist
{
    static func remappingReferences(in info: [String: Any], originalGroups: [String], authorizedGroups: [String], teamIdentifier: String) -> [String: Any]
    {
        let authorized = Set(authorizedGroups)
        var replacements = [String: String]()
        for group in originalGroups
        {
            if authorized.contains(group)
            {
                replacements[group] = group
            }
            else
            {
                let adjustedGroup = group + "." + teamIdentifier
                if authorized.contains(adjustedGroup)
                {
                    replacements[group] = adjustedGroup
                }
            }
        }

        // SDKs and extensions can store their shared-container identifier in
        // arbitrary plist keys. Remap exact authorized group references only,
        // including nested dictionaries/arrays, without changing keys or URLs.
        func remap(_ value: Any) -> Any
        {
            if let string = value as? String
            {
                return replacements[string] ?? string
            }
            if let dictionary = value as? [String: Any]
            {
                return dictionary.mapValues(remap)
            }
            if let array = value as? [Any]
            {
                return array.map(remap)
            }
            return value
        }

        return info.mapValues(remap)
    }
}
