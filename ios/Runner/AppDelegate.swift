import Flutter
import MediaPipeTasksVision
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var handLandmarker: HandLandmarker?
  private let inputSize = 224
  private let existThreshold: Float = 0.5
  private let scoreThreshold: Float = 0.5

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "channel_Mediapipe", binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler {
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "load":
        self?.loadModel(result: result)
      case "inference":
        self?.runInference(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    //
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func runInference(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let handLandmarker = handLandmarker else {
      result(FlutterError(code: "NO_MODEL", message: "Model not loaded", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any],
      let imageData = args["imageData"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      do {
        /// UIImage(data:)는 Raw RGB/YUV 바이트를 직접 읽지 못합니다.
        /// camera 패키지의 CameraImage에서 얻은 bytes는 대부분 YUV420 또는 BGRA8888 "raw" 픽셀 데이터입니다.
        /// 이건 파일 포맷(JPEG, PNG)이 아니라 그냥 메모리에 나열된 픽셀 값이라,
        /// UIImage(data:)가 이해할 수 없습니다 → 그래서 nil 반환.
        /// =>  iOS에서 Raw YUV/BGRA를 UIImage로 변환
        imageData.data.withUnsafeBytes { ptr in
          let context = CGContext(
            data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
          do {
            if let cgImage = context?.makeImage() {
              let uiImage = UIImage(cgImage: cgImage)
              let mpImage = try MPImage(uiImage: uiImage)

              // MediaPipe 추론 실행
              let handLandmarkerResult = try handLandmarker.detect(image: mpImage)
              // 결과 파싱
              let parseResult = self.parseMediaPipeResults(handLandmarkerResult)

              // PNG 또는 JPEG 포맷으로 인코딩
              guard let processedImageData = uiImage.pngData() else {
                // 인코딩 실패 처리
                return
              }

              DispatchQueue.main.async {
                result([
                  "success": true,
                  "processedImageData": FlutterStandardTypedData(bytes: processedImageData),
                  "result": parseResult,
                ])
              }

            } else {
              result("Inference Fail")
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "INFERENCE_ERROR", message: error.localizedDescription, details: nil)
              )
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(code: "INFERENCE_ERROR", message: error.localizedDescription, details: nil)
          )
        }
      }
    }
  }

  private func loadModel(result: FlutterResult) {
    do {
      guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
        NSLog("Model file not found at path: hand_landmarker.task")
        result(FlutterError(code: "MODEL_NOT_FOUND", message: "Model file not found", details: nil))
        return
      }

      let options = HandLandmarkerOptions()
      options.baseOptions.modelAssetPath = modelPath
      options.runningMode = .image
      options.numHands = 2
      options.minHandDetectionConfidence = existThreshold
      options.minHandPresenceConfidence = existThreshold
      options.minTrackingConfidence = scoreThreshold
      
      // [STEP 3] GPU 가속 활성화로 추론 성능 향상
      options.baseOptions.delegate = .GPU

      handLandmarker = try HandLandmarker(options: options)

      result("Model loaded successfully")
    } catch {
      NSLog("Model load error: \(error.localizedDescription)")
      result(
        FlutterError(code: "MODEL_LOAD_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func parseMediaPipeResults(_ handLandmarkerResult: HandLandmarkerResult) -> [String: Any]
  {
    NSLog("MediaPipe result - hands detected: \(handLandmarkerResult.landmarks.count)")

    guard let firstHand = handLandmarkerResult.landmarks.first else {
      NSLog("No hands detected in MediaPipe result")
      return [
        "landmarks": [],
        "confidence": 0.0,
        "detected": false,
        "validLandmarks": 0,
      ]
    }

    NSLog("First hand landmarks count: \(firstHand.count)")

    var parsedLandmarks: [[String: Any]] = []
    var validLandmarks = 0

    // MediaPipe 21개 랜드마크 파싱
    for landmark in firstHand {
      let x = Double(landmark.x) * Double(inputSize)  // 정규화된 좌표를 224 스케일로 변환
      let y = Double(landmark.y) * Double(inputSize)
      let z = Double(landmark.z ?? 0.0)

      // 유효한 랜드마크인지 확인
      if landmark.x >= 0.0 && landmark.x <= 1.0 && landmark.y >= 0.0 && landmark.y <= 1.0 {
        parsedLandmarks.append([
          "x": x,
          "y": y,
          "z": z,
        ])
        validLandmarks += 1
      }
    }

    // 첫 번째 손의 handedness confidence 사용
    let handednessConfidence = handLandmarkerResult.handedness.first?.first?.score ?? 0.0

    NSLog("Handedness confidence: \(handednessConfidence), Valid landmarks: \(validLandmarks)")

    return [
      "landmarks": parsedLandmarks,
      "confidence": Double(handednessConfidence),
      "detected": true,
      "validLandmarks": validLandmarks,
      "presenceConfidence": Double(handednessConfidence),
    ]
  }
}
