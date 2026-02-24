import SwiftUI
import MarkdownUI
import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterPython
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterRust
import TreeSitterGo
import TreeSitterBash
import TreeSitterJSON
import TreeSitterYAML
import TreeSitterHTML
import TreeSitterCSS

struct WispCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        guard let language = language?.lowercased(), !code.isEmpty else {
            return Text(code)
        }

        guard let config = Self.configuration(for: language),
              let query = config.queries[.highlights] else {
            return Text(code)
        }

        let parser = Parser()
        do {
            try parser.setLanguage(config.language)
        } catch {
            return Text(code)
        }

        guard let tree = parser.parse(code) else {
            return Text(code)
        }

        let cursor = query.execute(in: tree)

        let nsCode = code as NSString
        let textProvider: SwiftTreeSitter.Predicate.TextProvider = { range, _ in
            guard range.location >= 0,
                  range.location + range.length <= nsCode.length else { return nil }
            return nsCode.substring(with: range)
        }

        let context = SwiftTreeSitter.Predicate.Context(
            textProvider: textProvider,
            groupMembershipProvider: { _, _, _ in false }
        )
        let highlights = cursor.resolve(with: context).highlights()

        // Build styled Text from highlight ranges
        var result = Text("")
        var lastEnd = 0

        for highlight in highlights {
            let range = highlight.range
            guard range.location >= lastEnd,
                  range.location + range.length <= nsCode.length else { continue }

            // Fill gap before this highlight with plain text
            if range.location > lastEnd {
                let gap = nsCode.substring(
                    with: NSRange(location: lastEnd, length: range.location - lastEnd)
                )
                result = result + Text(gap)
            }

            let text = nsCode.substring(with: range)
            result = result + Text(text).foregroundColor(Self.color(for: highlight.name))
            lastEnd = range.location + range.length
        }

        // Remaining plain text after last highlight
        if lastEnd < nsCode.length {
            result = result + Text(nsCode.substring(from: lastEnd))
        }

        return result
    }

    // MARK: - Language Configurations (lazy, cached)

    private static func configuration(for language: String) -> LanguageConfiguration? {
        configCache[language]
    }

    private static let configCache: [String: LanguageConfiguration] = {
        var cache: [String: LanguageConfiguration] = [:]

        func add(_ tsLanguage: OpaquePointer, name: String, bundleName: String, aliases: [String]) {
            guard let config = try? LanguageConfiguration(
                tsLanguage, name: name, bundleName: bundleName
            ) else { return }
            for alias in aliases {
                cache[alias] = config
            }
        }

        add(tree_sitter_swift(), name: "Swift",
            bundleName: "TreeSitterSwiftQueries_TreeSitterSwiftQueries",
            aliases: ["swift"])
        add(tree_sitter_python(), name: "Python",
            bundleName: "TreeSitterPythonQueries_TreeSitterPythonQueries",
            aliases: ["python", "py"])
        add(tree_sitter_javascript(), name: "JavaScript",
            bundleName: "TreeSitterJavaScriptQueries_TreeSitterJavaScriptQueries",
            aliases: ["javascript", "js", "jsx"])
        add(tree_sitter_typescript(), name: "TypeScript",
            bundleName: "TreeSitterTypeScriptQueries_TreeSitterTypeScriptQueries",
            aliases: ["typescript", "ts", "tsx"])
        add(tree_sitter_rust(), name: "Rust",
            bundleName: "TreeSitterRustQueries_TreeSitterRustQueries",
            aliases: ["rust", "rs"])
        add(tree_sitter_go(), name: "Go",
            bundleName: "TreeSitterGoQueries_TreeSitterGoQueries",
            aliases: ["go", "golang"])
        add(tree_sitter_bash(), name: "Bash",
            bundleName: "TreeSitterBashQueries_TreeSitterBashQueries",
            aliases: ["bash", "sh", "shell", "zsh"])
        add(tree_sitter_json(), name: "JSON",
            bundleName: "TreeSitterJSONQueries_TreeSitterJSONQueries",
            aliases: ["json"])
        add(tree_sitter_yaml(), name: "YAML",
            bundleName: "TreeSitterYAMLQueries_TreeSitterYAMLQueries",
            aliases: ["yaml", "yml"])
        add(tree_sitter_html(), name: "HTML",
            bundleName: "TreeSitterHTMLQueries_TreeSitterHTMLQueries",
            aliases: ["html", "xml", "svg"])
        add(tree_sitter_css(), name: "CSS",
            bundleName: "TreeSitterCSSQueries_TreeSitterCSSQueries",
            aliases: ["css", "scss"])

        return cache
    }()

    // MARK: - Capture Name to Color Mapping

    private static func color(for captureName: String) -> Color {
        let base = captureName.split(separator: ".").first.map(String.init) ?? captureName

        switch base {
        case "keyword", "conditional", "repeat", "include", "operator":
            return adaptiveColor(light: (0.67, 0.05, 0.57), dark: (0.99, 0.37, 0.53))
        case "string":
            return adaptiveColor(light: (0.77, 0.10, 0.09), dark: (0.99, 0.56, 0.37))
        case "comment":
            return adaptiveColor(light: (0.42, 0.47, 0.51), dark: (0.50, 0.55, 0.59))
        case "number", "float", "boolean":
            return adaptiveColor(light: (0.11, 0.44, 0.69), dark: (0.51, 0.75, 0.98))
        case "type", "constructor":
            return adaptiveColor(light: (0.11, 0.46, 0.53), dark: (0.31, 0.82, 0.80))
        case "function", "method":
            return adaptiveColor(light: (0.44, 0.22, 0.68), dark: (0.71, 0.52, 0.95))
        default:
            return adaptiveColor(light: (0.02, 0.02, 0.02), dark: (0.98, 0.98, 0.99))
        }
    }

    private static func adaptiveColor(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
            } else {
                UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
            }
        })
    }
}
