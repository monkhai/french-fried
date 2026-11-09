import XCTest
@testable import AppleSignIn

final class AppleSignInTests: XCTestCase {
    func testSHA256UsesUTF8AndLowercaseHex() {
        XCTAssertEqual(AppleNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNonceHas256BitsAndFreshValues() throws {
        let a = try AppleNonce.make()
        let b = try AppleNonce.make()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertNotEqual(a, b)
    }

    @MainActor
    func testResponseWithoutRequestIsRejected() {
        let flow = AppleSignInFlow()
        XCTAssertThrowsError(try flow.complete(.failure(NSError(domain: "test", code: 1)))) {
            XCTAssertEqual($0 as? AppleSignInError, .missingRequest)
        }
    }
}
