import Foundation

/// A small source guard tokenizer for ASCII architecture identifiers.
/// It skips comments and plain string contents. If a string contains a Swift
/// interpolation, it scans that whole literal conservatively so executable
/// identifiers cannot hide there (at the cost of possible literal-text hits).
enum SwiftSourceIdentifierScanner {
    static func identifiers(in source: String) -> Set<String> {
        var lexer = Lexer(Array(source))
        return lexer.identifiers()
    }

    private struct Lexer {
        let characters: [Character]
        var index = 0
        var found: Set<String> = []

        init(_ characters: [Character]) {
            self.characters = characters
        }

        mutating func identifiers() -> Set<String> {
            while index < characters.count {
                if starts(with: "//") {
                    skipLineComment()
                } else if starts(with: "/*") {
                    skipBlockComment()
                } else if let (quote, hashes) = stringStart() {
                    let (content, interpolated) = consumeString(quote: quote, hashes: hashes)
                    if interpolated {
                        found.formUnion(Self.identifierTokens(in: content))
                    }
                } else if isIdentifierStart(characters[index]) {
                    found.insert(readIdentifier())
                } else {
                    index += 1
                }
            }
            return found
        }

        private mutating func skipLineComment() {
            index += 2
            while index < characters.count, characters[index] != "\n" {
                index += 1
            }
        }

        private mutating func skipBlockComment() {
            index += 2
            var depth = 1
            while index < characters.count, depth > 0 {
                if starts(with: "/*") {
                    depth += 1
                    index += 2
                } else if starts(with: "*/") {
                    depth -= 1
                    index += 2
                } else {
                    index += 1
                }
            }
        }

        private func stringStart() -> (quote: Int, hashes: Int)? {
            var cursor = index
            while cursor < characters.count, characters[cursor] == "#" {
                cursor += 1
            }
            guard cursor < characters.count, characters[cursor] == "\"" else { return nil }
            return (cursor, cursor - index)
        }

        private mutating func consumeString(quote: Int, hashes: Int) -> (content: String, interpolated: Bool) {
            let multiline = quote + 2 < characters.count
                && characters[quote + 1] == "\""
                && characters[quote + 2] == "\""
            let openingLength = multiline ? 3 : 1
            let contentStart = quote + openingLength
            index = contentStart
            var interpolated = false
            var interpolationDepth = 0

            while index < characters.count {
                if interpolationDepth > 0 {
                    if starts(with: "//") {
                        skipLineComment()
                    } else if starts(with: "/*") {
                        skipBlockComment()
                    } else if let (nestedQuote, nestedHashes) = stringStart() {
                        _ = consumeString(quote: nestedQuote, hashes: nestedHashes)
                    } else {
                        if characters[index] == "(" {
                            interpolationDepth += 1
                        } else if characters[index] == ")" {
                            interpolationDepth -= 1
                        }
                        index += 1
                    }
                    continue
                }

                if isInterpolationStart(at: index, hashes: hashes) {
                    interpolated = true
                    index += hashes + 2
                    interpolationDepth = 1
                    continue
                }

                let closes = multiline
                    ? starts(with: "\"\"\"", at: index)
                    : characters[index] == "\""
                if closes,
                   !isEscapedQuote(at: index, hashes: hashes),
                   hasClosingHashes(after: index + openingLength, count: hashes) {
                    let content = String(characters[contentStart..<index])
                    index += openingLength + hashes
                    return (content, interpolated)
                }
                index += 1
            }

            let content = String(characters[contentStart..<characters.count])
            return (content, interpolated)
        }

        private func isInterpolationStart(at position: Int, hashes: Int) -> Bool {
            guard position < characters.count, characters[position] == "\\" else { return false }
            var cursor = position + 1
            if hashes == 0 {
                var previous = position - 1
                var precedingSlashes = 0
                while previous >= 0, characters[previous] == "\\" {
                    precedingSlashes += 1
                    previous -= 1
                }
                guard precedingSlashes.isMultiple(of: 2) else { return false }
            } else {
                for _ in 0..<hashes {
                    guard cursor < characters.count, characters[cursor] == "#" else { return false }
                    cursor += 1
                }
            }
            return cursor < characters.count && characters[cursor] == "("
        }

        private func isEscapedQuote(at quote: Int, hashes: Int) -> Bool {
            guard quote > 0 else { return false }
            var cursor = quote - 1
            for _ in 0..<hashes {
                guard cursor >= 0, characters[cursor] == "#" else { return false }
                cursor -= 1
            }
            var slashCount = 0
            while cursor >= 0, characters[cursor] == "\\" {
                slashCount += 1
                cursor -= 1
            }
            return slashCount.isMultiple(of: 2) == false
        }

        private func hasClosingHashes(after position: Int, count: Int) -> Bool {
            guard position + count <= characters.count else { return false }
            for offset in 0..<count where characters[position + offset] != "#" {
                return false
            }
            return true
        }

        private mutating func readIdentifier() -> String {
            let start = index
            index += 1
            while index < characters.count, isIdentifierContinuation(characters[index]) {
                index += 1
            }
            return String(characters[start..<index])
        }

        private func starts(with value: String, at position: Int? = nil) -> Bool {
            let start = position ?? index
            let target = Array(value)
            guard start + target.count <= characters.count else { return false }
            return characters[start..<(start + target.count)].elementsEqual(target)
        }

        private func isIdentifierStart(_ character: Character) -> Bool {
            character == "_" || character.isASCIILetter
        }

        private func isIdentifierContinuation(_ character: Character) -> Bool {
            character == "_" || character.isASCIILetter || character.isASCIIDigit
        }

        private static func identifierTokens(in source: String) -> Set<String> {
            let values = Array(source)
            var tokens: Set<String> = []
            var cursor = 0
            while cursor < values.count {
                guard values[cursor] == "_" || values[cursor].isASCIILetter else {
                    cursor += 1
                    continue
                }
                let start = cursor
                cursor += 1
                while cursor < values.count,
                      values[cursor] == "_" || values[cursor].isASCIILetter || values[cursor].isASCIIDigit {
                    cursor += 1
                }
                tokens.insert(String(values[start..<cursor]))
            }
            return tokens
        }
    }
}

private extension Character {
    var isASCIILetter: Bool { isASCIIUppercase || isASCIILowercase }
    var isASCIIUppercase: Bool { ("A"..."Z").contains(self) }
    var isASCIILowercase: Bool { ("a"..."z").contains(self) }
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
