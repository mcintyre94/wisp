import Foundation

/// Shell-escapes a string for safe interpolation into single-quoted shell arguments.
/// Replaces each `'` with `'\''` (end quote, escaped quote, start quote).
func shellEscape(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
