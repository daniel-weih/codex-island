import SwiftUI

/// One field appearance for the app's selectors, including open/hover/focus.
struct IslandPickerSurface: ViewModifier {
    let theme: IslandColorTheme
    let isActive: Bool
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.accent.opacity(isActive ? 0.12 : 0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.accent.opacity(isActive ? 0.18 : 0.10),
                                      lineWidth: 1 / max(1, displayScale))
                }
        }
    }
}

struct IslandPickerLabel: View {
    let title: String
    let systemImage: String
    let theme: IslandColorTheme
    let isPresented: Bool
    var isHovered = false
    var height: CGFloat = 28
    private var isActive: Bool { isHovered || isPresented }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 1)
            Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.58)
        }
        .foregroundStyle(theme.accent.opacity(isActive ? 0.90 : 0.72))
        .padding(.horizontal, 7)
        .frame(height: height)
        .modifier(IslandPickerSurface(theme: theme, isActive: isActive))
    }
}

/// Shared by the display, model, and interval pickers so menus stay opaque and use
/// the selected theme instead of the system menu's material and blue tint.
struct IslandSelectionMenuStyle: ViewModifier {
    static let rowHeight: CGFloat = 24
    static let spacing: CGFloat = 1
    static let inset: CGFloat = 3
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .padding(Self.inset)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.028, blue: 0.036))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 1 / max(1, displayScale))
            )
            .shadow(color: .black.opacity(0.62), radius: 5, y: 2)
    }
}

struct IslandSelectionMenuLabel: View {
    let title: String
    let isSelected: Bool
    let theme: IslandColorTheme
    var isAvailable = true
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? theme.accent.opacity(0.86) : .white.opacity(0.18))
                .frame(width: 8)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isAvailable ? 0.72 : 0.45))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: IslandSelectionMenuStyle.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.accent.opacity(isHighlighted ? 0.09 : 0))
        )
        .contentShape(Rectangle())
    }
}
