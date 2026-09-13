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

/// Чем закончилась проверка обновления — для ручной кнопки в настройках.
enum AppBankUpdateOutcome {
	case updateAvailable    // окно показано
	case upToDate           // стоит последняя сборка
	case unavailable        // нет адреса или сеть подвела
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

	@discardableResult
	func check(presenting: Bool = true, manual: Bool = false) async -> AppBankUpdateOutcome {
		guard let endpoint = _endpoint else { return .unavailable }
		guard !isChecking else { return .unavailable }

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
			// Тело разобрали, но сборка совпала с нашей — значит всё свежее.
			if let data = try? await _fetchBuild(endpoint), data == _currentBuild {
				available = nil
				return .upToDate
			}
			return .unavailable
		}

		let update = AppBankUpdate(
			build: build,
			version: (json["version"] as? String) ?? "",
			notes: (json["notes"] as? String) ?? "",
			size: (json["size"] as? NSNumber)?.int64Value ?? 0,
			install: install
		)

		available = update

		// Ручная проверка показывает окно всегда; авто — раз на сборку.
		if presenting, manual || _shownBuild != build {
			_shownBuild = build
			isPresented = true
		}
		return .updateAvailable
	}

	private func _request(_ url: URL) -> URLRequest {
		var request = URLRequest(url: url)
		request.setValue(NBFetchService.userAgent, forHTTPHeaderField: "User-Agent")
		return request
	}

	/// Отдельный лёгкий запрос: нужен только чтобы отличить «сборка та же»
	/// (upToDate) от настоящей ошибки сети, когда основной разбор не прошёл.
	private func _fetchBuild(_ endpoint: URL) async -> String? {
		guard
			let (data, response) = try? await URLSession.shared.data(for: _request(endpoint)),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }
		return json["build"] as? String
	}

	func install() {
		guard let update = available else { return }
		UIApplication.shared.open(update.install)
	}
}
