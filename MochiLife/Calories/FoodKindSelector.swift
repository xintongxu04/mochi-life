import SwiftUI

/// Picks a `FoodKind`: one flat row of five equal-width chips, each the kind's picture above its
/// name. One tap selects; the selected chip is filled with the accent tint. Used by quick entry,
/// the food form (manual and Add with AI) and editing a logged entry.
struct FoodKindSelector: View {
    @Binding var kind: FoodKind

    static let imageSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FoodKind.allCases, id: \.self) { option in
                let isSelected = option == kind
                Button {
                    kind = option
                } label: {
                    VStack(spacing: 4) {
                        Image(option.defaultImageName)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: Self.imageSize, height: Self.imageSize)
                            .accessibilityHidden(true)
                        Text(option.displayName)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.quaternary),
                                in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
                    }
                    .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind of food")
        .rowSeparatorAligned()
    }
}
