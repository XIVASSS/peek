//
//  PassiveAntiSpoof.swift
//  glance
//
//  Presentation-attack cues from a face crop — moiré / screen grid energy,
//  unnaturally uniform sharpness, and "cardboard flatness" of local contrast.
//  Complements gloss/device detectors. Not a substitute for TrueDepth; tuned
//  to reject printed photos and phone-screen replays with high confidence.
//

import CoreGraphics
import Foundation

/// Texture measurements from one face crop. Fed into the `passiveSpoof` deny cue.
/// Type lives in `GlareCue.swift` so the offline liveness selftest can compile without this file.
nonisolated enum PassiveAntiSpoof {
    private static let analysisSize = 96
    private static let tileGrid = 4

    static func extract(faceCrop: CGImage) -> SpoofTextureSample? {
        guard let gray = downsampleGray(faceCrop, size: analysisSize) else { return nil }
        let n = analysisSize
        let periodic = periodicHighFrequencyEnergy(gray, width: n, height: n)
        let (meanSharp, uniformity) = sharpnessStats(gray, width: n, height: n)
        let banding = bandingEnergy(gray, width: n, height: n)

        // Live skin: moderate local variance, low periodicity, uneven sharpness (nose vs cheek focus).
        // Print/screen: higher periodic energy and/or near-uniform sharpness across tiles.
        let periodicScore = ramp(periodic, floor: 0.08, ceiling: 0.35)
        let uniformScore = ramp(uniformity, floor: 0.55, ceiling: 0.92)
        let bandingScore = ramp(banding, floor: 0.04, ceiling: 0.2)
        // Very low overall sharpness can also mean a blurry photo held to camera — mild contribution.
        let softScore = 1 - ramp(meanSharp, floor: 0.008, ceiling: 0.04)

        let spoof = min(1, 0.45 * periodicScore + 0.35 * uniformScore + 0.15 * bandingScore + 0.05 * softScore)

        return SpoofTextureSample(
            cropPixelWidth: CGFloat(faceCrop.width),
            spoofScore: spoof,
            periodicEnergy: periodic,
            sharpnessUniformity: uniformity,
            bandingEnergy: banding
        )
    }

    // MARK: - Features

    /// Fraction of spectral energy in mid/high bands with neighbor-bin peaks — a cheap moiré proxy
    /// without a full FFT (row/column 1D periodograms).
    private static func periodicHighFrequencyEnergy(_ gray: [Float], width: Int, height: Int) -> Float {
        var rowEnergy: Float = 0
        var rowHigh: Float = 0
        for y in 0..<height {
            let base = y * width
            var prev = gray[base]
            var diffs: [Float] = []
            diffs.reserveCapacity(width - 1)
            for x in 1..<width {
                let v = gray[base + x]
                diffs.append(v - prev)
                prev = v
            }
            let energy = diffs.reduce(0) { $0 + $1 * $1 }
            rowEnergy += energy
            // Zero-crossing rate of the derivative ≈ high-frequency content.
            var crossings = 0
            for i in 1..<diffs.count where diffs[i - 1] * diffs[i] < 0 {
                crossings += 1
            }
            let rate = Float(crossings) / Float(max(diffs.count, 1))
            // Dense regular crossings (pixel grid) score higher than organic skin texture.
            if rate > 0.35 {
                rowHigh += energy * rate
            }
        }

        var colEnergy: Float = 0
        var colHigh: Float = 0
        for x in 0..<width {
            var prev = gray[x]
            var diffs: [Float] = []
            diffs.reserveCapacity(height - 1)
            for y in 1..<height {
                let v = gray[y * width + x]
                diffs.append(v - prev)
                prev = v
            }
            let energy = diffs.reduce(0) { $0 + $1 * $1 }
            colEnergy += energy
            var crossings = 0
            for i in 1..<diffs.count where diffs[i - 1] * diffs[i] < 0 {
                crossings += 1
            }
            let rate = Float(crossings) / Float(max(diffs.count, 1))
            if rate > 0.35 {
                colHigh += energy * rate
            }
        }

        let total = rowEnergy + colEnergy
        guard total > 1e-6 else { return 0 }
        return (rowHigh + colHigh) / total
    }

    private static func sharpnessStats(_ gray: [Float], width: Int, height: Int) -> (mean: Float, uniformity: Float) {
        let tileW = width / tileGrid
        let tileH = height / tileGrid
        guard tileW > 2, tileH > 2 else { return (0, 0) }

        var variances: [Float] = []
        variances.reserveCapacity(tileGrid * tileGrid)

        for ty in 0..<tileGrid {
            for tx in 0..<tileGrid {
                let x0 = tx * tileW
                let y0 = ty * tileH
                var sum: Float = 0
                var sumSq: Float = 0
                var count: Float = 0
                for y in (y0 + 1)..<(y0 + tileH - 1) {
                    for x in (x0 + 1)..<(x0 + tileW - 1) {
                        let i = y * width + x
                        // 4-neighbor Laplacian magnitude.
                        let lap = abs(
                            4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - width] - gray[i + width]
                        )
                        sum += lap
                        sumSq += lap * lap
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                let mean = sum / count
                let variance = max(0, sumSq / count - mean * mean)
                variances.append(variance)
            }
        }

        guard !variances.isEmpty else { return (0, 0) }
        let meanVar = variances.reduce(0, +) / Float(variances.count)
        // Coefficient of variation inverted → uniformity (1 = all tiles identical).
        let std = sqrt(variances.reduce(0) { $0 + ($1 - meanVar) * ($1 - meanVar) } / Float(variances.count))
        let cv = meanVar > 1e-8 ? std / meanVar : 0
        let uniformity = max(0, min(1, 1 - cv / 1.2))
        return (meanVar, uniformity)
    }

    /// Quantization / banding: histogram occupancy of coarse luma bins vs smooth skin.
    private static func bandingEnergy(_ gray: [Float], width: Int, height: Int) -> Float {
        var hist = [Float](repeating: 0, count: 32)
        let count = Float(width * height)
        for v in gray {
            let bin = min(31, max(0, Int(v * 31)))
            hist[bin] += 1
        }
        // Peakiness: few bins dominate → posterized screen/print.
        let sorted = hist.sorted(by: >)
        let top = sorted.prefix(3).reduce(0, +)
        return top / count
    }

    // MARK: - Image

    private static func downsampleGray(_ image: CGImage, size: Int) -> [Float]? {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = rgba.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var gray = [Float](repeating: 0, count: size * size)
        for i in 0..<(size * size) {
            let o = i * 4
            let r = Float(rgba[o])
            let g = Float(rgba[o + 1])
            let b = Float(rgba[o + 2])
            gray[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        }
        return gray
    }

    private static func ramp(_ value: Float, floor: Float, ceiling: Float) -> Float {
        min(max((value - floor) / max(ceiling - floor, 0.0001), 0), 1)
    }
}
