#!/usr/bin/env swift
//
// Converts an SVG into a SwiftUI `Canvas` view in this project's art idiom.
//
//     swift Scripts/svg2swift.swift path/to/fx-coin-sparkle.svg [OutputName]
//
// Writes the generated Swift to stdout; redirect it where you want it:
//
//     swift Scripts/svg2swift.swift art/burger.svg BurgerArt > Sources/UI/Art/BurgerArt.swift
//
// WHY THIS EXISTS
//
// Every drawn asset in `Sources/UI/Art` was hand-transcribed from a design SVG - `CoinBurst`
// still says so in its doc comment ("transcribed from fx-coin-sparkle.svg"), and none of those
// source SVGs are in the repo. That made art a bottleneck: a new food sprite meant a person
// reading Bezier control points off a file and retyping them as Swift, which is slow, silent
// when wrong, and impossible to re-run when the artwork changes. This closes that loop, so art
// can be authored in Figma or Illustrator and dropped in.
//
// WHAT IT SUPPORTS
//
//   elements    path, circle, ellipse, rect (incl. rx/ry), line, polygon, polyline, g
//   path data   M m L l H h V v C c S s Q q T t A a Z z, including elliptical arcs
//   transforms  translate, scale, rotate (incl. about a point), skewX, skewY, matrix
//   paint       fill, stroke, stroke-width, opacity, fill-opacity, stroke-opacity,
//               stroke-linecap, stroke-linejoin, fill-rule / clip-rule (evenodd),
//               #rgb / #rrggbb / #rrggbbaa, rgb() and rgba() - alpha carried by the colour
//               itself is multiplied into the emitted opacity, not dropped, and composes with
//               fill-opacity/stroke-opacity/opacity - plus the ~25 CSS named colours
//               in `namedColors` - anything else warns and falls back to black rather than
//               guessing, so an unexpected name is loud instead of silently wrong,
//               presentation attributes and inline `style="..."`, inherited through <g>
//
// Transforms are baked into the emitted coordinates rather than reproduced as Swift, so the
// output is a flat list of paths with no matrix arithmetic left at runtime.
//
// WHAT IT DOES NOT SUPPORT - it warns on stderr and skips, rather than emitting silently wrong
// geometry: gradients and patterns (`fill="url(#...)"`), clipPath, mask, filter, text, and
// <use>/<defs> instancing. Flatten or expand those in the design tool before exporting.
//
import Foundation

// MARK: - CLI

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: svg2swift <file.svg> [OutputName]\n".utf8))
    exit(2)
}
let inputURL = URL(fileURLWithPath: args[1])
let explicitName = args.count >= 3 ? args[2] : nil

