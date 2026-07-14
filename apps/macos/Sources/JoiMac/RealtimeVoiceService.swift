@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class RealtimeVoiceService: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        case listening
        case speaking
        case error(String)

        var isConnected: Bool {
            switch self {
            case .connecting, .listening, .speaking: true
            case .disconnected, .error: false
            }
        }

        var label: String {
            switch self {
            case .disconnected: "Start voice"
            case .connecting: "Connecting…"
            case .listening: "Listening…"
            case .speaking: "Joi is speaking…"
            case .error: "Voice unavailable"
            }
        }
    }

    static let model = "gpt-realtime-2.1"

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var assistantTranscript = ""
    @Published private(set) var userTranscript = ""

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let realtimeFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var inputConverter: AVAudioConverter?
    private var hasInputTap = false

    func connect(apiKey: String, voice: String, instructions: String) async {
        guard !status.isConnected else { return }
        status = .connecting
        assistantTranscript = ""
        userTranscript = ""

        guard await microphonePermission() else {
            status = .error("Microphone permission is required.")
            return
        }

        do {
            try prepareAudio()
            var request = URLRequest(
                url: URL(string: "wss://api.openai.com/v1/realtime?model=\(Self.model)")!
            )
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request)
            webSocket = socket
            socket.resume()
            receiveTask = Task { [weak self] in
                await self?.receiveLoop()
            }
            try await send(Self.sessionUpdate(voice: voice, instructions: instructions))
            try startMicrophoneCapture()
        } catch {
            disconnect()
            status = .error(error.localizedDescription)
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        playerNode.stop()
        audioEngine.stop()
        inputConverter = nil
        status = .disconnected
    }

    static func sessionUpdate(voice: String, instructions: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": model,
                "instructions": instructions,
                "output_modalities": ["audio"],
                "max_output_tokens": 1_200,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": ["model": "gpt-4o-mini-transcribe"],
                        "turn_detection": [
                            "type": "semantic_vad",
                            "eagerness": "auto",
                            "create_response": true,
                            "interrupt_response": true,
                        ],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "voice": voice,
                        "speed": 1.04,
                    ],
                ],
            ],
        ]
    }

    private func microphonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func prepareAudio() throws {
        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
        }
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: realtimeFormat)
        try? audioEngine.inputNode.setVoiceProcessingEnabled(true)
        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()
    }

    private func startMicrophoneCapture() throws {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: realtimeFormat) else {
            throw VoiceError.audioConversionUnavailable
        }
        inputConverter = converter
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let data = Self.convert(buffer, with: converter, to: self.realtimeFormat) else { return }
            Task { @MainActor [weak self] in
                await self?.sendAudio(data)
            }
        }
        hasInputTap = true
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> Data? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, capacity)) else {
            return nil
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outputStatus in
            if supplied {
                outputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outputStatus.pointee = .haveData
            return input
        }
        guard conversionError == nil, status != .error, output.frameLength > 0 else { return nil }
        let audioBuffer = output.mutableAudioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return nil }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }

    private func sendAudio(_ data: Data) async {
        guard status.isConnected else { return }
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString(),
        ]
        try? await send(event)
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let socket = webSocket {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(binary): data = binary
                @unknown default: continue
                }
                handleServerEvent(data)
            } catch {
                if !Task.isCancelled {
                    status = .error(error.localizedDescription)
                }
                return
            }
        }
    }

    private func handleServerEvent(_ data: Data) {
        guard
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = event["type"] as? String
        else { return }

        switch type {
        case "session.created", "session.updated", "input_audio_buffer.speech_started":
            status = .listening
        case "conversation.item.input_audio_transcription.completed":
            userTranscript = event["transcript"] as? String ?? userTranscript
        case "response.created":
            assistantTranscript = ""
        case "response.output_audio.delta":
            status = .speaking
            if let delta = event["delta"] as? String, let audio = Data(base64Encoded: delta) {
                play(audio)
            }
        case "response.output_audio_transcript.delta":
            assistantTranscript += event["delta"] as? String ?? ""
        case "response.output_audio.done", "response.done":
            status = .listening
        case "error":
            let details = event["error"] as? [String: Any]
            status = .error(details?["message"] as? String ?? "The Realtime API returned an error.")
        default:
            break
        }
    }

    private func play(_ data: Data) {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: realtimeFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData else { return }
        data.withUnsafeBytes { raw in
            guard let source = raw.baseAddress else { return }
            memcpy(destination, source, min(data.count, Int(audioBuffer.mDataByteSize)))
        }
        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func send(_ payload: [String: Any]) async throws {
        guard let webSocket else { throw VoiceError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { throw VoiceError.invalidPayload }
        try await webSocket.send(.string(text))
    }
}

private enum VoiceError: LocalizedError {
    case notConnected
    case invalidPayload
    case audioConversionUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected: "Voice is not connected."
        case .invalidPayload: "The Realtime request could not be encoded."
        case .audioConversionUnavailable: "The microphone audio format is unavailable."
        }
    }
}
