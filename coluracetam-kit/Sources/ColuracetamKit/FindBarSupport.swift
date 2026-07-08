import AppKit
import SwiftUI

/// An `NSScrollView` that reports find-bar visibility changes.
///
/// `NSTextView` hosts its find bar in the enclosing scroll view (its
/// `NSTextFinderBarContainer`), so overriding the visibility setter is the one
/// place that sees *every* change — including the user closing the bar — which
/// the text view otherwise keeps to itself.
open class FindBarObservingScrollView: NSScrollView {
    public var onFindBarVisibilityChange: (@MainActor (Bool) -> Void)?

    override open var isFindBarVisible: Bool {
        get { super.isFindBarVisible }
        set {
            guard newValue != super.isFindBarVisible else { return }
            super.isFindBarVisible = newValue
            onFindBarVisibilityChange?(newValue)
        }
    }
}

/// Keeps a shared `isPresented` binding and a text view's actual find bar in
/// step, whichever side changes first: a toolbar button (or ⌘F menu item)
/// drives the bar through ``sync(_:in:)``, and changes AppKit makes itself —
/// most importantly the user dismissing the bar — flow back through
/// ``visibilityChanged(_:)``. The internal latch ensures neither path
/// re-issues a redundant show/hide.
public final class FindBarPresenter {
    /// The shared find state this presenter mirrors.
    public var isPresented: Binding<Bool>?
    private var shown = false

    public init() {}

    /// Drives the find bar from the shared state (toolbar button / ⌘F).
    public func sync(_ presented: Bool, in textView: NSTextView) {
        guard presented != shown else { return }
        shown = presented
        let item = NSMenuItem()
        item.tag = (
            presented ? NSTextFinder.Action.showFindInterface
                : NSTextFinder.Action.hideFindInterface
        ).rawValue
        DispatchQueue.main.async { textView.performTextFinderAction(item) }
    }

    /// Reports a visibility change AppKit made itself (e.g. the user pressing
    /// Escape) back into the shared state.
    public func visibilityChanged(_ visible: Bool) {
        guard visible != shown else { return }
        shown = visible
        if let binding = isPresented, binding.wrappedValue != visible {
            binding.wrappedValue = visible
        }
    }
}
