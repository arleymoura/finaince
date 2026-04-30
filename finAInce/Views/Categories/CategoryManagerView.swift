import SwiftUI
import SwiftData

// MARK: - Category Manager (root list)

struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var categories: [Category]

    @State private var categoryToEdit: Category? = nil
    @State private var showAddRoot     = false
    @State private var categoryToDelete: Category? = nil
    @State private var showDeleteAlert = false
    private let regularContentMaxWidth: CGFloat = 1100
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }

    private var rootCategories: [Category] {
        categories
            .filter { $0.parent == nil }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if isRegularLayout {
                regularCategoryManagerView
            } else {
                categoryList
                    .navigationTitle(t("category.title"))
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showAddRoot = true } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(t("category.addRoot"))
                        }
                    }
            }
        }
        .sheet(item: $categoryToEdit) { cat in
            CategoryFormView(category: cat)
        }
        .sheet(isPresented: $showAddRoot) {
            CategoryFormView()
        }
        .alert(t("category.deleteTitle"), isPresented: $showDeleteAlert, presenting: categoryToDelete) { cat in
            Button(t("common.delete"), role: .destructive) { modelContext.delete(cat) }
            Button(t("common.cancel"), role: .cancel) {}
        } message: { cat in
            if !(cat.subcategories ?? []).isEmpty {
                Text(t("category.deleteWithSubs", (cat.subcategories ?? []).count))
            } else {
                Text(t("category.deleteMessage"))
            }
        }
    }

    private var categoryList: some View {
        List {
            ForEach(rootCategories) { root in
                Section {
                    categoryRow(root)

                    NavigationLink {
                        SubcategoryListView(parent: root)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(t("category.subcategories"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if !(root.subcategories ?? []).isEmpty {
                                Text("\((root.subcategories ?? []).count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: root.color))
                                    .clipShape(Capsule())
                            } else {
                                Text(t("category.none"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var regularCategoryManagerView: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }

                        Text(t("category.title"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button { showAddRoot = true } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(t("category.addRoot"))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))

                    categoryList
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Category row

    private func categoryRow(_ cat: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cat.icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: cat.color))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(cat.displayName)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Image(systemName: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { categoryToEdit = cat }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                categoryToDelete = cat
                showDeleteAlert  = true
            } label: {
                Label(t("common.delete"), systemImage: "trash")
            }
            Button { categoryToEdit = cat } label: {
                Label(t("common.edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Subcategory List

struct SubcategoryListView: View {
    let parent: Category

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var categoryToEdit: Category?   = nil
    @State private var showAdd                     = false
    @State private var categoryToDelete: Category? = nil
    @State private var showDeleteAlert             = false
    private let regularContentMaxWidth: CGFloat = 1100
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }

    private var subcategories: [Category] {
        (parent.subcategories ?? []).sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if isRegularLayout {
                regularSubcategoryListView
            } else {
                subcategoryList
                    .navigationTitle(parent.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showAdd = true } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(t("category.addSubLabel"))
                        }
                    }
            }
        }
        .sheet(item: $categoryToEdit) { cat in
            CategoryFormView(category: cat)
        }
        .sheet(isPresented: $showAdd) {
            CategoryFormView(parent: parent)
        }
        .alert(t("category.deleteTitle"), isPresented: $showDeleteAlert, presenting: categoryToDelete) { cat in
            
            Button(t("common.delete"), role: .destructive) {
                modelContext.delete(cat)
                
                do {
                    try modelContext.save()
                } catch {
                    print("\(t("category.deleteErrorLog")): \(error)")
                }
            }
            
            Button(t("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(t("category.deleteMessage"))
        }
    }

    private var subcategoryList: some View {
        List {
            if subcategories.isEmpty {
                emptyState
            } else {
                ForEach(subcategories) { sub in
                    subcategoryRow(sub)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var regularSubcategoryListView: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }

                        Text(parent.displayName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer()

                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(t("category.addSubLabel"))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))

                    subcategoryList
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(t("category.noSubs"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showAdd = true
            } label: {
                Label(t("category.addSubLabel"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Subcategory row

    private func subcategoryRow(_ cat: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cat.icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: cat.color))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(cat.displayName)
                .font(.subheadline)

            Spacer()

            Image(systemName: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { categoryToEdit = cat }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                categoryToDelete = cat
                showDeleteAlert  = true
            } label: {
                Label(t("common.delete"), systemImage: "trash")
            }
            Button { categoryToEdit = cat } label: {
                Label(t("common.edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
