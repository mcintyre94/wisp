import Testing
import Foundation
@testable import Wisp

@Suite("Service Types")
struct ServiceTypesTests {

    // MARK: - ServiceLogEvent Decoding

    @Test func decodeStdoutEvent() throws {
        let json = #"{"type":"stdout","data":"hello world\n","timestamp":1700000000000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .stdout)
        #expect(event.data == "hello world\n")
        #expect(event.timestamp == 1700000000000)
        #expect(event.exitCode == nil)
        #expect(event.logFiles == nil)
    }

    @Test func decodeStderrEvent() throws {
        let json = #"{"type":"stderr","data":"warning: something\n","timestamp":1700000001000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .stderr)
        #expect(event.data == "warning: something\n")
    }

    @Test func decodeExitEvent() throws {
        let json = #"{"type":"exit","exit_code":0,"timestamp":1700000002000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .exit)
        #expect(event.exitCode == 0)
        #expect(event.data == nil)
    }

    @Test func decodeExitEventNonZero() throws {
        let json = #"{"type":"exit","exit_code":1,"timestamp":1700000002000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .exit)
        #expect(event.exitCode == 1)
    }

    @Test func decodeErrorEvent() throws {
        let json = #"{"type":"error","data":"something went wrong","timestamp":1700000003000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .error)
        #expect(event.data == "something went wrong")
    }

    @Test func decodeCompleteEventWithLogFiles() throws {
        let json = """
        {"type":"complete","timestamp":1700000004000,"log_files":{"combined":"/.sprite/logs/services/claude.log","stdout":"/.sprite/logs/services/claude.stdout.log","stderr":"/.sprite/logs/services/claude.stderr.log"}}
        """
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .complete)
        #expect(event.logFiles?["combined"] == "/.sprite/logs/services/claude.log")
        #expect(event.logFiles?["stdout"] == "/.sprite/logs/services/claude.stdout.log")
    }

    @Test func decodeStartedEvent() throws {
        let json = #"{"type":"started","timestamp":1700000005000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .started)
    }

    @Test func decodeStoppingEvent() throws {
        let json = #"{"type":"stopping","timestamp":1700000006000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .stopping)
    }

    @Test func decodeStoppedEvent() throws {
        let json = #"{"type":"stopped","timestamp":1700000007000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .stopped)
    }

    @Test func decodeUnknownEventType() throws {
        let json = #"{"type":"future_event","timestamp":1700000008000}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .unknown)
    }

    @Test func decodeEventOptionalTimestamp() throws {
        let json = #"{"type":"stdout","data":"test"}"#
        let event = try JSONDecoder().decode(ServiceLogEvent.self, from: Data(json.utf8))
        #expect(event.type == .stdout)
        #expect(event.data == "test")
        #expect(event.timestamp == nil)
    }

    // MARK: - ServiceRequest Encoding

    @Test func encodeServiceRequestFull() throws {
        let req = ServiceRequest(cmd: "bash", args: ["-c", "echo hello"], needs: nil, httpPort: nil)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["cmd"] as? String == "bash")
        #expect(json["args"] as? [String] == ["-c", "echo hello"])
    }

    @Test func encodeServiceRequestMinimal() throws {
        let req = ServiceRequest(cmd: "node", args: nil, needs: nil, httpPort: nil)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["cmd"] as? String == "node")
    }

    @Test func encodeServiceRequestWithHttpPort() throws {
        let req = ServiceRequest(cmd: "npm", args: ["run", "dev"], needs: ["database"], httpPort: 3000)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["cmd"] as? String == "npm")
        #expect(json["args"] as? [String] == ["run", "dev"])
        #expect(json["needs"] as? [String] == ["database"])
        #expect(json["http_port"] as? Int == 3000)
    }

    // MARK: - ServiceSignalRequest Encoding

    @Test func encodeServiceSignalRequest() throws {
        let req = ServiceSignalRequest(name: "claude", signal: "TERM")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["name"] as? String == "claude")
        #expect(json["signal"] as? String == "TERM")
    }
}
