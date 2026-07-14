@preconcurrency import AVFoundation
import Combine
import CryptoKit
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
    @Published private(set) var lastWarning: String?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let clock = ContinuousClock()
    private let realtimeFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    private var webSocket: URLSessionWebSocketTask?
    private var writer: RealtimeSocketWriter?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var connectionID: UUID?
    private var inputConverter: AVAudioConverter?
    private var hasInputTap = false
    private var audioConfigurationObserver: NSObjectProtocol?

    private var didReceiveSessionCreated = false
    private var didReceiveSessionUpdated = false
    private var handshakeError: String?

    private var currentAssistantItemID: String?
    private var activeResponseID: String?
    private var suppressedResponseIDs: Set<String> = []
    private var playbackStart: ContinuousClock.Instant?
    private var scheduledAudioMilliseconds = 0
    private var pendingAudioBuffers = 0
    private var playbackGeneration = 0
    private var responseAudioFinished = false
    private var suppressUnidentifiedInterruptedAudio = false

    func connect(apiKey: String, voice: String, instructions: String) async {
        guard !status.isConnected else { return }
        tearDownTransport()
        let id = UUID()
        connectionID = id
        status = .connecting
        assistantTranscript = ""
        userTranscript = ""
        lastWarning = nil
        didReceiveSessionCreated = false
        didReceiveSessionUpdated = false
        handshakeError = nil

        guard await microphonePermission() else {
            finish(connection: id, with: .error("Microphone permission is required. Enable it in System Settings → Privacy & Security → Microphone."))
            return
        }
        guard connectionID == id else { return }

        do {
            var request = URLRequest(
                url: URL(string: "wss://api.openai.com/v1/realtime?model=\(Self.model)")!
            )
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.safetyIdentifier(), forHTTPHeaderField: "OpenAI-Safety-Identifier")

            let socket = URLSession.shared.webSocketTask(with: request)
            webSocket = socket
            writer = RealtimeSocketWriter(socket: socket)
            socket.resume()

            receiveTask = Task { [weak self] in
                await self?.receiveLoop(socket: socket, connection: id)
            }

            try await waitForHandshake(.created, connection: id)
            try await send(Self.sessionUpdate(voice: voice, instructions: instructions))
            try await waitForHandshake(.updated, connection: id)
            try prepareAudio(connection: id)
            guard connectionID == id else { return }
            status = .listening
            startAudioConfigurationObserver(connection: id)
            startHeartbeat(socket: socket, connection: id)
        } catch is CancellationError {
            if connectionID == id {
                finish(connection: id, with: .disconnected)
            }
        } catch {
            guard connectionID == id else { return }
            finish(connection: id, with: .error(Self.friendlyMessage(for: error)))
        }
    }

    func disconnect() {
        connectionID = nil
        tearDownTransport()
        status = .disconnected
    }

    static func sessionUpdate(voice: String, instructions: String) -> [String: Any] {
        [
            "event_id": "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
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
                        "noise_reduction": ["type": "near_field"],
                        "transcription": ["model": "gpt-4o-mini-transcribe"],
                        "turn_detection": [
                            "type": "semantic_vad",
                            "eagerness": "auto",
                            "create_response": true,
                            "interrupt_response": true,
                        ],
                    ],
                    "output": [
                        "format": ["type": "audio/pcm"],
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

    private func prepareAudio(connection id: UUID) throws {
        guard connectionID == id else { throw VoiceError.cancelled }
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
        } else {
            audioEngine.disconnectNodeOutput(playerNode)
        }
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: realtimeFormat)

        let input = audioEngine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: realtimeFormat) else {
            throw VoiceError.audioConversionUnavailable
        }
        inputConverter = converter
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let data = Self.convert(buffer, with: converter, to: self.realtimeFormat) else { return }
            Task { @MainActor [weak self] in
                await self?.sendAudio(data, connection: id)
            }
        }
        hasInputTap = true

        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()
    }

    private func startAudioConfigurationObserver(connection id: UUID) {
        stopAudioConfigurationObserver()
        audioConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAudioConfigurationChange(connection: id)
            }
        }
    }

    private func stopAudioConfigurationObserver() {
        if let audioConfigurationObserver {
            NotificationCenter.default.removeObserver(audioConfigurationObserver)
            self.audioConfigurationObserver = nil
        }
    }

    private func handleAudioConfigurationChange(connection id: UUID) {
        guard connectionID == id, didReceiveSessionUpdated else { return }
        stopAudioConfigurationObserver()
        if let activeResponseID {
            suppressedResponseIDs.insert(activeResponseID)
        }
        interruptPlayback(connection: id)
        do {
            try prepareAudio(connection: id)
            status = .listening
            lastWarning = "Audio device changed. Joi reconnected the microphone automatically."
            startAudioConfigurationObserver(connection: id)
        } catch {
            finish(connection: id, with: .error("The audio device changed and Joi could not reconnect it. Open Voice again to retry."))
        }
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
        let conversionStatus = converter.convert(to: output, error: &conversionError) { _, outputStatus in
            if supplied {
                outputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outputStatus.pointee = .haveData
            return input
        }
        guard conversionError == nil, conversionStatus != .error, output.frameLength > 0 else { return nil }
        let audioBuffer = output.mutableAudioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return nil }
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }

    private func sendAudio(_ data: Data, connection id: UUID) async {
        guard connectionID == id, didReceiveSessionUpdated else { return }
        do {
            try await send([
                "event_id": "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString(),
            ])
        } catch {
            guard connectionID == id else { return }
            finish(connection: id, with: .error(Self.friendlyMessage(for: error)))
        }
    }

    private func receiveLoop(socket: URLSessionWebSocketTask, connection id: UUID) async {
        while !Task.isCancelled, connectionID == id {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(binary): data = binary
                @unknown default: continue
                }
                handleServerEvent(data, connection: id)
            } catch {
                guard !Task.isCancelled, connectionID == id else { return }
                finish(connection: id, with: .error(Self.friendlyMessage(for: error)))
                return
            }
        }
    }

    private func handleServerEvent(_ data: Data, connection id: UUID) {
        guard connectionID == id,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return }

        switch type {
        case "session.created":
            didReceiveSessionCreated = true
        case "session.updated":
            didReceiveSessionUpdated = true
        case "input_audio_buffer.speech_started":
            if let activeResponseID {
                suppressedResponseIDs.insert(activeResponseID)
            } else if currentAssistantItemID != nil || pendingAudioBuffers > 0 {
                suppressUnidentifiedInterruptedAudio = true
            }
            interruptPlayback(connection: id)
            status = .listening
        case "conversation.item.input_audio_transcription.completed":
            userTranscript = event["transcript"] as? String ?? userTranscript
        case "response.created":
            assistantTranscript = ""
            lastWarning = nil
            responseAudioFinished = false
            let response = event["response"] as? [String: Any]
            activeResponseID = response?["id"] as? String
            suppressUnidentifiedInterruptedAudio = false
            currentAssistantItemID = nil
        case "response.output_item.added":
            if !shouldSuppress(event), let item = event["item"] as? [String: Any] {
                currentAssistantItemID = item["id"] as? String
            }
        case "response.output_audio.delta":
            guard !shouldSuppress(event) else { break }
            status = .speaking
            if currentAssistantItemID == nil {
                currentAssistantItemID = event["item_id"] as? String
            }
            if let delta = event["delta"] as? String, let audio = Data(base64Encoded: delta) {
                play(audio, connection: id)
            }
        case "response.output_audio_transcript.delta":
            guard !shouldSuppress(event) else { break }
            assistantTranscript += event["delta"] as? String ?? ""
        case "response.output_audio.done":
            guard !shouldSuppress(event) else { break }
            responseAudioFinished = true
            finishPlaybackIfDrained(connection: id)
        case "response.done":
            handleResponseDone(event, connection: id)
        case "error":
            let details = event["error"] as? [String: Any]
            let message = details?["message"] as? String ?? "The Realtime API returned an error."
            let code = details?["code"] as? String
            if !didReceiveSessionUpdated {
                handshakeError = message
            } else if Self.isFatalServerError(code: code) {
                finish(connection: id, with: .error(message))
            } else {
                lastWarning = message
                if status != .speaking {
                    status = .listening
                }
            }
        default:
            break
        }
    }

    private func play(_ data: Data, connection id: UUID) {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: realtimeFormat, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData else { return }
        data.withUnsafeBytes { raw in
            guard let source = raw.baseAddress else { return }
            memcpy(destination, source, min(data.count, Int(audioBuffer.mDataByteSize)))
        }

        if playbackStart == nil {
            playbackStart = clock.now
        }
        scheduledAudioMilliseconds += Int(Double(frameCount) / realtimeFormat.sampleRate * 1_000)
        pendingAudioBuffers += 1
        let generation = playbackGeneration
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.audioBufferDidFinish(connection: id, generation: generation)
            }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func audioBufferDidFinish(connection id: UUID, generation: Int) {
        guard connectionID == id, generation == playbackGeneration else { return }
        pendingAudioBuffers = max(0, pendingAudioBuffers - 1)
        finishPlaybackIfDrained(connection: id)
    }

    private func finishPlaybackIfDrained(connection id: UUID) {
        guard connectionID == id, responseAudioFinished, pendingAudioBuffers == 0 else { return }
        status = .listening
        resetPlaybackTracking()
    }

    private func interruptPlayback(connection id: UUID) {
        guard connectionID == id else { return }
        let heardMilliseconds: Int
        if let playbackStart {
            let duration = playbackStart.duration(to: clock.now).components
            let elapsed = Int(
                Double(duration.seconds) * 1_000
                    + Double(duration.attoseconds) / 1_000_000_000_000_000
            )
            heardMilliseconds = min(max(0, elapsed), scheduledAudioMilliseconds)
        } else {
            heardMilliseconds = 0
        }
        let itemID = currentAssistantItemID

        playbackGeneration += 1
        playerNode.stop()
        playerNode.reset()
        if audioEngine.isRunning {
            playerNode.play()
        }
        resetPlaybackTracking()

        if let itemID {
            Task { [weak self] in
                guard let self, self.connectionID == id else { return }
                do {
                    try await self.send([
                        "event_id": "evt_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                        "type": "conversation.item.truncate",
                        "item_id": itemID,
                        "content_index": 0,
                        "audio_end_ms": heardMilliseconds,
                    ])
                } catch {
                    guard self.connectionID == id else { return }
                    self.finish(connection: id, with: .error(Self.friendlyMessage(for: error)))
                }
            }
        }
    }

    private func resetPlaybackTracking() {
        playbackStart = nil
        scheduledAudioMilliseconds = 0
        pendingAudioBuffers = 0
        currentAssistantItemID = nil
        responseAudioFinished = false
    }

    private func shouldSuppress(_ event: [String: Any]) -> Bool {
        let responseID = event["response_id"] as? String ?? activeResponseID
        if let responseID, suppressedResponseIDs.contains(responseID) {
            return true
        }
        return responseID == nil && suppressUnidentifiedInterruptedAudio
    }

    private func handleResponseDone(_ event: [String: Any], connection id: UUID) {
        guard connectionID == id else { return }
        let response = event["response"] as? [String: Any]
        let responseID = response?["id"] as? String
        let isCurrentResponse = responseID == nil || activeResponseID == nil || responseID == activeResponseID
        if let responseID {
            suppressedResponseIDs.remove(responseID)
            if activeResponseID == responseID {
                activeResponseID = nil
            }
        }
        guard isCurrentResponse else { return }
        let responseStatus = response?["status"] as? String ?? "completed"

        switch responseStatus {
        case "completed":
            responseAudioFinished = true
            finishPlaybackIfDrained(connection: id)
        case "cancelled":
            suppressUnidentifiedInterruptedAudio = false
            responseAudioFinished = true
            finishPlaybackIfDrained(connection: id)
        case "failed", "incomplete":
            let details = response?["status_details"] as? [String: Any]
            let nestedError = details?["error"] as? [String: Any]
            lastWarning = nestedError?["message"] as? String
                ?? details?["reason"] as? String
                ?? "That voice turn did not complete. You can keep talking and try again."
            responseAudioFinished = true
            finishPlaybackIfDrained(connection: id)
        default:
            lastWarning = "That voice turn ended unexpectedly. You can keep talking and try again."
            responseAudioFinished = true
            finishPlaybackIfDrained(connection: id)
        }
    }

    private enum HandshakePhase {
        case created
        case updated
    }

    private func waitForHandshake(_ phase: HandshakePhase, connection id: UUID) async throws {
        for _ in 0 ..< 120 {
            guard connectionID == id else { throw VoiceError.cancelled }
            if let handshakeError { throw VoiceError.server(handshakeError) }
            switch phase {
            case .created where didReceiveSessionCreated:
                return
            case .updated where didReceiveSessionUpdated:
                return
            default:
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw VoiceError.handshakeTimedOut
    }

    private func startHeartbeat(socket: URLSessionWebSocketTask, connection id: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, self.connectionID == id else { return }
                do {
                    try await Self.ping(socket)
                } catch {
                    guard self.connectionID == id else { return }
                    self.finish(connection: id, with: .error(Self.friendlyMessage(for: error)))
                    return
                }
            }
        }
    }

    private static func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func send(_ payload: [String: Any]) async throws {
        guard let writer else { throw VoiceError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { throw VoiceError.invalidPayload }
        try await writer.send(text)
    }

    private func finish(connection id: UUID, with finalStatus: Status) {
        guard connectionID == id else { return }
        connectionID = nil
        tearDownTransport()
        status = finalStatus
    }

    private func tearDownTransport() {
        stopAudioConfigurationObserver()
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        writer = nil
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        playbackGeneration += 1
        playerNode.stop()
        playerNode.reset()
        audioEngine.stop()
        audioEngine.reset()
        inputConverter = nil
        didReceiveSessionCreated = false
        didReceiveSessionUpdated = false
        handshakeError = nil
        activeResponseID = nil
        suppressedResponseIDs.removeAll()
        suppressUnidentifiedInterruptedAudio = false
        resetPlaybackTracking()
    }

    private static func safetyIdentifier() -> String {
        let defaults = UserDefaults.standard
        let key = "joi.realtimeSafetyIdentifierSeed"
        let seed: String
        if let existing = defaults.string(forKey: key) {
            seed = existing
        } else {
            seed = UUID().uuidString
            defaults.set(seed, forKey: key)
        }
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let voiceError = error as? VoiceError {
            return voiceError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "The realtime voice connection failed. Check your internet connection and API key, then try again."
        }
        return error.localizedDescription
    }

    private static func isFatalServerError(code: String?) -> Bool {
        guard let code = code?.lowercased() else { return false }
        let fatalFragments = [
            "auth", "api_key", "permission", "quota", "billing", "model_not_found",
            "session_expired", "account_deactivated",
        ]
        return fatalFragments.contains { code.contains($0) }
    }
}

