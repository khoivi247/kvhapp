import Foundation

enum PlistJsonError: LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg):
            return "Định dạng không hợp lệ: \(msg)"
        }
    }
}

enum PlistJsonEditorService {

    // MARK: - Load as Editable Text

    static func readAsPrettyText(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()

        if ext == "plist" {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            let xmlData = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
            return String(data: xmlData, encoding: .utf8) ?? ""
        } else if ext == "json" {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8) ?? ""
        } else {
            if let str = String(data: data, encoding: .utf8) {
                return str
            }
            return data.prefix(4096).map { String(format: "%02X ", $0) }.joined()
        }
    }

    static func saveEditedText(_ text: String, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard let rawData = text.data(using: .utf8) else {
            throw PlistJsonError.invalidFormat("Không thể mã hóa UTF-8.")
        }

        if ext == "plist" {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let obj = try PropertyListSerialization.propertyList(from: rawData, options: [], format: &format)
            let validated = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
            try validated.write(to: url, options: .atomic)
        } else if ext == "json" {
            let obj = try JSONSerialization.jsonObject(with: rawData, options: [.fragmentsAllowed])
            let validated = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            try validated.write(to: url, options: .atomic)
        } else {
            try rawData.write(to: url, options: .atomic)
        }
    }

    // MARK: - Deep Merge Helpers for .kvh Patches

    static func mergePlist(patchData: Data, intoExistingFileAt existingURL: URL) throws -> Data {
        var patchFmt = PropertyListSerialization.PropertyListFormat.xml
        let patchObj = try PropertyListSerialization.propertyList(from: patchData, options: [], format: &patchFmt)

        guard FileManager.default.fileExists(atPath: existingURL.path),
              let existingData = try? Data(contentsOf: existingURL) else {
            return patchData
        }

        var existingFmt = PropertyListSerialization.PropertyListFormat.xml
        guard let existingObj = try? PropertyListSerialization.propertyList(from: existingData, options: [], format: &existingFmt),
              let existingDict = existingObj as? [String: Any],
              let patchDict = patchObj as? [String: Any] else {
            return patchData
        }

        let merged = deepMergeDictionaries(base: existingDict, overlay: patchDict)
        return try PropertyListSerialization.data(fromPropertyList: merged, format: existingFmt, options: 0)
    }

    static func mergeJSON(patchData: Data, intoExistingFileAt existingURL: URL) throws -> Data {
        let patchObj = try JSONSerialization.jsonObject(with: patchData, options: [])

        guard FileManager.default.fileExists(atPath: existingURL.path),
              let existingData = try? Data(contentsOf: existingURL),
              let existingObj = try? JSONSerialization.jsonObject(with: existingData, options: []),
              let existingDict = existingObj as? [String: Any],
              let patchDict = patchObj as? [String: Any] else {
            return patchData
        }

        let merged = deepMergeDictionaries(base: existingDict, overlay: patchDict)
        return try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
    }

    private static func deepMergeDictionaries(base: [String: Any], overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let overlayDict = value as? [String: Any],
               let baseDict = result[key] as? [String: Any] {
                result[key] = deepMergeDictionaries(base: baseDict, overlay: overlayDict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