func warn(_ message: String) {
    FileHandle.standardError.write(Data("svg2swift: \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
    warn(message)
    exit(1)
}

// MARK: - Geometry

/// A 2x3 affine transform, composed as SVG composes them (parent applied outermost).
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = Affine()

    /// `self` then `other` - i.e. `other` is the outer, parent transform.
    func concatenating(_ outer: Affine) -> Affine {
        Affine(a: a * outer.a + b * outer.c,
               b: a * outer.b + b * outer.d,
               c: c * outer.a + d * outer.c,
               d: c * outer.b + d * outer.d,
               e: e * outer.a + f * outer.c + outer.e,
               f: e * outer.b + f * outer.d + outer.f)
    }

    func apply(_ x: Double, _ y: Double) -> (Double, Double) {
        (a * x + c * y + e, b * x + d * y + f)
    }

    /// The scale this transform applies to a stroke width. SVG scales stroke by the geometric
    /// mean of the axis scales, which is what `sqrt(|det|)` gives.
    var strokeScale: Double { (a * d - b * c).magnitude.squareRoot() }
}

// MARK: - Paint

struct Paint {
    var fill: String? = "#000000"      // SVG's initial fill is black
    var stroke: String?
    var strokeWidth = 1.0
    var opacity = 1.0
    var fillOpacity = 1.0
    var strokeOpacity = 1.0
    /// Alpha carried by the colour value itself - `rgba(...)`'s fourth channel or the last byte
    /// of `#rrggbbaa`. Kept separate from `fill-opacity` because SVG multiplies the two rather
    /// than letting one win, and because a child that re-declares `fill` must reset this while
    /// inheriting the parent's `fill-opacity`.
    var fillColorAlpha = 1.0
    var strokeColorAlpha = 1.0
    var evenOdd = false
    /// SVG's initial values are `butt` and `miter`. This codebase's own art is round-capped
    /// throughout, but honouring the file rather than imposing the house style keeps the
    /// output faithful - set round caps in the design tool and they come through.
    var lineCap = "butt"
    var lineJoin = "miter"
    /// The transform scale in force where the element was declared. Geometry is baked, so the
    /// stroke width has to be too, or a scaled group's outline comes out the wrong weight.
    var strokeScale = 1.0

    var effectiveFillOpacity: Double { opacity * fillOpacity * fillColorAlpha }
    var effectiveStrokeOpacity: Double { opacity * strokeOpacity * strokeColorAlpha }
}

/// The subset of SVG named colours worth carrying; anything else falls through with a warning.
let namedColors: [String: String] = [
    "black": "#000000", "white": "#FFFFFF", "red": "#FF0000", "green": "#008000",
    "blue": "#0000FF", "yellow": "#FFFF00", "orange": "#FFA500", "purple": "#800080",
    "gray": "#808080", "grey": "#808080", "silver": "#C0C0C0", "maroon": "#800000",
    "olive": "#808000", "lime": "#00FF00", "aqua": "#00FFFF", "cyan": "#00FFFF",
    "teal": "#008080", "navy": "#000080", "fuchsia": "#FF00FF", "magenta": "#FF00FF",
    "brown": "#A52A2A", "pink": "#FFC0CB", "gold": "#FFD700", "beige": "#F5F5DC",
    "tan": "#D2B48C", "transparent": "none",
]

/// Normalises an SVG paint value to `#RRGGBB` plus the alpha the value carried, or nil for
/// "no paint".
///
/// The alpha is returned rather than discarded: dropping it silently turns a designer's
/// `rgba(0,0,0,0.3)` drop shadow into an opaque black slab, with nothing on stderr to say so -
/// the one failure mode this script is otherwise careful to avoid.
func normalizeColor(_ raw: String) -> (hex: String, alpha: Double)? {
    let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if value.isEmpty || value == "none" { return nil }
    if value.hasPrefix("url(") {
        warn("gradient or pattern paint '\(raw)' is not supported - flatten it in the design tool; painting it flat black instead")
        return ("#000000", 1)
    }
    if value == "currentcolor" { return ("#000000", 1) }
    if let named = namedColors[value] { return named == "none" ? nil : (named, 1) }

    if value.hasPrefix("#") {
        let hex = String(value.dropFirst())
        if hex.count == 3 {
            return ("#" + hex.map { "\($0)\($0)" }.joined().uppercased(), 1)
        }
        if hex.count == 6 { return ("#" + hex.uppercased(), 1) }
        if hex.count == 8 {
            let alpha = Double(UInt8(hex.suffix(2), radix: 16) ?? 255) / 255
            return ("#" + hex.prefix(6).uppercased(), alpha)
        }
    }

    // rgb(...) / rgba(...)
    if value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") {
        let parts = value[value.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count >= 3 {
            let rgb = Array(parts.prefix(3))
            // `rgb(0 0 0)` and `rgb(0, 0, 0)` are 0-255; a fourth channel is 0-1.
            let channels = rgb.map { Int($0) }
            let hex = "#" + channels.map { String(format: "%02X", max(0, min(255, $0))) }.joined()
            let alpha = parts.count >= 4 ? max(0, min(1, parts[3])) : 1
            return (hex, alpha)
        }
    }

    warn("unrecognised colour '\(raw)' - painting it flat black")
    return ("#000000", 1)
}

// MARK: - Path data

/// Emits Swift `Path` builder statements for one shape.
struct PathEmitter {
    var lines: [String] = []
    private let transform: Affine

    init(transform: Affine) { self.transform = transform }

    private func fmt(_ v: Double) -> String {
        // Three decimals is well under a device pixel at any size these assets render at, and
        // keeps the generated source readable.
        let rounded = (v * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private func point(_ x: Double, _ y: Double) -> String {
        let (tx, ty) = transform.apply(x, y)
        return "p(\(fmt(tx)), \(fmt(ty)))"
    }

    mutating func move(_ x: Double, _ y: Double) { lines.append("$0.move(to: \(point(x, y)))") }
    mutating func line(_ x: Double, _ y: Double) { lines.append("$0.addLine(to: \(point(x, y)))") }

    mutating func curve(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        lines.append("$0.addCurve(to: \(point(x, y)), control1: \(point(x1, y1)), control2: \(point(x2, y2)))")
    }

    mutating func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        lines.append("$0.addQuadCurve(to: \(point(x, y)), control: \(point(cx, cy)))")
    }

    mutating func close() { lines.append("$0.closeSubpath()") }
}

/// Splits SVG path data into commands and numbers. Hand-rolled because SVG permits implicit
/// separators that no general tokenizer expects: `1-2` is two numbers, and so is `.5.5`.
struct PathScanner {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) { chars = Array(s) }

    private mutating func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n"
                || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
    }

    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard i < chars.count, chars[i].isLetter else { return nil }
        defer { i += 1 }
        return chars[i]
    }

    var atCommand: Bool {
        var j = i
        while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n"
                || chars[j] == "\t" || chars[j] == "\r" { j += 1 }
        return j < chars.count && chars[j].isLetter
    }

    var atEnd: Bool {
        var j = i
        while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n"
                || chars[j] == "\t" || chars[j] == "\r" { j += 1 }
        return j >= chars.count
    }

    mutating func nextNumber() -> Double? {
        skipSeparators()
        guard i < chars.count else { return nil }
        var s = ""
        if chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
        var sawDot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c); i += 1 }
            else if c == ".", !sawDot { sawDot = true; s.append(c); i += 1 }
            else if c == "e" || c == "E" {
                // Exponent, with its own optional sign.
                s.append(c); i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            } else { break }
        }
        return Double(s)
    }

    /// Arc flags are single characters and may be written with no separator at all
    /// (`a5 5 0 1150 50`), so they cannot go through `nextNumber`.
    mutating func nextFlag() -> Bool? {
        skipSeparators()
        guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
        defer { i += 1 }
        return chars[i] == "1"
    }
}

