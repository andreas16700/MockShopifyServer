@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    func testHelloWorld() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

//        try app.test(.GET, "hello", afterResponse: { res in
//            XCTAssertEqual(res.status, .ok)
//            XCTAssertEqual(res.body.string, "Hello, world!")
//        })
		let s = await store.getPage(of: \.productsByID)
    }
}
