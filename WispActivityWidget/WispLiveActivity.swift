import ActivityKit
import SwiftUI
import WidgetKit

struct WispLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WispActivityAttributes.self) { context in
            // Lock Screen banner
            LockScreenBanner(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    StatusDot(isFinished: context.state.isFinished)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.subject ?? context.attributes.spriteName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.currentIntent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.stepNumber > 0 {
                        Text("Step \(context.state.stepNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let previous = context.state.previousIntent {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(previous)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                StatusDot(isFinished: context.state.isFinished)
            } compactTrailing: {
                if context.state.isFinished {
                    Text("Done")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.currentIntent)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                StatusDot(isFinished: context.state.isFinished)
            }
        }
    }
}

// MARK: - Lock Screen Banner

private struct LockScreenBanner: View {
    let context: ActivityViewContext<WispActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
                Text(context.state.subject ?? context.attributes.spriteName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if context.state.stepNumber > 0 {
                    Text("\(context.state.stepNumber) steps")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            // Middle: intent cards or task text
            if context.state.previousIntent != nil || context.state.secondPreviousIntent != nil {
                IntentCardStack(context: context)
            } else {
                Text(context.attributes.userTask)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Footer: current intent with timer or completion
            if context.state.isFinished {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Task complete")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: context.state.currentIntentIcon ?? "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(context.state.currentIntent)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.intentStartDate, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: 160)
    }
}

// MARK: - Intent Card Stack

private struct IntentCardStack: View {
    let context: ActivityViewContext<WispActivityAttributes>

    var body: some View {
        ZStack(alignment: .bottom) {
            // Second-previous intent (behind)
            if let secondPrevious = context.state.secondPreviousIntent {
                IntentCard(text: secondPrevious)
                    .scaleEffect(0.9)
                    .offset(y: -10)
                    .opacity(0.72)
            }

            // Previous intent (front)
            if let previous = context.state.previousIntent {
                IntentCard(text: previous)
            }
        }
    }
}

// MARK: - Intent Card

private struct IntentCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .transition(.asymmetric(
            insertion: .offset(y: 120).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Status Dot

private struct StatusDot: View {
    let isFinished: Bool

    var body: some View {
        Circle()
            .fill(isFinished ? .green : .blue)
            .frame(width: 10, height: 10)
    }
}
