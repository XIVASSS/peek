//
//  GlareCue.swift
//  glance
//
//  Pixel-domain half of the gloss/glare cue (see `LivenessCues.glossGlare`);
//  no Vision/CoreImage import, so it stays usable from `tools/liveness_selftest.swift`.
//  Populated by `GlareCueExtractor.extract(faceCrop:)`.
//

import CoreGraphics

/// Specular-highlight measurements from a native-resolution face crop; `nil` when no crop
/// was available, in which case the `glossGlare` deny cue abstains.
struct GlareSample: Equatable {
    /// Native pixel width of the measured crop; `renderCrop` only ever downsamples, so this
    /// is an honest detail measure — the cue confidence-weights down as it shrinks.
    let cropPixelWidth: CGFloat

    /// Fraction of crop pixels that are near-saturated and low-chroma — direct specular reflection.
    let specularFraction: Float

    /// How concentrated the specular pixels are into one region (densest 8x8 grid cell's
    /// share) vs. scattered — distinguishes glass glare from a shiny forehead.
    let specularClusterRatio: Float
}

/// Texture measurements from one face crop. Fed into the `passiveSpoof` deny cue.
/// Defined here (not beside the extractor) so `tools/liveness_selftest.swift` can build
/// frames without compiling CoreGraphics raster code.
struct SpoofTextureSample: Equatable, Sendable {
    let cropPixelWidth: CGFloat
    /// 0...1 likelihood this crop is a print or screen rather than live skin.
    let spoofScore: Float
    /// High-frequency periodic energy (moire / pixel grid).
    let periodicEnergy: Float
    /// How uniform local Laplacian variance is across tiles (screens/prints often look "equally sharp").
    let sharpnessUniformity: Float
    /// Mid-band color banding / posterization hint.
    let bandingEnergy: Float
}