/// Converts an SVG elliptical arc to cubic Beziers, appending them to the emitter.
///
/// Endpoint parameterisation per the SVG 1.1 implementation notes (F.6.5), then split into
/// segments of at most 90 degrees - a single cubic cannot approximate a wider sweep to within
/// a usable tolerance.
func appendArc(_ emitter: inout PathEmitter,
               from x0: Double, _ y0: Double,
               rx rxIn: Double, ry ryIn: Double,
               rotation: Double, largeArc: Bool, sweep: Bool,
               to x: Double, _ y: Double) {
    var rx = rxIn.magnitude, ry = ryIn.magnitude
    // Degenerate radii mean a straight line, per spec.
    guard rx > 0, ry > 0, !(x0 == x && y0 == y) else {
        emitter.line(x, y)
        return
    }

    let phi = rotation * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)

    let dx2 = (x0 - x) / 2, dy2 = (y0 - y) / 2
    let x1p = cosPhi * dx2 + sinPhi * dy2
    let y1p = -sinPhi * dx2 + cosPhi * dy2

    // Scale radii up if they are too small to span the endpoints (F.6.6).
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 {
        let s = lambda.squareRoot()
        rx *= s
        ry *= s
    }

    let sign: Double = (largeArc != sweep) ? 1 : -1
    let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
    let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    let coefficient = denominator == 0 ? 0 : sign * (numerator / denominator).squareRoot()

    let cxp = coefficient * rx * y1p / ry
    let cyp = -coefficient * ry * x1p / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (x0 + x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (y0 + y) / 2

    func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        let dot = ux * vx + uy * vy
        let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
        guard len > 0 else { return 0 }
        let a = acos(max(-1, min(1, dot / len)))
        return (ux * vy - uy * vx) < 0 ? -a : a
    }

    let startX = (x1p - cxp) / rx, startY = (y1p - cyp) / ry
    let endX = (-x1p - cxp) / rx, endY = (-y1p - cyp) / ry
    let theta1 = angle(1, 0, startX, startY)
    var delta = angle(startX, startY, endX, endY)
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    let segments = max(1, Int(ceil((delta.magnitude) / (.pi / 2))))
    let step = delta / Double(segments)
    // Control-point distance for a cubic approximation of a circular arc of angle `step`.
    let alpha = 4.0 / 3.0 * tan(step / 4)

    var theta = theta1
    for _ in 0..<segments {
        let next = theta + step
        let cosT = cos(theta), sinT = sin(theta)
        let cosN = cos(next), sinN = sin(next)

        func pointOn(_ ct: Double, _ st: Double) -> (Double, Double) {
            (cx + rx * cosPhi * ct - ry * sinPhi * st,
             cy + rx * sinPhi * ct + ry * cosPhi * st)
        }
        func derivativeAt(_ ct: Double, _ st: Double) -> (Double, Double) {
            (-rx * cosPhi * st - ry * sinPhi * ct,
             -rx * sinPhi * st + ry * cosPhi * ct)
        }

        let (px, py) = pointOn(cosT, sinT)
        let (nx, ny) = pointOn(cosN, sinN)
        let (dpx, dpy) = derivativeAt(cosT, sinT)
        let (dnx, dny) = derivativeAt(cosN, sinN)

        emitter.curve(px + alpha * dpx, py + alpha * dpy,
                      nx - alpha * dnx, ny - alpha * dny,
                      nx, ny)
        theta = next
    }
}

