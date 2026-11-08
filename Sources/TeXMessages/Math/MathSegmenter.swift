import Foundation

enum Segment: Equatable {
    case text(String)
    case math(String, display: Bool, raw: String)
}

enum MathSegmenter {
    static func split(_ input: String) -> [Segment] {
        guard input.contains("$") || input.contains("\\(") || input.contains("\\[") else { return [.text(input)] }
        let chars = Array(input)
        var segments: [Segment] = []
        var buffer = ""
        var index = 0

        func flush() {
            if !buffer.isEmpty { segments.append(.text(buffer)) }
            buffer = ""
        }

        func emit(from start: Int, to end: Int, close: Int, display: Bool) {
            flush()
            segments.append(.math(String(chars[start..<end]), display: display, raw: String(chars[(start - close)..<(end + close)])))
            index = end + close
        }

        while index < chars.count {
            let char = chars[index]
            if char == "\\", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "$" || next == "\\" {
                    buffer.append(char)
                    buffer.append(next)
                    index += 2
                    continue
                }
                if next == "(", let end = closeBracket(chars, from: index + 2, closer: ")", allowsNewlines: false) {
                    emit(from: index + 2, to: end, close: 2, display: false)
                    continue
                }
                if next == "[", let end = closeBracket(chars, from: index + 2, closer: "]", allowsNewlines: true) {
                    emit(from: index + 2, to: end, close: 2, display: true)
                    continue
                }
            }
            if char == "$" {
                if index + 1 < chars.count, chars[index + 1] == "$", let end = closeDisplay(chars, from: index + 2) {
                    emit(from: index + 2, to: end, close: 2, display: true)
                    continue
                }
                if let end = closeInline(chars, from: index + 1) {
                    emit(from: index + 1, to: end, close: 1, display: false)
                    continue
                }
            }
            buffer.append(char)
            index += 1
        }
        flush()

        guard segments.contains(where: { if case .math = $0 { true } else { false } }) else { return [.text(input)] }
        return segments.map { segment in
            if case .text(let text) = segment { return .text(text.replacingOccurrences(of: "\\$", with: "$")) }
            return segment
        }
    }

    private static func closeBracket(_ chars: [Character], from start: Int, closer: Character, allowsNewlines: Bool) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "\\" {
                if chars[index + 1] == closer {
                    let body = String(chars[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return body.isEmpty ? nil : index
                }
                index += 2
                continue
            }
            if !allowsNewlines, chars[index].isNewline { return nil }
            index += 1
        }
        return nil
    }

    private static func closeInline(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
        var index = start
        while index < chars.count {
            let char = chars[index]
            if char == "\\" { index += 2; continue }
            if char.isNewline { return nil }
            if char == "$" {
                let previousOK = !chars[index - 1].isWhitespace
                let nextOK = index + 1 >= chars.count || !chars[index + 1].isNumber
                return previousOK && nextOK ? index : nil
            }
            index += 1
        }
        return nil
    }

    private static func closeDisplay(_ chars: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == "$", chars[index + 1] == "$" {
                let body = String(chars[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? nil : index
            }
            index += 1
        }
        return nil
    }
}
