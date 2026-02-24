import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "LiveActivity")

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WispActivityAttributes>?
    private var pendingContent: WispActivityAttributes.ContentState?
    private var debounceTimer: Timer?
    private var lastStepNumber: Int = 0
    private var activityStartDate: Date?

    private init() {}

    func startActivity(spriteName: String, userTask: String) {
        // End any existing activity first
        if currentActivity != nil {
            endActivity()
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities not enabled")
            return
        }

        let attributes = WispActivityAttributes(
            spriteName: spriteName,
            userTask: userTask
        )

        let now = Date()
        activityStartDate = now
        lastStepNumber = 0

        let initialState = WispActivityAttributes.ContentState(
            subject: nil,
            currentIntent: "Thinking...",
            currentIntentIcon: nil,
            previousIntent: nil,
            secondPreviousIntent: nil,
            intentStartDate: now,
            stepNumber: 0
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            logger.info("Started Live Activity for sprite: \(spriteName)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func update(
        subject: String?,
        currentIntent: String,
        currentIntentIcon: String?,
        previousIntent: String?,
        secondPreviousIntent: String?,
        stepNumber: Int
    ) {
        let state = WispActivityAttributes.ContentState(
            subject: subject,
            currentIntent: currentIntent,
            currentIntentIcon: currentIntentIcon,
            previousIntent: previousIntent,
            secondPreviousIntent: secondPreviousIntent,
            intentStartDate: Date(),
            stepNumber: stepNumber
        )

        pendingContent = state
        lastStepNumber = stepNumber

        // Debounce: batch rapid updates into 1-second intervals
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingUpdate()
            }
        }
    }

    func endActivity(completionSummary: String? = nil) {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard let activity = currentActivity else { return }

        let finalState = WispActivityAttributes.ContentState(
            subject: pendingContent?.subject,
            currentIntent: completionSummary ?? "Task complete",
            currentIntentIcon: "checkmark.circle.fill",
            previousIntent: pendingContent?.previousIntent,
            secondPreviousIntent: pendingContent?.secondPreviousIntent,
            intentStartDate: pendingContent?.intentStartDate ?? Date(),
            intentEndDate: Date(),
            stepNumber: lastStepNumber
        )

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 8)
            )
            logger.info("Ended Live Activity")
        }

        currentActivity = nil
        pendingContent = nil
    }

    func resetState() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingContent = nil
        lastStepNumber = 0
        activityStartDate = nil
    }

    // MARK: - Private

    private func flushPendingUpdate() {
        guard let activity = currentActivity, let state = pendingContent else { return }

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}
