import Foundation

/// What a page drag carries and where it may land.
///
/// Kept out of the view so it can be tested: getting either rule wrong moves
/// pages the user never touched.
public enum PageDragRules {

    /// The pages a drag carries.
    ///
    /// The selection travels only when the drag starts on one of its pages.
    /// Starting on any other page drags that page alone, as in Finder.
    public static func pages(startingAt index: Int, selection: Set<Int>) -> Set<Int> {
        selection.contains(index) ? selection : [index]
    }

    /// Whether a drop may move pages.
    ///
    /// A drag carries page indices, which only mean something in the document
    /// they came from. Dropped on another window, they would rearrange that
    /// window's pages instead.
    public static func accepts(dragFrom source: UUID, into target: UUID) -> Bool {
        source == target
    }
}
