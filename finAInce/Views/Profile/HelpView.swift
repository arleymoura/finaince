import SwiftUI

// MARK: - Models

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private struct FAQSection: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let items: [FAQItem]
    var isExpanded: Bool = false
}

// MARK: - HelpView

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sections: [FAQSection] = []
    private let regularContentMaxWidth: CGFloat = 1100
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegularLayout {
                regularHelpView
            } else {
                helpList
                    .navigationTitle(t("help.title"))
                    .navigationBarTitleDisplayMode(.large)
            }
        }
        .onAppear { sections = makeSections() }
    }

    private var helpList: some View {
        List {
            Section {
                privacyHighlightCard
                    .listRowBackground(Color.clear)
            }

            ForEach($sections) { $section in
                faqSection($section)
            }

            Section {
                footerView
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 16, trailing: 0))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(6)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var regularHelpView: some View {
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

                        Text(t("help.title"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))

                    helpList
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Privacy Highlight Card

    private var privacyHighlightCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text(t("help.privacy.highlight.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(t("help.privacy.highlight.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - FAQ Section

    @ViewBuilder
    private func faqSection(_ section: Binding<FAQSection>) -> some View {
        Section {
            // Header row (tap to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    section.wrappedValue.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(section.wrappedValue.iconColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: section.wrappedValue.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(section.wrappedValue.iconColor)
                    }

                    Text(section.wrappedValue.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(section.wrappedValue.isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.22), value: section.wrappedValue.isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable items
            if section.wrappedValue.isExpanded {
                ForEach(section.wrappedValue.items) { item in
                    FAQItemRow(item: item)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 10) {
            Text(t("help.contactSupport"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "mailto:arleymoura@gmail.com")!) {
                Label(t("help.contactAction"), systemImage: "envelope.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Data

    private func makeSections() -> [FAQSection] {
        [
            FAQSection(
                icon: "lock.shield",
                iconColor: Color.accentColor,
                title: t("help.privacy.section"),
                items: [
                    FAQItem(question: t("help.privacy.q1"), answer: t("help.privacy.a1")),
                    FAQItem(question: t("help.privacy.q2"), answer: t("help.privacy.a2")),
                    FAQItem(question: t("help.privacy.q3"), answer: t("help.privacy.a3")),
                ],
                isExpanded: true // Privacy is most important — open by default
            ),
            FAQSection(
                icon: "icloud",
                iconColor: .blue,
                title: t("help.backup.section"),
                items: [
                    FAQItem(question: t("help.backup.q1"), answer: t("help.backup.a1")),
                    FAQItem(question: t("help.backup.q2"), answer: t("help.backup.a2")),
                    FAQItem(question: t("help.backup.q3"), answer: t("help.backup.a3")),
                ]
            ),
            FAQSection(
                icon: "brain",
                iconColor: .purple,
                title: t("help.ai.section"),
                items: [
                    FAQItem(question: t("help.ai.q1"), answer: t("help.ai.a1")),
                    FAQItem(question: t("help.ai.q2"), answer: t("help.ai.a2")),
                    FAQItem(question: t("help.ai.q3"), answer: t("help.ai.a3")),
                    FAQItem(question: t("help.ai.q4"), answer: t("help.ai.a4")),
                ]
            ),
            FAQSection(
                icon: "tray.and.arrow.down",
                iconColor: .orange,
                title: t("help.import.section"),
                items: [
                    FAQItem(question: t("help.import.q1"), answer: t("help.import.a1")),
                    FAQItem(question: t("help.import.q2"), answer: t("help.import.a2")),
                ]
            ),
            FAQSection(
                icon: "creditcard",
                iconColor: .green,
                title: t("help.pricing.section"),
                items: [
                    FAQItem(question: t("help.pricing.q1"), answer: t("help.pricing.a1")),
                    FAQItem(question: t("help.pricing.q2"), answer: t("help.pricing.a2")),
                ]
            ),
            FAQSection(
                icon: "gear",
                iconColor: .secondary,
                title: t("help.general.section"),
                items: [
                    FAQItem(question: t("help.general.q1"), answer: t("help.general.a1")),
                    FAQItem(question: t("help.general.q2"), answer: t("help.general.a2")),
                    FAQItem(question: t("help.general.q3"), answer: t("help.general.a3")),
                ]
            ),
        ]
    }
}

// MARK: - FAQ Item Row

private struct FAQItemRow: View {
    let item: FAQItem
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(item.question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.top, 2)
                }

                if isExpanded {
                    Text(item.answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