/// Walks SVG path data, emitting Swift as it goes.
func emitPathData(_ data: String, transform: Affine) -> [String] {
    var emitter = PathEmitter(transform: transform)
    var scanner = PathScanner(data)

    var current = (x: 0.0, y: 0.0)
    var subpathStart = (x: 0.0, y: 0.0)
    // Reflected control point for smooth curves (S/T); nil when the previous command was not
    // a curve of the matching kind, in which case the spec says to reuse the current point.
    var lastCubicControl: (x: Double, y: Double)?
    var lastQuadControl: (x: Double, y: Double)?

    var command: Character = " "
    while !scanner.atEnd {
        if scanner.atCommand, let next = scanner.nextCommand() {
            command = next
        } else if command == "M" {
            command = "L"           // implicit lineto after a moveto
        } else if command == "m" {
            command = "l"
        }

        let relative = command.isLowercase
        func resolve(_ x: Double, _ y: Double) -> (Double, Double) {
            relative ? (current.x + x, current.y + y) : (x, y)
        }

        switch Character(command.uppercased()) {
        case "M":
            guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let (ax, ay) = resolve(x, y)
            emitter.move(ax, ay)
            current = (ax, ay)
            subpathStart = (ax, ay)
            lastCubicControl = nil; lastQuadControl = nil

        case "L":
            guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let (ax, ay) = resolve(x, y)
            emitter.line(ax, ay)
            current = (ax, ay)
            lastCubicControl = nil; lastQuadControl = nil

        case "H":
            guard let x = scanner.nextNumber() else { break }
            let ax = relative ? current.x + x : x
            emitter.line(ax, current.y)
            current = (ax, current.y)
            lastCubicControl = nil; lastQuadControl = nil

        case "V":
            guard let y = scanner.nextNumber() else { break }
            let ay = relative ? current.y + y : y
            emitter.line(current.x, ay)
            current = (current.x, ay)
            lastCubicControl = nil; lastQuadControl = nil

        case "C":
            guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                  let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                  let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let (c1x, c1y) = resolve(x1, y1)
            let (c2x, c2y) = resolve(x2, y2)
            let (ax, ay) = resolve(x, y)
            emitter.curve(c1x, c1y, c2x, c2y, ax, ay)
            current = (ax, ay)
            lastCubicControl = (c2x, c2y); lastQuadControl = nil

        case "S":
            guard let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                  let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let reflected = lastCubicControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) }
                ?? (current.x, current.y)
            let (c2x, c2y) = resolve(x2, y2)
            let (ax, ay) = resolve(x, y)
            emitter.curve(reflected.0, reflected.1, c2x, c2y, ax, ay)
            current = (ax, ay)
            lastCubicControl = (c2x, c2y); lastQuadControl = nil

        case "Q":
            guard let cx = scanner.nextNumber(), let cy = scanner.nextNumber(),
                  let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let (qx, qy) = resolve(cx, cy)
            let (ax, ay) = resolve(x, y)
            emitter.quad(qx, qy, ax, ay)
            current = (ax, ay)
            lastQuadControl = (qx, qy); lastCubicControl = nil

        case "T":
            guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let reflected = lastQuadControl.map { (2 * current.x - $0.x, 2 * current.y - $0.y) }
                ?? (current.x, current.y)
            let (ax, ay) = resolve(x, y)
            emitter.quad(reflected.0, reflected.1, ax, ay)
            current = (ax, ay)
            lastQuadControl = (reflected.0, reflected.1); lastCubicControl = nil

        case "A":
            guard let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                  let rot = scanner.nextNumber(), let large = scanner.nextFlag(),
                  let sweep = scanner.nextFlag(),
                  let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
            let (ax, ay) = resolve(x, y)
            appendArc(&emitter, from: current.x, current.y, rx: rx, ry: ry,
                      rotation: rot, largeArc: large, sweep: sweep, to: ax, ay)
            current = (ax, ay)
            lastCubicControl = nil; lastQuadControl = nil

        case "Z":
            emitter.close()
            current = subpathStart
            lastCubicControl = nil; lastQuadControl = nil

        default:
            warn("unknown path command '\(command)' - skipping the rest of this path")
            return emitter.lines
        }
    }
    return emitter.lines
}

