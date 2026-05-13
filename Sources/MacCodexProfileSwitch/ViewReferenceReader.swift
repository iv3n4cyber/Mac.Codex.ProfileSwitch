import AppKit
import SwiftUI

struct ViewReferenceReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> ReporterView {
        ReporterView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveIfAttached()
    }

    final class ReporterView: NSView {
        var onResolve: (NSView) -> Void

        init(onResolve: @escaping (NSView) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveIfAttached()
        }

        override func layout() {
            super.layout()
            resolveIfAttached()
        }

        func resolveIfAttached() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onResolve(self)
            }
        }
    }
}

