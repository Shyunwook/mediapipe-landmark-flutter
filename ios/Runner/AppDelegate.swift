import Flutter
import MediaPipeTasksVision
import UIKit

/// iOS MediaPipe 손 랜드마크 및 제스처 인식 네이티브 구현
/// Flutter와 MethodChannel을 통해 통신하여 실시간 추론 수행
@main
@objc class AppDelegate: FlutterAppDelegate {
  // === MediaPipe 모델 인스턴스 ===
  private var handLandmarker: HandLandmarker?      // 손 랜드마크 감지 모델
  private var gestureRecognizer: GestureRecognizer? // 제스처 인식 모델

  // === MediaPipe 설정값 ===
  private let inputSize = 224                    // 입력 이미지 크기 (사용되지 않음)
  private let existThreshold: Float = 0.5       // 손 감지 최소 신뢰도
  private let scoreThreshold: Float = 0.5       // 추적 최소 신뢰도

  // === 성능 최적화: 메모리 재사용 ===
  private var reusableLandmarks: [[String: Any]] = []

  /// 앱 시작시 Flutter 채널 설정 및 메소드 핸들러 등록
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Flutter와의 양방향 통신을 위한 MethodChannel 설정
    let channel = FlutterMethodChannel(
      name: "channel_Mediapipe", binaryMessenger: controller.binaryMessenger
    )

