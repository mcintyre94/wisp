import Testing
import Foundation
@testable import Wisp

@Suite("JSONValue")
struct JSONValueTests {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private func decode(_ json: String) throws -> JSONValue {
        try decoder.decode(JSONValue.self, from: Data(json.utf8))
    }

    private func roundTrip(_ value: JSONValue) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try decoder.decode(JSONValue.self, from: data)
    }

    // MARK: - Round-trip

    @Test func roundTripString() throws {
        let value = JSONValue.string("hello")
        #expect(try roundTrip(value) == value)
    }

    @Test func roundTripNumber() throws {
        let value = JSONValue.number(42.5)
        #expect(try roundTrip(value) == value)
    }

    @Test func roundTripBool() throws {
        let value = JSONValue.bool(true)
        #expect(try roundTrip(value) == value)
    }

    @Test func roundTripNull() throws {
        let value = JSONValue.null
        #expect(try roundTrip(value) == value)
    }

    @Test func roundTripArray() throws {
        let value = JSONValue.array([.string("a"), .number(1), .bool(false)])
        #expect(try roundTrip(value) == value)
    }

    @Test func roundTripObject() throws {
        let value = JSONValue.object(["key": .string("val"), "num": .number(3)])
        #expect(try roundTrip(value) == value)
    }

    // MARK: - Nested structures

    @Test func nestedArrayOfObjects() throws {
        let json = #"[{"name":"a"},{"name":"b"}]"#
        let value = try decode(json)
        #expect(value[0]?["name"] == .string("a"))
        #expect(value[1]?["name"] == .string("b"))
    }

    @Test func nestedObjectWithArrays() throws {
        let json = #"{"items":[1,2,3]}"#
        let value = try decode(json)
        #expect(value["items"]?[1] == .number(2))
    }

    // MARK: - Subscripts

    @Test func subscriptKeyOnObject() throws {
        let value = JSONValue.object(["foo": .string("bar")])
        #expect(value["foo"] == .string("bar"))
        #expect(value["missing"] == nil)
    }

    @Test func subscriptKeyOnNonObject() {
        let value = JSONValue.string("not an object")
        #expect(value["key"] == nil)
    }

    @Test func subscriptIndexOnArray() {
        let value = JSONValue.array([.number(10), .number(20)])
        #expect(value[0] == .number(10))
        #expect(value[1] == .number(20))
    }

    @Test func subscriptIndexOutOfBounds() {
        let value = JSONValue.array([.number(1)])
        #expect(value[5] == nil)
    }

    @Test func subscriptIndexOnNonArray() {
        let value = JSONValue.number(42)
        #expect(value[0] == nil)
    }

    // MARK: - Typed getters

    @Test func stringValueCorrectType() {
        #expect(JSONValue.string("hello").stringValue == "hello")
    }

    @Test func stringValueWrongType() {
        #expect(JSONValue.number(1).stringValue == nil)
    }

    @Test func numberValueCorrectType() {
        #expect(JSONValue.number(3.14).numberValue == 3.14)
    }

    @Test func numberValueWrongType() {
        #expect(JSONValue.string("3.14").numberValue == nil)
    }

    @Test func intValueCorrectType() {
        #expect(JSONValue.number(42).intValue == 42)
    }

    @Test func intValueWrongType() {
        #expect(JSONValue.bool(true).intValue == nil)
    }

    @Test func boolValueCorrectType() {
        #expect(JSONValue.bool(false).boolValue == false)
    }

    @Test func boolValueWrongType() {
        #expect(JSONValue.number(1).boolValue == nil)
    }

    @Test func arrayValueCorrectType() {
        let arr: [JSONValue] = [.number(1)]
        #expect(JSONValue.array(arr).arrayValue == arr)
    }

    @Test func arrayValueWrongType() {
        #expect(JSONValue.null.arrayValue == nil)
    }

    @Test func objectValueCorrectType() {
        let dict: [String: JSONValue] = ["k": .string("v")]
        #expect(JSONValue.object(dict).objectValue == dict)
    }

    @Test func objectValueWrongType() {
        #expect(JSONValue.array([]).objectValue == nil)
    }

    // MARK: - isNull

    @Test func isNullTrue() {
        #expect(JSONValue.null.isNull == true)
    }

    @Test func isNullFalse() {
        #expect(JSONValue.string("").isNull == false)
        #expect(JSONValue.number(0).isNull == false)
        #expect(JSONValue.bool(false).isNull == false)
    }

    // MARK: - prettyString

    @Test func prettyStringForString() {
        #expect(JSONValue.string("raw text").prettyString == "raw text")
    }

    @Test func prettyStringForInteger() {
        #expect(JSONValue.number(42).prettyString == "42")
    }

    @Test func prettyStringForBool() {
        #expect(JSONValue.bool(true).prettyString == "true")
        #expect(JSONValue.bool(false).prettyString == "false")
    }

    @Test func prettyStringForNull() {
        #expect(JSONValue.null.prettyString == "null")
    }
}
