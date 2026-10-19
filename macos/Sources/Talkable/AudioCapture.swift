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
    /// Start/stop of AVCaptureSession block until the hardware responds, so they
    /// run here instead of on the main thread. Serial, so start always precedes stop.
    private let controlQueue = DispatchQueue(label: "talkable.capture.control")
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
        // Ask for one mono, non-interleaved float32 buffer: the conversion in
        // pcmBuffer then doesn't have to guess the device's layout.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVNumberOfChannelsKey: 1,
        ]
        guard session.canAddOutput(output) else {
            throw NSError(domain: "Talkable", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't open the selected microphone."])
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        usingCaptureSession = true
        captureSession = session
        controlQueue.async { session.startRunning() }
    }

    func stop() {
        if usingCaptureSession {
            let finished = captureSession
            captureSession = nil
            usingCaptureSession = false
            controlQueue.async { finished?.stopRunning() }
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

    /// Converts a captured CMSampleBuffer to a mono float32 PCM buffer. The
    /// output is configured in `startCaptureSession` (one non-interleaved
    /// channel), so the audio list has exactly one buffer.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let sampleRate = asbdPtr.pointee.mSampleRate > 0 ? asbdPtr.pointee.mSampleRate : 44100
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let dst = pcm.floatChannelData?[0] else {
            return nil
        }
        var audioBufferList = AudioBufferList()
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
        // blockBuffer keeps the samples alive until the copy below is done.
        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard status == noErr, buffers.count == 1, let src = buffers[0].mData else {
            return nil
        }
        let byteCount = min(Int(buffers[0].mDataByteSize),
                            Int(frameCount) * MemoryLayout<Float32>.size)
        memcpy(dst, src, byteCount)
        pcm.frameLength = AVAudioFrameCount(byteCount / MemoryLayout<Float32>.size)
        return pcm
    }
}
