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

    /// Last error from starting a Live Activity, surfaced for diagnostics.
    private(set) var lastError: String?

    /// Whether Live Activities are enabled on this device for this app.
    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {}

    /// Starts a Live Activity. Returns `true` if the activity was created successfully.
    @discardableResult
    func startActivity(spriteName: String, userTask: String) -> Bool {
        // End any existing activity first
        if currentActivity != nil {
            endActivity()
        }

        lastError = nil

        guard activitiesEnabled else {
            let msg = "Live Activities not enabled — check Settings > Wisp > Live Activities"
            logger.warning("\(msg)")
            lastError = msg
            return false
        }

        // ActivityKit has a 4KB limit on attributes + state payload.
        // Truncate the user task to avoid exceeding it.
        let truncatedTask = userTask.count > 200
            ? String(userTask.prefix(200)) + "..."
            : userTask

        let attributes = WispActivityAttributes(
            spriteName: spriteName,
            userTask: truncatedTask
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
            logger.info("Started Live Activity: id=\(self.currentActivity?.id ?? "nil") sprite=\(spriteName)")
            return true
        } catch {
            let msg = "Failed to start Live Activity: \(error)"
            logger.error("\(msg)")
            lastError = msg
            return false
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
        guard currentActivity != nil else { return }

        let state = WispActivityAttributes.ContentState(
            subject: subject.map { String($0.prefix(100)) },
            currentIntent: String(currentIntent.prefix(100)),
            currentIntentIcon: currentIntentIcon,
            previousIntent: previousIntent.map { String($0.prefix(100)) },
            secondPreviousIntent: secondPreviousIntent.map { String($0.prefix(100)) },
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
            logger.info("Ended Live Activity: id=\(activity.id)")
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
            logger.debug("Updated Live Activity: id=\(activity.id) step=\(state.stepNumber)")
        }
    }
}
