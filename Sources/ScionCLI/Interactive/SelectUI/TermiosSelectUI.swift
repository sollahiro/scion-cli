import Foundation
import Darwin

/// Pure-Swift termios arrow-key menu selector.
/// No external dependencies — works anywhere Swift runs on Darwin.
struct TermiosSelectUI: SelectUI {

    // MARK: - Public

    func select(prompt: String, items: [String]) throws -> Int? {
        guard !items.isEmpty else { return nil }

        print(prompt)
        var selected = 0

        var oldTerm = termios()
        tcgetattr(STDIN_FILENO, &oldTerm)
        var raw = oldTerm
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        setCC(&raw, index: VMIN,  value: 1)
        setCC(&raw, index: VTIME, value: 0)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        printEsc("[?25l")   // hide cursor

        defer {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldTerm)
            printEsc("[?25h")   // show cursor
        }

        renderItems(items, selected: selected)

        while true {
            switch readKey(raw: raw) {
            case .up:
                selected = selected > 0 ? selected - 1 : items.count - 1
                moveUp(items.count)
                renderItems(items, selected: selected)
            case .down:
                selected = selected < items.count - 1 ? selected + 1 : 0
                moveUp(items.count)
                renderItems(items, selected: selected)
            case .enter:
                clearLines(items.count)
                return selected
            case .escape, .quit:
                clearLines(items.count)
                return nil
            case .other:
                break
            }
        }
    }

    // MARK: - Key Reading

    private enum KeyPress { case up, down, enter, escape, quit, other }

    private func readKey(raw: termios) -> KeyPress {
        var c: UInt8 = 0
        _ = Darwin.read(STDIN_FILENO, &c, 1)
        switch c {
        case 13, 10:                 return .enter
        case 27:                     return readEscapeSequence(raw: raw)
        case UInt8(ascii: "k"):      return .up
        case UInt8(ascii: "j"):      return .down
        case UInt8(ascii: "q"):      return .quit
        default:                     return .other
        }
    }

    /// Read the rest of a CSI escape sequence, with a short timeout so lone ESC works.
    private func readEscapeSequence(raw: termios) -> KeyPress {
        var nb = raw
        setCC(&nb, index: VMIN,  value: 0)
        setCC(&nb, index: VTIME, value: 1)  // 100 ms
        tcsetattr(STDIN_FILENO, TCSANOW, &nb)

        var seq = [UInt8](repeating: 0, count: 2)
        let n = Darwin.read(STDIN_FILENO, &seq, 2)

        var restore = raw
        tcsetattr(STDIN_FILENO, TCSANOW, &restore)

        guard n == 2, seq[0] == UInt8(ascii: "[") else { return .escape }
        switch seq[1] {
        case UInt8(ascii: "A"): return .up
        case UInt8(ascii: "B"): return .down
        default:                return .other
        }
    }

    // MARK: - Rendering

    private func renderItems(_ items: [String], selected: Int) {
        for (i, item) in items.enumerated() {
            // Clear the line first, then print
            Swift.print("\u{1B}[2K", terminator: "")
            if i == selected {
                Swift.print("  \u{1B}[38;2;1;103;236m▶\u{1B}[0m \u{1B}[1m\(item)\u{1B}[0m")
            } else {
                Swift.print("    \(item)")
            }
        }
        fflush(stdout)
    }

    private func moveUp(_ n: Int) {
        guard n > 0 else { return }
        printEsc("[\(n)A")
    }

    private func clearLines(_ n: Int) {
        guard n > 0 else { return }
        printEsc("[\(n)A")
        for _ in 0..<n { Swift.print("\u{1B}[2K") }
        printEsc("[\(n)A")
    }

    // MARK: - Helpers

    private func printEsc(_ code: String) {
        Swift.print("\u{1B}\(code)", terminator: "")
        fflush(stdout)
    }

    private func setCC(_ t: inout termios, index: Int32, value: cc_t) {
        withUnsafeMutableBytes(of: &t.c_cc) { $0[Int(index)] = value }
    }
}
