/// Arrow-key menu selector abstraction.
///
/// Concrete implementations:
///   - `TermiosSelectUI`  — pure Swift, zero dependencies (default)
///   - `FuzzySelectUI`    — future fuzzy-search integration stub
protocol SelectUI: Sendable {
    /// Present an interactive menu and return the 0-based index of the chosen item,
    /// or `nil` if the user cancelled (ESC / q).
    func select(prompt: String, items: [String]) throws -> Int?
}
