package com.example.mediapipe_channeling_test

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker.HandLandmarkerOptions
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer.GestureRecognizerOptions
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Android MediaPipe 손 랜드마크 및 제스처 인식 네이티브 구현
 * Flutter와 MethodChannel을 통해 통신하여 실시간 추론 수행
 * 
 * 주요 기능:
 * - YUV420 이미지 데이터를 RGB 비트맵으로 변환
 * - 카메라 회전 보정 (90도 반시계방향 회전)
 * - MediaPipe 모델 로딩 및 추론 실행
 * - 백그라운드 스레드에서 비동기 처리
 */
class MainActivity : FlutterActivity() {
    // === MediaPipe 모델 인스턴스 ===
    private var handLandmarker: HandLandmarker? = null      // 손 랜드마크 감지 모델
    private var gestureRecognizer: GestureRecognizer? = null // 제스처 인식 모델
    
    // === 스레드 관리 ===
    private lateinit var backgroundExecutor: ExecutorService // 백그라운드 스레드 풀
    private val handler = Handler(Looper.getMainLooper())    // 메인 스레드 핸들러
    
    // === MediaPipe 설정값 ===
    private val existThreshold = 0.5f    // 손 감지/존재 최소 신뢰도
    private val scoreThreshold = 0.5f    // 추적 최소 신뢰도
    private val channelName = "channel_Mediapipe" // Flutter 통신 채널명
    
    /**
     * Flutter 엔진 설정 및 MethodChannel 초기화
     * Flutter에서 호출할 수 있는 네이티브 메소드들 등록
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 백그라운드 처리용 단일 스레드 실행기 생성
        backgroundExecutor = Executors.newSingleThreadExecutor()
        
        // Flutter와의 양방향 통신을 위한 MethodChannel 설정
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load_landmark" -> loadLandmarkModel(result)        // 랜드마크 모델 로딩
                "load_gesture" -> loadGestureModel(result)          // 제스처 모델 로딩
                "inference_landmark" -> runInferenceLandmark(call, result)  // 랜드마크 추론 수행
                "inference_gesture" -> runInferenceGesture(call, result)    // 제스처 추론 수행
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        backgroundExecutor.shutdown()
        handLandmarker?.close()
        gestureRecognizer?.close()
    }
    
    private fun loadLandmarkModel(result: MethodChannel.Result) {
        backgroundExecutor.execute {
            try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("hand_landmarker.task")
                    .setDelegate(Delegate.GPU)
                    .build()
                    
                val options = HandLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumHands(2)
                    .setMinHandDetectionConfidence(existThreshold)
                    .setMinHandPresenceConfidence(existThreshold)
                    .setMinTrackingConfidence(scoreThreshold)
                    .build()
                    
                handLandmarker = HandLandmarker.createFromOptions(applicationContext, options)
                
                handler.post {
                    result.success("Model loaded successfully")
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Model load error: ${e.message}")
                handler.post {
                    result.error("MODEL_LOAD_ERROR", e.message, null)
                }
            }
        }
    }
    
    /**
     * 제스처 인식 모델 로딩
     * gesture_recognizer.task 파일을 앱 에셋에서 로드하여 MediaPipe 초기화
     * 
     * 설정 옵션:
     * - GPU 가속 활성화로 추론 성능 향상
     * - 최대 2개 손 동시 감지
     * - 신뢰도 임계값 0.5 적용
     * 
     * @param result Flutter로 반환할 결과 콜백
     */
    private fun loadGestureModel(result: MethodChannel.Result) {
        backgroundExecutor.execute {
            try {
                // 1. MediaPipe 기본 옵션 설정
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("gesture_recognizer.task")  // 앱 에셋의 모델 파일
                    .setDelegate(Delegate.GPU)                    // GPU 가속 활성화
                    .build()
                    
                // 2. 제스처 인식 전용 옵션 설정
                val options = GestureRecognizerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE)            // 정적 이미지 처리 모드
                    .setNumHands(2)                               // 최대 2개 손 감지
                    .setMinHandDetectionConfidence(existThreshold) // 손 감지 최소 신뢰도 (0.5)
                    .setMinHandPresenceConfidence(existThreshold)  // 손 존재 최소 신뢰도 (0.5)
                    .setMinTrackingConfidence(scoreThreshold)     // 추적 최소 신뢰도 (0.5)
                    .build()
                    
                // 3. 제스처 인식기 인스턴스 생성
                gestureRecognizer = GestureRecognizer.createFromOptions(applicationContext, options)
                
                // 4. 메인 스레드에서 성공 결과 반환
                handler.post {
                    result.success("Model loaded successfully")
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Model load error: ${e.message}")
                handler.post {
                    result.error("MODEL_LOAD_ERROR", e.message, null)
                }
            }
        }
    }
    
