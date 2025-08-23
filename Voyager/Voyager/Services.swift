import Foundation
import CoreLocation
import Speech
import AVFoundation

// MARK: - Location
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {    @Published var status: CLAuthorizationStatus?
    @Published var lastLocation: CLLocation?

    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUse() {
        let current: CLAuthorizationStatus
        if #available(iOS 14.0, *) { current = mgr.authorizationStatus }
        else { current = CLLocationManager.authorizationStatus() }

        if current == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        } else {
            status = current
            if current == .authorizedWhenInUse || current == .authorizedAlways {
                mgr.startUpdatingLocation()
            }
        }
    }

    func requestAlways() {
        mgr.requestAlwaysAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) { status = manager.authorizationStatus }
        else { status = type(of: manager).authorizationStatus() }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            mgr.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
}

// MARK: - Speech
final class SpeechService: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    override init() {
        super.init()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.authStatus = status }
        }
    }

    func start() throws {
        guard authStatus == .authorized else {
            throw NSError(domain: "Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech not authorized"])
        }
        if isListening { return }

        // Mic permission (iOS 17+ API)
        var granted = false
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { ok in granted = ok }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { ok in granted = ok }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if !granted {
            throw NSError(domain: "Speech", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone not allowed"])
        }

        // Audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Recognition
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        transcript = ""

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            if let r = result {
                self?.transcript = r.bestTranscription.formattedString
                if r.isFinal { self?.stop() }
            }
            if error != nil { self?.stop() }
        }
    }

    func stop() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isListening = false
    }
}
