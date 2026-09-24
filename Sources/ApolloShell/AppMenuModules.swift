import AppKit
import ApolloShellCore
import SwiftUI

// The blocks of the macOS template (spec topbar.md, "Entscheid 23.09.
// abends"): Apple's menu, the frontmost app's name and menus, and the other
// apps' status items - Apple's menu bar, drawn by the shell. Their models:
// `AppMenuModel`, `StatusItemsModel`.

// MARK: - Anchor

/// The AppKit view a menu opens below. SwiftUI buttons have none, and
/// `NSMenu.popUp` wants one; this one sits behind the title and lets every
/// click through.
@MainActor
final class MenuAnchorBox {
    weak var view: NSView?
}

struct MenuAnchor: NSViewRepresentable {
    let box: MenuAnchorBox

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        box.view = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        box.view = view
    }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A title in the menu bar: text or a symbol, lit while its menu is open or
/// the mouse is over it, as in Apple's bar.
private struct MenuBarTitle<Label: View>: View {
    let help: String
    var lit = false
    let action: @MainActor (NSView) -> Void
    @ViewBuilder let label: () -> Label
    @State private var box = MenuAnchorBox()
    @State private var hovering = false
    @Environment(\.barPreview) private var preview
    @Environment(\.barControlSize) private var size

    var body: some View {
        Button {
            if let view = box.view { action(view) }
        } label: {
            label()
                .padding(.horizontal, 7)
                .frame(minWidth: size, minHeight: size)
                .background(Color.primary.opacity(lit ? 0.18 : hovering ? 0.1 : 0), in: .rect(cornerRadius: 6))
                .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background {
            if !preview {
                MenuAnchor(box: box)
                HoverTracker { hovering = $0 }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Apple menu

/// The Apple menu of the frontmost app - every app serves its own copy.
struct BarAppleMenuModule: View {
    let model: AppMenuModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        MenuBarTitle(help: String(localized: "Apple Menu"), lit: model.openIndex == 0,
                     action: { model.open(index: 0, below: $0) }) {
            Image(systemName: "apple.logo")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(style.paint(.barIcon, or: .primary))
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }
}

// MARK: - App menu

/// The frontmost app's name in bold, then its menus. Along the menu bar it
/// takes the room it is given (`BarModuleKind.growsAlongMenuBar`) and
/// shows as many titles as fit, the rest behind "…" (`AppMenuCollapse`).
/// Across the sidebar: one button with every menu as a submenu.
struct BarAppMenuModule: View {
    let model: AppMenuModel
    @Environment(\.barAxis) private var axis
    @Environment(\.shellStyle) private var style
    @State private var hidden: [Int] = []

    var body: some View {
        Group {
            if axis == .horizontal {
                AppMenuRow(overflow: $hidden) {
                    title(model.appTitle, index: 1, bold: true)
                    ForEach(model.menuTitles, id: \.index) { entry in
                        title(entry.title, index: entry.index, bold: false)
                    }
                    MenuBarTitle(help: String(localized: "More Menus"), lit: false,
                                 action: { model.openOverflow(indices: hidden, below: $0) }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.barText)
                    }
                }
            } else {
                MenuBarTitle(help: model.appTitle, action: { view in
                    model.openOverflow(indices: Array(1..<max(model.titles.count, 2)), below: view)
                }) {
                    Image(systemName: "filemenu.and.selection")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(style.paint(.barIcon, or: .primary))
                }
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }

    private func title(_ text: String, index: Int, bold: Bool) -> some View {
        MenuBarTitle(help: text, lit: model.openIndex == index, action: { model.open(index: index, below: $0) }) {
            Text(text)
                .font(style.font(size: 13, weight: bold ? .bold : .regular))
                .foregroundStyle(style.barText)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The app's name, its menu titles and the "…" button - in that order as
/// subviews. Shows the name, as many titles as fit the width it is given,
/// and "…" only when some did not; the others are laid far outside, where
/// they can be neither seen nor clicked. Which ones fit is the core's
/// (`AppMenuCollapse`); the hidden menu indices go to `overflow` for the
/// "…" menu.
private struct AppMenuRow: Layout {
    @Binding var overflow: [Int]
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = proposal.height ?? sizes.map(\.height).max() ?? 0
        // Measured without a width: everything but "…".
        let natural = sizes.dropLast().reduce(0) { $0 + $1.width } + CGFloat(max(sizes.count - 2, 0)) * spacing
        guard let width = proposal.width else { return CGSize(width: natural, height: height) }
        return CGSize(width: min(width, natural), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let widths = subviews.map { Double($0.sizeThatFits(.unspecified).width) }
        let titles = Array(widths.dropFirst().dropLast())
        let fit = AppMenuCollapse.fit(available: Double(proposal.width ?? bounds.width), lead: widths[0],
                                      titles: titles, overflow: widths.last ?? 0, spacing: Double(spacing))
        var x = bounds.minX
        let away = CGPoint(x: -100_000, y: bounds.midY)
        for (index, subview) in subviews.enumerated() {
            let isOverflow = index == subviews.count - 1
            let shown = index == 0 || (isOverflow ? fit.overflow : index - 1 < fit.shown)
            if shown {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
                x += CGFloat(widths[index]) + spacing
            } else {
                subview.place(at: away, anchor: .leading, proposal: .unspecified)
            }
        }
        // Top-level indices of the hidden titles: the menu bar's 0 and 1 are
        // the Apple and app menus, the titles start at 2.
        let hidden = fit.overflow ? Array((fit.shown + 2)..<(titles.count + 2)) : []
        if hidden != overflow {
            DispatchQueue.main.async { overflow = hidden }
        }
    }
}

// MARK: - Status items

/// Other apps' status items, in Apple's order. Across the sidebar one below
/// the other.
struct BarStatusItemsModule: View {
    let model: StatusItemsModel
    @Environment(\.barAxis) private var axis
    @Environment(\.barControlSize) private var size
    @Environment(\.shellStyle) private var style

    var body: some View {
        axis.stack(spacing: 2) {
            ForEach(model.items) { item in
                MenuBarTitle(help: item.record.name.isEmpty ? String(localized: "Status Item") : item.record.name,
                             lit: model.openID == item.id, action: { model.click(item, below: $0) }) {
                    picture(item)
                }
            }
        }
        .onAppear { model.acquire() }
        .onDisappear { model.release() }
    }

    @ViewBuilder
    private func picture(_ item: StatusItemsModel.Item) -> some View {
        if let image = item.image {
            // At Apple's size, but never taller than our bar.
            let height = min(image.size.height, size)
            let width = image.size.height > 0 ? image.size.width * height / image.size.height : height
            Image(nsImage: image)
                .renderingMode(item.template ? .template : .original)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .foregroundStyle(style.paint(.barIcon, or: .primary))
                .padding(.horizontal, -7)
        } else if !item.record.title.isEmpty {
            Text(item.record.title)
                .font(style.font(size: 13))
                .foregroundStyle(style.barText)
                .lineLimit(1)
                .fixedSize()
        } else if let icon = item.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.paint(.barIcon, or: .primary))
        }
    }
}
