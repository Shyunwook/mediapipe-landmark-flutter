import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import '../common/mediapipe_interface.dart';

/// 네이티브 플랫폼(iOS/Android)용 MediaPipe 구현체
class MediaPipeNative implements MediaPipeInterface {
  /// Android/iOS 네이티브와 통신하는 메소드 채널
  static const MethodChannel _channel = MethodChannel('channel_Mediapipe');

  /// MediaPipe 설정
  final MediaPipeConfig config;

  /// 현재 모델 로딩 상태
  bool _isModelLoaded = false;

  /// 현재 추론 모드
  InferenceMode _currentMode = InferenceMode.landmark;

  MediaPipeNative({
    this.config = const MediaPipeConfig(),
  });

  @override
  Future<void> initialize() async {
    // 네이티브 플랫폼에서는 별도 초기화 불필요
    // 모델 로딩이 초기화 역할
  }

  @override
  Future<bool> loadModel(InferenceMode mode) async {
    try {
      final methodName = mode == InferenceMode.landmark
          ? 'load_landmark'
          : 'load_gesture';

      await _channel.invokeMethod(methodName);
      _isModelLoaded = true;
      _currentMode = mode;
      
      return true;
    } catch (e) {
      _isModelLoaded = false;
      return false;
    }
  }

  @override
  Future<MediaPipeResult> detectLandmarks({
    required CameraImage image,
  }) async {
    if (!_isModelLoaded || _currentMode != InferenceMode.landmark) {
      return const MediaPipeResult(
        success: false,
        error: 'Landmark model not loaded',
      );
    }

    try {
      final imageBytes = _cameraImageToBytes(image);
      
      final result = await _channel.invokeMethod('inference_landmark', {
        'imageData': imageBytes,
        'width': image.width,
        'height': image.height,
      });

      return MediaPipeResult(
        success: result?['success'] ?? false,
        data: Map<String, dynamic>.from(result),
      );
    } catch (e) {
      return MediaPipeResult(
        success: false,
        error: 'Landmark detection failed: $e',
      );
    }
  }

  @override
  Future<MediaPipeResult> recognizeGesture({
    required CameraImage image,
  }) async {
    if (!_isModelLoaded || _currentMode != InferenceMode.gesture) {
      return const MediaPipeResult(
        success: false,
        error: 'Gesture model not loaded',
      );
    }

    try {
      final imageBytes = _cameraImageToBytes(image);
      
      final result = await _channel.invokeMethod('inference_gesture', {
        'imageData': imageBytes,
        'width': image.width,
        'height': image.height,
      });

      return MediaPipeResult(
        success: result?['success'] ?? false,
        data: Map<String, dynamic>.from(result),
      );
    } catch (e) {
      return MediaPipeResult(
        success: false,
        error: 'Gesture recognition failed: $e',
      );
    }
  }

  @override
  Future<void> dispose() async {
    _isModelLoaded = false;
    // 네이티브 리소스는 자동으로 정리됨
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  @override
  InferenceMode get currentMode => _currentMode;

  /// CameraImage를 MediaPipe 입력용 바이트 배열로 변환
  /// YUV420 포맷에서 Y(휘도) 평면만 추출하여 성능 최적화
  Uint8List _cameraImageToBytes(CameraImage image) {
    return image.planes[0].bytes; // Y plane만 사용 (그레이스케일)
  }
}