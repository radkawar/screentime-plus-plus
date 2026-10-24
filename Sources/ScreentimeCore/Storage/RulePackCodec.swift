import Foundation

/// Portable rules only: no history, settings, grants, or Focus session state.
public enum RulePackCodec {
    public static let currentVersion = 1

    public enum FileError: LocalizedError, Equatable {
        case malformed
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .malformed: return "This file is not a valid Screentime++ rule pack."
            case .unsupportedVersion(let version):
                return "This rule pack uses version \(version). Update Screentime++ to open it."
            }
        }
    }

    private struct Document: Codable {
        let version: Int
        let rules: [Rule]
    }

    public static func encode(_ rules: [Rule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: currentVersion, rules: rules))
    }

    public static func decode(_ data: Data) throws -> [Rule] {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        do {
            let header = try decoder.decode(Header.self, from: data)
            guard header.version == currentVersion else { throw FileError.unsupportedVersion(header.version) }
            return try decoder.decode(Document.self, from: data).rules
        } catch let error as FileError {
            throw error
        } catch {
            throw FileError.malformed
        }
    }

    /// Imported rules never replace existing rules, including while rules are locked.
    public static func rulesToAdd(_ rules: [Rule], existingNames: Set<String>) -> [Rule] {
        var names = existingNames
        return rules.compactMap { rule in
            guard names.insert(rule.name).inserted else { return nil }
            var copy = rule
            copy.id = UUID()
            return copy
        }
    }
}
