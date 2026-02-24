import SwiftUI

struct UnifiedDiffView: View {
    let oldString: String
    let newString: String

    @State private var isExpanded = false

    private static let maxCollapsedLines = 20

    var body: some View {
        let diffLines = computeDiff()
        let showExpand = diffLines.count > Self.maxCollapsedLines && !isExpanded
        let visibleLines = showExpand ? Array(diffLines.prefix(Self.maxCollapsedLines)) : diffLines

        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            Text(line.prefix)
                                .foregroundStyle(line.color)
                                .frame(width: 14, alignment: .center)

                            Text(line.text)
                                .foregroundStyle(line.color)
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(line.backgroundColor)
                    }
                }
            }

            if showExpand {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Text("\(diffLines.count - Self.maxCollapsedLines) more lines...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
    }

    // MARK: - Diff Computation

    private struct DiffLine {
        let prefix: String
        let text: String
        let kind: Kind

        enum Kind {
            case removed
            case added
            case context
        }

        var color: Color {
            switch kind {
            case .removed: return Color(.systemRed)
            case .added: return Color(.systemGreen)
            case .context: return .secondary
            }
        }

        var backgroundColor: Color {
            switch kind {
            case .removed: return Color.red.opacity(0.1)
            case .added: return Color.green.opacity(0.1)
            case .context: return .clear
            }
        }
    }

    private func computeDiff() -> [DiffLine] {
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")

        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var result: [DiffLine] = []
        var oldIdx = 0
        var newIdx = 0

        for commonLine in lcs {
            // Removed lines before this common line
            while oldIdx < oldLines.count && oldLines[oldIdx] != commonLine {
                result.append(DiffLine(prefix: "-", text: oldLines[oldIdx], kind: .removed))
                oldIdx += 1
            }
            // Added lines before this common line
            while newIdx < newLines.count && newLines[newIdx] != commonLine {
                result.append(DiffLine(prefix: "+", text: newLines[newIdx], kind: .added))
                newIdx += 1
            }
            // Context line
            result.append(DiffLine(prefix: " ", text: commonLine, kind: .context))
            oldIdx += 1
            newIdx += 1
        }

        // Remaining removed lines
        while oldIdx < oldLines.count {
            result.append(DiffLine(prefix: "-", text: oldLines[oldIdx], kind: .removed))
            oldIdx += 1
        }
        // Remaining added lines
        while newIdx < newLines.count {
            result.append(DiffLine(prefix: "+", text: newLines[newIdx], kind: .added))
            newIdx += 1
        }

        return result
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...max(m, 1) {
            for j in 1...max(n, 1) {
                guard i <= m, j <= n else { continue }
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }
}
