//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
	@State private var handoffTask: Task<Void, Never>?
	@State private var isPreparingInstall = false
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if _installationMethod == 0 {
				if case .ready = newStatus {
					_openInstallation()
				}
				
				if case .sendingPayload = newStatus {
					handoffTask?.cancel()
					handoffTask = nil
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus {
					if progressTask == nil {
						progressTask = startInstallProgressPolling(
							bundleID: app.identifier!,
							viewModel: viewModel
						)
					}
				}
				
				switch newStatus {
				case .completed, .broken(_):
					handoffTask?.cancel()
					handoffTask = nil
					progressTask?.cancel()
					progressTask = nil
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear(perform: _install)
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
			handoffTask?.cancel()
			handoffTask = nil
			progressTask?.cancel()
			progressTask = nil
			
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Label(isPreparingInstall ? String.localized("Checking installation") : viewModel.statusLabel, systemImage: viewModel.statusImage)
			if case .broken(let error) = viewModel.status {
				Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
			}
		}
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
    private var _canRetry: Bool {
        switch viewModel.status {
        case .broken, .ready: return !isPreparingInstall
        default: return false
        }
    }

	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if _canRetry, installer.packageUrl != nil {
				Button {
					Task { await _prepareInstallation() }
				} label: {
					NBButton("Retry", systemImage: "arrow.clockwise", style: .text)
				}
				.padding()
			} else if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}
				
		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
					if await _installationMethod == 0 {
						await MainActor.run {
							installer.packageUrl = packageUrl
						}
						await _prepareInstallation()
						
						if case .installing = await viewModel.status {
							let task = await startInstallProgressPolling(
								bundleID: app.identifier!,
								viewModel: viewModel
							)

							await MainActor.run {
								progressTask = task
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()
				
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: String(describing: error),
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}
	
	@MainActor
	private func _prepareInstallation() async {
		guard !isPreparingInstall else { return }
		isPreparingInstall = true
		defer { isPreparingInstall = false }
		viewModel.status = .none
		do {
			try await installer.prepare()
			viewModel.status = .ready
		} catch {
			viewModel.status = .broken(error)
		}
	}

	@MainActor
	private func _openInstallation() {
		handoffTask?.cancel()
		let fullyLocal = installer.getServerMethod() == 0
		let link = fullyLocal ? installer.iTunesLink : installer.iTunesLinkExternal
		guard let url = URL(string: link) else { return }
		// RyukSign: use the system scheme first, Safari only as a fallback.
		UIApplication.shared.open(url) { opened in
			Task { @MainActor in
				if !opened {
					if fullyLocal {
						await _recoverInstallation()
					} else {
						_isWebviewPresenting = true
					}
				}
			}
		}
		handoffTask = Task { @MainActor in
			// Never restart an accepted install or an open confirmation prompt.
			try? await Task.sleep(nanoseconds: 20_000_000_000)
			guard !Task.isCancelled, fullyLocal, case .ready = viewModel.status,
				UIApplication.shared.applicationState == .active else { return }
			await _recoverInstallation()
		}
	}

	@MainActor
	private func _recoverInstallation() async {
		guard !isPreparingInstall, case .ready = viewModel.status else { return }
		isPreparingInstall = true
		defer { isPreparingInstall = false }
		do {
			if try await installer.recoverToSemiLocal() {
				_openInstallation()
			}
		} catch {
			viewModel.status = .broken(error)
		}
	}

	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let observedProgress = await UIApplication.installProgress(for: bundleID)
				let rawProgress = observedProgress ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				Logger.misc.info("Install progress for \(bundleID): \(progress)")

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && observedProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 250_000_000)
			}
		}
	}

	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
