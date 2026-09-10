//
//  MiniFASNetPAD.swift
//  glance
//
//  On-device silent presentation-attack detection via MiniFASNetV2
//  (https://github.com/minivision-ai/Silent-Face-Anti-Spoofing).
//  Label index 1 = real; 0 and 2 = spoof. Input is 80×80 BGR float32 in 0…255.
//

import CoreGraphics
import CoreML
import Foundation

enum MiniFASNetPADError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "MiniFASNetV2.mlmodelc not found in the app bundle. Run tools/convert_minifasnet_coreml.py."
        }
    }
}

nonisolated final class MiniFASNetPAD: @unchecked Sendable {
    static let shared: MiniFASNetPAD? = {
        do { return try MiniFASNetPAD() }
        catch {
            return nil
        }
    }()

    private static let inputSize = 80
    /// Same crop expansion as upstream Silent-Face-Anti-Spoofing / yakhyo (V2 scale).
    private static let cropScale: CGFloat = 2.7
    private static let inputName = "input_image"
    private static let outputName = "logits"

    private let model: MLModel

    init() throws {
        guard let url = Bundle.main.url(forResource: "MiniFASNetV2", withExtension: "mlmodelc") else {
            throw MiniFASNetPADError.modelNotFound
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    /// Score a face in a full camera frame. `faceBox` is Vision-normalized (origin bottom-left).
    func score(frame: CGImage, faceBox: CGRect) -> SilentAntiSpoofSample? {
        guard let crop = expandedFaceCrop(from: frame, faceBox: faceBox, scale: Self.cropScale) else {
            return nil
        }
        guard let resized = resize(crop, to: Self.inputSize) else { return nil }
        guard let multiArray = bgrFloatArray(from: resized) else { return nil }

        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: multiArray)
        ])
        guard let provider,
              let out = try? model.prediction(from: provider),
              let logits = out.featureValue(for: Self.outputName)?.multiArrayValue else {
            return nil
        }

        let probs = softmax3(logits)
        return SilentAntiSpoofSample(realProbability: probs[1])
    }

    // MARK: - Preprocess

    private func expandedFaceCrop(from frame: CGImage, faceBox: CGRect, scale: CGFloat) -> CGImage? {
        let w = CGFloat(frame.width)
        let h = CGFloat(frame.height)
        // Vision normalized → pixel, origin top-left for CGImage cropping.
        let faceW = faceBox.width * w
        let faceH = faceBox.height * h
        let faceX = faceBox.minX * w
        let faceY = (1 - faceBox.maxY) * h

        let newW = min(w, faceW * scale)
        let newH = min(h, faceH * scale)
        let centerX = faceX + faceW / 2
        let centerY = faceY + faceH / 2
        var x1 = centerX - newW / 2
        var y1 = centerY - newH / 2
        x1 = max(0, min(x1, w - newW))
        y1 = max(0, min(y1, h - newH))

        let rect = CGRect(x: x1.rounded(.down), y: y1.rounded(.down),
                          width: newW.rounded(.down), height: newH.rounded(.down))
        guard rect.width >= 16, rect.height >= 16 else { return nil }
        return frame.cropping(to: rect)
    }

    private func resize(_ image: CGImage, to size: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }

    /// NCHW BGR float32 in 0…255 — matches OpenCV training pipeline.
    private func bgrFloatArray(from image: CGImage) -> MLMultiArray? {
        let size = Self.inputSize
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
                                            dataType: .float32) else { return nil }
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let r = Float(ptr[i])
                let g = Float(ptr[i + 1])
                let b = Float(ptr[i + 2])
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: b)
                array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: g)
                array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: r)
            }
        }
        return array
    }

    private func softmax3(_ logits: MLMultiArray) -> [Float] {
        var vals: [Float] = [0, 0, 0]
        for i in 0..<3 {
            if logits.shape.count >= 2 {
                vals[i] = logits[[0, i] as [NSNumber]].floatValue
            } else if i < logits.count {
                vals[i] = logits[i].floatValue
            }
        }
        let maxV = vals.max() ?? 0
        let exps = vals.map { expf($0 - maxV) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return [0, 0, 0] }
        return exps.map { $0 / sum }
    }
}