private actor RealtimeSocketWriter {
    private let socket: URLSessionWebSocketTask
    private var sendLocked = false
    private var sendWaiters: [CheckedContinuation<Void, Never>] = []

    init(socket: URLSessionWebSocketTask) {
        self.socket = socket
    }

    func send(_ text: String) async throws {
        await acquireSendLock()
        do {
            try Task.checkCancellation()
            try await socket.send(.string(text))
            releaseSendLock()
        } catch {
            releaseSendLock()
            throw error
        }
    }

    private func acquireSendLock() async {
        if !sendLocked {
            sendLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            sendWaiters.append(continuation)
        }
    }

    private func releaseSendLock() {
        if sendWaiters.isEmpty {
            sendLocked = false
        } else {
            let next = sendWaiters.removeFirst()
            next.resume()
        }
    }
}

private enum VoiceError: LocalizedError {
    case notConnected
    case invalidPayload
    case audioConversionUnavailable
    case handshakeTimedOut
    case server(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Voice is not connected."
        case .invalidPayload:
            "The Realtime request could not be encoded."
        case .audioConversionUnavailable:
            "The microphone audio format is unavailable."
        case .handshakeTimedOut:
            "OpenAI voice did not finish connecting. Check your API key and network, then try again."
        case let .server(message):
            message
        case .cancelled:
            "The voice connection was cancelled."
        }
    }
}
