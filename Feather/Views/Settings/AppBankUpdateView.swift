//
//  AppBankUpdateView.swift
//  Feather
//
//  Окно обновления сборки AppBank. Оформление взято у самого Feather:
//  NBSheetButton, системные материалы, иконка приложения — чтобы не
//  выглядело чужой вставкой.
//

import NimbleViews
import SwiftUI

struct AppBankUpdateView: View {
	@Environment(\.dismiss) private var dismiss
	@StateObject private var manager = AppBankUpdateManager.shared
	@State private var _contentHeight: CGFloat = 430
	@State private var _footerHeight: CGFloat = 150

	private let _update: AppBankUpdate

	init(update: AppBankUpdate) {
		self._update = update
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				_header
				_notes
			}
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 22)
			.padding(.top, 28)
			.padding(.bottom, 20)
			.background {
				GeometryReader { geometry in
					Color.clear.preference(key: _UpdateContentHeight.self, value: geometry.size.height)
				}
			}
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			_buttons
				.padding(.horizontal, 22)
				.padding(.top, 14)
				.padding(.bottom, 12)
				.background(.regularMaterial)
				.background {
					GeometryReader { geometry in
						Color.clear.preference(key: _UpdateFooterHeight.self, value: geometry.size.height)
					}
				}
		}
		.onPreferenceChange(_UpdateContentHeight.self) { height in
			if height > 0 { _contentHeight = height }
		}
		.onPreferenceChange(_UpdateFooterHeight.self) { height in
			if height > 0 { _footerHeight = height }
		}
		.presentationDetents([.height(_contentHeight + _footerHeight)])
		.presentationDragIndicator(.hidden)
		.interactiveDismissDisabled(manager.isWorking)
		.modifier(_SheetCorners())
	}

	private var _header: some View {
		VStack(spacing: 14) {
			// Тот же глиф, что в шапке экрана подписи: иконку приложения
			// из каталога напрямую не достать, а глиф уже есть в ассетах.
			Image("Glyph")
				.resizable()
				.scaledToFit()
				.frame(height: 52)
				.foregroundStyle(Color.accentColor)

			Text(verbatim: .localized("Update Available"))
				.font(.title2).bold()
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)

			Text(verbatim: _versionLine)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity)
	}

	private var _versionLine: String {
		var parts: [String] = []
		if !_update.version.isEmpty { parts.append("Feather \(_update.version)") }
		if _update.size > 0 { parts.append(_update.sizeText) }
		return parts.joined(separator: " • ")
	}

	@ViewBuilder
	private var _notes: some View {
		if !_update.notes.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				Text(verbatim: .localized("What's New"))
					.font(.footnote).bold()
					.foregroundStyle(.secondary)

				Text(verbatim: _update.notes)
					.font(.callout)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.background(Color(uiColor: .quaternarySystemFill))
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		}
	}

	private var _buttons: some View {
		VStack(spacing: 10) {
			// Ставится поверх: bundle id тот же, поэтому сертификаты,
			// источники и приложения внутри Feather остаются на месте.
			Text(verbatim: .localized("Your certificates, sources and apps will be kept."))
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity)
				.padding(.bottom, 2)

			if let stage = manager.stage {
				Text(stage).font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
			}
			if let error = manager.errorMessage {
				Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
			}
			if let ipa = manager.preparedUpdateURL {
				ShareLink(item: ipa) {
					NBSheetButton(title: "Передать IPA в установщик", systemImage: "square.and.arrow.up", style: .prominent)
				}
				Text("Можно сохранить IPA в «Файлы» и импортировать в другой установщик.")
					.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			Button {
				manager.install()
			} label: {
				NBSheetButton(
						title: manager.isWorking ? "Подготовка…" : (manager.isInstalling ? "Установка…" : (manager.usesExternalInstaller ? "Подписать обновление" : (manager.hasPreparedUpdate ? "Повторить установку" : .localized("Download Update")))),
					systemImage: "arrow.down.circle",
					style: .prominent
				)
			}

			.disabled(manager.isWorking || manager.isInstalling)
			Button {
				dismiss()
			} label: {
				NBSheetButton(title: .localized("Close"))
			}
			.disabled(manager.isWorking)
		}
	}
}

private struct _UpdateContentHeight: PreferenceKey {
	static let defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}

private struct _UpdateFooterHeight: PreferenceKey {
	static let defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}


/// Скругление шита появилось только в iOS 16.4, а Feather держит 16.0.
private struct _SheetCorners: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 16.4, *) {
			content.presentationCornerRadius(28)
		} else {
			content
		}
	}
}
