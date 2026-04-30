import SwiftUI

struct HouseholdCompositionEditor: View {
    @Binding var adults: Int
    @Binding var children: Int

    var body: some View {
        VStack(spacing: 20) {
            familyCard

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(householdSummary(adults: adults, children: children))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var familyCard: some View {
        VStack(spacing: 0) {
            familyRow(
                icon: "person.fill",
                color: Color.accentColor,
                title: t("ob.step1.adults"),
                subtitle: t("ob.step1.adultsDesc"),
                value: $adults,
                range: 1...8
            )
            Divider().padding(.horizontal, 16)
            familyRow(
                icon: "figure.and.child.holdinghands",
                color: Color(hex: "#34C759"),
                title: t("ob.step1.children"),
                subtitle: t("ob.step1.childrenDesc"),
                value: $children,
                range: 0...8
            )
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func familyRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(value.wrappedValue > range.lowerBound ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.title3.bold().monospacedDigit())
                    .frame(width: 44)
                    .multilineTextAlignment(.center)

                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(value.wrappedValue < range.upperBound ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

func householdSummary(adults: Int, children: Int) -> String {
    let total = adults + children
    let peopleWord = total == 1 ? t("ob.step1.person") : t("ob.step1.people")
    let adultsWord = t("ob.step1.adults")
    let childStr: String

    if children == 0 {
        childStr = t("ob.step1.noChildren")
    } else {
        childStr = "\(children) \(t("ob.step1.children").lowercased())"
    }

    return "\(total) \(peopleWord.lowercased()) · \(adults) \(adultsWord.lowercased()) · \(childStr)"
}

struct FamilyMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("user.adultsCount") private var storedAdults = 1
    @AppStorage("user.childrenCount") private var storedChildren = 0

    @State private var adults = 1
    @State private var children = 0
    @State private var didLoadStoredValues = false
    private let regularContentMaxWidth: CGFloat = 1100
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegularLayout {
                regularFamilyMembersView
            } else {
                familyMembersForm
                    .navigationTitle(t("settings.familyMembers"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("common.save")) {
                                saveAndDismiss()
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
        }
        .onAppear {
            guard !didLoadStoredValues else { return }
            adults = max(storedAdults, 1)
            children = max(storedChildren, 0)
            didLoadStoredValues = true
        }
    }

    private var familyMembersForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("settings.familyMembers"), systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(t("ob.step1.heroSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section {
                HouseholdCompositionEditor(adults: $adults, children: $children)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listSectionSpacing(.compact)
    }

    private var regularFamilyMembersView: some View {
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

                        Text(t("settings.familyMembers"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button(t("common.save")) {
                            saveAndDismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))

                    familyMembersForm
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func saveAndDismiss() {
        storedAdults = adults
        storedChildren = children
        dismiss()
    }
}
