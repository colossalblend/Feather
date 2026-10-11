//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
    private(set) var startupError: Error?
    private(set) var manifestUrl: URL?
    private var _serverMethod = UserDefaults.standard.integer(forKey: "Feather.serverMethod")
    private var _didFallback = false
    private var _semiLocalHost: String = "127.0.0.1"
	
	var packageUrl: URL?
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	private var _server: Application?

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel
        _semiLocalHost = InstallationLinks.semiLocalHost(wifiAddress: Self.getLocalAddress(), onlyLocalhost: getIPFix())
        do {
            try _startServer()
        } catch {
            startupError = error
        }
	}
	
	deinit {
		_shutdownServer()
	}
	
    private func _startServer() throws {
        let server = try setupApp(port: port)
        _server = server
        do {
            try _configureRoutes()
            try server.server.start()
            _needsShutdown = true
        } catch {
            server.shutdown()
            _server = nil
            throw error
        }
    }

    // Inspired by RyukSign's server self-check and ManifestService (GPL-3.0).
    // Probe /healthz, not /manifest: a diagnostic must not advance install status.
    @MainActor
    func prepare() async throws {
        do {
            if let startupError { throw startupError }
            var components = URLComponents(url: pageEndpoint, resolvingAgainstBaseURL: false)!
            components.path = "/healthz"
            let (_, response) = try await URLSession.shared.data(for: URLRequest(url: components.url!, timeoutInterval: 8))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw installationError("Local installation server is unavailable.")
            }
        } catch {
            guard _serverMethod == 0, !_didFallback else { throw error }
            try switchToSemiLocal()
            try await prepare()
            return
        }
        if _serverMethod == 1 {
            // Existing public services used by RyukSign. No AppBank server,
            // uploaded IPA, stored manifest or certificate is involved.
            manifestUrl = nil
            for endpoint in ["https://ryuksign-install.ryuksign.workers.dev/genPlist", "https://api.palera.in/genPlist"] {
                let url = InstallationLinks.manifestURL(identifier: app.identifier ?? "", name: app.name ?? "", version: app.version ?? "1", payload: payloadEndpoint, endpoint: endpoint)
                guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      InstallationLinks.validatesManifest(data, identifier: app.identifier ?? "", payload: payloadEndpoint) else { continue }
                manifestUrl = url
                break
            }
            guard manifestUrl != nil else {
                throw installationError("Could not load the installation manifest. Check your internet connection and try again.")
            }
        }
    }

    @MainActor
    func recoverToSemiLocal() async throws -> Bool {
        guard _serverMethod == 0, !_didFallback else { return false }
        try switchToSemiLocal()
        try await prepare()
        return true
    }

    private func switchToSemiLocal() throws {
        // This override belongs to this install only; keep the user's setting.
        _didFallback = true
        _shutdownServer()
        _server = nil
        _serverMethod = 1
        _semiLocalHost = "127.0.0.1"
        startupError = nil
        try _startServer()
    }

    func semiLocalHost() -> String { _semiLocalHost }

    func installationError(_ message: String) -> Error {
        NSError(domain: "AppBank.Installation", code: -1, userInfo: [NSLocalizedDescriptionKey: String.localized(message)])
    }
		
	private func _configureRoutes() throws {
		_server?.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
			switch req.url.path {
			case plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}
				
				self._updateStatus(.sendingPayload)
				
				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
					switch result {
					case .success:
						self._updateStatus(.installing)
					case .failure(let error):
						self._updateStatus(.broken(error))
					}

				}
            case "/healthz":
                return Response(status: .ok)
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server?.server.shutdown()
		_server?.shutdown()
	}
	
	private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}
		
	func getServerMethod() -> Int {
		_serverMethod
	}
	
	func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
}
