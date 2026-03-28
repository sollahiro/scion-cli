/// Stub for a future fuzzy-search selector (e.g., fzf / custom incremental search).
///
/// When a fuzzy implementation is ready, replace the body of `select(prompt:items:)`
/// with the real logic. `TermiosSelectUI` acts as the fallback until then.
struct FuzzySelectUI: SelectUI {
    private let fallback = TermiosSelectUI()

    func select(prompt: String, items: [String]) throws -> Int? {
        // TODO: implement fuzzy search (fzf or native) and remove fallback
        try fallback.select(prompt: prompt, items: items)
    }
}
