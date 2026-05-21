import SwiftUI

/// Vakter's design system, v1.2 — a **thin layer over Apple's native
/// system tokens**, not a replacement for them.
///
/// **What this means in practice**
///   - Semantic colours (`accent`, `healthy`, `alarm`, `watch`) wire
///     directly to `NSColor` system tints (controlAccent, systemGreen,
///     systemRed, systemBlue). Vakter inherits the user's macOS Accent
///     Colour choice, follows Increase Contrast / Reduce Transparency
///     accessibility flags, and renders correctly in light / dark /
///     vibrant contexts for free.
///   - Brand colours (`anchor` navy, `lantern` amber) appear ONLY in
///     marketing surfaces: the lighthouse glyph, the onboarding hero,
///     the arming overlay. Never on buttons, status pills, or list
///     selections — those use system tints so they match the rest of
///     the user's Mac.
///   - Typography is SF Pro at exactly 4 sizes: 13 body / 15 emphasis
///     / 22 title / 34 display. Same as macOS System Settings. No SF
///     Rounded except for the brand wordmark (kept as a brand asset).
///   - Spacing is anchored to the macOS 4-pt baseline grid: 4, 8, 12,
///     20, 28, 40. These are the gutters Apple uses in System Settings
///     forms.
///
/// Pre-v1.2 Vakter shipped a fully-custom palette + bespoke wordmark
/// + non-grid spacing. It read as "competent indie 2024." This rewrite
/// shifts the look to match macOS Sequoia's house style while keeping
/// the brand-defining lighthouse mark intact.
enum VakterDesign {

    // MARK: - Semantic colours (wired to Apple's system tints)
    //
    // These are the colours you use for buttons, list selections, status
    // pills, and any UI affordance that needs to feel native. They
    // adapt to:
    //   - the user's macOS Accent Colour choice
    //   - the user's Highlight Colour choice
    //   - Light / Dark / Vibrant appearance
    //   - Increase Contrast / Reduce Transparency accessibility flags
    // All of which the brand colours below cannot do.

    /// Primary semantic accent — Apple's controlAccentColor. Follows
    /// the user's "Accent Colour" choice in System Settings → Appearance.
    /// Use this for primary actions, selection highlights, focus rings.
    static let accent = Color(nsColor: .controlAccentColor)

    /// Healthy / "all clear" — Apple's `systemGreen`. Same tint as
    /// macOS's own success states (Find My green dot, password-strong
    /// indicator). Looks right in every appearance.
    static let healthy = Color(nsColor: .systemGreen)

    /// Watching / armed-state — Apple's `systemBlue`. Lower-stakes than
    /// the alarm red; matches the macOS Lock Screen accent.
    static let watch = Color(nsColor: .systemBlue)

    /// Alarm — Apple's `systemRed`. The exact red Apple uses for
    /// delete actions and battery-low warnings, so it carries the
    /// existing semantic weight without us inventing a new "Vakter red."
    static let alarm = Color(nsColor: .systemRed)

    /// Warning — Apple's `systemOrange`. For the Defenses checklist
    /// "could be better but not broken" rows.
    static let warning = Color(nsColor: .systemOrange)

    // MARK: - Brand colours (use sparingly, marketing only)
    //
    // These are the deep navy + warm amber of the Vakter wordmark and
    // lighthouse glyph. They appear in EXACTLY four places:
    //   1. The lighthouse silhouette (LighthouseGlyph)
    //   2. The onboarding welcome hero
    //   3. The arming overlay caption + lantern halo
    //   4. The About tab
    // Everywhere else uses the semantic colours above.

    /// Deep navy "anchor watch" — the dark fjord under a clear sky.
    /// Brand only. For UI affordances use `.accent`.
    static let anchor = Color(red: 0.10, green: 0.20, blue: 0.36)

    /// Appearance-adapting anchor: navy on light, moonlight blue-white
    /// on dark. Used by the menubar lighthouse glyph so it stays
    /// visible on both menubar backgrounds.
    static let anchorAdaptive = Color(
        NSColor(name: "VakterAnchorAdaptive") { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil {
                return NSColor(red: 0.78, green: 0.86, blue: 0.96, alpha: 1.0)
            }
            return NSColor(red: 0.10, green: 0.20, blue: 0.36, alpha: 1.0)
        }
    )

    /// Appearance-adapting watch — the in-grace menubar state.
    static let watchAdaptive = Color(
        NSColor(name: "VakterWatchAdaptive") { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil {
                return NSColor(red: 0.70, green: 0.80, blue: 0.92, alpha: 1.0)
            }
            return NSColor(red: 0.46, green: 0.56, blue: 0.72, alpha: 1.0)
        }
    )

