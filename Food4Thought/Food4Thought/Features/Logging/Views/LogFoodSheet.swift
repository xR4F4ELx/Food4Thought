import SwiftUI
import Food4ThoughtCore

/// Handoff 2a — the recents-first log sheet.
///
/// Search sits on top but does not take focus: opening the keyboard would make
/// typing the default, and for most entries the food is already three rows
/// down. The chip strip keeps every other fast path one tap away.
struct LogFoodSheet: View {
    let userID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LogFoodViewModel?
    @State private var quickAddText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.Palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                ToolbarItem(placement: .principal) { slotPicker }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
        .task {
            guard viewModel == nil else { return }
            let model = LogFoodViewModel(userID: userID)
            await model.load()
            viewModel = model
        }
    }

    // MARK: - Slot

    @ViewBuilder
    private var slotPicker: some View {
        if let viewModel, let selected = viewModel.selectedSlot {
            Menu {
                ForEach(viewModel.slots, id: \.key) { slot in
                    Button(slot.label) { viewModel.select(slot: slot) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Add to \(selected.label)")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
            }
            .accessibilityLabel("Meal: \(selected.label)")
            .accessibilityHint("Changes which meal this is logged to")
        }
    }

    // MARK: - Body

    private func content(_ viewModel: LogFoodViewModel) -> some View {
        VStack(spacing: 0) {
            searchField(viewModel)
            chips(viewModel)

            if let notice = viewModel.searchNotice {
                noteRow(notice, tint: Theme.Palette.inkSecondary)
            }
            if let error = viewModel.errorMessage {
                noteRow(error, tint: Theme.Palette.over)
            }

            list(viewModel)

            Button("Quick add calories only") {
                viewModel.isQuickAdding = true
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.inkSecondary)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
        .sheet(item: Binding(get: { viewModel.pendingPortion }, set: { viewModel.pendingPortion = $0 })) { portion in
            QuantitySheet(
                portion: portion,
                slotLabel: viewModel.selectedSlot?.label ?? "this meal",
                isFavorite: viewModel.isFavorite(portion.food),
                isLogging: viewModel.isCommitting,
                onStep: { isIncrement in
                    viewModel.adjustPortion { isIncrement ? $0.incremented() : $0.decremented() }
                },
                onToggleFavorite: { Task { await viewModel.toggleFavorite(portion.food) } },
                onLog: { Task { await viewModel.confirmPendingPortion() } }
            )
        }
        .sheet(isPresented: Binding(get: { viewModel.isQuickAdding }, set: { viewModel.isQuickAdding = $0 })) {
            QuickAddSheet(
                slotLabel: viewModel.selectedSlot?.label ?? "this meal",
                isLogging: viewModel.isCommitting,
                onLog: { calories in Task { await viewModel.quickAdd(calories: calories) } }
            )
        }
        .onChange(of: viewModel.didLog) { _, didLog in
            if didLog { dismiss() }
        }
    }

    private func searchField(_ viewModel: LogFoodViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? Theme.Palette.accent : Theme.Palette.inkTertiary)

            TextField(
                "Search foods",
                text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 })
            )
            .focused($isSearchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)

            if viewModel.isSearching {
                ProgressView().controlSize(.small)
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .stroke(Theme.Palette.accent, lineWidth: isSearchFocused ? 1.5 : 0)
        }
        .padding(.top, 8)
    }

    private func chips(_ viewModel: LogFoodViewModel) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LogFoodViewModel.FastPath.allCases) { path in
                    let isOn = viewModel.path == path && viewModel.query.isEmpty

                    Button {
                        Task { await viewModel.select(path: path) }
                    } label: {
                        Text(path.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? .white : Theme.Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isOn ? Theme.Palette.ink : Theme.Palette.fill,
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func list(_ viewModel: LogFoodViewModel) -> some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if viewModel.path == .copyYesterday && viewModel.query.isEmpty {
            copyYesterdayList(viewModel)
        } else if viewModel.suggestions.isEmpty {
            Spacer()
            Text(emptyMessage(viewModel))
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.suggestions) { suggestion in
                        FoodSuggestionRow(
                            suggestion: suggestion,
                            isFavorite: viewModel.isFavorite(suggestion.item)
                        ) {
                            viewModel.pick(suggestion)
                        }
                        Divider().overlay(Theme.Palette.line)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func copyYesterdayList(_ viewModel: LogFoodViewModel) -> some View {
        if viewModel.copyableEntries.isEmpty {
            Spacer()
            Text("Nothing logged to \(viewModel.selectedSlot?.label ?? "this meal") yesterday.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.copyableEntries) { entry in
                        HStack {
                            Text(entry.item.name)
                                .font(.body)
                                .foregroundStyle(Theme.Palette.ink)
                            Spacer()
                            Text("\(Int(entry.facts.calories.rounded()))")
                                .font(Theme.Typography.stat(16))
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)

            Button {
                Task { await viewModel.copyYesterday() }
            } label: {
                Text("Log all \(viewModel.copyableEntries.count) items · \(copyTotal(viewModel)) kcal")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.primaryButtonHeight)
                    .background(Theme.Palette.accent, in: .rect(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCommitting)
        }
    }

    private func copyTotal(_ viewModel: LogFoodViewModel) -> Int {
        Int(viewModel.copyableEntries.reduce(0) { $0 + $1.facts.calories }.rounded())
    }

    private func emptyMessage(_ viewModel: LogFoodViewModel) -> String {
        if !viewModel.query.isEmpty {
            return "No foods matched. Quick add works if you just need the calories."
        }
        return switch viewModel.path {
        case .favorites: "No favourites yet. Star a food while logging it."
        default: "Nothing logged in the last week yet. Search, or quick add the calories."
        }
    }

    private func noteRow(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}

extension PortionStepper: @retroactive Identifiable {
    /// Identity is the food, not the quantity: the sheet must stay up while the
    /// stepper is stepped, and re-identifying on every tap would dismiss it.
    public var id: FoodItem.Identity { food.id }
}
