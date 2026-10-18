@preconcurrency import AudioKit
import AVFoundation

/// A `RenderDSP` as an AudioKit node.
final class RenderNode<DSP: RenderDSP>: Node {
    let dsp: DSP
    let avAudioNode: AVAudioNode
    var connections: [Node] { [] }

    init(_ dsp: DSP, format: AVAudioFormat = AudioKit.Settings.audioFormat) {
        self.dsp = dsp
        avAudioNode = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: dsp))
    }

    // Built outside any actor: the block runs on the audio thread.
    nonisolated static func renderBlock(for dsp: DSP) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, audioBufferList -> OSStatus in
            dsp.render(frameCount: Int(frameCount), buffers: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
    }
}
