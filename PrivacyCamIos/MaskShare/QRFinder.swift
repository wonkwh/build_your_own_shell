import CoreGraphics

/// 디코딩 없이 QR 의 세 모서리 finder 패턴(어둠:밝음:어둠:밝음:어둠 = 1:1:3:1:1)을 찾아 QR 영역을 추정한다.
/// Vision 은 해석 가능한 코드만 돌려주므로, 흐리거나 깨져서 읽히지 않는 QR 도 가리기 위한 보조 검출.
enum QRFinder {
    struct Candidate { var x: Double; var y: Double; var module: Double; var hits: Int }

    /// - Returns: 원본 이미지 픽셀 좌표의 QR 추정 영역(quiet zone 1 모듈 포함).
    static func detect(_ image: CGImage, maxSide: Int = 1600) -> [CGRect] {
        // 작은 이미지도 키운다. 모듈이 2px 남짓이면 1px 반올림 오차로 1:1:3:1:1 비율이 깨진다.
        let scale = Double(maxSide) / Double(max(image.width, image.height))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let dark = binarize(image, width: w, height: h) else { return [] }
        let candidates = findCandidates(dark, width: w, height: h).filter { $0.hits >= 2 }
        return group(candidates).map {
            CGRect(x: $0.minX / scale, y: $0.minY / scale, width: $0.width / scale, height: $0.height / scale)
        }
    }

    // MARK: 이진화

