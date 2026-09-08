import AVFoundation

struct AudioMicrophone: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AudioDeviceList {
    static let systemDefaultID = "default"

    static func listMicrophones() -> [AudioMicrophone] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        let mics = session.devices.map {
            AudioMicrophone(id: $0.uniqueID, name: $0.localizedName)
        }.sorted { $0.name < $1.name }
        return [AudioMicrophone(id: systemDefaultID, name: "System default")] + mics
    }

    static func device(for id: String) -> AVCaptureDevice? {
        if id.isEmpty || id == systemDefaultID {
            return AVCaptureDevice.default(for: .audio)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.first { $0.uniqueID == id }
            ?? AVCaptureDevice.default(for: .audio)
    }
}

final class AudioCapture: NSObject {
    private let engine = AVAudioEngine()
    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "talkable.capture")
    private var usingCaptureSession = false
    var preferredMicrophoneID: String = AudioDeviceList.systemDefaultID
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start() throws {
        if preferredMicrophoneID.isEmpty || preferredMicrophoneID == AudioDeviceList.systemDefaultID {
            try startEngine()
        } else {
            // Fall back to the system default when the saved device is gone.
            if AudioDeviceList.device(for: preferredMicrophoneID) == nil {
                try startEngine()
            } else {
                try startCaptureSession(deviceID: preferredMicrophoneID)
            }
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Talkable", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The microphone returned no valid audio format."])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        usingCaptureSession = false
        engine.prepare()
        try engine.start()
    }

    private func startCaptureSession(deviceID: String) throws {
        guard let device = AudioDeviceList.device(for: deviceID) else {
            throw NSError(domain: "Talkable", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The selected microphone is not available."])
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "Talkable", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't open the selected microphone."])
        }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            throw NSError(domain: "Talkable", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't open the selected microphone."])
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        usingCaptureSession = true
        captureSession = session
        session.startRunning()
    }

    func stop() {
        if usingCaptureSession {
            captureSession?.stopRunning()
            captureSession = nil
            usingCaptureSession = false
            return
        }
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(pcm)
    }

    /// Converts a captured CMSampleBuffer to a float32 non-interleaved PCM buffer.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPtr.pointee
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100
        let channels = asbd.mChannelsPerFrame > 0 ? asbd.mChannelsPerFrame : 1
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        pcm.frameLength = frameCount
        var audioBufferList = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil))
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        // Copy planar float32 data when possible.
        let numBuffers = Int(audioBufferList.mNumberBuffers)
        withUnsafePointer(to: audioBufferList) { listPtr in
            let bufferPtr = UnsafeRawPointer(listPtr).assumingMemoryBound(to: AudioBuffer.self).advanced(by: 1)
            // Note: mBuffers is inline; walk the trailing AudioBuffers manually.
            let first = withUnsafePointer(to: audioBufferList.mBuffers) { $0 }
            for i in 0..<numBuffers {
                let buf = first.advanced(by: i).pointee
                guard let srcData = buf.mData, buf.mDataByteSize > 0 else { continue }
                if i < Int(pcm.format.channelCount), let dst = pcm.floatChannelData?[i] {
                    let frames = min(Int(frameCount), Int(buf.mDataByteSize) / MemoryLayout<Float32>.size)
                    let byteCount = frames * MemoryLayout<Float32>.size
                    memcpy(dst, srcData, byteCount)
                }
            }
            _ = bufferPtr
        }
        return pcm
    }
}