    /// Warm amber "lantern" — the watchman's lantern, the lighthouse
    /// beam at sunset. Brand-only complement to `anchor`. Appears in
    /// the arming overlay halo and the lighthouse glyph's lamp.
    static let lantern = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let lanternSoft = Color(red: 0.95, green: 0.78, blue: 0.45)

    /// Warm ivory base for marketing surfaces. Subtle off-white that
    /// suggests reassurance. NOT a UI fill — use system control colours
    /// (`.controlBackgroundColor`, `.windowBackgroundColor`) for that.
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)

    /// Legacy aliases. Kept for one release so existing call sites
    /// don't have to update in lockstep with this rewrite. New code
    /// should use the semantic colours above instead.
    static let anchorSecondary = anchor.opacity(0.7)

    /// A subtle navy → slate-blue gradient used for armed-state surfaces
    /// (the arming overlay, the brand-mark glow, etc.). Diagonal flow
    /// from top-leading (navy) to bottom-trailing (slate-blue).
    static let anchorGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.16, blue: 0.30),
            Color(red: 0.20, green: 0.32, blue: 0.50)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A coral-into-deep-coral gradient for alarm visuals.
    static let alarmGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.45, blue: 0.38),
            Color(red: 0.78, green: 0.28, blue: 0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm-light gradient — used as the lantern halo behind the
    /// lighthouse beam in hero contexts (onboarding welcome, About
    /// tab, app icon).
    static let lanternGradient = RadialGradient(
        colors: [
            Color(red: 0.98, green: 0.82, blue: 0.45),
            Color(red: 0.85, green: 0.55, blue: 0.18).opacity(0.0)
        ],
        center: .center,
        startRadius: 4,
        endRadius: 200
    )

    // MARK: - Spacing — macOS 4-pt baseline grid
    //
    // Anchored to the multiples Apple uses in System Settings forms.
    // The "L = 20" and "XL = 28" gutters are the gold standard for
    // section padding in macOS Sequoia. Don't invent new spacings
    // outside this scale.

    static let spacingXS: CGFloat = 4    // inline icon-to-text gap
    static let spacingS: CGFloat  = 8    // tight vertical rhythm
    static let spacingM: CGFloat  = 12   // form-row vertical
    static let spacingL: CGFloat  = 20   // section padding
    static let spacingXL: CGFloat = 28   // tab content padding
    static let spacing2XL: CGFloat = 40  // hero / onboarding only

    // MARK: - Radius scale

    /// Mathematical progression: 4 → 6 → 12 → 18 → 28 → 40
    /// Matches the curvature Apple uses on Mac controls (6 for
    /// buttons, 10 for cards, 18 for groupboxes).
    static let radiusXS: CGFloat = 4
    static let radiusS: CGFloat  = 6
    static let radiusM: CGFloat  = 10
    static let radiusL: CGFloat  = 18
    static let radiusXL: CGFloat = 28
    static let radius2XL: CGFloat = 40

    // MARK: - Typography — SF Pro at macOS-native sizes
    //
    // The four sizes that appear in every modern Mac app. We add a SF
    // Rounded wordmark for the brand mark and SF Mono variants for
    // shortcuts / monospaced data. No serif anywhere. No additional
    // sizes — if you need something different, you're inventing
    // hierarchy that doesn't belong in a polished macOS app.

    /// Brand wordmark — SF Rounded, semibold. The ONE place SF Rounded
    /// appears: the "Vakter" wordmark in onboarding + About. Treat as
    /// a logo asset, not a typographic style.
    static let wordmark       = Font.system(size: 30, weight: .semibold, design: .rounded)

    /// Display — onboarding hero ("Welcome to Vakter"), About hero,
    /// arming overlay "On watch". 34 pt matches macOS System Settings.
    static let displayLarge   = Font.system(size: 34, weight: .semibold)

    /// Title — Settings page H1 ("Sound", "Modes"). 22 pt matches
    /// the System Settings tab content title.
    static let titleFont      = Font.system(size: 22, weight: .semibold)

    /// Section header — inset list group titles. 15 pt semibold.
    static let sectionTitle   = Font.system(size: 15, weight: .semibold)

    /// Body — paragraph text, list rows, button labels. 13 pt regular
    /// is macOS's default for body content; matches System Settings.
    static let bodyFont       = Font.system(size: 13, weight: .regular)

    /// Caption — secondary helper text under a control, status pills.
    /// 11 pt with `.secondary` foregroundStyle is the macOS standard
    /// for "this is a hint, not the primary content."
    static let captionFont    = Font.system(size: 11, weight: .regular)

    /// All-caps eyebrow — sidebar section headers ("TODAY", "TRUSTED").
    /// Use with `.kerning(0.8)` and `.textCase(.uppercase)`.
    static let eyebrow        = Font.system(size: 11, weight: .semibold)

    /// Mono — keyboard shortcuts, timing readouts. 15 pt semibold.
    static let monoEmphasized = Font.system(size: 15, weight: .semibold, design: .monospaced)

    /// Mono small — UUIDs, version strings, log snippets.
    static let monoCaption    = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Tabular numeric — for column-aligned stats (scores, counts).
    static let tabularLarge   = Font.system(size: 30, weight: .semibold)
        .monospacedDigit()

    // MARK: - Motion

    /// 0.18s — instant feedback. Selection bounces, tap highlights, chip
    /// toggle. Snaps into place; the user feels the click.
    static let easeSnappy = Animation.spring(response: 0.18, dampingFraction: 0.85)

    /// 0.32s — the workhorse curve for most state transitions. Smooth
    /// enough to feel intentional, fast enough to feel responsive.
    static let easeStandard = Animation.spring(response: 0.32, dampingFraction: 0.78)

    /// 0.60s — gentle, breath-like. Hero animations, ambient pulses,
    /// onboarding step transitions.
    static let easeGentle = Animation.spring(response: 0.60, dampingFraction: 0.80)

    /// Selection cards (mode picker, sound picker) — bouncy when tapped.
    static let springTactile = Animation.spring(response: 0.35, dampingFraction: 0.65)
}

