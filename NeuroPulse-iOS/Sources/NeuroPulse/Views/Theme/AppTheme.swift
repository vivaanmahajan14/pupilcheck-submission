import SwiftUI

/// Shared styling modifiers and visual elements for NeuroPulse.
public struct ClinicalCardModifier: ViewModifier {
    public var borderColor: Color = NeuroPulseColor.borderSlate
    public var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(NeuroPulseColor.cardSlate)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

public struct GlowingButtonModifier: ViewModifier {
    public var color: Color = NeuroPulseColor.trackingAccent

    public func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(NeuroPulseColor.obsidianBase)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: color.opacity(0.35), radius: 12, x: 0, y: 4)
    }
}

extension View {
    public func clinicalCard(borderColor: Color = NeuroPulseColor.borderSlate, cornerRadius: CGFloat = 16) -> some View {
        self.modifier(ClinicalCardModifier(borderColor: borderColor, cornerRadius: cornerRadius))
    }

    public func glowingButton(color: Color = NeuroPulseColor.trackingAccent) -> some View {
        self.modifier(GlowingButtonModifier(color: color))
    }

    @ViewBuilder
    public func navigationInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    public func examPresentationCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

/// Quiet surface shared by setup, roster, and result cards.
struct AppSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NeuroPulseColor.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NeuroPulseColor.pantoneBlue.opacity(0.10), lineWidth: 1)
            }
    }
}

extension View {
    func appSurface() -> some View { modifier(AppSurface()) }
}

/// Keeps long labels and values readable at accessibility text sizes.
struct MeasurementRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.76))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// Shared by the home screen and the player's complete recording history.
struct RecordingSummaryRow: View {
    let record: SCAT6TriageResult
    let detail: String?
    let badgeColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.isBaselineTest ? "bookmark" : "waveform.path")
                .font(.body.weight(.semibold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .frame(width: 40, height: 40)
                .background(NeuroPulseColor.pantoneBlueSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.isBaselineTest ? "Baseline recording" : "Test session")
                    .font(.headline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.80))
                }
                Text(record.concussionBadgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.6))
                .padding(.top, 12)
                .accessibilityHidden(true)
        }
        .appSurface()
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
