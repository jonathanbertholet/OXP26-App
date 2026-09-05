import SwiftUI
import UIKit

/// Native pinch/pan with a centered resting position, including after resizing.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    var identity: String
    var contentSize: CGSize
    var minimumZoomScale: CGFloat = 1
    var focusRect: CGRect?
    @Binding var isZoomed: Bool
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FloorScrollView {
        let scroll = FloorScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 10
        scroll.bouncesZoom = true
        scroll.decelerationRate = .normal
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.safeAreaRegions = []
        host.sizingOptions = []
        scroll.addSubview(host.view)
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        scroll.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.centerContent()
        }
        // A double tap on empty floor space zooms; room buttons retain immediate taps.
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.oxpHandleMapDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: FloorScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isZoomed = $isZoomed
        coordinator.host?.rootView = content()
        scroll.minimumZoomScale = max(minimumZoomScale, 0.05)
        let size = CGSize(width: max(contentSize.width, 1), height: max(contentSize.height, 1))
        let resized = coordinator.contentSize != size
        let reset = coordinator.identity != identity || resized
        if reset {
            coordinator.focusGeneration += 1
            coordinator.identity = identity
            coordinator.contentSize = size
            coordinator.lastFocus = nil
            scroll.setZoomScale(scroll.minimumZoomScale, animated: false)
            // Set bounds and center, never a transformed frame.
            coordinator.host?.view.bounds = CGRect(origin: .zero, size: size)
            coordinator.host?.view.center = CGPoint(x: size.width / 2, y: size.height / 2)
            scroll.contentSize = size
            coordinator.centerContent()
            scroll.contentOffset = CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top)
            coordinator.publishZoomState()
        }
        if focusRect != coordinator.lastFocus {
            coordinator.lastFocus = focusRect
            coordinator.focusGeneration += 1
            let generation = coordinator.focusGeneration
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.focusGeneration == generation else { return }
                if let focusRect {
                    scroll.zoom(to: focusRect.insetBy(dx: -focusRect.width * 0.4, dy: -focusRect.height * 0.4),
                                animated: !UIAccessibility.isReduceMotionEnabled)
                } else {
                    scroll.setZoomScale(scroll.minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        weak var scroll: FloorScrollView?
        var identity = ""
        var contentSize = CGSize.zero
        var lastFocus: CGRect?
        var focusGeneration = 0
        var isZoomed: Binding<Bool>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            publishZoomState()
        }

        func publishZoomState() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scroll else { return }
                let zoomed = scroll.zoomScale > scroll.minimumZoomScale * 1.05
                if isZoomed?.wrappedValue != zoomed { isZoomed?.wrappedValue = zoomed }
            }
        }

        func centerContent() {
            guard let scroll, let view = host?.view else { return }
            let x = max((scroll.bounds.width - view.frame.width) / 2, 0)
            let y = max((scroll.bounds.height - view.frame.height) / 2, 0)
            let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
            if scroll.contentInset != inset { scroll.contentInset = inset }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view, current !== scroll {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        @objc func oxpHandleMapDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll, let host else { return }
            let animated = !UIAccessibility.isReduceMotionEnabled
            if scroll.zoomScale > scroll.minimumZoomScale * 1.15 {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: animated)
            } else {
                let point = gesture.location(in: host.view)
                let zoom = min(scroll.minimumZoomScale * 2.5, scroll.maximumZoomScale)
                let size = CGSize(width: scroll.bounds.width / zoom, height: scroll.bounds.height / zoom)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: animated)
            }
        }
    }
}

final class FloorScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
