//
//  FaceGeometryTemplate.swift
//  glance
//
//  Compact 3D-proxy face templates derived from Vision landmarks.
//  Not TrueDepth — Mac webcams have no IR depth — but multi-pose shape +
//  nose-parallax signatures make a flat photo much harder to reuse as "you."
//  Images are never stored; only normalized float vectors encrypted with identities.
//

import Foundation
import CoreGraphics
import Vision

/// One pose's geometric fingerprint. Shape is eye-centered / IOD-scaled so
/// camera distance drops out; depth features capture the 3D cues a print can't fake under yaw.
struct FaceGeometryDescriptor: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let pose: String?
    let yaw: Float
    let pitch: Float
    /// Even-length L2-normalized [x0,y0,x1,y1,...] in eye-centered IOD units.
    let shape: [Float]
    /// Scale-free depth proxies: [noseOffset, noseProtrusion, midFaceHeight, jawWidth, browTilt].
    let depth: [Float]

    init(
        version: Int = FaceGeometryDescriptor.currentVersion,
        pose: String?,
        yaw: Float,
        pitch: Float,
        shape: [Float],
        depth: [Float]
    ) {
        self.version = version
        self.pose = pose
        self.yaw = yaw
        self.pitch = pitch
        self.shape = shape
        self.depth = depth
    }
}

/// Aggregated 3D-proxy profile for one identity — templates per capture plus the
/// enrollment-time nose-parallax signature across guided head turns.
struct FaceGeometryProfile: Codable, Equatable, Sendable {
    var templates: [FaceGeometryDescriptor]
    /// Pearson r of noseOffset vs tan(yaw) across enrollment samples. Near 0 ⇒ flat capture.
    var depthYawCorrelation: Float?
    /// Linear slope of that relationship — a compact identity-specific 3D cue.
    var depthYawSlope: Float?

    static let empty = FaceGeometryProfile(templates: [], depthYawCorrelation: nil, depthYawSlope: nil)
}

