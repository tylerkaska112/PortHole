// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// A Zstandard decoder (RFC 8878), written for this project. Steam packs the chunks of newer games with it ("VSZa"); iOS has no
// Zstandard in its system libraries. Decoding only, no dictionaries. Every read is bounds-checked: damaged or hostile data makes
// `decompress` return nil, never crash.
import Foundation

enum Zstd {
    /// Decodes the zstd frame(s) in `input[start..<end]`, which must produce exactly `expectedSize` bytes.
    static func decompress(_ input: [UInt8], from start: Int, to end: Int, expectedSize: Int) -> [UInt8]? {
        guard expectedSize >= 0, expectedSize < 1 << 30, start >= 0, start <= end, end <= input.count else { return nil }
        var decoder = Decoder(input: input, end: end, limit: expectedSize)
        var at = start
        while at < end {
            guard let next = decoder.frame(at: at) else { return nil }
            at = next
        }
        return decoder.output.count == expectedSize ? decoder.output : nil
    }

    // MARK: Tables

    struct FSETable {
        var symbol: [UInt8]
        var nbBits: [UInt8]
        var baseline: [UInt16]
        var log: Int
    }

    /// Builds the decoding table for normalised counts (-1 marks a "less than one" probability).
    static func buildTable(counts: [Int16], log: Int) -> FSETable? {
        let size = 1 << log
        guard log >= 1, log <= 15, counts.count <= 256 else { return nil }
        var symbol = [UInt8](repeating: 0, count: size)
        var next = [Int](repeating: 0, count: counts.count)
        var high = size - 1
        var total = 0
        for (s, count) in counts.enumerated() {
            if count == -1 { guard high >= 0 else { return nil }; symbol[high] = UInt8(s); high -= 1; next[s] = 1; total += 1 }
            else if count >= 0 { next[s] = Int(count); total += Int(count) }
            else { return nil }
        }
        guard total == size else { return nil }
        let step = (size >> 1) + (size >> 3) + 3, mask = size - 1
        var position = 0
        for (s, count) in counts.enumerated() where count > 0 {
            for _ in 0..<Int(count) {
                symbol[position] = UInt8(s)
                repeat { position = (position + step) & mask } while position > high
            }
        }
        guard position == 0 else { return nil }
        var nbBits = [UInt8](repeating: 0, count: size), baseline = [UInt16](repeating: 0, count: size)
        for state in 0..<size {
            let s = Int(symbol[state])
            let n = next[s]; next[s] += 1
            let bits = log - (Int.bitWidth - 1 - n.leadingZeroBitCount)          // log - floor(log2(n))
            guard bits >= 0, bits <= log else { return nil }
            nbBits[state] = UInt8(bits)
            let base = (n << bits) - size
            guard base >= 0, base < 65536 else { return nil }
            baseline[state] = UInt16(base)
        }
        return FSETable(symbol: symbol, nbBits: nbBits, baseline: baseline, log: log)
    }

