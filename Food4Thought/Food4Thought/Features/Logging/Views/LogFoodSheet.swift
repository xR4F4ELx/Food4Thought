import SwiftUI
import Food4ThoughtCore

/// Handoff 2a — the recents-first log sheet.
///
/// Search sits on top but does not take focus: opening the keyboard would make
/// typing the default, and for most entries the food is already three rows
/// down. The chip strip keeps every other fast path one tap away.
struct LogFoodSheet: View {
    let userID: UUID

    /// Nil when opened from the centre + button, where the slot is inferred
    /// from the clock. Set when a Home meal row named one.
    var initialSlotKey: String?

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
                    // "Cancel" stops meaning anything once something has been
                    // written — there is nothing left to cancel, and offering
                    // it suggests the entries would be taken back.
                    let hasLogged = viewModel?.hasLogged ?? false

                    Button(hasLogged ? "Done" : "Cancel") { dismiss() }
                        .font(hasLogged ? .body.weight(.semibold) : .body)
                        .foregroundStyle(hasLogged ? Theme.Palette.accent : Theme.Palette.inkSecondary)
                }
                ToolbarItem(placement: .principal) { slotPicker }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
        .task {
            guard viewModel == nil else { return }
            let model = LogFoodViewModel(userID: userID, initialSlotKey: initialSlotKey)
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
                .sheet(isPresented: Binding(get: { viewModel.isQuickAdding }, set: { viewModel.isQuickAdding = $0 })) {
                    QuickAddSheet(
                        slotLabel: viewModel.selectedSlot?.label ?? "this meal",
                        isLogging: viewModel.isCommitting,
                        onLog: { calories in Task { await viewModel.quickAdd(calories: calories) } }
                    )
                }
            chips(viewModel)
            tally(viewModel)

            if let notice = viewModel.searchNotice {
                noteRow(notice, tint: Theme.Palette.inkSecondary)
            }
            if let error = viewModel.errorMessage {
                noteRow(error, tint: Theme.Palette.over)
            }

            list(viewModel)
                // Each sheet hangs off a different view rather than stacking
                // three modifiers on one: SwiftUI only reliably honours one
                // .sheet per view, and the failure is a button that silently
                // does nothing.
                .sheet(item: Binding(get: { viewModel.customFoodRoute }, set: { viewModel.customFoodRoute = $0 })) { route in
                    customFoodSheet(route, viewModel)
                }
                .alert(
                    "Still in use",
                    isPresented: Binding(
                        get: { viewModel.blockedDeletion != nil },
                        set: { if !$0 { viewModel.blockedDeletion = nil } }
                    ),
                    presenting: viewModel.blockedDeletion
                ) { food in
                    Button("Edit instead") {
                        viewModel.blockedDeletion = nil
                        // A turn later: the alert still owns the presentation
                        // slot as its button action runs, and a sheet assigned
                        // here never appears.
                        DispatchQueue.main.async { viewModel.customFoodRoute = .edit(food) }
                    }
                    Button("OK", role: .cancel) { viewModel.blockedDeletion = nil }
                } message: { _ in
                    Text(FoodRepositoryError.foodInUse.errorDescription ?? "")
                }

            HStack(spacing: 18) {
                Button("Create a food") {
                    viewModel.customFoodRoute = .create
                }
                Button("Quick add calories only") {
                    viewModel.isQuickAdding = true
                }
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
    }

    @ViewBuilder
    private func customFoodSheet(
        _ route: LogFoodViewModel.CustomFoodRoute,
        _ viewModel: LogFoodViewModel
    ) -> some View {
        switch route {
        case .create:
            CustomFoodSheet(isSaving: viewModel.isCommitting) { draft in
                Task { await viewModel.createCustomFood(draft) }
            }
        case .edit(let food):
            CustomFoodSheet(
                isSaving: viewModel.isCommitting,
                draft: CustomFoodDraft(food: food),
                title: "Edit food",
                focusesNameOnAppear: false,
                onSave: { draft in
                    Task {
                        if await viewModel.saveCustomFood(draft, to: food) {
                            viewModel.customFoodRoute = nil
                        }
                    }
                }
            )
        }
    }

    /// What has gone in so far this sitting.
    ///
    /// The sheet no longer closes on the first write, so this is what tells the
    /// user the tap landed. Without it, logging a burger looks like nothing
    /// happened and they log it twice.
    @ViewBuilder
    private func tally(_ viewModel: LogFoodViewModel) -> some View {
        if viewModel.hasLogged {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.fat)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(countLabel(viewModel.loggedItems.count)) added · \(viewModel.loggedKcal) kcal")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Palette.ink)

                    // Middot, not comma: USDA names contain commas of their own.
                    Text(viewModel.loggedItems.map(\.name).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.Palette.fat.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.control))
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
        }
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
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
        } else if viewModel.path == .myFoods && viewModel.query.isEmpty {
            myFoodsList(viewModel)
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

    /// The user's own library, inside the sheet that logs from it.
    ///
    /// A `List` rather than the scroll view the other shelves use, for the
    /// swipe actions: this is the one place a food can be corrected or removed,
    /// so the rows have to carry more than a tap.
    @ViewBuilder
    private func myFoodsList(_ viewModel: LogFoodViewModel) -> some View {
        if viewModel.myFoods.isEmpty {
            Spacer()
            Text("Nothing here yet. Anything you cook or buy that isn't in the food database can live here — tap Create a food to add one.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        } else {
            List {
                ForEach(viewModel.myFoods) { food in
                    let suggestion = FoodSuggestion(item: food, origin: .catalogue)

                    FoodSuggestionRow(
                        suggestion: suggestion,
                        isFavorite: viewModel.isFavorite(food)
                    ) {
                        viewModel.pick(suggestion)
                    }
                    // Overrides the row's own hint: here the same row also
                    // hides edit and delete behind a swipe, which nobody using
                    // VoiceOver would otherwise know about.
                    .accessibilityHint("Opens the quantity step. Swipe left to edit or delete this food.")
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Theme.Palette.paper)
                    .listRowSeparatorTint(Theme.Palette.line)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteCustomFood(food) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            viewModel.customFoodRoute = .edit(food)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Theme.Palette.inkSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
    }

    private func emptyMessage(_ viewModel: LogFoodViewModel) -> String {
        if !viewModel.query.isEmpty {
            return "No foods matched “\(viewModel.query)”. Create it as a food, or quick add the calories."
        }
        return switch viewModel.path {
        case .favorites: "No favourites yet. Star a food while logging it."
        default: "Nothing logged in the last week yet. Search, create a food, or quick add the calories."
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