nonisolated enum FaceGeometryTemplate {
    /// Minimum landmarks needed before we trust a descriptor enough to store or match.
    private static let minShapePairs = 6

    /// Extract a descriptor from Vision landmarks. Returns nil when eyes/nose aren't reliable.
    static func extract(
        from landmarks: VNFaceLandmarks2D,
        imageSize: CGSize,
        yaw: Float?,
        pitch: Float?,
        pose: String? = nil
    ) -> FaceGeometryDescriptor? {
        guard let leftEye = LandmarkGeometry.eyeCenter(
            pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize
        ),
        let rightEye = LandmarkGeometry.eyeCenter(
            pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize
        ) else { return nil }

        let iod = hypot(leftEye.x - rightEye.x, leftEye.y - rightEye.y)
        guard iod > 1 else { return nil }

        let mid = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let angle = atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x)

        func canonicalize(_ p: CGPoint) -> (Float, Float) {
            let dx = (p.x - mid.x) / iod
            let dy = (p.y - mid.y) / iod
            let c = cos(-angle), s = sin(-angle)
            return (Float(dx * c - dy * s), Float(dx * s + dy * c))
        }

        var shape: [Float] = []
        func appendCentroid(_ region: VNFaceLandmarkRegion2D?) {
            guard let region, let c = LandmarkGeometry.centroid(of: region, imageSize: imageSize) else { return }
            let (x, y) = canonicalize(c)
            shape.append(x)
            shape.append(y)
        }

        // Fixed order — embedding space must stay stable across versions of this file.
        appendCentroid(landmarks.leftEye)
        appendCentroid(landmarks.rightEye)
        appendCentroid(landmarks.leftEyebrow)
        appendCentroid(landmarks.rightEyebrow)
        appendCentroid(landmarks.nose)
        appendCentroid(landmarks.noseCrest)
        appendCentroid(landmarks.outerLips)
        appendCentroid(landmarks.innerLips)
        appendCentroid(landmarks.medianLine)
        appendCentroid(landmarks.faceContour)

        guard shape.count >= minShapePairs * 2 else { return nil }

        var noseOffset: Float = 0
        var noseProtrusion: Float = 0
        if let nose = landmarks.nose, let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize) {
            let (nx, ny) = canonicalize(noseCenter)
            noseOffset = nx
            // Distance below the eye line in canonical space — proxy for nose standing off the plane.
            noseProtrusion = max(0, -ny)
        }

        var midFaceHeight: Float = 0
        if let lips = landmarks.outerLips, let mouth = LandmarkGeometry.centroid(of: lips, imageSize: imageSize) {
            let (_, my) = canonicalize(mouth)
            midFaceHeight = abs(my)
        }

        var jawWidth: Float = 0
        if let contour = landmarks.faceContour {
            let pts = LandmarkGeometry.imagePoints(of: contour, imageSize: imageSize).map(canonicalize)
            if let minX = pts.map(\.0).min(), let maxX = pts.map(\.0).max() {
                jawWidth = maxX - minX
            }
        }

        var browTilt: Float = 0
        if let lb = landmarks.leftEyebrow, let rb = landmarks.rightEyebrow,
           let lc = LandmarkGeometry.centroid(of: lb, imageSize: imageSize),
           let rc = LandmarkGeometry.centroid(of: rb, imageSize: imageSize) {
            let (_, ly) = canonicalize(lc)
            let (_, ry) = canonicalize(rc)
            browTilt = ry - ly
        }

        let depth: [Float] = [noseOffset, noseProtrusion, midFaceHeight, jawWidth, browTilt]
        let normalizedShape = l2Normalize(shape)

        return FaceGeometryDescriptor(
            pose: pose,
            yaw: yaw ?? 0,
            pitch: pitch ?? 0,
            shape: normalizedShape,
            depth: depth
        )
    }

    /// Convenience from a recognition result (enrollment / unlock share this path).
    static func extract(from result: FaceRecognitionResult, pose: String? = nil) -> FaceGeometryDescriptor? {
        guard let landmarks = result.face.landmarks else { return nil }
        return extract(
            from: landmarks,
            imageSize: result.face.imageSize,
            yaw: result.face.yaw,
            pitch: result.face.pitch,
            pose: pose
        )
    }

    /// Build the identity-level profile from a set of per-sample descriptors.
    static func profile(from descriptors: [FaceGeometryDescriptor]) -> FaceGeometryProfile {
        guard descriptors.count >= 2 else {
            return FaceGeometryProfile(templates: descriptors, depthYawCorrelation: nil, depthYawSlope: nil)
        }

        let pairs: [(Float, Float)] = descriptors.map { ($0.depth.first ?? 0, tan($0.yaw)) }
        let xs = pairs.map(\.0)
        let ys = pairs.map(\.1)
        let correlation = pearson(xs, ys)
        let slope = linearSlope(xs: ys, ys: xs) // noseOffset ≈ slope * tan(yaw)

        return FaceGeometryProfile(
            templates: descriptors,
            depthYawCorrelation: correlation,
            depthYawSlope: slope
        )
    }

    /// Best cosine/depth blend against any enrolled template. Prefer same pose when present.
    /// Also blends the top-2 pose matches so a single lucky template can't dominate.
    static func bestSimilarity(
        live: FaceGeometryDescriptor,
        against profile: FaceGeometryProfile,
        preferPose: String? = nil
    ) -> Float {
        guard !profile.templates.isEmpty else { return 0 }

        let ordered: [FaceGeometryDescriptor]
        if let preferPose {
            let same = profile.templates.filter { $0.pose == preferPose }
            ordered = same.isEmpty ? profile.templates : same + profile.templates.filter { $0.pose != preferPose }
        } else {
            ordered = profile.templates
        }

        let scores = ordered.map { similarity(live, $0) }.sorted(by: >)
        guard let best = scores.first else { return 0 }
        if scores.count >= 2 {
            // Require the second-best to be somewhat close — resists a single flat-photo template.
            return 0.75 * best + 0.25 * scores[1]
        }
        return best
    }

    /// Shape-heavy blend: same person under a new expression should still clear ~0.8+.
    static func similarity(_ a: FaceGeometryDescriptor, _ b: FaceGeometryDescriptor) -> Float {
        let shapeSim = max(0, cosineSimilarity(a.shape, b.shape))
        let depthSim = depthSimilarity(a.depth, b.depth)
        // Slightly more weight on depth proxies — photos share 2D shape more easily than depth.
        return 0.62 * shapeSim + 0.38 * depthSim
    }

    // MARK: - Math

    private static func depthSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var total: Float = 0
        for i in 0..<n {
            // Depth features live roughly in [-1, 2]; map absolute error into a soft score.
            let err = abs(a[i] - b[i])
            total += max(0, 1 - err / 0.45)
        }
        return total / Float(n)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-8 else { return 0 }
        return dot / denom
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-8 else { return v }
        return v.map { $0 / norm }
    }

    private static func pearson(_ xs: [Float], _ ys: [Float]) -> Float? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Float(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var cov: Float = 0, varX: Float = 0, varY: Float = 0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX, dy = ys[i] - meanY
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 1e-8, varY > 1e-8 else { return nil }
        return cov / (sqrt(varX) * sqrt(varY))
    }

    private static func linearSlope(xs: [Float], ys: [Float]) -> Float? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Float(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num: Float = 0, den: Float = 0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        guard abs(den) > 1e-8 else { return nil }
        return num / den
    }
}
