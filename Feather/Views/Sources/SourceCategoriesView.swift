//
//  SourceCategoriesView.swift
//  Feather
//
//  Просмотр каталога по категориям (как в Scarlet). Экран-шит: крупные
//  категории списком, категории из одного приложения — сразу карточка.
//

import SwiftUI
import AltSourceKit
import NimbleViews

// MARK: - Предикат: единственный источник истины для фильтра и поиска
extension ASRepository.App {
	/// Нормализованное имя категории; nil, если поля нет или оно пустое.
	var categoryName: String? {
		guard
			let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines),
			!trimmed.isEmpty
		else { return nil }
		return trimmed
	}

	/// Фильтр по категории и поиск складываются по И.
	/// Поиск дополнительно матчит имя категории — «урал» находит Уралсиб,
	/// «VK» находит Дзен и Одноклассников.
	func matches(search: String, category: String?) -> Bool {
		if let category {
			guard categoryName?.localizedCaseInsensitiveCompare(category) == .orderedSame else {
				return false
			}
		}

		guard !search.isEmpty else { return true }

		return (id?.range(of: search, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")) != nil)
			|| (name?.localizedCaseInsensitiveContains(search) ?? false)
			|| (self.description?.localizedCaseInsensitiveContains(search) ?? false)
			|| (subtitle?.localizedCaseInsensitiveContains(search) ?? false)
			|| (localizedDescription?.localizedCaseInsensitiveContains(search) ?? false)
			|| (categoryName?.localizedCaseInsensitiveContains(search) ?? false)
	}
}

// MARK: - Модель
// Только Identifiable. НЕ Hashable и НЕ Equatable: внутри SourceAppEntry лежит
// ASRepository целиком, синтез сравнения потянул бы все 68 приложений.
struct SourceCategory: Identifiable {
	let name: String
	let entries: [SourceAppEntry]
	var id: String { name }

	// ponytail: O(n) группировка по всем приложениям при каждой загрузке экрана.
	// 68 приложений — микросекунды. Переносить в SourcesViewModel, если каталог
	// вырастет до тысяч. Вызывать ТОЛЬКО из SourceAppsView._load(), никогда из body.
	static func build(from contexts: [SourceAppsView.SourceRepositoryContext]) -> [SourceCategory] {
		let entries = contexts.flatMap { context in
			context.repository.apps.compactMap { app -> SourceAppEntry? in
				guard app.categoryName != nil else { return nil }
				return SourceAppEntry(sourceURL: context.sourceURL, source: context.repository, app: app)
			}
		}

		return Dictionary(grouping: entries) { $0.app.categoryName?.lowercased() ?? "" }
			.values
			.compactMap { group -> SourceCategory? in
				guard let name = group.first?.app.categoryName else { return nil }
				return SourceCategory(name: name, entries: group)
			}
			// Dictionary порядок недетерминирован — comparator обязан быть полным.
			.sorted {
				$0.entries.count != $1.entries.count
					? $0.entries.count > $1.entries.count
					: $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
	}
}

// MARK: - Экран
struct SourceCategoriesView: View {
	let object: [AltSource]
	@ObservedObject var viewModel: SourcesViewModel
	let categories: [SourceCategory]

	@State private var _searchText = ""

	private var _filtered: [SourceCategory] {
		guard !_searchText.isEmpty else { return categories }
		return categories.filter { category in
			category.name.localizedCaseInsensitiveContains(_searchText) ||
			category.entries.contains { $0.app.currentName.localizedCaseInsensitiveContains(_searchText) }
		}
	}

	var body: some View {
		let filtered = _filtered
		let groups = filtered.filter { $0.entries.count > 1 }
		let singles = filtered.filter { $0.entries.count == 1 }

		NBNavigationView(.localized("Categories")) {
			NBListAdaptable {
				if !groups.isEmpty {
					NBSection(.localized("Categories"), secondary: groups.count.description) {
						ForEach(groups) { category in
							NavigationLink {
								SourceAppsView(
									object: object,
									viewModel: viewModel,
									categoryFilter: category.name
								)
							} label: {
								FRIconCellView(
									title: category.name,
									subtitle: .localized("%lld Apps", arguments: category.entries.count),
									iconUrl: category.entries.first?.app.originalIconURL ?? category.entries.first?.app.iconURL
								)
							}
							.buttonStyle(.plain)
						}
					}
				}

				// Категория из одного приложения — это и есть приложение.
				// Строка ведёт сразу в карточку; на iOS 16 это единственный путь туда.
				// Кнопки Get здесь НЕТ намеренно: Button внутри NavigationLink label
				// не получает тап, а Get живёт в карточке приложения.
				if !singles.isEmpty {
					NBSection(.localized("Single Apps"), secondary: singles.count.description) {
						ForEach(singles) { category in
							let entry = category.entries[0]
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: entry.sourceURL,
									source: entry.source,
									app: entry.app
								)
							} label: {
								FRIconCellView(
									title: entry.app.currentName,
									subtitle: SourceAppsCellView.appDescription(app: entry.app),
									iconUrl: entry.app.iconURL
								)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.animation(.easeInOut(duration: 0.25), value: filtered.count)
			.searchable(text: $_searchText, placement: .platform())
			.overlay {
				if filtered.isEmpty {
					if #available(iOS 17, *) {
						ContentUnavailableView.search(text: _searchText)
					} else {
						VStack(spacing: 8) {
							Image(systemName: "square.grid.3x3.fill").font(.largeTitle)
							Text(.localized("No Apps")).font(.headline)
						}
						.foregroundStyle(.secondary)
					}
				}
			}
			.animation(.easeInOut(duration: 0.2), value: filtered.isEmpty)
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
	}
}
