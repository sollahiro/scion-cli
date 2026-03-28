import Foundation

struct InteractiveShell {
    func run() async throws {
        printLogo()
        print("対話モード  ('help' でヘルプ, 'quit' で終了)")
        print()

        while true {
            print("scion> ", terminator: "")
            fflush(stdout)

            guard let line = readLine() else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed == "quit" || trimmed == "exit" {
                print("終了します。")
                break
            }

            let args = shellSplit(trimmed)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["scion"] + args
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                fputs("エラー: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - Logo

    private func printLogo() {
        let T = true, F = false

        // 7行 × 各幅 のピクセルグリッド（S・C・I・O・N）
        let glyphs: [[[Bool]]] = [
            // S
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,F],
             [F,T,T,T,F],
             [F,F,F,F,T],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // C
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,F],
             [T,F,F,F,F],
             [T,F,F,F,F],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // I
            [[T,T,T],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [F,T,F],
             [T,T,T]],
            // O
            [[F,T,T,T,F],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [F,T,T,T,F]],
            // N
            [[T,F,F,F,T],
             [T,T,F,F,T],
             [T,F,T,F,T],
             [T,F,F,T,T],
             [T,F,F,F,T],
             [T,F,F,F,T],
             [T,F,F,F,T]],
        ]

        let spacing  = 1   // 文字間スペース
        let shadowDX = 1   // 影のX方向オフセット
        let shadowDY = 1   // 影のY方向オフセット
        let rows     = 7

        // キャンバスサイズ計算
        let faceWidth = glyphs.reduce(0) { $0 + $1[0].count } + spacing * (glyphs.count - 1)
        let canvasW   = faceWidth + shadowDX
        let canvasH   = rows      + shadowDY

        // 0=空, 1=影のみ, 2=面（優先）
        var canvas = Array(repeating: Array(repeating: 0, count: canvasW), count: canvasH)

        var x0 = 0
        for glyph in glyphs {
            let gw = glyph[0].count
            for r in 0..<rows {
                for c in 0..<gw {
                    guard glyph[r][c] else { continue }
                    // 影レイヤ
                    let sy = r + shadowDY, sx = x0 + c + shadowDX
                    if canvas[sy][sx] < 2 { canvas[sy][sx] = 1 }
                    // 面レイヤ
                    canvas[r][x0 + c] = 2
                }
            }
            x0 += gw + spacing
        }

        // 描画
        for row in canvas {
            var line = ""
            for (col, pixel) in row.enumerated() {
                switch pixel {
                case 2:
                    // グラデーション面
                    let t = Double(col) / Double(faceWidth - 1)
                    let (r, g, b) = gradientColor(t: t)
                    line += "\u{1B}[38;2;\(r);\(g);\(b)m█"
                case 1:
                    // ダークネイビーの影
                    line += "\u{1B}[38;2;10;28;85m█"
                default:
                    line += " "
                }
            }
            line += "\u{1B}[0m"
            print(line)
        }
        print()
    }

    // MARK: - Gradient

    /// 0.0〜1.0 の位置に対応するグラデーション色を返す
    /// 0%: #0167EC  50%: #099AE2  100%: #1BBED0
    private func gradientColor(t: Double) -> (Int, Int, Int) {
        let t = max(0.0, min(1.0, t))
        if t <= 0.5 {
            let s = t / 0.5
            return (lerp(1, 9, s), lerp(103, 154, s), lerp(236, 226, s))
        } else {
            let s = (t - 0.5) / 0.5
            return (lerp(9, 27, s), lerp(154, 190, s), lerp(226, 208, s))
        }
    }

    private func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
        Int((Double(a) + Double(b - a) * t).rounded())
    }

    // MARK: - Argument parsing

    /// シェルに近いトークン分割（シングル/ダブルクォート対応）
    private func shellSplit(_ line: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quoteChar: Character? = nil

        for ch in line {
            if let q = quoteChar {
                if ch == q { quoteChar = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quoteChar = ch
            } else if ch == " " {
                if !current.isEmpty { args.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
    }
}
