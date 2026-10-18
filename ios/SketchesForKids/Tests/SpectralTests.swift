import simd
import XCTest
@testable import SketchesForKids

/// The paint mixes as spectral.js 3.0.0 does (reference values computed with
/// spectral.js itself, `mix([a, 1], [b, 1])`, clamped to 255).
final class SpectralTests: XCTestCase {
    private func hex(_ s: String) -> SIMD3<Float> {
        let v = Int(s.dropFirst(), radix: 16)!
        return SIMD3(Float((v >> 16) & 255), Float((v >> 8) & 255), Float(v & 255)) / 255
    }

    func testMixesLikeSpectralJS() {
        let cases: [(String, String, SIMD3<Float>)] = [
            ("#FF6B6B", "#FFD140", SIMD3(255, 150, 81)),    // coral + lemon: orange
            ("#4D96FF", "#FFD140", SIMD3(126, 187, 95)),    // ocean + lemon: green, as paint does
            ("#4D96FF", "#FF6B6B", SIMD3(123, 127, 138)),   // ocean + coral
            ("#5FD168", "#9B5DE5", SIMD3(116, 150, 125)),   // grass + berry
            ("#FFA62B", "#4D96FF", SIMD3(124, 165, 78)),    // tangerine + ocean: green too
            ("#FFFFFF", "#4D96FF", SIMD3(136, 197, 255)),   // white + ocean: a tint
        ]
        for (a, b, expected) in cases {
            let m = Spectral.mix([(hex(a), 1), (hex(b), 1)]) * 255
            XCTAssertLessThanOrEqual(simd_reduce_max(abs(m.rounded(.toNearestOrEven) - expected)), 1, "\(a) + \(b) = \(m)")
        }
    }

    func testAPigmentAloneKeepsItsColour() {
        for color in [hex("#FF6B6B"), hex("#4D96FF"), hex("#FFD140"), hex("#9B5DE5")] {
            let m = Spectral.mix([(color, 1)])
            XCTAssertLessThan(simd_reduce_max(abs(m - color)), 1.5 / 255, "\(color)")
        }
    }

    func testTheGPUTablesMatchThePalette() {
        let t = Spectral.tables(for: [hex("#FF6B6B"), hex("#4D96FF")])
        XCTAssertEqual(t.ks.count, 7 * 38)
        XCTAssertEqual(t.luminance.count, 8)
        XCTAssertEqual(t.cmf.count, 3 * 38)
        XCTAssertEqual(t.bytes.count, (7 * 38 + 8 + 3 * 38), "the layout of SpectralData in Fluid.metal")
        XCTAssertGreaterThan(t.luminance[0], t.luminance[1], "coral is lighter than ocean blue")
    }
}
