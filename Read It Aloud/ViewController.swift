import UIKit
import AVFoundation
import Vision
import Speech

class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var startbtn: UIButton!
    @IBOutlet weak var pausebtn: UIButton!
    @IBOutlet weak var stopbtn: UIButton!
    var inputNode: AVAudioInputNode!
    var audioEngine = AVAudioEngine()
    var audioSession = AVAudioSession()
    var session = AVCaptureSession()
    var requests = [VNRequest]()
    var predictedText = ""
    var synthesizer = AVSpeechSynthesizer()
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        
    override func viewDidLoad() {
        super.viewDidLoad()
        checkPermissions()
        startbtn.titleLabel?.adjustsFontSizeToFitWidth = true
        pausebtn.titleLabel?.adjustsFontSizeToFitWidth = true
        stopbtn.titleLabel?.adjustsFontSizeToFitWidth = true
        
        startLiveVideo()
        doTextDetection()
        listenForCommands()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func speakButtonPressed(_ sender: Any) {
        doSpeakActions()
    }
    
    @IBAction func pauseButtonPressed(_ sender: Any) {
        if (synthesizer.isPaused) {
            doResumeActions()
        } else if (synthesizer.isSpeaking) {
            doPauseActions()
        } else {
            return
        }
    }
    
    @IBAction func stopButtonPressed(_ sender: Any) {
        doStopActions()
    }
    
    func doSpeakActions() {
        if (synthesizer.isSpeaking) {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: predictedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.40
        utterance.volume = 2
        
        synthesizer.speak(utterance)
    }
    
    func doPauseActions() {
        synthesizer.pauseSpeaking(at: .immediate)
        pausebtn.setTitle("RESUME", for: .normal)
    }
    
    func doResumeActions() {
        synthesizer.continueSpeaking()
        pausebtn.setTitle("PAUSE", for: .normal)
    }
    
    func doStopActions() {
        pausebtn.setTitle("PAUSE", for: .normal)
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    private func listenForCommands() {
            guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
                print("Speech recognizer unavailable")
                return
            }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest!.shouldReportPartialResults = true

            recognizer.recognitionTask(with: recognitionRequest!) { (result, error) in
                guard error == nil else {
                    print(error as Any)
                    return
                }
                guard let result = result else { return }

                print("got a new result: \(result.bestTranscription.formattedString), final : \(result.isFinal)")
                DispatchQueue.main.async {
                    let resultArr = result.bestTranscription.formattedString.byWords
                    let resultStr = resultArr.last
                    print("last word: \(String(describing: resultStr))")
                    if (resultStr?.caseInsensitiveCompare("speak") == .orderedSame) {
                        self.doSpeakActions()
                    } else if (resultStr?.caseInsensitiveCompare("stop") == .orderedSame) {
                        self.doStopActions()
                    } else if (resultStr?.caseInsensitiveCompare("pause") == .orderedSame) {
                        self.doPauseActions()
                    } else if (resultStr?.caseInsensitiveCompare("resume") == .orderedSame) {
                        self.doResumeActions()
                    }
                }
            }

            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()

            // MARK: 4. Start recognizing speech.
            do {
                audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                try audioSession.overrideOutputAudioPort(.speaker)
                try audioEngine.start()
            } catch {
                print(error.localizedDescription)
            }
        }

    
    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                    case .authorized:
                        break
                    case .denied:
                        break
                    case .restricted:
                        break
                    case .notDetermined:
                        break
                    @unknown default:
                        fatalError()
                }
            }
        }
    }
    
    func startLiveVideo() {
        self.session.sessionPreset = AVCaptureSession.Preset.high
        let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
        
        let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
        let deviceOutput = AVCaptureVideoDataOutput()
        deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        session.addInput(deviceInput)
        session.addOutput(deviceOutput)

        let imageLayer = AVCaptureVideoPreviewLayer(session: session)
        imageLayer.frame = imageView.bounds
        imageView.layer.addSublayer(imageLayer)
        
        session.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        imageView.layer.sublayers?[0].frame = imageView.bounds
    }
    
    func doTextDetection() {
        let readRequest = VNRecognizeTextRequest(completionHandler: self.readTextHandler)
        readRequest.recognitionLevel = .accurate
        let textRequest = VNDetectTextRectanglesRequest(completionHandler: self.detectTextHandler)
        textRequest.reportCharacterBoxes = true
        self.requests = [readRequest, textRequest]
    }

    func detectTextHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results else {
            print("no result")
            return
        }
        
        let result = observations.map({$0 as? VNTextObservation})
        
        DispatchQueue.main.async() {
            self.imageView.layer.sublayers?.removeSubrange(1...)
            for region in result {
                guard let rg = region else {
                    continue
                }

                self.highlightWord(box: rg)            }
        }
    }
    
    func readTextHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("No result")
            return
        }
        
        let recognizedStrings = observations.compactMap { observation in
            return observation.topCandidates(1).first?.string
        }
        
        let detectedText = recognizedStrings.joined(separator: ",")
        
        predictedText = detectedText
    }
    
    func highlightWord(box: VNTextObservation) {
        guard let boxes = box.characterBoxes else {
            return
        }
        
        var maxX: CGFloat = 9999.0
        var minX: CGFloat = 0.0
        var maxY: CGFloat = 9999.0
        var minY: CGFloat = 0.0
        
        for char in boxes {
            if char.bottomLeft.x < maxX {
                maxX = char.bottomLeft.x
            }
            if char.bottomRight.x > minX {
                minX = char.bottomRight.x
            }
            if char.bottomRight.y < maxY {
                maxY = char.bottomRight.y
            }
            if char.topRight.y > minY {
                minY = char.topRight.y
            }
        }
        
        let xCord = maxX * imageView.frame.size.width
        let yCord = (1 - minY) * imageView.frame.size.height
        let width = (minX - maxX) * imageView.frame.size.width
        let height = (minY - maxY) * imageView.frame.size.height
        
        let outline = CALayer()
        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
        outline.borderWidth = 2.0
        outline.borderColor = UIColor.red.cgColor
        
        imageView.layer.addSublayer(outline)
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        var requestOptions:[VNImageOption : Any] = [:]
        
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics:camData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: requestOptions)

        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
}

extension StringProtocol {
    var byWords: [SubSequence] {
        var byWords: [SubSequence] = []
        enumerateSubstrings(in: startIndex..., options: .byWords) { _, range, _, _ in
            byWords.append(self[range])
        }
        return byWords
    }
}