    // The defaults the format prescribes when a block says "predefined".
    private static let literalLengthCounts: [Int16] = [4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1]
    private static let matchLengthCounts: [Int16] = [1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1]
    private static let offsetCounts: [Int16] = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1]
    static let defaultLiteralLength = buildTable(counts: literalLengthCounts, log: 6)!
    static let defaultMatchLength = buildTable(counts: matchLengthCounts, log: 6)!
    static let defaultOffset = buildTable(counts: offsetCounts, log: 5)!

    private static let literalLengthBase: [Int] = Array(0..<16) + [16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536]
    private static let literalLengthBits: [Int] = [Int](repeating: 0, count: 16) + [1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    private static let matchLengthBase: [Int] = Array(3..<35) + [35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539]
    private static let matchLengthBits: [Int] = [Int](repeating: 0, count: 32) + [1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

    // MARK: Bit readers

    /// Bits from the low end of each byte upwards (how table descriptions are stored).
    struct ForwardBits {
        let data: [UInt8]
        let start: Int
        let end: Int
        var bitPos = 0
        init(data: [UInt8], start: Int, end: Int) { self.data = data; self.start = start; self.end = end }
        mutating func read(_ n: Int) -> Int? {
            guard n >= 0, n <= 24 else { return nil }
            guard start + (bitPos + n + 7) / 8 <= end else { return nil }
            var value = 0
            for i in 0..<n { let bit = bitPos + i; value |= Int((data[start + bit >> 3] >> UInt8(bit & 7)) & 1) << i }
            bitPos += n
            return value
        }
        var bytesUsed: Int { (bitPos + 7) / 8 }
    }

    /// Bits read from the end of a stream towards its start (how Huffman and sequence streams are stored). The last byte holds a
    /// marker: its highest set bit is the stream's first bit.
    struct BackwardBits {
        let data: [UInt8]
        let start: Int
        var bitPos: Int
        init?(data: [UInt8], start: Int, end: Int) {
            guard end > start, end <= data.count, let last = Optional(data[end - 1]), last != 0 else { return nil }
            self.data = data; self.start = start
            bitPos = (end - start) * 8 - (last.leadingZeroBitCount + 1)
        }
        /// Bits `[lo, lo + count)` of the stream as an integer (bit `lo` is the lowest). Bytes outside the stream read as zero.
        private func raw(_ lo: Int, _ count: Int) -> UInt64 {
            if count <= 0 { return 0 }
            var value: UInt64 = 0
            let firstByte = lo >> 3, shift = lo & 7
            let bytes = (shift + count + 7) / 8
            for i in 0..<bytes {
                let index = start + firstByte + i
                if index >= start, index < data.count { value |= UInt64(data[index]) << UInt64(8 * i) }
            }
            return (value >> UInt64(shift)) & (count >= 64 ? UInt64.max : (UInt64(1) << UInt64(count)) - 1)
        }
        /// The next `n` bits without consuming them; anything before the start of the stream reads as zeros.
        func peek(_ n: Int) -> Int {
            guard n > 0 else { return 0 }
            let low = bitPos - n
            if low >= 0 { return Int(raw(low, n)) }
            if bitPos <= 0 { return 0 }
            return Int(raw(0, bitPos)) << (-low)
        }
        mutating func read(_ n: Int) -> Int { let v = peek(n); bitPos -= n; return v }
        var overran: Bool { bitPos < 0 }
    }

    // MARK: Table descriptions

    /// Reads an FSE table description (accuracy log, then the normalised counts).
    static func readTable(data: [UInt8], start: Int, end: Int, maxSymbol: Int, maxLog: Int) -> (table: FSETable, next: Int)? {
        var bits = ForwardBits(data: data, start: start, end: end)
        guard let accuracy = bits.read(4) else { return nil }
        let log = accuracy + 5
        guard log <= maxLog else { return nil }
        var remaining = (1 << log) + 1
        var threshold = 1 << log
        var nbBits = log + 1
        var counts: [Int16] = []
        var previousZero = false
        while remaining > 1 {
            if previousZero {
                var repeats = 0
                while true { guard let r = bits.read(2) else { return nil }; repeats += r; if r != 3 { break } }
                guard counts.count + repeats <= maxSymbol + 1 else { return nil }
                counts += [Int16](repeating: 0, count: repeats)
                previousZero = false
                if remaining <= 1 { break }
            }
            guard counts.count <= maxSymbol else { return nil }
            let max = (2 * threshold - 1) - remaining
            guard let low = bits.read(nbBits - 1) else { return nil }
            var count: Int
            if low < max { count = low }
            else {
                guard let high = bits.read(1) else { return nil }
                count = low | (high << (nbBits - 1))
                if count >= threshold { count -= max }
            }
            count -= 1                                               // the stored value is one more than the probability
            remaining -= count < 0 ? -count : count
            guard remaining >= 1 else { return nil }
            counts.append(Int16(count))
            previousZero = count == 0
            while remaining < threshold { nbBits -= 1; threshold >>= 1 }
        }
        guard remaining == 1, counts.count <= maxSymbol + 1, let table = buildTable(counts: counts, log: log) else { return nil }
        return (table, start + bits.bytesUsed)
    }

    // MARK: Huffman

    struct HuffmanTable {
        var symbol: [UInt8]
        var nbBits: [UInt8]
        var maxBits: Int
    }

    static func huffmanTable(weights: [Int]) -> HuffmanTable? {
        var sum = 0
        for w in weights { guard w >= 0, w <= 11 else { return nil }; if w > 0 { sum += 1 << (w - 1) } }
        guard sum > 0 else { return nil }
        let maxBits = (Int.bitWidth - sum.leadingZeroBitCount)                  // floor(log2(sum)) + 1
        guard maxBits <= 11 else { return nil }
        let rest = (1 << maxBits) - sum
        guard rest > 0, rest & (rest - 1) == 0 else { return nil }             // the implied last weight must be a power of two
        var all = weights
        all.append((Int.bitWidth - 1 - rest.leadingZeroBitCount) + 1)
        guard all.count <= 256 else { return nil }
        var rankCount = [Int](repeating: 0, count: 13)
        for w in all { rankCount[w] += 1 }
        var rankStart = [Int](repeating: 0, count: 13)
        var running = 0
        for w in 1...11 { rankStart[w] = running; running += rankCount[w] << (w - 1) }
        guard running == 1 << maxBits else { return nil }
        var symbol = [UInt8](repeating: 0, count: 1 << maxBits), nbBits = [UInt8](repeating: 0, count: 1 << maxBits)
        for (s, w) in all.enumerated() where w > 0 {
            let length = 1 << (w - 1), begin = rankStart[w]
            for i in 0..<length { symbol[begin + i] = UInt8(s); nbBits[begin + i] = UInt8(maxBits + 1 - w) }
            rankStart[w] += length
        }
        return HuffmanTable(symbol: symbol, nbBits: nbBits, maxBits: maxBits)
    }

    /// The Huffman tree at the start of a compressed literals section. Returns the table and the offset after it.
    static func readHuffmanTree(data: [UInt8], at start: Int, end: Int) -> (table: HuffmanTable, next: Int)? {
        guard start < end else { return nil }
        let header = Int(data[start])
        var weights: [Int] = []
        var next: Int
        if header >= 128 {
            let count = header - 127
            let bytes = (count + 1) / 2
            guard start + 1 + bytes <= end else { return nil }
            for i in 0..<count { let byte = data[start + 1 + i / 2]; weights.append(Int(i % 2 == 0 ? byte >> 4 : byte & 15)) }
            next = start + 1 + bytes
        } else {
            guard header > 0, start + 1 + header <= end else { return nil }
            guard let (table, used) = readTable(data: data, start: start + 1, end: start + 1 + header, maxSymbol: 12, maxLog: 6),
                  var stream = BackwardBits(data: data, start: used, end: start + 1 + header) else { return nil }
            var state1 = stream.read(table.log), state2 = stream.read(table.log)
            if stream.overran { return nil }
            while true {
                weights.append(Int(table.symbol[state1]))
                state1 = Int(table.baseline[state1]) + stream.read(Int(table.nbBits[state1]))
                if stream.overran { weights.append(Int(table.symbol[state2])); break }
                weights.append(Int(table.symbol[state2]))
                state2 = Int(table.baseline[state2]) + stream.read(Int(table.nbBits[state2]))
                if stream.overran { weights.append(Int(table.symbol[state1])); break }
                if weights.count > 255 { return nil }
            }
            next = start + 1 + header
        }
        guard weights.count <= 255, let table = huffmanTable(weights: weights) else { return nil }
        return (table, next)
    }

    /// Decodes `count` symbols from one backward Huffman stream.
    static func decodeHuffman(_ table: HuffmanTable, data: [UInt8], start: Int, end: Int, count: Int, into output: inout [UInt8]) -> Bool {
        guard var stream = BackwardBits(data: data, start: start, end: end) else { return count == 0 && end == start ? true : false }
        let maxBits = table.maxBits
        for _ in 0..<count {
            let index = stream.peek(maxBits)
            output.append(table.symbol[index])
            stream.bitPos -= Int(table.nbBits[index])
        }
        return !stream.overran
    }

    // MARK: Decoder

    struct Decoder {
        let input: [UInt8]
        let end: Int
        let limit: Int
        var output: [UInt8] = []
        var huffman: HuffmanTable?
        var literalLength: FSETable?, offsetTable: FSETable?, matchLength: FSETable?
        var repeated = [1, 4, 8]

        init(input: [UInt8], end: Int, limit: Int) { self.input = input; self.end = end; self.limit = limit; output.reserveCapacity(limit) }

        /// One frame starting at `at`; returns where the next one starts.
        mutating func frame(at start: Int) -> Int? {
            var at = start
            guard at + 4 <= end else { return nil }
            let magic = UInt32(input[at]) | UInt32(input[at + 1]) << 8 | UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24
            at += 4
            if magic >> 4 == 0x184D2A5 {                                        // skippable frame
                guard at + 4 <= end else { return nil }
                let size = Int(UInt32(input[at]) | UInt32(input[at + 1]) << 8 | UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24)
                at += 4
                return at + size <= end ? at + size : nil
            }
            guard magic == 0xFD2F_B528, at < end else { return nil }
            let descriptor = Int(input[at]); at += 1
            let contentSizeFlag = descriptor >> 6, singleSegment = (descriptor >> 5) & 1, checksum = (descriptor >> 2) & 1, dictionaryFlag = descriptor & 3
            guard descriptor & 8 == 0 else { return nil }                       // reserved bit
            if singleSegment == 0 { at += 1 }                                   // window descriptor: the whole output is the window
            let dictionaryBytes = [0, 1, 2, 4][dictionaryFlag]
            guard at + dictionaryBytes <= end else { return nil }
            for i in 0..<dictionaryBytes where input[at + i] != 0 { return nil } // dictionaries are not supported
            at += dictionaryBytes
            let sizeBytes = [singleSegment == 1 ? 1 : 0, 2, 4, 8][contentSizeFlag]
            at += sizeBytes
            guard at <= end else { return nil }
            huffman = nil; literalLength = nil; offsetTable = nil; matchLength = nil; repeated = [1, 4, 8]
            var last = false
            while !last {
                guard at + 3 <= end else { return nil }
                let header = Int(input[at]) | Int(input[at + 1]) << 8 | Int(input[at + 2]) << 16
                at += 3
                last = header & 1 == 1
                let type = (header >> 1) & 3, size = header >> 3
                switch type {
                case 0:                                                         // raw
                    guard at + size <= end, output.count + size <= limit else { return nil }
                    output.append(contentsOf: input[at..<at + size]); at += size
                case 1:                                                         // one byte repeated
                    guard at < end, output.count + size <= limit else { return nil }
                    output.append(contentsOf: repeatElement(input[at], count: size)); at += 1
                case 2:
                    guard size <= 128 * 1024, at + size <= end, block(at, at + size) else { return nil }
                    at += size
                default: return nil
                }
            }
            if checksum == 1 { at += 4 }                                        // the content checksum is not needed: Steam's own hash is checked
            return at <= end ? at : nil
        }

        /// A compressed block: literals, then sequences that interleave them with copies from earlier output.
        mutating func block(_ start: Int, _ blockEnd: Int) -> Bool {
            guard let (literals, at) = readLiterals(start, blockEnd) else { return false }
            return sequences(from: at, to: blockEnd, literals: literals)
        }

        mutating func readLiterals(_ start: Int, _ blockEnd: Int) -> (literals: [UInt8], next: Int)? {
            guard start < blockEnd else { return nil }
            let first = Int(input[start])
            let type = first & 3, format = (first >> 2) & 3
            switch type {
            case 0, 1:
                var size = 0, headerBytes = 1
                switch format {
                case 0, 2: size = first >> 3
                case 1: guard start + 2 <= blockEnd else { return nil }; size = (first | Int(input[start + 1]) << 8) >> 4; headerBytes = 2
                default: guard start + 3 <= blockEnd else { return nil }; size = (first | Int(input[start + 1]) << 8 | Int(input[start + 2]) << 16) >> 4; headerBytes = 3
                }
                let at = start + headerBytes
                if type == 0 { guard at + size <= blockEnd else { return nil }; return (Array(input[at..<at + size]), at + size) }
                guard at < blockEnd, size <= 128 * 1024 else { return nil }
                return ([UInt8](repeating: input[at], count: size), at + 1)
            default:
                let streams = format == 0 ? 1 : 4
                let headerBytes = [3, 3, 4, 5][format], fieldBits = [10, 10, 14, 18][format]
                guard start + headerBytes <= blockEnd else { return nil }
                var value = 0
                for i in 0..<headerBytes { value |= Int(input[start + i]) << (8 * i) }
                let regenerated = (value >> 4) & ((1 << fieldBits) - 1), compressed = (value >> (4 + fieldBits)) & ((1 << fieldBits) - 1)
                var at = start + headerBytes
                let literalsEnd = at + compressed
                guard literalsEnd <= blockEnd, regenerated <= 128 * 1024 else { return nil }
                if type == 2 {
                    guard let (table, next) = Zstd.readHuffmanTree(data: input, at: at, end: literalsEnd) else { return nil }
                    huffman = table; at = next
                }
                guard let table = huffman else { return nil }                   // "treeless" needs an earlier table
                var out: [UInt8] = []
                out.reserveCapacity(regenerated)
                if streams == 1 {
                    guard Zstd.decodeHuffman(table, data: input, start: at, end: literalsEnd, count: regenerated, into: &out) else { return nil }
                } else {
                    guard at + 6 <= literalsEnd else { return nil }
                    let s1 = Int(input[at]) | Int(input[at + 1]) << 8, s2 = Int(input[at + 2]) | Int(input[at + 3]) << 8, s3 = Int(input[at + 4]) | Int(input[at + 5]) << 8
                    let begin = at + 6
                    guard begin + s1 + s2 + s3 < literalsEnd else { return nil }
                    let each = (regenerated + 3) / 4
                    let counts = [each, each, each, regenerated - 3 * each]
                    guard counts[3] >= 0 else { return nil }
                    let bounds = [begin, begin + s1, begin + s1 + s2, begin + s1 + s2 + s3, literalsEnd]
                    for i in 0..<4 {
                        guard Zstd.decodeHuffman(table, data: input, start: bounds[i], end: bounds[i + 1], count: counts[i], into: &out) else { return nil }
                    }
                }
                guard out.count == regenerated else { return nil }
                return (out, literalsEnd)
            }
        }

        mutating func sequences(from start: Int, to blockEnd: Int, literals: [UInt8]) -> Bool {
            var at = start
            guard at < blockEnd else { return false }
            var count = Int(input[at]); at += 1
            if count == 0 {
                guard output.count + literals.count <= limit else { return false }
                output.append(contentsOf: literals); return at == blockEnd
            }
            if count >= 128 {
                if count == 255 { guard at + 2 <= blockEnd else { return false }; count = Int(input[at]) | Int(input[at + 1]) << 8 + 0x7F00; at += 2 }
                else { guard at < blockEnd else { return false }; count = ((count - 128) << 8) + Int(input[at]); at += 1 }
            }
            guard at < blockEnd else { return false }
            let modes = Int(input[at]); at += 1
            guard modes & 3 == 0 else { return false }
            func table(mode: Int, current: FSETable?, predefined: FSETable, maxSymbol: Int, maxLog: Int) -> FSETable? {
                switch mode {
                case 0: return predefined
                case 1:
                    guard at < blockEnd else { return nil }
                    let symbol = input[at]; at += 1
                    guard Int(symbol) <= maxSymbol else { return nil }
                    // One symbol, no bits: a table with a single state that always gives this symbol and reads nothing.
                    return FSETable(symbol: [symbol], nbBits: [0], baseline: [0], log: 0)
                case 2:
                    guard let (built, next) = Zstd.readTable(data: input, start: at, end: blockEnd, maxSymbol: maxSymbol, maxLog: maxLog) else { return nil }
                    at = next; return built
                default: return current
                }
            }
            guard let ll = table(mode: modes >> 6, current: literalLength, predefined: Zstd.defaultLiteralLength, maxSymbol: 35, maxLog: 9),
                  let of = table(mode: (modes >> 4) & 3, current: offsetTable, predefined: Zstd.defaultOffset, maxSymbol: 31, maxLog: 8),
                  let ml = table(mode: (modes >> 2) & 3, current: matchLength, predefined: Zstd.defaultMatchLength, maxSymbol: 52, maxLog: 9) else { return false }
            literalLength = ll; offsetTable = of; matchLength = ml
            guard var stream = BackwardBits(data: input, start: at, end: blockEnd) else { return false }
            var llState = stream.read(ll.log), ofState = stream.read(of.log), mlState = stream.read(ml.log)
            if stream.overran { return false }
            var used = 0                                                          // literals consumed so far
            for index in 0..<count {
                let ofCode = Int(of.symbol[ofState]), mlCode = Int(ml.symbol[mlState]), llCode = Int(ll.symbol[llState])
                guard ofCode <= 31, mlCode < Zstd.matchLengthBase.count, llCode < Zstd.literalLengthBase.count else { return false }
                let offsetValue = (1 << ofCode) + stream.read(ofCode)
                let matchLen = Zstd.matchLengthBase[mlCode] + stream.read(Zstd.matchLengthBits[mlCode])
                let literalLen = Zstd.literalLengthBase[llCode] + stream.read(Zstd.literalLengthBits[llCode])
                if index + 1 < count {
                    llState = Int(ll.baseline[llState]) + stream.read(Int(ll.nbBits[llState]))
                    mlState = Int(ml.baseline[mlState]) + stream.read(Int(ml.nbBits[mlState]))
                    ofState = Int(of.baseline[ofState]) + stream.read(Int(of.nbBits[ofState]))
                }
                if stream.overran { return false }
                // Which distance: a new one, or one of the three most recent (with a shift when there are no literals)
                var offset: Int
                if offsetValue > 3 {
                    offset = offsetValue - 3
                    repeated = [offset, repeated[0], repeated[1]]
                } else {
                    let choice = literalLen == 0 ? offsetValue + 1 : offsetValue
                    switch choice {
                    case 1: offset = repeated[0]
                    case 2: offset = repeated[1]; repeated = [offset, repeated[0], repeated[2]]
                    case 3: offset = repeated[2]; repeated = [offset, repeated[0], repeated[1]]
                    default: offset = repeated[0] - 1; repeated = [offset, repeated[0], repeated[1]]
                    }
                    guard offset > 0 else { return false }
                }
                guard used + literalLen <= literals.count, output.count + literalLen + matchLen <= limit else { return false }
                output.append(contentsOf: literals[used..<used + literalLen]); used += literalLen
                guard offset <= output.count else { return false }
                var from = output.count - offset
                for _ in 0..<matchLen { output.append(output[from]); from += 1 }
            }
            guard output.count + (literals.count - used) <= limit else { return false }
            output.append(contentsOf: literals[used...])
            return true
        }
    }
}