    /**
     * 손 랜드마크 감지 추론 수행
     * Flutter에서 전송된 YUV420 이미지를 처리하여 21개 랜드마크 반환
     * 
     * @param call Flutter에서 전송된 메소드 호출 (imageData, width, height 포함)
     * @param result 결과 반환용 콜백
     */
    private fun runInferenceLandmark(call: MethodCall, result: MethodChannel.Result) {
        // 1. 모델 로딩 상태 확인
        val landmarker = handLandmarker
        if (landmarker == null) {
            result.error("NO_MODEL", "Model not loaded", null)
            return
        }
        
        // 2. Flutter에서 전송된 파라미터 파싱
        val arguments = call.arguments as? Map<String, Any>
        if (arguments == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        val imageData = arguments["imageData"] as? ByteArray  // YUV420 Y plane 데이터
        val width = arguments["width"] as? Int               // 카메라 이미지 너비
        val height = arguments["height"] as? Int             // 카메라 이미지 높이
        
        if (imageData == null || width == null || height == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        // 3. 백그라운드 스레드에서 추론 수행 (UI 블로킹 방지)
        backgroundExecutor.execute {
            try {
                // 4. YUV420 Y plane → RGB 비트맵 변환 + 90도 회전
                val bitmap = createBitmapFromRawBytes(imageData, width, height)
                
                // 5. MediaPipe 입력 형태로 변환
                val mpImage = BitmapImageBuilder(bitmap).build()
                
                // 6. 손 랜드마크 감지 실행
                val landmarkResult = landmarker.detect(mpImage)
                
                // 7. 결과를 Flutter에서 사용할 수 있는 형태로 파싱
                val parseResult = parseLandmarkResult(landmarkResult)
                
                // 8. 메인 스레드에서 결과 반환
                handler.post {
                    result.success(mapOf(
                        "success" to true,
                        "result" to parseResult
                    ))
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Inference error: ${e.message}")
                handler.post {
                    result.error("INFERENCE_ERROR", e.message, null)
                }
            }
        }
    }
    
    /**
     * 제스처 인식 추론 수행
     * Flutter에서 전송된 YUV420 이미지를 처리하여 제스처 분류 결과 반환
     * 
     * 처리 과정:
     * 1. 모델 로딩 상태 확인
     * 2. 파라미터 유효성 검증
     * 3. 이미지 전처리 (YUV420 → RGB + 90도 회전)
     * 4. MediaPipe 제스처 인식 실행
     * 5. 결과 파싱 및 Flutter 반환
     * 
     * @param call Flutter에서 전송된 메소드 호출 (imageData, width, height 포함)
     * @param result 결과 반환용 콜백
     */
    private fun runInferenceGesture(call: MethodCall, result: MethodChannel.Result) {
        // 1. 제스처 인식 모델 로딩 상태 확인
        val recognizer = gestureRecognizer
        if (recognizer == null) {
            result.error("NO_MODEL", "Model not loaded", null)
            return
        }
        
        // 2. Flutter에서 전송된 파라미터 파싱
        val arguments = call.arguments as? Map<String, Any>
        if (arguments == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        val imageData = arguments["imageData"] as? ByteArray  // YUV420 Y plane 데이터
        val width = arguments["width"] as? Int               // 카메라 이미지 너비
        val height = arguments["height"] as? Int             // 카메라 이미지 높이
        
        if (imageData == null || width == null || height == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        // 3. 백그라운드 스레드에서 추론 수행 (UI 블로킹 방지)
        backgroundExecutor.execute {
            try {
                // 4. YUV420 Y plane → RGB 비트맵 변환 + 90도 회전
                val bitmap = createBitmapFromRawBytes(imageData, width, height)
                
                // 5. MediaPipe 입력 형태로 변환
                val mpImage = BitmapImageBuilder(bitmap).build()
                
                // 6. 제스처 인식 실행 (랜드마크 + 제스처 분류 동시 수행)
                val gestureResult = recognizer.recognize(mpImage)
                
                // 7. 결과를 Flutter에서 사용할 수 있는 형태로 파싱
                val parseResult = parseGestureResult(gestureResult)
                
                // 8. 디버깅용 로그 출력
                Log.d("MainActivity", "Gesture result: $parseResult")
                
                // 9. 메인 스레드에서 결과 반환
                handler.post {
                    result.success(mapOf(
                        "success" to true,
                        "result" to parseResult
                    ))
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Inference error: ${e.message}")
                handler.post {
                    result.error("INFERENCE_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun createBitmapFromRawBytes(imageData: ByteArray, width: Int, height: Int): Bitmap {
        // YUV420 Y plane data (grayscale) to RGB conversion
        val expectedYSize = width * height // Y plane size
        val actualSize = imageData.size
        
        Log.d("MainActivity", "Expected Y plane size: $expectedYSize, Actual size: $actualSize")
        
        // Create RGB bitmap from Y plane (grayscale) - efficient native conversion
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        
        // Efficient Y to ARGB conversion
        for (i in 0 until minOf(actualSize, expectedYSize)) {
            val y = imageData[i].toInt() and 0xFF
            // Convert grayscale Y to ARGB (A=255, R=G=B=Y)
            pixels[i] = (0xFF shl 24) or (y shl 16) or (y shl 8) or y
        }
        
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        
        // Rotate bitmap 90 degrees counterclockwise for proper MediaPipe orientation
        // TODO: 성능 최적화 고려사항
        // 현재: 매 프레임마다 새 비트맵 생성 (메모리 2배 사용, GC 압박)
        // 최적화 옵션들:
        // 1. matrix.filter = false로 필터링 비활성화
        // 2. 픽셀 레벨 회전으로 더 빠른 처리
        // 3. 비트맵 풀 사용으로 메모리 재사용
        // 4. 네이티브 C++ 구현으로 성능 향상
        return rotateBitmap(bitmap, -90f)
    }
    
    private fun rotateBitmap(bitmap: Bitmap, degrees: Float): Bitmap {
        val matrix = Matrix()
        matrix.postRotate(degrees)
        // TODO: 성능 이슈 발생시 마지막 파라미터를 false로 변경 (필터링 비활성화)
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
    
    // TODO: 성능 최적화 - 픽셀 레벨 회전 (더 빠름)
    // private fun rotatePixelsOptimized(pixels: IntArray, width: Int, height: Int): IntArray {
    //     val rotated = IntArray(width * height)
    //     for (i in 0 until height) {
    //         for (j in 0 until width) {
    //             rotated[j * height + (height - 1 - i)] = pixels[i * width + j]
    //         }
    //     }
    //     return rotated
    // }
    
    // TODO: 성능 최적화 - 비트맵 풀 (메모리 재사용)
    // class BitmapPool {
    //     private val pool = mutableListOf<Bitmap>()
    //     fun getBitmap(width: Int, height: Int): Bitmap {
    //         return pool.removeFirstOrNull { it.width == width && it.height == height }
    //             ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    //     }
    //     fun recycleBitmap(bitmap: Bitmap) {
    //         if (pool.size < 3) pool.add(bitmap)
    //     }
    // }
    
    /**
     * 손 랜드마크 감지 결과를 Flutter에서 사용할 수 있는 형태로 파싱
     * 
     * MediaPipe HandLandmarkerResult → Flutter Map 변환
     * - 21개 랜드마크 좌표 (정규화된 0.0~1.0 범위)
     * - 손 감지 신뢰도 및 유효성 정보
     * - 좌/우손 분류 결과
     * 
     * @param result MediaPipe 손 랜드마크 감지 결과
     * @return Flutter에서 파싱 가능한 Map 형태 결과
     */
    private fun parseLandmarkResult(result: HandLandmarkerResult): Map<String, Any> {
        // 1. 손이 감지되지 않은 경우 빈 결과 반환
        if (result.landmarks().isEmpty()) {
            return mapOf(
                "landmarks" to emptyList<Any>(),
                "confidence" to 0.0,
                "detected" to false,
                "validLandmarks" to 0
            )
        }
        
        // 2. 첫 번째 손의 랜드마크 추출 (다중 손 감지 시 첫 번째만 사용)
        val firstHand = result.landmarks()[0]
        val landmarks = mutableListOf<Map<String, Double>>()
        var validLandmarks = 0
        
        // 3. 21개 랜드마크 좌표 파싱 및 유효성 검증
        for (landmark in firstHand) {
            val x = landmark.x().toDouble()  // 정규화된 x 좌표 (0.0~1.0)
            val y = landmark.y().toDouble()  // 정규화된 y 좌표 (0.0~1.0)
            val z = landmark.z().toDouble()  // 상대적 깊이 값
            
            // 유효한 좌표 범위 내에 있는지 확인
            if (x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
                landmarks.add(mapOf(
                    "x" to x,
                    "y" to y,
                    "z" to z
                ))
                validLandmarks++
            }
        }
        
        // 4. 좌/우손 분류 신뢰도 추출
        val handednessConfidence = if (result.handedness().isNotEmpty() && result.handedness()[0].isNotEmpty()) {
            result.handedness()[0][0].score().toDouble()
        } else {
            0.0
        }
        
        // 5. Flutter에서 사용할 결과 맵 생성
        return mapOf(
            "landmarks" to landmarks,              // 21개 랜드마크 좌표 배열
            "confidence" to handednessConfidence, // 좌/우손 분류 신뢰도
            "detected" to true,                   // 손 감지 성공 여부
            "validLandmarks" to validLandmarks,   // 유효한 랜드마크 개수
            "presenceConfidence" to handednessConfidence // 손 존재 신뢰도
        )
    }
    
    /**
     * 제스처 인식 결과를 Flutter에서 사용할 수 있는 형태로 파싱
     * 
     * MediaPipe GestureRecognizerResult → Flutter Map 변환
     * - 인식된 제스처 분류 결과 (Open_Palm, Closed_Fist 등)
     * - 손 랜드마크 좌표 (화면 좌표계)
     * - 월드 랜드마크 좌표 (실제 3D 좌표계)
     * - 좌/우손 분류 정보
     * 
     * @param result MediaPipe 제스처 인식 결과
     * @return Flutter에서 파싱 가능한 Map 형태 결과
     */
    private fun parseGestureResult(result: GestureRecognizerResult): Map<String, Any> {
        // 1. 제스처가 감지되지 않은 경우 빈 결과 반환
        if (result.gestures().isEmpty()) {
            return mapOf(
                "gestures" to emptyList<Any>(),
                "handedness" to emptyList<Any>(),
                "landmarks" to emptyList<Any>(),
                "worldLandmarks" to emptyList<Any>(),
                "detected" to false
            )
        }
        
        // 2. 결과 저장용 컬렉션 초기화
        val gestures = mutableListOf<Map<String, Any>>()
        val handedness = mutableListOf<Map<String, Any>>()
        val landmarks = mutableListOf<List<Map<String, Double>>>()
        val worldLandmarks = mutableListOf<List<Map<String, Double>>>()
        
        // 3. 감지된 제스처 분류 결과 파싱
        // 각 손별로 감지된 제스처들 (Open_Palm, Closed_Fist, Peace 등)
        for (handGestures in result.gestures()) {
            for (gestureCategory in handGestures) {
                gestures.add(mapOf(
                    "categoryName" to gestureCategory.categoryName(), // 제스처 이름
                    "score" to gestureCategory.score().toDouble()     // 인식 신뢰도 (0.0~1.0)
                ))
            }
        }
        
        // 4. 좌/우손 분류 결과 파싱
        for (handHandedness in result.handedness()) {
            for (handednessCategory in handHandedness) {
                handedness.add(mapOf(
                    "categoryName" to handednessCategory.categoryName(), // "Left" 또는 "Right"
                    "score" to handednessCategory.score().toDouble()     // 분류 신뢰도
                ))
            }
        }
        
        // 5. 손 랜드마크 좌표 파싱 (화면 좌표계, 정규화됨)
        for (handLandmarks in result.landmarks()) {
            val handLandmarkData = mutableListOf<Map<String, Double>>()
            for (landmark in handLandmarks) {
                handLandmarkData.add(mapOf(
                    "x" to landmark.x().toDouble(), // 정규화된 x 좌표 (0.0~1.0)
                    "y" to landmark.y().toDouble(), // 정규화된 y 좌표 (0.0~1.0)
                    "z" to landmark.z().toDouble()  // 상대적 깊이 값
                ))
            }
            landmarks.add(handLandmarkData)
        }
        
        // 6. 월드 랜드마크 좌표 파싱 (실제 3D 공간 좌표)
        for (handWorldLandmarks in result.worldLandmarks()) {
            val handWorldLandmarkData = mutableListOf<Map<String, Double>>()
            for (worldLandmark in handWorldLandmarks) {
                handWorldLandmarkData.add(mapOf(
                    "x" to worldLandmark.x().toDouble(), // 실제 x 좌표 (미터 단위)
                    "y" to worldLandmark.y().toDouble(), // 실제 y 좌표 (미터 단위)
                    "z" to worldLandmark.z().toDouble()  // 실제 z 좌표 (미터 단위)
                ))
            }
            worldLandmarks.add(handWorldLandmarkData)
        }
        
        // 7. Flutter에서 사용할 결과 맵 생성
        return mapOf(
            "gestures" to gestures,           // 인식된 제스처 목록
            "handedness" to handedness,       // 좌/우손 분류 결과
            "landmarks" to landmarks,         // 화면 좌표계 랜드마크
            "worldLandmarks" to worldLandmarks, // 실제 3D 좌표계 랜드마크
            "detected" to true                // 제스처 감지 성공 여부
        )
    }
}