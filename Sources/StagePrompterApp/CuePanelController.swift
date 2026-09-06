import AppKit
import SwiftUI

@MainActor
final class CuePanelController {
    private var panel: NSPanel?

    func show(model: AppModel) {
        let panel = panel ?? makePanel(model: model)
        if panel.parent != nil {
            panel.parent?.removeChildWindow(panel)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let size = NSSize(width: 520, height: 150)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 36
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Smart Prompter Cue"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = false
        panel.minSize = NSSize(width: 280, height: 90)
        panel.maxSize = NSSize(width: 1_200, height: 600)
        panel.setFrameAutosaveName("StagePrompterCuePanel")
        panel.contentView = NSHostingView(
            rootView: CuePanelView(model: model) { [weak self] in
                self?.hide()
            }
        )
        NSApp.addWindowsItem(panel, title: "Cue Panel", filename: false)
        self.panel = panel
        return panel
    }
}

private struct CuePanelView: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.mint)
                Text(model.suggestionLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide cue")
                .accessibilityLabel("Hide cue")
            }

            ScrollView(.vertical) {
                Text(model.suggestion)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.64))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.mint.opacity(0.42), lineWidth: 1)
                }
        }
        .padding(8)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
                .padding(14)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }
}
