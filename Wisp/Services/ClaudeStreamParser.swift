import Foundation

actor ClaudeStreamParser {
    private var buffer = Data()
    private let decoder = JSONDecoder.apiDecoder()

    func parse(data: Data) -> [ClaudeStreamEvent] {
        buffer.append(data)

        var events: [ClaudeStreamEvent] = []
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            do {
                let event = try decoder.decode(ClaudeStreamEvent.self, from: Data(lineData))
                events.append(event)
            } catch {
                // Skip lines that can't be decoded (forward compatibility)
            }
        }

        return events
    }

    func reset() {
        buffer = Data()
    }

    func flush() -> [ClaudeStreamEvent] {
        guard !buffer.isEmpty else { return [] }

        let remaining = buffer
        buffer = Data()

        do {
            let event = try decoder.decode(ClaudeStreamEvent.self, from: remaining)
            return [event]
        } catch {
            return []
        }
    }
}