    // Flutter에서 호출할 수 있는 네이티브 메소드들 등록
    channel.setMethodCallHandler {
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "load_landmark":        // 랜드마크 모델 로딩
        self?.loadLandmarkModel(result: result)
      case "load_gesture":         // 제스처 모델 로딩
        self?.loadGestureModel(result: result)
      case "inference_landmark":   // 랜드마크 추론 수행
        self?.runInferenceLandmark(call: call, result: result)
      case "inference_gesture":    // 제스처 추론 수행
        self?.runInferenceGesture(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 손 랜드마크 감지 추론 수행
  /// Flutter에서 전송된 카메라 이미지를 MediaPipe로 처리하여 21개 랜드마크 반환
  private func runInferenceLandmark(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // 1. 모델 로딩 상태 확인
    guard let handLandmarker = handLandmarker else {
      result(FlutterError(code: "NO_MODEL", message: "Model not loaded", details: nil))
      return
    }

    // 2. Flutter에서 전송된 파라미터 파싱
    guard let args = call.arguments as? [String: Any],
      let imageData = args["imageData"] as? FlutterStandardTypedData,  // YUV420 Y plane 데이터
      let width = args["width"] as? Int,                               // 카메라 이미지 너비
      let height = args["height"] as? Int                              // 카메라 이미지 높이
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
      return
    }

    // 3. 백그라운드 스레드에서 추론 수행 (UI 블로킹 방지)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      do {
        // 4. Raw 이미지 데이터를 MediaPipe 입력 형태로 변환
        // Flutter Camera의 YUV420 Y plane → CGContext → UIImage → MPImage 순서로 변환
        imageData.data.withUnsafeBytes { ptr in
          // CGContext로 Raw 바이트를 비트맵으로 변환
          let context = CGContext(
            data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
            width: width,
            height: height,
            bitsPerComponent: 8,                                    // 8비트 컬러 채널
            bytesPerRow: width * 4,                                // RGBA 4바이트 per pixel
            space: CGColorSpaceCreateDeviceRGB(),                  // RGB 컬러스페이스
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue // Alpha 채널 설정
          )
          
          do {
            if let cgImage = context?.makeImage() {
              let uiImage = UIImage(cgImage: cgImage)
              let mpImage = try MPImage(uiImage: uiImage)

              // 5. MediaPipe 손 랜드마크 감지 실행
              let handLandmarkerResult = try handLandmarker.detect(image: mpImage)
              
              // 6. 결과를 Flutter에서 사용할 수 있는 형태로 파싱
              let parseResult = self.parseLandmarkResult(handLandmarkerResult)

              // 7. 메인 스레드에서 결과 반환
              DispatchQueue.main.async {
                result([
                  "success": true,
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

  private func runInferenceGesture(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let gestureRecognizer = gestureRecognizer else {
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
              let gestureRecognizerResult = try gestureRecognizer.recognize(image: mpImage)
              // 결과 파싱
              let parseResult = self.parseGestureResult(gestureRecognizerResult)
              
              // 디버깅을 위한 로그 출력
              NSLog("Gesture result: \(parseResult)")

              DispatchQueue.main.async {
                result([
                  "success": true,
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

  /// 손 랜드마크 감지 모델 로딩
  /// hand_landmarker.task 파일을 앱 번들에서 로드하여 MediaPipe 초기화
  private func loadLandmarkModel(result: FlutterResult) {
    do {
      // 1. 앱 번들에서 모델 파일 경로 확인
      guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
        result(
          FlutterError(
            code: "MODEL_NOT_FOUND", 
            message: "Model file 'hand_landmarker.task' not found in app bundle",
            details: nil))
        return
      }

      // 2. MediaPipe HandLandmarker 옵션 설정
      let options = HandLandmarkerOptions()
      options.baseOptions.modelAssetPath = modelPath
      options.runningMode = .image                          // 정적 이미지 모드 (vs 비디오/라이브 스트림)
      options.numHands = 2                                  // 최대 감지할 손 개수
      options.minHandDetectionConfidence = existThreshold  // 손 감지 최소 신뢰도 (0.5)
      options.minHandPresenceConfidence = existThreshold   // 손 존재 최소 신뢰도 (0.5)
      options.minTrackingConfidence = scoreThreshold       // 추적 최소 신뢰도 (0.5)

      // 3. GPU 가속 활성화 (성능 향상)
      options.baseOptions.delegate = .GPU

      // 4. HandLandmarker 인스턴스 생성
      handLandmarker = try HandLandmarker(options: options)

      result("Model loaded successfully")
    } catch {
      NSLog("Model load error: \(error.localizedDescription)")
      result(
        FlutterError(code: "MODEL_LOAD_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func loadGestureModel(result: FlutterResult) {
    do {
      guard let modelPath = Bundle.main.path(forResource: "gesture_recognizer", ofType: "task")
      else {
        // // 사용 가능한 모든 파일 나열
        // let bundle = Bundle.main
        // let allFiles = bundle.paths(forResourcesOfType: nil, inDirectory: nil)
        // NSLog("Available files in bundle: \(allFiles)")

        result(
          FlutterError(
            code: "MODEL_NOT_FOUND", message: "Model file 'gesture_recognizer.task' not found",
            details: nil))
        return
      }

      let options = GestureRecognizerOptions()
      options.baseOptions.modelAssetPath = modelPath
      options.runningMode = .image
      options.numHands = 2
      options.minHandDetectionConfidence = existThreshold
      options.minHandPresenceConfidence = existThreshold
      options.minTrackingConfidence = scoreThreshold

      // [STEP 3] GPU 가속 활성화로 추론 성능 향상
      options.baseOptions.delegate = .GPU

      gestureRecognizer = try GestureRecognizer(options: options)

      result("Model loaded successfully")
    } catch {
      NSLog("Model load error: \(error.localizedDescription)")
      result(
        FlutterError(code: "MODEL_LOAD_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func parseLandmarkResult(_ handLandmarkerResult: HandLandmarkerResult) -> [String: Any] {
    guard let firstHand = handLandmarkerResult.landmarks.first else {
      return [
        "landmarks": [],
        "confidence": 0.0,
        "detected": false,
        "validLandmarks": 0,
      ]
    }

    // 재사용 가능한 배열 초기화 (새 할당 대신 기존 배열 재사용)
    reusableLandmarks.removeAll(keepingCapacity: true)
    var validLandmarks = 0

    // MediaPipe 21개 랜드마크 파싱 (정규화된 좌표 그대로 반환)
    for landmark in firstHand {
      let x = Double(landmark.x)  // 정규화된 좌표 (0.0-1.0)
      let y = Double(landmark.y)
      let z = Double(landmark.z ?? 0.0)

      // 유효한 랜드마크인지 확인
      if landmark.x >= 0.0 && landmark.x <= 1.0 && landmark.y >= 0.0 && landmark.y <= 1.0 {
        reusableLandmarks.append([
          "x": x,
          "y": y,
          "z": z,
        ])
        validLandmarks += 1
      }
    }

    // 첫 번째 손의 handedness confidence 사용
    let handednessConfidence = handLandmarkerResult.handedness.first?.first?.score ?? 0.0

    return [
      "landmarks": reusableLandmarks,
      "confidence": Double(handednessConfidence),
      "detected": true,
      "validLandmarks": validLandmarks,
      "presenceConfidence": Double(handednessConfidence),
    ]
  }

  private func parseGestureResult(_ gestureRecognizerResult: GestureRecognizerResult) -> [String:
    Any]
  {
    guard !gestureRecognizerResult.gestures.isEmpty,
      let firstHandGestures = gestureRecognizerResult.gestures.first
    else {
      return [
        "gestures": [],
        "handedness": [],
        "landmarks": [],
        "worldLandmarks": [],
        "detected": false,
      ]
    }

    var gestures: [[String: Any]] = []
    var handedness: [[String: Any]] = []
    var landmarks: [[[String: Any]]] = []
    var worldLandmarks: [[[String: Any]]] = []

    // Parse gestures for each detected hand
    for (handIndex, handGestures) in gestureRecognizerResult.gestures.enumerated() {
      var handGestureData: [[String: Any]] = []

      for gestureCategory in handGestures {
        handGestureData.append([
          "categoryName": gestureCategory.categoryName,
          "score": Double(gestureCategory.score)
        ])
      }
      gestures.append(contentsOf: handGestureData)
    }

    // Parse handedness
    for (handIndex, handHandedness) in gestureRecognizerResult.handedness.enumerated() {
      var handHandednessData: [[String: Any]] = []

      for handednessCategory in handHandedness {
        handHandednessData.append([
          "categoryName": handednessCategory.categoryName,
          "score": Double(handednessCategory.score)
        ])
      }
      handedness.append(contentsOf: handHandednessData)
    }

    // Parse landmarks (screen coordinates)
    for handLandmarks in gestureRecognizerResult.landmarks {
      var handLandmarkData: [[String: Any]] = []

      for landmark in handLandmarks {
        handLandmarkData.append([
          "x": Double(landmark.x),  // 정규화된 좌표 (0.0-1.0)
          "y": Double(landmark.y),
          "z": Double(landmark.z ?? 0.0),
        ])
      }
      landmarks.append(handLandmarkData)
    }

    // Parse world landmarks (real-world 3D coordinates)
    for handWorldLandmarks in gestureRecognizerResult.worldLandmarks {
      var handWorldLandmarkData: [[String: Any]] = []

      for worldLandmark in handWorldLandmarks {
        handWorldLandmarkData.append([
          "x": Double(worldLandmark.x),
          "y": Double(worldLandmark.y),
          "z": Double(worldLandmark.z ?? 0.0),
        ])
      }
      worldLandmarks.append(handWorldLandmarkData)
    }

    return [
      "gestures": gestures,
      "handedness": handedness,
      "landmarks": landmarks,
      "worldLandmarks": worldLandmarks,
      "detected": true,
    ]
  }
}
