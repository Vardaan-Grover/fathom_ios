import SwiftUI

struct BookFilterSheet: View {
    @ObservedObject var viewModel: VocabularyTabViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: 0) {
            sheetHandle
            sheetHeader
            Divider().opacity(0.4)
            filterList
        }
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var sheetHeader: some View {
        HStack {
            Text("Filter by Book").font(theme.typography.headline)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var filterList: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterRow(option: .all)
                ForEach(viewModel.availableBooks) { option in filterRow(option: option) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func filterRow(option: BookFilterOption) -> some View {
        let isSelected = viewModel.selectedBookFilter == option.id
        return Button {
            viewModel.selectedBookFilter = option.id
            dismiss()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                Text(option.title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primary)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SpringPressStyle())
    }
}