// MARK: - Transform attribute

func parseTransform(_ raw: String) -> Affine {
    var result = Affine.identity
    var remaining = Substring(raw)

    while let open = remaining.firstIndex(of: "("), let close = remaining.firstIndex(of: ")") {
        let name = remaining[remaining.startIndex..<open]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t\r"))
        let numbers = remaining[remaining.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            .compactMap { Double($0) }
        remaining = remaining[remaining.index(after: close)...]

        var step = Affine.identity
        switch name {
        case "translate":
            step.e = numbers.first ?? 0
            step.f = numbers.count > 1 ? numbers[1] : 0
        case "scale":
            step.a = numbers.first ?? 1
            step.d = numbers.count > 1 ? numbers[1] : (numbers.first ?? 1)
        case "rotate":
            let angle = (numbers.first ?? 0) * .pi / 180
            var rotation = Affine(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), e: 0, f: 0)
            if numbers.count >= 3 {
                // rotate(a, cx, cy) == translate(cx,cy) rotate(a) translate(-cx,-cy)
                let cx = numbers[1], cy = numbers[2]
                let toOrigin = Affine(a: 1, b: 0, c: 0, d: 1, e: -cx, f: -cy)
                let back = Affine(a: 1, b: 0, c: 0, d: 1, e: cx, f: cy)
                rotation = toOrigin.concatenating(rotation).concatenating(back)
            }
            step = rotation
        case "skewX":
            step.c = tan((numbers.first ?? 0) * .pi / 180)
        case "skewY":
            step.b = tan((numbers.first ?? 0) * .pi / 180)
        case "matrix":
            guard numbers.count >= 6 else { break }
            step = Affine(a: numbers[0], b: numbers[1], c: numbers[2],
                          d: numbers[3], e: numbers[4], f: numbers[5])
        case "":
            break
        default:
            warn("unsupported transform '\(name)' - ignoring it")
        }
        // Left-to-right in the attribute means the leftmost is outermost.
        result = step.concatenating(result)
    }
    return result
}

// MARK: - Parsing

struct Shape {
    let comment: String
    let buildLines: [String]
    let paint: Paint
}

final class SVGParser: NSObject, XMLParserDelegate {
    var shapes: [Shape] = []
    var viewBox: (x: Double, y: Double, w: Double, h: Double)?
    var declaredWidth: Double?
    var declaredHeight: Double?

    private var paintStack: [Paint] = [Paint()]
    private var transformStack: [Affine] = [.identity]
    /// Depth of elements we are ignoring wholesale (defs, clipPath, mask, filter, text).
    private var skipDepth = 0

    private func length(_ s: String?) -> Double? {
        guard var v = s?.trimmingCharacters(in: .whitespaces) else { return nil }
        for unit in ["px", "pt", "mm", "cm", "in", "%"] where v.hasSuffix(unit) {
            v = String(v.dropLast(unit.count))
        }
        return Double(v)
    }