// MARK: - Reusable building blocks

/// macOS-native inset group, with an optional subtitle.
///
/// **v1.2 redesign:** dropped the heavy border + drop-shadow card
/// look that was reading "Web admin dashboard 2022." Now uses Apple's
/// `GroupBox`-style inset: a single fill, no border, generous breathing
/// room. The header sits OUTSIDE the box (Apple's pattern in System
/// Settings — "Display", "Network", etc.) so the visual weight is on
/// the content, not the chrome.
///
/// If you need the legacy bordered card (e.g. a sidebar status block
/// where the border IS the affordance), set `bordered: true`.
struct VakterCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let bordered: Bool
    @ViewBuilder var content: Content

    init(title: String,
         subtitle: String? = nil,
         bordered: Bool = false,
         @ViewBuilder content: () -> Content)
    {
        self.title = title
        self.subtitle = subtitle
        self.bordered = bordered
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            // Header lives OUTSIDE the box — Apple's pattern in
            // System Settings forms ("Display" then a boxed group of
            // controls under it).
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VakterDesign.sectionTitle)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(VakterDesign.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
                .padding(VakterDesign.spacingL)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    bordered
                        ? RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        : nil
                )
        }
    }
}

/// Subtle status pill. Used for "Helper: enabled" / "On watch" /
/// "Touch ID enrolled" badges.
///
/// **v1.2:** tone colours wire to the new `VakterDesign.healthy/.watch/
/// .alarm` semantic tokens, which are themselves `NSColor.system*`. So
/// pills now match Apple's own status colours throughout System
/// Settings — same green-tint, same red-tint, same blue-tint.
struct VakterStatusPill: View {
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
        HStack(spacing: VakterDesign.spacingXS + 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(Capsule().fill(background))
    }

    private var background: Color {
        switch tone {
        case .neutral:   return Color.primary.opacity(0.07)
        case .healthy:   return VakterDesign.healthy.opacity(0.15)
        case .watching:  return VakterDesign.watch.opacity(0.15)
        case .attention: return VakterDesign.alarm.opacity(0.15)
        }
    }
    private var foreground: Color {
        switch tone {
        case .neutral:   return .secondary
        case .healthy:   return VakterDesign.healthy
        case .watching:  return VakterDesign.watch
        case .attention: return VakterDesign.alarm
        }
    }
}

/// A polished selection card used for picking modes.
struct VakterSelectableCard<Trailing: View>: View {
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
            HStack(spacing: VakterDesign.spacingM) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? VakterDesign.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(
                            isSelected
                                ? VakterDesign.accent.opacity(0.15)
                                : Color.primary.opacity(0.05)
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? VakterDesign.accent : Color.primary.opacity(0.25))
            }
            .padding(.horizontal, VakterDesign.spacingM)
            .padding(.vertical, VakterDesign.spacingS + 2)
            .background(
                RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                    .fill(isSelected
                          ? VakterDesign.accent.opacity(0.07)
                          : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? VakterDesign.accent.opacity(0.5)
                            : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .animation(VakterDesign.springTactile, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// All-caps eyebrow label — used above section groups to convey hierarchy
/// without consuming the precious "title" font slot.
struct VakterEyebrow: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(VakterDesign.eyebrow)
            .kerning(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
