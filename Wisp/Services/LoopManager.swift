import Foundation
import SwiftData
import os

@Observable
@MainActor
final class LoopManager {
    private let logger = Logger(subsystem: "com.wisp.app", category: "LoopManager")

    private var timers: [UUID: Timer] = [:]
    private var runningIterations: Set<UUID> = []

    var apiClient: SpritesAPIClient?

    var activeLoopIds: Set<UUID> {
        Set(timers.keys)
    }

    // MARK: - Public Methods

    func register(loop: SpriteLoop, modelContext: ModelContext) {
        if loop.isExpired {
            loop.state = .stopped
            try? modelContext.save()
            logger.info("Loop \(loop.id) is expired, setting to stopped")
            return
        }

        // Invalidate existing timer if any
        timers[loop.id]?.invalidate()

        let loopId = loop.id
        let interval = loop.interval.seconds

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(loopId: loopId, modelContext: modelContext)
            }
        }
        timers[loopId] = timer

        // Run first iteration immediately
        Task {
            await runIteration(loopId: loopId, modelContext: modelContext)
        }

        logger.info("Registered loop \(loopId) with interval \(interval)s")
    }

    func pause(loopId: UUID, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        timers.removeValue(forKey: loopId)

        let targetId = loopId
        let descriptor = FetchDescriptor<SpriteLoop>(predicate: #Predicate { $0.id == targetId })
        if let loop = try? modelContext.fetch(descriptor).first {
            loop.state = .paused
            try? modelContext.save()
        }

        logger.info("Paused loop \(loopId)")
    }

    func resume(loop: SpriteLoop, modelContext: ModelContext) {
        loop.state = .active
        try? modelContext.save()
        register(loop: loop, modelContext: modelContext)
        logger.info("Resumed loop \(loop.id)")
    }

    func stop(loopId: UUID, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        timers.removeValue(forKey: loopId)

        let targetId = loopId
        let descriptor = FetchDescriptor<SpriteLoop>(predicate: #Predicate { $0.id == targetId })
        if let loop = try? modelContext.fetch(descriptor).first {
            loop.state = .stopped
            try? modelContext.save()
        }

        logger.info("Stopped loop \(loopId)")
    }

    func stopAll() {
        for (_, timer) in timers {
            timer.invalidate()
        }
        timers.removeAll()
        logger.info("Stopped all loops")
    }

    func restoreLoops(modelContext: ModelContext) {
        let activeState = LoopState.active.rawValue
        let descriptor = FetchDescriptor<SpriteLoop>(predicate: #Predicate { $0.stateRaw == activeState })
        guard let loops = try? modelContext.fetch(descriptor) else { return }

        for loop in loops {
            register(loop: loop, modelContext: modelContext)
        }

        logger.info("Restored \(loops.count) active loops")
    }

    // MARK: - Private Methods

    private func tick(loopId: UUID, modelContext: ModelContext) {
        guard !runningIterations.contains(loopId) else {
            logger.debug("Skipping tick for loop \(loopId) — iteration already running")
            return
        }

        Task {
            await runIteration(loopId: loopId, modelContext: modelContext)
        }
    }

    private func runIteration(loopId: UUID, modelContext: ModelContext) async {
        let targetId = loopId
        let descriptor = FetchDescriptor<SpriteLoop>(predicate: #Predicate { $0.id == targetId })
        guard let loop = try? modelContext.fetch(descriptor).first else {
            logger.error("Loop \(loopId) not found in model context")
            return
        }

        if loop.isExpired {
            stop(loopId: loopId, modelContext: modelContext)
            await NotificationService.postNotification(
                title: "Loop ended",
                body: "Loop for \(loop.spriteName) has expired",
                loopId: loopId.uuidString,
                iterationId: UUID().uuidString
            )
            return
        }

        runningIterations.insert(loopId)
        defer { runningIterations.remove(loopId) }

        var iteration = LoopIteration(prompt: loop.prompt)

        let result = await executeLoopPrompt(
            spriteName: loop.spriteName,
            workingDirectory: loop.workingDirectory,
            prompt: loop.prompt
        )

        iteration.completedAt = Date()

        switch result {
        case .success(let response):
            iteration.status = .completed
            iteration.responseText = response
            iteration.notificationSummary = NotificationService.truncatedSummary(response)
            await NotificationService.postNotification(
                title: "Loop: \(loop.spriteName)",
                body: iteration.notificationSummary ?? "Completed",
                loopId: loopId.uuidString,
                iterationId: iteration.id.uuidString
            )
        case .failure(let error):
            iteration.status = .failed(error.localizedDescription)
            await NotificationService.postNotification(
                title: "Loop failed: \(loop.spriteName)",
                body: error.localizedDescription,
                loopId: loopId.uuidString,
                iterationId: iteration.id.uuidString
            )
        }

        var iterations = loop.iterations
        iterations.append(iteration)
        loop.iterations = iterations
        loop.lastRunAt = Date()
        try? modelContext.save()

        logger.info("Completed iteration for loop \(loopId)")
    }

    private func executeLoopPrompt(spriteName: String, workingDirectory: String, prompt: String) async -> Result<String, Error> {
        // Stub — will be wired up in Task 5
        return .failure(NSError(domain: "LoopManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not yet implemented"]))
    }
}
