import Testing
import Foundation
@testable import Wisp

@Suite("ClaudeStreamParser")
struct ClaudeStreamParserTests {

    private func makeData(_ string: String) -> Data {
        Data(string.utf8)
    }

    @Test func singleCompleteLine() async {
        let parser = ClaudeStreamParser()
        let json = #"{"type":"system","session_id":"abc123","model":"claude-sonnet-4-20250514"}"# + "\n"
        let events = await parser.parse(data: makeData(json))
        #expect(events.count == 1)
        if case .system(let e) = events.first {
            #expect(e.sessionId == "abc123")
            #expect(e.model == "claude-sonnet-4-20250514")
        } else {
            Issue.record("Expected system event")
        }
    }

    @Test func multipleLinesinOneChunk() async {
        let parser = ClaudeStreamParser()
        let chunk = """
        {"type":"system","session_id":"s1","model":"m"}
        {"type":"result","session_id":"s1","subtype":"success"}

        """
        let events = await parser.parse(data: makeData(chunk))
        #expect(events.count == 2)
        if case .system = events[0] {} else { Issue.record("Expected system event at index 0") }
        if case .result = events[1] {} else { Issue.record("Expected result event at index 1") }
    }

    @Test func lineSplitAcrossTwoCalls() async {
        let parser = ClaudeStreamParser()
        let full = #"{"type":"system","session_id":"split","model":"m"}"# + "\n"
        let splitPoint = full.index(full.startIndex, offsetBy: 20)
        let part1 = String(full[full.startIndex..<splitPoint])
        let part2 = String(full[splitPoint...])

        let events1 = await parser.parse(data: makeData(part1))
        #expect(events1.isEmpty)

        let events2 = await parser.parse(data: makeData(part2))
        #expect(events2.count == 1)
        if case .system(let e) = events2.first {
            #expect(e.sessionId == "split")
        } else {
            Issue.record("Expected system event")
        }
    }

    @Test func emptyLinesSkipped() async {
        let parser = ClaudeStreamParser()
        let chunk = "\n\n" + #"{"type":"system","session_id":"s1","model":"m"}"# + "\n\n"
        let events = await parser.parse(data: makeData(chunk))
        #expect(events.count == 1)
    }

    @Test func invalidJSONLinesSkipped() async {
        let parser = ClaudeStreamParser()
        let chunk = "not valid json\n" + #"{"type":"system","session_id":"ok","model":"m"}"# + "\n"
        let events = await parser.parse(data: makeData(chunk))
        #expect(events.count == 1)
        if case .system(let e) = events.first {
            #expect(e.sessionId == "ok")
        } else {
            Issue.record("Expected system event")
        }
    }

    @Test func flushParsesRemainingBuffer() async {
        let parser = ClaudeStreamParser()
        // Send data without trailing newline
        let json = #"{"type":"system","session_id":"flush","model":"m"}"#
        let events = await parser.parse(data: makeData(json))
        #expect(events.isEmpty)

        let flushed = await parser.flush()
        #expect(flushed.count == 1)
        if case .system(let e) = flushed.first {
            #expect(e.sessionId == "flush")
        } else {
            Issue.record("Expected system event")
        }
    }

    @Test func flushOnEmptyBuffer() async {
        let parser = ClaudeStreamParser()
        let events = await parser.flush()
        #expect(events.isEmpty)
    }

    @Test func twoLevelNDJSONFromServiceLogData() async {
        // Simulates feeding ServiceLogEvent.data strings to the parser
        // (the two-level NDJSON pattern used with services)
        let parser = ClaudeStreamParser()

        // Simulate a stdout event's data field containing a Claude NDJSON line
        let line1 = #"{"type":"system","session_id":"svc1","model":"claude-sonnet-4-20250514"}"# + "\n"
        let events1 = await parser.parse(data: makeData(line1))
        #expect(events1.count == 1)
        if case .system(let e) = events1.first {
            #expect(e.sessionId == "svc1")
        } else {
            Issue.record("Expected system event")
        }

        // Simulate a stdout event's data WITHOUT trailing newline — parser buffers
        let line2 = #"{"type":"result","session_id":"svc1","subtype":"success"}"#
        let events2 = await parser.parse(data: makeData(line2))
        #expect(events2.isEmpty)

        // Appending newline in next chunk flushes the buffered line
        let events3 = await parser.parse(data: makeData("\n"))
        #expect(events3.count == 1)
        if case .result = events3.first {} else { Issue.record("Expected result event") }
    }

    @Test func resetClearsBuffer() async {
        let parser = ClaudeStreamParser()
        // Send partial data
        let partial = #"{"type":"system","ses"#
        _ = await parser.parse(data: makeData(partial))
        await parser.reset()

        // Flush should return nothing since buffer was cleared
        let events = await parser.flush()
        #expect(events.isEmpty)
    }
}
