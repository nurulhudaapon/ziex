import XCTest
import SwiftTreeSitter
import TreeSitterZx

final class TreeSitterZxTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_zx())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading ZX grammar")
    }
}
