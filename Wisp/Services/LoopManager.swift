import BackgroundTasks
import Foundation
import SwiftData
import os

@Observable
@MainActor
final class LoopManager {
    private let logger = Logger(subsystem: "com.wisp.app", category: "LoopManager")

    private var timers: [UUID: Timer] = [:]
    private var runningIterations: Set<UUID> = []
    private var iterationTasks: [UUID: Task<Void, Never>] = [:]

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

        scheduleLoop(loop, modelContext: modelContext, triggerImmediately: true)
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
        let shouldRunNow = !runningIterations.contains(loop.id) && nextRunDate(for: loop) <= Date()
        if runningIterations.contains(loop.id) {
            scheduleRepeatingTimer(loopId: loop.id, interval: loop.interval.seconds, modelContext: modelContext)
        } else {
            scheduleLoop(loop, modelContext: modelContext, triggerImmediately: shouldRunNow)
        }
        logger.info("Resumed loop \(loop.id)")
    }

    func stop(loopId: UUID, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        timers.removeValue(forKey: loopId)
        iterationTasks[loopId]?.cancel()
        iterationTasks.removeValue(forKey: loopId)
        runningIterations.remove(loopId)

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
        for (_, task) in iterationTasks {
            task.cancel()
        }
        timers.removeAll()
        iterationTasks.removeAll()
        runningIterations.removeAll()
        logger.info("Stopped all loops")
    }

    func restoreLoops(modelContext: ModelContext) {
        let loops = activeLoops(modelContext: modelContext)

        for loop in loops {
            guard timers[loop.id] == nil else { continue }
            scheduleLoop(loop, modelContext: modelContext, triggerImmediately: nextRunDate(for: loop) <= Date())
        }

        logger.info("Restored \(loops.count) active loops")
    }

    // MARK: - Background Task Support

    static let bgTaskIdentifier = "com.wisp.app.loop-refresh"

    func scheduleBackgroundRefresh(modelContext: ModelContext) {
        let loops = activeLoops(modelContext: modelContext)
        guard !loops.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
            logger.info("No active loops to schedule for background refresh")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        let earliestNextRun = loops.map(nextRunDate(for:)).min() ?? Date().addingTimeInterval(600)
        let shortestInterval = max(1, earliestNextRun.timeIntervalSinceNow)

        request.earliestBeginDate = Date(timeIntervalSinceNow: shortestInterval)

        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background refresh in \(shortestInterval)s")
        } catch {
            logger.error("Failed to schedule background refresh: \(error)")
        }
    }

    func handleBackgroundRefresh(modelContext: ModelContext) async -> Bool {
        defer {
            scheduleBackgroundRefresh(modelContext: modelContext)
        }

        let dueLoops = activeLoops(modelContext: modelContext)
            .filter { nextRunDate(for: $0) <= Date() }
            .sorted { nextRunDate(for: $0) < nextRunDate(for: $1) }

        for loop in dueLoops {
            guard !Task.isCancelled else { return false }
            guard !runningIterations.contains(loop.id) else { continue }
            await runIteration(loopId: loop.id, modelContext: modelContext)
            guard !Task.isCancelled else { return false }
        }

        return !Task.isCancelled
    }

    // MARK: - Private Methods

    private func tick(loopId: UUID, modelContext: ModelContext) {
        guard !runningIterations.contains(loopId) else {
            logger.debug("Skipping tick for loop \(loopId) — iteration already running")
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runIteration(loopId: loopId, modelContext: modelContext)
            await MainActor.run {
                self.iterationTasks.removeValue(forKey: loopId)
            }
        }
        iterationTasks[loopId] = task
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

        guard !Task.isCancelled else {
            logger.info("Loop \(loopId) iteration cancelled")
            return
        }

        guard let loop = try? modelContext.fetch(descriptor).first else {
            logger.info("Loop \(loopId) no longer exists after iteration")
            return
        }

        guard loop.state != .stopped else {
            logger.info("Loop \(loopId) was stopped before iteration completed")
            return
        }

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

    private func activeLoops(modelContext: ModelContext) -> [SpriteLoop] {
        let activeState = LoopState.active.rawValue
        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.stateRaw == activeState },
            sortBy: [SortDescriptor(\SpriteLoop.createdAt)]
        )
        return (try? modelContext.fetch(descriptor).filter { !$0.isExpired }) ?? []
    }

    private func nextRunDate(for loop: SpriteLoop) -> Date {
        let referenceDate = loop.lastRunAt ?? loop.createdAt
        return referenceDate.addingTimeInterval(loop.interval.seconds)
    }

    private func scheduleLoop(_ loop: SpriteLoop, modelContext: ModelContext, triggerImmediately: Bool) {
        timers[loop.id]?.invalidate()

        let loopId = loop.id
        let interval = loop.interval.seconds

        if triggerImmediately {
            scheduleRepeatingTimer(loopId: loopId, interval: interval, modelContext: modelContext)
            tick(loopId: loopId, modelContext: modelContext)
            logger.info("Registered loop \(loopId) with immediate execution and interval \(interval)s")
            return
        }

        let initialDelay = nextRunDate(for: loop).timeIntervalSinceNow
        if initialDelay <= 0 {
            scheduleRepeatingTimer(loopId: loopId, interval: interval, modelContext: modelContext)
            tick(loopId: loopId, modelContext: modelContext)
            logger.info("Registered overdue loop \(loopId) with catch-up execution")
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleRepeatingTimer(loopId: loopId, interval: interval, modelContext: modelContext)
                self.tick(loopId: loopId, modelContext: modelContext)
            }
        }
        timers[loopId] = timer
        logger.info("Registered loop \(loopId) to resume in \(initialDelay)s")
    }

    private func scheduleRepeatingTimer(loopId: UUID, interval: TimeInterval, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(loopId: loopId, modelContext: modelContext)
            }
        }
        timers[loopId] = timer
    }

    private func executeLoopPrompt(spriteName: String, workingDirectory: String, prompt: String) async -> Result<String, Error> {
        guard let apiClient else {
            return .failure(NSError(domain: "LoopManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API client configured"]))
        }

        // 1. Wake sprite if needed
        do {
            try Task.checkCancellation()
            let sprite = try await apiClient.getSprite(name: spriteName)
            if sprite.status != .running {
                _ = await apiClient.runExec(spriteName: spriteName, command: "true", timeout: 60)
                for _ in 0..<30 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(2))
                    let updated = try await apiClient.getSprite(name: spriteName)
                    if updated.status == .running { break }
                }
            }
        } catch {
            return .failure(error)
        }

        // 2. Build command
        guard let claudeToken = apiClient.claudeToken else {
            return .failure(NSError(domain: "LoopManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No Claude token configured"]))
        }

        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let commandParts = [
            "export CLAUDE_CODE_OAUTH_TOKEN='\(claudeToken)'",
            "mkdir -p \(workingDirectory)",
            "cd \(workingDirectory)",
            "claude -p --verbose --output-format stream-json --dangerously-skip-permissions '\(escapedPrompt)'"
        ]
        let fullCommand = commandParts.joined(separator: " && ")

        let serviceName = "wisp-loop-\(UUID().uuidString.prefix(8).lowercased())"
        let config = ServiceRequest(cmd: "bash", args: ["-c", fullCommand], needs: nil, httpPort: nil)

        return await withTaskCancellationHandler {
            // 3. Stream and parse
            let stream = apiClient.streamService(spriteName: spriteName, serviceName: serviceName, config: config)
            let parser = ClaudeStreamParser()
            var responseText = ""

            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    guard event.type == .stdout, let base64Data = event.data else { continue }
                    guard let rawData = Data(base64Encoded: base64Data) else { continue }
                    let claudeEvents = await parser.parse(data: rawData)
                    for claudeEvent in claudeEvents {
                        if case .assistant(let assistantEvent) = claudeEvent {
                            for block in assistantEvent.message.content {
                                if case .text(let text) = block {
                                    responseText += text
                                }
                            }
                        }
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)
                    return .failure(CancellationError())
                }
                if responseText.isEmpty {
                    try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)
                    return .failure(error)
                }
            }

            let remaining = await parser.flush()
            for claudeEvent in remaining {
                if case .assistant(let assistantEvent) = claudeEvent {
                    for block in assistantEvent.message.content {
                        if case .text(let text) = block {
                            responseText += text
                        }
                    }
                }
            }

            try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)

            if Task.isCancelled {
                return .failure(CancellationError())
            }

            return .success(responseText.isEmpty ? "(No response)" : responseText)
        } onCancel: {
            Task {
                try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)
            }
        }
    }
}
