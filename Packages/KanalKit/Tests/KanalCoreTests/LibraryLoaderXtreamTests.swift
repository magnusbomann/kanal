import Foundation
import Testing
@testable import KanalCore

@Suite("Xtream staged import")
struct LibraryLoaderXtreamTests {
    @Test("An authenticated VOD-only panel does not fail its empty live stage")
    func emptyLiveStageFallsBackToDeferredCatalogue() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [XtreamStageURLProtocol.self]
        let loader = LibraryLoader(session: URLSession(configuration: configuration))
        let source = PlaylistSource(
            kind: .xtream,
            name: "VOD only",
            portalURL: URL(string: "https://panel.test")!,
            username: "viewer",
            password: "secret"
        )

        let result = try await loader.loadPlayableChannels(for: source)

        #expect(result == nil)
    }
}

private final class XtreamStageURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let action = components?.queryItems?.first(where: { $0.name == "action" })?.value
        let body: String
        switch action {
        case nil:
            body = #"{"user_info":{"auth":1,"status":"Active"},"server_info":{}}"#
        case "get_live_categories":
            body = "[]"
        case "get_live_streams":
            body = "[]"
        default:
            body = "[]"
        }
        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
