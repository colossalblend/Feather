// AppBank: check once per launch, without blocking the interface.
import Foundation

actor GitHubAvailability {
	static let shared = GitHubAvailability()
	private var probe: Task<Bool, Never>?

	func check() async -> Bool {
		if let probe { return await probe.value }
		let task = Task<Bool, Never> {
			let configuration = URLSessionConfiguration.ephemeral
			configuration.timeoutIntervalForRequest = 3
			configuration.timeoutIntervalForResource = 3
			configuration.urlCache = nil
			let session = URLSession(configuration: configuration)
			defer { session.invalidateAndCancel() }
			var request = URLRequest(url: URL(string: "https://github.com/")!,
				cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
			request.httpMethod = "HEAD"
			do {
				let (_, response) = try await session.data(for: request)
				guard let http = response as? HTTPURLResponse,
					http.url?.host?.lowercased() == "github.com" else { return false }
				return (200..<400).contains(http.statusCode)
			} catch {
				return false
			}
		}
		probe = task
		return await task.value
	}
}