    /// 주변 평균보다 15% 이상 어두우면 어둠. 조명이 고르지 않은 사진(화이트보드 등)에서도 버틴다.
    static func binarize(_ image: CGImage, width w: Int, height h: Int) -> [Bool]? {
        var gray = [UInt8](repeating: 0, count: w * h)
        let drawn = gray.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        let stride = w + 1
        var integral = [Int](repeating: 0, count: stride * (h + 1))
        for y in 0..<h {
            var row = 0
            for x in 0..<w {
                row += Int(gray[y * w + x])
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
            }
        }
        let r = max(8, max(w, h) / 32)
        var dark = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - r), y1 = min(h, y + r + 1)
            for x in 0..<w {
                let x0 = max(0, x - r), x1 = min(w, x + r + 1)
                let sum = integral[y1 * stride + x1] - integral[y0 * stride + x1] - integral[y1 * stride + x0] + integral[y0 * stride + x0]
                dark[y * w + x] = Int(gray[y * w + x]) * (x1 - x0) * (y1 - y0) * 100 < sum * 85
            }
        }
        return dark
    }

    // MARK: finder 패턴 후보

    static func findCandidates(_ dark: [Bool], width w: Int, height h: Int) -> [Candidate] {
        var found: [Candidate] = []

        func add(_ x: Double, _ y: Double, _ module: Double) {
            if let i = found.firstIndex(where: { abs($0.x - x) <= $0.module && abs($0.y - y) <= $0.module
                && abs($0.module - module) <= max(1, $0.module * 0.5) }) {
                let c = found[i], n = Double(c.hits)
                found[i] = Candidate(x: (c.x * n + x) / (n + 1), y: (c.y * n + y) / (n + 1),
                                     module: (c.module * n + module) / (n + 1), hits: c.hits + 1)
            } else {
                found.append(Candidate(x: x, y: y, module: module, hits: 1))
            }
        }

        /// 가로 런에서 찾은 중심을 세로·가로로 다시 확인해 (x, y, module) 을 돌려준다.
        func confirm(_ cx: Double, _ cy: Int, _ counts: [Int]) -> (Double, Double, Double)? {
            let total = counts.reduce(0, +)
            let col = Int(cx)
            guard let (vy, vTotal) = crossCheck(start: cy, limit: h, maxCount: counts[2], total: total, isDark: { dark[$0 * w + col] })
            else { return nil }
            let row = min(max(Int(vy), 0), h - 1)
            guard let (hx, hTotal) = crossCheck(start: col, limit: w, maxCount: counts[2], total: total, isDark: { dark[row * w + $0] })
            else { return nil }
            return (hx, vy, Double(total + vTotal + hTotal) / 21)
        }

        for y in 0..<h {
            var counts = [0, 0, 0, 0, 0], state = 0
            for x in 0...w {
                let d = x < w && dark[y * w + x]
                if d {
                    if state % 2 == 1 { state += 1 }
                    counts[state] += 1
                } else if state == 0 && counts[0] == 0 {
                    continue
                } else if state % 2 == 1 {
                    counts[state] += 1
                } else if state < 4 {
                    state += 1
                    counts[state] += 1
                } else {
                    if ratioOK(counts) {
                        let cx = Double(x - counts[4] - counts[3]) - Double(counts[2]) / 2
                        if let (fx, fy, m) = confirm(cx, y, counts) { add(fx, fy, m) }
                    }
                    counts = [counts[2], counts[3], counts[4], 1, 0]
                    state = 3
                }
            }
        }
        return found
    }

    static func ratioOK(_ c: [Int]) -> Bool {
        let total = c.reduce(0, +)
        guard total >= 7, !c.contains(0) else { return false }
        // 1 모듈 런은 ±0.75 모듈까지 허용. JPEG·확대 블러로 얇은 밝은 고리가 1~2px 줄어든다.
        let m = Double(total) / 7, v = m * 0.75
        return abs(m - Double(c[0])) < v && abs(m - Double(c[1])) < v && abs(3 * m - Double(c[2])) < m * 1.5
            && abs(m - Double(c[3])) < v && abs(m - Double(c[4])) < v
    }

    /// `start` 에서 양쪽으로 1:1:3:1:1 을 다시 세어 중심 좌표와 전체 길이를 돌려준다.
    static func crossCheck(start: Int, limit: Int, maxCount: Int, total: Int, isDark: (Int) -> Bool) -> (Double, Int)? {
        var c = [0, 0, 0, 0, 0]
        var i = start
        while i >= 0 && isDark(i) { c[2] += 1; i -= 1 }
        while i >= 0 && !isDark(i) && c[1] <= maxCount { c[1] += 1; i -= 1 }
        while i >= 0 && isDark(i) && c[0] <= maxCount { c[0] += 1; i -= 1 }
        i = start + 1
        while i < limit && isDark(i) { c[2] += 1; i += 1 }
        while i < limit && !isDark(i) && c[3] <= maxCount { c[3] += 1; i += 1 }
        while i < limit && isDark(i) && c[4] <= maxCount { c[4] += 1; i += 1 }
        let sum = c.reduce(0, +)
        guard c.allSatisfy({ $0 <= maxCount * 2 }), ratioOK(c), 5 * abs(sum - total) < 2 * total else { return nil }
        return (Double(i - c[4] - c[3]) - Double(c[2]) / 2, sum)
    }

    // MARK: 세 개씩 묶기

    /// 모듈 크기가 비슷하고 직각이등변삼각형을 이루는 세 후보를 한 QR 로 본다.
    static func group(_ all: [Candidate]) -> [CGRect] {
        // ponytail: 후보 조합 O(n³). 후보가 많아 느려지면 모듈 크기별로 나눠 묶는다.
        let cs = Array(all.sorted { $0.hits > $1.hits }.prefix(60))
        func dist(_ a: Candidate, _ b: Candidate) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }

        var triples: [(leg: Double, ids: [Int])] = []
        for i in cs.indices {
            for j in cs.indices where j > i {
                for k in cs.indices where k > j {
                    let mods = [cs[i].module, cs[j].module, cs[k].module]
                    guard mods.max()! <= mods.min()! * 1.4 else { continue }
                    // 가장 긴 변의 맞은편 꼭짓점이 직각.
                    let sides = [(dist(cs[j], cs[k]), [i, j, k]), (dist(cs[i], cs[k]), [j, i, k]), (dist(cs[i], cs[j]), [k, i, j])]
                    let (hyp, ids) = sides.max { $0.0 < $1.0 }!
                    let a = cs[ids[0]], ab = dist(a, cs[ids[1]]), ac = dist(a, cs[ids[2]])
                    let leg = (ab + ac) / 2, module = mods.reduce(0, +) / 3
                    let legDiff = abs(ab - ac) / leg, hypDiff = abs(hyp / leg - 2.squareRoot()) / 2.squareRoot()
                    // 버전 1(14 모듈)~40(170 모듈) 범위의 finder 간격.
                    guard legDiff < 0.2, hypDiff < 0.12, (12...180).contains(leg / module) else { continue }
                    triples.append((leg, ids))
                }
            }
        }

        // 작은 삼각형부터 고른다. 여러 QR 의 finder 를 가로지르는 삼각형은 항상 한 QR 안의 것보다 크다.
        var used = Set<Int>(), rects: [CGRect] = []
        for t in triples.sorted(by: { $0.leg < $1.leg }) where used.isDisjoint(with: t.ids) {
            used.formUnion(t.ids)
            let a = cs[t.ids[0]], b = cs[t.ids[1]], c = cs[t.ids[2]]
            let xs = [a.x, b.x, c.x, b.x + c.x - a.x], ys = [a.y, b.y, c.y, b.y + c.y - a.y]
            // finder 중심은 코드 가장자리에서 3.5 모듈 안쪽. quiet zone 1 모듈을 더한다.
            let pad = (a.module + b.module + c.module) / 3 * 4.5
            let rect = CGRect(x: xs.min()! - pad, y: ys.min()! - pad,
                              width: xs.max()! - xs.min()! + pad * 2, height: ys.max()! - ys.min()! + pad * 2)
            // 한 finder 가 후보 둘로 갈라지면 같은 QR 이 두 번 잡힌다.
            guard !rects.contains(where: { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else { continue }
            rects.append(rect)
        }
        return rects
    }
}
