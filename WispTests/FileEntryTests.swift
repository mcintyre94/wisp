import Testing

@testable import Wisp

@Suite("FileEntry")
struct FileEntryTests {
    @Test("Parses directory line")
    func parseDirectoryLine() {
        let entry = FileEntry.parse(line: "d 4096 /home/sprite/project/src")
        #expect(entry != nil)
        #expect(entry?.name == "src")
        #expect(entry?.path == "/home/sprite/project/src")
        #expect(entry?.isDirectory == true)
        #expect(entry?.size == nil)
    }

    @Test("Parses file line")
    func parseFileLine() {
        let entry = FileEntry.parse(line: "f 1234 /home/sprite/project/main.py")
        #expect(entry != nil)
        #expect(entry?.name == "main.py")
        #expect(entry?.path == "/home/sprite/project/main.py")
        #expect(entry?.isDirectory == false)
        #expect(entry?.size == 1234)
    }

    @Test("Returns nil for invalid line")
    func parseInvalidLine() {
        #expect(FileEntry.parse(line: "") == nil)
        #expect(FileEntry.parse(line: "x 100 /some/path") == nil)
        #expect(FileEntry.parse(line: "incomplete") == nil)
    }

    @Test("Parses multiline output")
    func parseOutput() {
        let output = """
        d 4096 /home/sprite/project
        d 4096 /home/sprite/project/src
        f 1234 /home/sprite/project/main.py
        f 567 /home/sprite/project/README.md
        """
        let entries = FileEntry.parseOutput(output)
        #expect(entries.count == 4)
        #expect(entries[0].isDirectory == true)
        #expect(entries[1].isDirectory == true)
        #expect(entries[2].isDirectory == false)
        #expect(entries[2].name == "main.py")
        #expect(entries[3].name == "README.md")
    }

    @Test("Handles file with spaces in path")
    func parseFileWithSpaces() {
        let entry = FileEntry.parse(line: "f 999 /home/sprite/my project/file name.txt")
        #expect(entry != nil)
        #expect(entry?.name == "file name.txt")
        #expect(entry?.path == "/home/sprite/my project/file name.txt")
    }

    @Test("Skips empty lines in output")
    func parseOutputSkipsEmptyLines() {
        let output = """
        f 100 /home/sprite/a.txt

        f 200 /home/sprite/b.txt
        """
        let entries = FileEntry.parseOutput(output)
        #expect(entries.count == 2)
    }
}
