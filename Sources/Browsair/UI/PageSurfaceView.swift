import AppKit
import SwiftUI

struct PageSurfaceView: View {
    @ObservedObject var tab: TabModel
    @ObservedObject var session: BrowserSession

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if tab.isStartPage {
                    NewTabView(session: session, tab: tab)
                } else if let image = tab.frameImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tab.isLoading {
                    ProgressView("Loading…")
                } else {
                    Text("No frame yet")
                        .foregroundStyle(.secondary)
                }

                if let error = tab.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .padding(8)
                            .background(.red.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let point = mapPoint(value.location, in: geo.size, image: tab.frameImage)
                    session.handleClick(at: point)
                }
            )
            .onAppear {
                session.updateViewport(
                    width: geo.size.width,
                    height: geo.size.height,
                    scale: NSScreen.main?.backingScaleFactor ?? 2
                )
            }
            .onChange(of: geo.size) { _, newSize in
                session.updateViewport(
                    width: newSize.width,
                    height: newSize.height,
                    scale: NSScreen.main?.backingScaleFactor ?? 2
                )
            }
            .background(ScrollWheelCatcher { delta, location in
                let point = mapPoint(location, in: geo.size, image: tab.frameImage)
                session.handleScroll(deltaY: delta, at: point)
            })
        }
        .focusable()
        .onKeyPress { keyPress in
            let chars = String(keyPress.characters)
            let key = chars.isEmpty ? keyPress.key.character.description : chars
            session.handleKey(
                characters: chars,
                key: key,
                code: key,
                modifiers: 0,
                isDown: true
            )
            session.handleKey(
                characters: chars,
                key: key,
                code: key,
                modifiers: 0,
                isDown: false
            )
            return .handled
        }
    }

    private func mapPoint(_ location: CGPoint, in viewSize: CGSize, image: NSImage?) -> CGPoint {
        guard let image else { return location }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return location }

        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawnW = imageSize.width * scale
        let drawnH = imageSize.height * scale
        let originX = (viewSize.width - drawnW) / 2
        let originY = (viewSize.height - drawnH) / 2

        let x = (location.x - originX) / scale
        let y = (location.y - originY) / scale
        return CGPoint(
            x: min(max(x, 0), imageSize.width),
            y: min(max(y, 0), imageSize.height)
        )
    }
}

/// Captures scroll wheel events that SwiftUI gestures often miss.
private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class ScrollCatcherView: NSView {
    var onScroll: ((CGFloat, CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // SwiftUI Y grows down; AppKit Y grows up — convert.
        let flipped = CGPoint(x: location.x, y: bounds.height - location.y)
        onScroll?(event.scrollingDeltaY, flipped)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Transparent to clicks; PageSurfaceView gesture handles those.
        nil
    }
}
