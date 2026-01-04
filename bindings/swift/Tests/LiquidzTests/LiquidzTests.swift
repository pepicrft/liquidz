import XCTest
@testable import Liquidz

final class LiquidzTests: XCTestCase {
    func testRenderWithDictionary() throws {
        let result = try Liquidz.render(template: "Hello, {{ name }}!", context: ["name": "World"])
        XCTAssertEqual(result, "Hello, World!")
    }

    func testRenderWithEncodable() throws {
        struct User: Codable {
            let name: String
            let age: Int
        }

        let user = User(name: "Ada", age: 36)
        let result = try Liquidz.render(template: "{{ name }} is {{ age }}.", context: user)
        XCTAssertEqual(result, "Ada is 36.")
    }

    func testRenderWithJsonContext() throws {
        let result = try Liquidz.render(template: "{{ project }}", jsonContext: "{\"project\":\"liquidz\"}")
        XCTAssertEqual(result, "liquidz")
    }
}
