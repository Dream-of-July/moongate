import Foundation
import MoongateMobileCore

public struct URLSessionMobileTranslationTransport: MobileTranslationTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: Self.ephemeralConfiguration())) {
        self.session = session
    }

    public static func ephemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    public func send(_ request: MobileTranslationTransportRequest) async throws -> MobileTranslationTransportResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return MobileTranslationTransportResponse(statusCode: statusCode, body: data)
    }
}