    /// Resolves this element's paint, inheriting whatever it does not override.
    private func resolvePaint(_ attrs: [String: String]) -> Paint {
        var paint = paintStack.last ?? Paint()

        // Inline `style` wins over presentation attributes, per CSS precedence.
        var declarations = attrs
        if let style = attrs["style"] {
            for declaration in style.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                declarations[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        if let value = declarations["fill"] {
            let resolved = normalizeColor(value)
            paint.fill = resolved?.hex
            paint.fillColorAlpha = resolved?.alpha ?? 1
        }
        if let value = declarations["stroke"] {
            let resolved = normalizeColor(value)
            paint.stroke = resolved?.hex
            paint.strokeColorAlpha = resolved?.alpha ?? 1
        }
        if let value = length(declarations["stroke-width"]) { paint.strokeWidth = value }
        if let value = Double(declarations["opacity"] ?? "") { paint.opacity = value }
        if let value = Double(declarations["fill-opacity"] ?? "") { paint.fillOpacity = value }
        if let value = Double(declarations["stroke-opacity"] ?? "") { paint.strokeOpacity = value }
        if let value = declarations["stroke-linecap"] {
            paint.lineCap = value.trimmingCharacters(in: .whitespaces)
        }
        if let value = declarations["stroke-linejoin"] {
            paint.lineJoin = value.trimmingCharacters(in: .whitespaces)
        }
        if let rule = declarations["fill-rule"] ?? declarations["clip-rule"] {
            paint.evenOdd = rule.trimmingCharacters(in: .whitespaces) == "evenodd"
        }
        return paint
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attrs: [String: String] = [:]) {

        if skipDepth > 0 { skipDepth += 1; return }

        let unsupportedContainers = ["defs", "clippath", "mask", "filter", "text", "pattern",
                                     "lineargradient", "radialgradient", "symbol"]
        if unsupportedContainers.contains(element.lowercased()) {
            warn("<\(element)> is not supported - skipping it and its contents")
            skipDepth = 1
            return
        }
        if element.lowercased() == "use" {
            warn("<use> instancing is not supported - expand it in the design tool")
            return
        }

        var paint = resolvePaint(attrs)
        let local = attrs["transform"].map(parseTransform) ?? .identity
        let transform = local.concatenating(transformStack.last ?? .identity)
        paint.strokeScale = transform.strokeScale

        switch element.lowercased() {
        case "svg":
            declaredWidth = length(attrs["width"])
            declaredHeight = length(attrs["height"])
            if let box = attrs["viewBox"] {
                let n = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                if n.count == 4 { viewBox = (n[0], n[1], n[2], n[3]) }
            }
            // An <svg> element paints nothing itself, but it does establish inherited paint.
            paintStack.append(paint)
            transformStack.append(transform)
            return

        case "g":
            paintStack.append(paint)
            transformStack.append(transform)
            return

        case "path":
            guard let d = attrs["d"], !d.isEmpty else { break }
            shapes.append(Shape(comment: "path", buildLines: emitPathData(d, transform: transform),
                                paint: paint))

        case "circle":
            let cx = length(attrs["cx"]) ?? 0, cy = length(attrs["cy"]) ?? 0
            guard let r = length(attrs["r"]), r > 0 else { break }
            shapes.append(Shape(comment: "circle",
                                buildLines: ellipseLines(cx: cx, cy: cy, rx: r, ry: r, transform: transform),
                                paint: paint))

        case "ellipse":
            let cx = length(attrs["cx"]) ?? 0, cy = length(attrs["cy"]) ?? 0
            guard let rx = length(attrs["rx"]), let ry = length(attrs["ry"]), rx > 0, ry > 0 else { break }
            shapes.append(Shape(comment: "ellipse",
                                buildLines: ellipseLines(cx: cx, cy: cy, rx: rx, ry: ry, transform: transform),
                                paint: paint))

        case "rect":
            let x = length(attrs["x"]) ?? 0, y = length(attrs["y"]) ?? 0
            guard let w = length(attrs["width"]), let h = length(attrs["height"]), w > 0, h > 0 else { break }
            // SVG lets one radius stand in for the other.
            let rx = length(attrs["rx"]) ?? length(attrs["ry"]) ?? 0
            let ry = length(attrs["ry"]) ?? rx
            shapes.append(Shape(comment: "rect",
                                buildLines: rectLines(x: x, y: y, w: w, h: h,
                                                      rx: min(rx, w / 2), ry: min(ry, h / 2),
                                                      transform: transform),
                                paint: paint))

        case "line":
            let x1 = length(attrs["x1"]) ?? 0, y1 = length(attrs["y1"]) ?? 0
            let x2 = length(attrs["x2"]) ?? 0, y2 = length(attrs["y2"]) ?? 0
            var emitter = PathEmitter(transform: transform)
            emitter.move(x1, y1)
            emitter.line(x2, y2)
            // A <line> has no interior; painting one would fill a hairline sliver.
            var linePaint = paint
            linePaint.fill = nil
            shapes.append(Shape(comment: "line", buildLines: emitter.lines, paint: linePaint))

        case "polygon", "polyline":
            guard let points = attrs["points"] else { break }
            let n = points.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
                .compactMap { Double($0) }
            guard n.count >= 4 else { break }
            var emitter = PathEmitter(transform: transform)
            emitter.move(n[0], n[1])
            var i = 2
            while i + 1 < n.count {
                emitter.line(n[i], n[i + 1])
                i += 2
            }
            // A <polyline> is filled as if closed, per SVG 1.1 s9.6 - it is only the path
            // that stays open, not the region. Only <line> genuinely has no fillable area.
            if element.lowercased() == "polygon" { emitter.close() }
            shapes.append(Shape(comment: element.lowercased(), buildLines: emitter.lines, paint: paint))

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if skipDepth > 0 { skipDepth -= 1; return }
        if ["g", "svg"].contains(element.lowercased()) {
            if paintStack.count > 1 { paintStack.removeLast() }
            if transformStack.count > 1 { transformStack.removeLast() }
        }
    }

    /// Four cubics, the standard Bezier circle approximation. Emitted as curves rather than as
    /// `Path(ellipseIn:)` because a transform may have sheared or rotated the ellipse, which a
    /// rect-based constructor cannot express.
    private func ellipseLines(cx: Double, cy: Double, rx: Double, ry: Double, transform: Affine) -> [String] {
        let k = 0.5522847498
        var emitter = PathEmitter(transform: transform)
        emitter.move(cx + rx, cy)
        emitter.curve(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry)
        emitter.curve(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy)
        emitter.curve(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry)
        emitter.curve(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy)
        emitter.close()
        return emitter.lines
    }

    private func rectLines(x: Double, y: Double, w: Double, h: Double,
                           rx: Double, ry: Double, transform: Affine) -> [String] {
        var emitter = PathEmitter(transform: transform)
        guard rx > 0, ry > 0 else {
            emitter.move(x, y)
            emitter.line(x + w, y)
            emitter.line(x + w, y + h)
            emitter.line(x, y + h)
            emitter.close()
            return emitter.lines
        }
        let k = 0.5522847498
        emitter.move(x + rx, y)
        emitter.line(x + w - rx, y)
        emitter.curve(x + w - rx + rx * k, y, x + w, y + ry - ry * k, x + w, y + ry)
        emitter.line(x + w, y + h - ry)
        emitter.curve(x + w, y + h - ry + ry * k, x + w - rx + rx * k, y + h, x + w - rx, y + h)
        emitter.line(x + rx, y + h)
        emitter.curve(x + rx - rx * k, y + h, x, y + h - ry + ry * k, x, y + h - ry)
        emitter.line(x, y + ry)
        emitter.curve(x, y + ry - ry * k, x + rx - rx * k, y, x + rx, y)
        emitter.close()
        return emitter.lines
    }
}

// MARK: - Run

guard let data = try? Data(contentsOf: inputURL) else {
    fail("could not read \(inputURL.path)")
}

let parser = XMLParser(data: data)
let delegate = SVGParser()
parser.delegate = delegate
guard parser.parse() else {
    fail("XML parse failed: \(parser.parserError?.localizedDescription ?? "unknown error")")
}
guard !delegate.shapes.isEmpty else {
    fail("no drawable shapes found - if the file uses <use>, <text> or gradients, flatten it first")
}

// The design frame: viewBox if present, else the declared width/height, else a 100x100 default.
let box = delegate.viewBox
let frameW = box?.w ?? delegate.declaredWidth ?? 100
let frameH = box?.h ?? delegate.declaredHeight ?? 100
if box == nil {
    warn("no viewBox - falling back to a \(Int(frameW))x\(Int(frameH)) design frame")
}
// A viewBox origin shifts every coordinate; fold it into the p() helper rather than into every
// emitted number, so the generated numbers still match what the design file shows.
let originX = box?.x ?? 0
let originY = box?.y ?? 0

func pascalCase(_ s: String) -> String {
    s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined()
}

let sourceName = inputURL.lastPathComponent
let typeName = explicitName ?? (pascalCase(inputURL.deletingPathExtension().lastPathComponent) + "Art")

func number(_ v: Double) -> String {
    let rounded = (v * 1000).rounded() / 1000
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

var out: [String] = []
out.append("// Generated by Scripts/svg2swift.swift from \(sourceName) - do not edit by hand.")
out.append("//")
out.append("// Regenerate with:")
out.append("//     swift Scripts/svg2swift.swift <path>/\(sourceName) \(typeName) \\")
out.append("//         > Sources/UI/Art/\(typeName).swift")
out.append("")
out.append("import SwiftUI")
out.append("")
out.append("/// Drawn from `\(sourceName)`, authored in a \(number(frameW)) x \(number(frameH)) frame.")
out.append("///")
out.append("/// Scales to whatever size it is given: every coordinate goes through `p()`, which maps")
out.append("/// the design frame onto the view's bounds, so the art has no fixed size of its own.")
out.append("struct \(typeName): View {")
out.append("    var body: some View {")
out.append("        Canvas { context, size in")
out.append("            let rect = CGRect(origin: .zero, size: size)")
out.append("")
out.append("            /// A design-space point mapped into the view's bounds.")
out.append("            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {")
out.append("                CGPoint(x: rect.minX + (x - \(number(originX))) / \(number(frameW)) * rect.width,")
out.append("                        y: rect.minY + (y - \(number(originY))) / \(number(frameH)) * rect.height)")
out.append("            }")
out.append("            /// Stroke widths key off width alone, matching the rest of `Sources/UI/Art` -")
out.append("            /// scaling them off the smaller axis thins every line on a non-square frame.")
out.append("            func w(_ v: CGFloat) -> CGFloat { v / \(number(frameW)) * rect.width }")
out.append("            func shape(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }")

for (index, shape) in delegate.shapes.enumerated() {
    guard shape.paint.fill != nil || shape.paint.stroke != nil else { continue }
    out.append("")
    out.append("            // \(index + 1). \(shape.comment)")
    out.append("            let shape\(index) = shape {")
    for line in shape.buildLines {
        out.append("                \(line)")
    }
    out.append("            }")

    if let fill = shape.paint.fill {
        let alpha = shape.paint.effectiveFillOpacity
        let color = alpha < 1
            ? "Color(hex: \"\(fill)\").opacity(\(number(alpha)))"
            : "Color(hex: \"\(fill)\")"
        let style = shape.paint.evenOdd ? ", style: FillStyle(eoFill: true)" : ""
        out.append("            context.fill(shape\(index), with: .color(\(color))\(style))")
    }
    if let stroke = shape.paint.stroke {
        let alpha = shape.paint.effectiveStrokeOpacity
        let color = alpha < 1
            ? "Color(hex: \"\(stroke)\").opacity(\(number(alpha)))"
            : "Color(hex: \"\(stroke)\")"
        // Bake the element's own transform scale into the emitted width, the way the geometry
        // already is - so the generated number is the width as it actually renders.
        let width = shape.paint.strokeWidth * shape.paint.strokeScale
        let cap = ["butt": "butt", "round": "round", "square": "square"][shape.paint.lineCap] ?? "butt"
        let join = ["miter": "miter", "round": "round", "bevel": "bevel"][shape.paint.lineJoin] ?? "miter"
        out.append("            context.stroke(shape\(index), with: .color(\(color)),")
        out.append("                           style: StrokeStyle(lineWidth: w(\(number(width))), lineCap: .\(cap), lineJoin: .\(join)))")
    }
}

out.append("        }")
out.append("        .accessibilityHidden(true)")
out.append("    }")
out.append("}")
out.append("")

print(out.joined(separator: "\n"))
warn("generated \(typeName) from \(delegate.shapes.count) shape(s)")
