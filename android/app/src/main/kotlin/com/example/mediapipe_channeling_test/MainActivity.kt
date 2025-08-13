package com.example.mediapipe_channeling_test

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerOptions
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerOptions
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var handLandmarker: HandLandmarker? = null
    private var gestureRecognizer: GestureRecognizer? = null
    private lateinit var backgroundExecutor: ExecutorService
    private val handler = Handler(Looper.getMainLooper())
    
    private val existThreshold = 0.5f
    private val scoreThreshold = 0.5f
    private val channelName = "channel_Mediapipe"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        backgroundExecutor = Executors.newSingleThreadExecutor()
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load_landmark" -> loadLandmarkModel(result)
                "load_gesture" -> loadGestureModel(result)
                "inference_landmark" -> runInferenceLandmark(call, result)
                "inference_gesture" -> runInferenceGesture(call, result)
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
    
    private fun loadGestureModel(result: MethodChannel.Result) {
        backgroundExecutor.execute {
            try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath("gesture_recognizer.task")
                    .setDelegate(Delegate.GPU)
                    .build()
                    
                val options = GestureRecognizerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumHands(2)
                    .setMinHandDetectionConfidence(existThreshold)
                    .setMinHandPresenceConfidence(existThreshold)
                    .setMinTrackingConfidence(scoreThreshold)
                    .build()
                    
                gestureRecognizer = GestureRecognizer.createFromOptions(applicationContext, options)
                
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
    
    private fun runInferenceLandmark(call: MethodCall, result: MethodChannel.Result) {
        val landmarker = handLandmarker
        if (landmarker == null) {
            result.error("NO_MODEL", "Model not loaded", null)
            return
        }
        
        val arguments = call.arguments as? Map<String, Any>
        if (arguments == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        val imageData = arguments["imageData"] as? ByteArray
        val width = arguments["width"] as? Int
        val height = arguments["height"] as? Int
        
        if (imageData == null || width == null || height == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        backgroundExecutor.execute {
            try {
                val bitmap = createBitmapFromRawBytes(imageData, width, height)
                val mpImage = BitmapImageBuilder(bitmap).build()
                
                val landmarkResult = landmarker.detect(mpImage)
                val parseResult = parseLandmarkResult(landmarkResult)
                
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
    
    private fun runInferenceGesture(call: MethodCall, result: MethodChannel.Result) {
        val recognizer = gestureRecognizer
        if (recognizer == null) {
            result.error("NO_MODEL", "Model not loaded", null)
            return
        }
        
        val arguments = call.arguments as? Map<String, Any>
        if (arguments == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        val imageData = arguments["imageData"] as? ByteArray
        val width = arguments["width"] as? Int
        val height = arguments["height"] as? Int
        
        if (imageData == null || width == null || height == null) {
            result.error("INVALID_ARGS", "Invalid arguments", null)
            return
        }
        
        backgroundExecutor.execute {
            try {
                val bitmap = createBitmapFromRawBytes(imageData, width, height)
                val mpImage = BitmapImageBuilder(bitmap).build()
                
                val gestureResult = recognizer.recognize(mpImage)
                val parseResult = parseGestureResult(gestureResult)
                
                Log.d("MainActivity", "Gesture result: $parseResult")
                
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
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val buffer = ByteBuffer.wrap(imageData)
        bitmap.copyPixelsFromBuffer(buffer)
        return bitmap
    }
    
    private fun parseLandmarkResult(result: HandLandmarkerResult): Map<String, Any> {
        if (result.landmarks().isEmpty()) {
            return mapOf(
                "landmarks" to emptyList<Any>(),
                "confidence" to 0.0,
                "detected" to false,
                "validLandmarks" to 0
            )
        }
        
        val firstHand = result.landmarks()[0]
        val landmarks = mutableListOf<Map<String, Double>>()
        var validLandmarks = 0
        
        for (landmark in firstHand) {
            val x = landmark.x().toDouble()
            val y = landmark.y().toDouble()
            val z = landmark.z().toDouble()
            
            if (x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
                landmarks.add(mapOf(
                    "x" to x,
                    "y" to y,
                    "z" to z
                ))
                validLandmarks++
            }
        }
        
        val handednessConfidence = if (result.handedness().isNotEmpty() && result.handedness()[0].isNotEmpty()) {
            result.handedness()[0][0].score().toDouble()
        } else {
            0.0
        }
        
        return mapOf(
            "landmarks" to landmarks,
            "confidence" to handednessConfidence,
            "detected" to true,
            "validLandmarks" to validLandmarks,
            "presenceConfidence" to handednessConfidence
        )
    }
    
    private fun parseGestureResult(result: GestureRecognizerResult): Map<String, Any> {
        if (result.gestures().isEmpty()) {
            return mapOf(
                "gestures" to emptyList<Any>(),
                "handedness" to emptyList<Any>(),
                "landmarks" to emptyList<Any>(),
                "worldLandmarks" to emptyList<Any>(),
                "detected" to false
            )
        }
        
        val gestures = mutableListOf<Map<String, Any>>()
        val handedness = mutableListOf<Map<String, Any>>()
        val landmarks = mutableListOf<List<Map<String, Double>>>()
        val worldLandmarks = mutableListOf<List<Map<String, Double>>>()
        
        for (handGestures in result.gestures()) {
            for (gestureCategory in handGestures) {
                gestures.add(mapOf(
                    "categoryName" to gestureCategory.categoryName(),
                    "score" to gestureCategory.score().toDouble()
                ))
            }
        }
        
        for (handHandedness in result.handedness()) {
            for (handednessCategory in handHandedness) {
                handedness.add(mapOf(
                    "categoryName" to handednessCategory.categoryName(),
                    "score" to handednessCategory.score().toDouble()
                ))
            }
        }
        
        for (handLandmarks in result.landmarks()) {
            val handLandmarkData = mutableListOf<Map<String, Double>>()
            for (landmark in handLandmarks) {
                handLandmarkData.add(mapOf(
                    "x" to landmark.x().toDouble(),
                    "y" to landmark.y().toDouble(),
                    "z" to landmark.z().toDouble()
                ))
            }
            landmarks.add(handLandmarkData)
        }
        
        for (handWorldLandmarks in result.worldLandmarks()) {
            val handWorldLandmarkData = mutableListOf<Map<String, Double>>()
            for (worldLandmark in handWorldLandmarks) {
                handWorldLandmarkData.add(mapOf(
                    "x" to worldLandmark.x().toDouble(),
                    "y" to worldLandmark.y().toDouble(),
                    "z" to worldLandmark.z().toDouble()
                ))
            }
            worldLandmarks.add(handWorldLandmarkData)
        }
        
        return mapOf(
            "gestures" to gestures,
            "handedness" to handedness,
            "landmarks" to landmarks,
            "worldLandmarks" to worldLandmarks,
            "detected" to true
        )
    }
}