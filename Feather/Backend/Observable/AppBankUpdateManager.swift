//
//  AppBankUpdateManager.swift
//  Feather
//
//  Обновление самой сборки Feather через API AppBank.
//
//  Штатный UpdateManager смотрит каталоги приложений, но обновить себя оттуда
//  нельзя: InstallPreviewView прямо запрещает ставить приложение поверх себя
//  через локальный сервер. Поэтому сборка спрашивает про обновление у своего
//  API и ставится через itms-services — тем же путём, каким пришла.
//
//  Адрес API вшит в Info.plist при подписи (AppBankUpdateURL) и у каждого
//  покупателя свой: сборка подписана его сертификатом.
//

import Foundation
import NimbleJSON
import SwiftUI

struct AppBankUpdate: Equatable {
	let build: String
	let version: String
	let notes: String
	let size: Int64
	let install: URL

	var sizeText: String {
		ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
	}
}

@MainActor
final class AppBankUpdateManager: ObservableObject {
	static let shared = AppBankUpdateManager()

	@Published private(set) var available: AppBankUpdate?
	@Published private(set) var isChecking = false
	/// Показываем окно один раз за запуск: навязчивость раздражает сильнее,
	/// чем устаревшая сборка.
	@Published var isPresented = false

	private var _shownBuild: String?

	private init() {}

	private var _endpoint: URL? {
		guard
			let raw = Bundle.main.object(forInfoDictionaryKey: "AppBankUpdateURL") as? String,
			!raw.isEmpty
		else {
			return nil
		}

		return URL(string: raw)
	}

	private var _currentBuild: String {
		(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
	}

	func check(presenting: Bool = true) async {
		guard !isChecking, let endpoint = _endpoint else { return }

		isChecking = true
		defer { isChecking = false }

		var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
		var items = components?.queryItems ?? []
		items.append(URLQueryItem(name: "b", value: _currentBuild))
		components?.queryItems = items

		guard
			let url = components?.url,
			let (data, response) = try? await URLSession.shared.data(for: _request(url)),
			let http = response as? HTTPURLResponse,
			http.statusCode == 200,
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			json["ok"] as? Bool == true,
			let build = json["build"] as? String,
			!build.isEmpty,
			build != _currentBuild,
			let install = (json["install"] as? String).flatMap(URL.init(string:))
		else {
			return
		}

		let update = AppBankUpdate(
			build: build,
			version: (json["version"] as? String) ?? "",
			notes: (json["notes"] as? String) ?? "",
			size: (json["size"] as? NSNumber)?.int64Value ?? 0,
			install: install
		)

		available = update

		guard presenting, _shownBuild != build else { return }
		_shownBuild = build
		isPresented = true
	}

	private func _request(_ url: URL) -> URLRequest {
		var request = URLRequest(url: url)
		request.setValue(NBFetchService.userAgent, forHTTPHeaderField: "User-Agent")
		return request
	}

	func install() {
		guard let update = available else { return }
		UIApplication.shared.open(update.install)
	}
}
