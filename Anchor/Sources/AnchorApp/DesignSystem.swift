import SwiftUI

/// Anchor's calm-protector design system.
///
/// The visual identity is the opposite of typical "security app" tropes
/// (red shields, military fonts, alarm-clock aesthetics). Anchor is a
/// confident, quiet companion — its UI should feel like a well-designed
/// thermostat, not a panic button.
///
/// Colour story:
///   - Deep navy "anchor" tone as the primary accent
///   - Warm ivory as the resting surface
///   - Single warm coral as the alarm/attention colour (used sparingly)
///   - System chrome (NSColor.windowBackgroundColor etc.) for outer
///     containers so we respect dark mode
///
/// Typography:
///   - SF Pro Display for headings
///   - SF Pro Rounded for the brand wordmark (subtle distinction)
///   - SF Mono for keyboard shortcuts and timing readouts
enum AnchorDesign {

    // MARK: Colours

    /// Primary brand accent. Deep, calm, marine.
    static let anchor = Color(red: 0.10, green: 0.20, blue: 0.36)

    /// Lighter version of anchor for hover/secondary surfaces.
    static let anchorSecondary = Color(red: 0.10, green: 0.20, blue: 0.36).opacity(0.7)

    /// Used only for active arming / alarm states.
    static let alarm = Color(red: 0.92, green: 0.40, blue: 0.34)

    /// Soft pale for armed / "watching" indication. Calm, not alarming.
    static let watch = Color(red: 0.46, green: 0.56, blue: 0.72)

    /// Calm green for "all systems healthy" indicators.
    static let healthy = Color(red: 0.30, green: 0.60, blue: 0.45)

    /// Warm ivory base. Subtle off-white that suggests reassurance.
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)

    // MARK: Spacing scale

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat  = 8
    static let spacingM: CGFloat  = 16
    static let spacingL: CGFloat  = 24
    static let spacingXL: CGFloat = 40

    // MARK: Radius scale

    static let radiusS: CGFloat = 6
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 18
    static let radiusXL: CGFloat = 28

    // MARK: Typography

    static let titleFont      = Font.system(size: 28, weight: .semibold, design: .default)
    static let sectionTitle   = Font.system(size: 17, weight: .semibold, design: .default)
    static let bodyFont       = Font.system(size: 13, weight: .regular, design: .default)
    static let captionFont    = Font.system(size: 11, weight: .regular, design: .default)
    static let monoEmphasized = Font.system(size: 15, weight: .semibold, design: .monospaced)
}

// MARK: - Reusable building blocks

/// A grouped settings card — replaces the plain VStack we had before.
struct AnchorCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnchorDesign.spacingM) {
            VStack(alignment: .leading, spacing: AnchorDesign.spacingXS) {
                Text(title)
                    .font(AnchorDesign.sectionTitle)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AnchorDesign.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(AnchorDesign.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A subtle status pill — used for showing the helper / daemon state
/// or "Anchor — armed (Travel mode)" badges.
struct AnchorStatusPill: View {
    enum Tone { case neutral, healthy, watching, attention }
    let tone: Tone
    let label: String
    let icon: String?

    init(_ label: String, tone: Tone = .neutral, icon: String? = nil) {
        self.label = label
        self.tone = tone
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: AnchorDesign.spacingS) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .foregroundStyle(foreground)
        .background(
            Capsule().fill(background)
        )
    }

    private var background: Color {
        switch tone {
        case .neutral:   return Color.primary.opacity(0.07)
        case .healthy:   return AnchorDesign.healthy.opacity(0.18)
        case .watching:  return AnchorDesign.watch.opacity(0.18)
        case .attention: return AnchorDesign.alarm.opacity(0.18)
        }
    }
    private var foreground: Color {
        switch tone {
        case .neutral:   return .primary
        case .healthy:   return AnchorDesign.healthy
        case .watching:  return AnchorDesign.watch
        case .attention: return AnchorDesign.alarm
        }
    }
}

/// A polished selection card used for picking modes.
struct AnchorSelectableCard<Trailing: View>: View {
    let title: String
    let blurb: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    @ViewBuilder let trailing: Trailing

    init(title: String, blurb: String, icon: String,
         isSelected: Bool, onTap: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.blurb = blurb
        self.icon = icon
        self.isSelected = isSelected
        self.onTap = onTap
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AnchorDesign.spacingM) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AnchorDesign.anchor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(
                            isSelected ?
                                AnchorDesign.anchor.opacity(0.12) :
                                Color.primary.opacity(0.05)
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(AnchorDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnchorDesign.anchor : Color.primary.opacity(0.2))
            }
            .padding(AnchorDesign.spacingM)
            .background(
                RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                    .fill(isSelected ?
                          AnchorDesign.anchor.opacity(0.05) :
                          Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                    .strokeBorder(
                        isSelected ?
                            AnchorDesign.anchor.opacity(0.4) :
                            Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
