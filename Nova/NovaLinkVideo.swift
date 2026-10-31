import UIKit
import VideoToolbox
import CoreMedia
import CoreVideo

// ════════════════════════════════════════════════════════════════════════════════════
//  v89 · Vídeo de las pestañas del PC que se ejecutan en el iPhone.
//  H.264 por hardware (VideoToolbox) a 60 fps y en alta resolución; el PC lo decodifica
//  con WebCodecs. Mucho más fluido y nítido que mandar fotos JPEG.
// ════════════════════════════════════════════════════════════════════════════════════

final class H264Encoder {
    let width: Int
    let height: Int
    private var session: VTCompressionSession?
    private var frameIndex: Int64 = 0
    private let fps: Int32
    /// El próximo fotograma será completo (al empezar, al reconectar o si el PC lo pide).
    var forceKey = true
    /// (avcC, ancho, alto) en cada fotograma clave.
    var onConfig: ((Data) -> Void)?
    /// (datos AVCC, ¿clave?)
    var onFrame: ((Data, Bool) -> Void)?

    init?(width: Int, height: Int, fps: Int, bitrate: Int) {
        self.width = width & ~1
        self.height = height & ~1
        self.fps = Int32(fps)
        let attrs = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                     kCVPixelBufferWidthKey as String: self.width,
                     kCVPixelBufferHeightKey as String: self.height,
                     kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as [String: Any]
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(self.width), height: Int32(self.height),
                                            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                            imageBufferAttributes: attrs as CFDictionary, compressedDataAllocator: nil,
                                            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let session = s else { return nil }
        self.session = session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps * 3))
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit { invalidate() }

    func invalidate() {
        if let s = session {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
        }
        session = nil
    }

    func makeBuffer() -> CVPixelBuffer? {
        guard let s = session, let pool = VTCompressionSessionGetPixelBufferPool(s) else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        return pb
    }

    func encode(_ pb: CVPixelBuffer) {
        guard let s = session else { return }
        let pts = CMTime(value: frameIndex, timescale: fps)
        frameIndex += 1
        var props: CFDictionary?
        if forceKey {
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
            forceKey = false
        }
        VTCompressionSessionEncodeFrame(s, imageBuffer: pb, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample = sample, let self = self else { return }
            self.output(sample)
        }
    }

    private func output(_ sample: CMSampleBuffer) {
        var isKey = true
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [NSDictionary],
           let first = atts.first, let notSync = first.object(forKey: kCMSampleAttachmentKey_NotSync) as? Bool {
            isKey = !notSync
        }
        if isKey, let fmt = CMSampleBufferGetFormatDescription(sample) {
            var spsPtr: UnsafePointer<UInt8>?
            var spsLen = 0
            var ppsPtr: UnsafePointer<UInt8>?
            var ppsLen = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 0, parameterSetPointerOut: &spsPtr,
                                                                  parameterSetSizeOut: &spsLen, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 1, parameterSetPointerOut: &ppsPtr,
                                                                  parameterSetSizeOut: &ppsLen, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let sp = spsPtr, let pp = ppsPtr, spsLen >= 4 {
                let sps = Data(bytes: sp, count: spsLen)
                let pps = Data(bytes: pp, count: ppsLen)
                var avcc = Data([1, sps[1], sps[2], sps[3], 0xFF, 0xE1, UInt8((spsLen >> 8) & 0xFF), UInt8(spsLen & 0xFF)])
                avcc.append(sps)
                avcc.append(contentsOf: [1, UInt8((ppsLen >> 8) & 0xFF), UInt8(ppsLen & 0xFF)])
                avcc.append(pps)
                onConfig?(avcc)
            }
        }
        guard let bb = CMSampleBufferGetDataBuffer(sample) else { return }
        let len = CMBlockBufferGetDataLength(bb)
        guard len > 0 else { return }
        var data = Data(count: len)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: base) == kCMBlockBufferNoErr
        }
        if ok { onFrame?(data, isKey) }
    }
}

/// CADisplayLink retiene su objetivo: este intermediario evita que la pestaña no se libere nunca.
final class DisplayLinkProxy: NSObject {
    let tick: () -> Void
    init(_ tick: @escaping () -> Void) { self.tick = tick }
    @objc func fire() { tick() }
}
