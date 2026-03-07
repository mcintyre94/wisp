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
        guard let apiClient else {
            return .failure(NSError(domain: "LoopManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API client configured"]))
        }

        // 1. Wake sprite if needed
        do {
            let sprite = try await apiClient.getSprite(name: spriteName)
            if sprite.status != .running {
                _ = await apiClient.runExec(spriteName: spriteName, command: "true", timeout: 60)
                for _ in 0..<30 {
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

        // 3. Stream and parse
        let stream = apiClient.streamService(spriteName: spriteName, serviceName: serviceName, config: config)
        let parser = ClaudeStreamParser()
        var responseText = ""

        do {
            for try await event in stream {
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
            if responseText.isEmpty {
                return .failure(error)
            }
        }

        // Flush remaining
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

        // 4. Cleanup
        try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)

        return .success(responseText.isEmpty ? "(No response)" : responseText)
    }
}
