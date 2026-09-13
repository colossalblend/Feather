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

	private let _update: AppBankUpdate

	init(update: AppBankUpdate) {
		self._update = update
	}

	var body: some View {
		VStack(spacing: 0) {
			_header
			_notes
			Spacer(minLength: 0)
			_buttons
		}
		.padding(.horizontal, 22)
		.padding(.top, 34)
		.padding(.bottom, 20)
		.presentationDetents([.height(430)])
		.presentationDragIndicator(.visible)
		.presentationCornerRadius(28)
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

			Text(verbatim: _versionLine)
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.bottom, 22)
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
				.padding(.bottom, 2)

			Button {
				manager.install()
				dismiss()
			} label: {
				NBSheetButton(
					title: .localized("Download Update"),
					systemImage: "arrow.down.circle",
					style: .prominent
				)
			}

			Button {
				dismiss()
			} label: {
				NBSheetButton(title: .localized("Close"))
			}
		}
	}
}
