import SwiftUI
import UIKit

/// Native pinch/pan zoom. Map buttons are the zooming content, so hits stay on the drawn shapes.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    var identity: String
    var contentSize: CGSize
    var minimumZoomScale: CGFloat = 1
    var focusRect: CGRect?
    @Binding var isZoomed: Bool
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = minimumZoomScale
        scroll.maximumZoomScale = 10
        scroll.bouncesZoom = true
        scroll.bounces = true
        scroll.alwaysBounceVertical = true
        scroll.alwaysBounceHorizontal = true
        scroll.decelerationRate = .fast
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
        host.view.autoresizingMask = []
        scroll.addSubview(host.view)

        context.coordinator.host = host
        context.coordinator.scroll = scroll
        context.coordinator.isZoomed = $isZoomed

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleFloorplanDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isZoomed = $isZoomed
        coordinator.host?.rootView = content()

        let size = CGSize(width: max(contentSize.width, 1), height: max(contentSize.height, 1))
        let minZoom = max(minimumZoomScale, 0.05)
        if abs(scroll.minimumZoomScale - minZoom) > 0.001 {
            scroll.minimumZoomScale = minZoom
        }
        let atIdentityZoom = abs(scroll.zoomScale - 1) < 0.03

        if coordinator.identity != identity {
            let previousFocus = coordinator.lastFocus
            coordinator.identity = identity
            coordinator.lastFocus = nil
            UIView.animate(withDuration: 0.36, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                scroll.zoomScale = 1
                scroll.contentOffset = .zero
            }
            if let host = coordinator.host {
                host.view.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
            }
            coordinator.isZoomed?.wrappedValue = false
            // Reset zoom used to nil lastFocus, then immediately zoom back to the same room.
            if let focusRect, focusRect == previousFocus {
                coordinator.lastFocus = focusRect
            }
        } else if atIdentityZoom, let host = coordinator.host {
            host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
        }

        if let focusRect, focusRect.width > 4, focusRect.height > 4, focusRect != coordinator.lastFocus {
            coordinator.lastFocus = focusRect
            let padded = focusRect.insetBy(dx: -focusRect.width * 0.4, dy: -focusRect.height * 0.4)
            DispatchQueue.main.async {
                scroll.zoom(to: padded, animated: true)
            }
        } else if focusRect == nil, coordinator.lastFocus != nil {
            // Leaving a focused room must zoom back out; pinch zoom is left alone.
            coordinator.lastFocus = nil
            UIView.animate(withDuration: 0.36, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                scroll.zoomScale = 1
                scroll.contentOffset = .zero
            }
            coordinator.isZoomed?.wrappedValue = false
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<Content>?
        weak var scroll: UIScrollView?
        var identity = ""
        var lastFocus: CGRect?
        var isZoomed: Binding<Bool>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            isZoomed?.wrappedValue = scrollView.zoomScale > max(scrollView.minimumZoomScale, 1) * 1.05
            centerContent(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZoomed?.wrappedValue = scale > max(scrollView.minimumZoomScale, 1) * 1.05
        }

        func centerContent(in scrollView: UIScrollView) {
            guard let view = host?.view else { return }
            let extraX = max((scrollView.bounds.width - view.frame.width) / 2, 0)
            let extraY = max((scrollView.bounds.height - view.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: extraY, left: extraX, bottom: extraY, right: extraX)
        }

        @objc func handleFloorplanDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll, let host else { return }
            if scroll.zoomScale > 1.15 {
                scroll.setZoomScale(1, animated: true)
                return
            }
            let point = gesture.location(in: host.view)
            let size = scroll.bounds.size
            let zoom: CGFloat = 3.4
            let rect = CGRect(
                x: point.x - size.width / (2 * zoom),
                y: point.y - size.height / (2 * zoom),
                width: size.width / zoom,
                height: size.height / zoom
            )
            scroll.zoom(to: rect, animated: true)
        }
    }
}
