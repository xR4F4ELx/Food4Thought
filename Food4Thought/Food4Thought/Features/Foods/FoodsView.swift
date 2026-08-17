import SwiftUI
import Food4ThoughtCore

/// Foods — the user's own library: the foods they created and the ones they
/// starred, with a way to fix or remove either.
///
/// The counterpart to the logging flow, which can only ever add. Without this
/// screen a typo in a home recipe is permanent and a mis-starred food sits at
/// the top of the log sheet forever.
struct FoodsView: View {
    let userID: UUID

    @State private var viewModel: FoodsViewModel?
    @State private var route: Route?

    /// Creating and editing share one presentation slot. Two `.sheet`
    /// modifiers on a single view is the bug that silently does nothing —
    /// SwiftUI only reliably honours one.
    private enum Route: Identifiable {
        case create
        case edit(FoodItem)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let food): "edit-\(food.id)"
            }
        }
    }

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
            .navigationTitle("Foods")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        route = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create a food")
                    .accessibilityHint("Adds a food to your library without logging it")
                }
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = FoodsViewModel(userID: userID)
            await model.load()
            viewModel = model
        }
    }

    // MARK: - Content

    private func content(_ viewModel: FoodsViewModel) -> some View {
        VStack(spacing: 0) {
            Picker("Shelf", selection: Binding(
                get: { viewModel.shelf },
                set: { viewModel.shelf = $0 }
            )) {
                ForEach(FoodsViewModel.Shelf.allCases) { shelf in
                    Text(shelf.title).tag(shelf)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Metrics.horizontalPadding)
            .padding(.bottom, 8)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.over)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metrics.horizontalPadding)
                    .padding(.bottom, 8)
            }

            list(viewModel)
        }
        .sheet(item: $route) { presented in
            switch presented {
            case .create:
                CustomFoodSheet(isSaving: viewModel.isSaving) { draft in
                    Task {
                        if await viewModel.create(draft) { route = nil }
                    }
                }
            case .edit(let food):
                CustomFoodSheet(
                    isSaving: viewModel.isSaving,
                    draft: CustomFoodDraft(food: food),
                    title: "Edit food",
                    focusesNameOnAppear: false,
                    onSave: { draft in
                        Task {
                            if await viewModel.save(draft, to: food) { route = nil }
                        }
                    }
                )
            }
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
                // A turn later: the alert still owns the presentation slot as
                // its button action runs, and a sheet assigned here never
                // appears.
                DispatchQueue.main.async { route = .edit(food) }
            }
            Button("OK", role: .cancel) { viewModel.blockedDeletion = nil }
        } message: { _ in
            Text(FoodRepositoryError.foodInUse.errorDescription ?? "")
        }
    }

    @ViewBuilder
    private func list(_ viewModel: FoodsViewModel) -> some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isEmpty {
            Text(viewModel.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                switch viewModel.shelf {
                case .myFoods:
                    ForEach(viewModel.customFoods) { food in
                        row(food)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(food) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    route = .edit(food)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.Palette.inkSecondary)
                            }
                            .onTapGesture { route = .edit(food) }
                    }

                case .favorites:
                    ForEach(viewModel.favorites) { suggestion in
                        row(suggestion.item)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    Task { await viewModel.unfavorite(suggestion.item) }
                                } label: {
                                    Label("Unstar", systemImage: "star.slash")
                                }
                                .tint(Theme.Palette.carbs)
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .refreshable { await viewModel.load() }
        }
    }

    private func row(_ food: FoodItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)

                Text(subtitle(food))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(food.facts.calories.rounded()))")
                    .font(Theme.Typography.stat(16))
                    .foregroundStyle(Theme.Palette.ink)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.Palette.surface)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// Says where the food came from, because it decides what can be done with
    /// it: a USDA row is a shared cache entry nobody owns and cannot be edited,
    /// only unstarred.
    private func subtitle(_ food: FoodItem) -> String {
        var parts: [String] = []
        if let brand = food.brand { parts.append(brand) }
        parts.append("per \(food.servingDescription)")
        if food.source == .usdaFDC { parts.append("USDA") }
        return parts.joined(separator: " · ")
    }
}
