import 'package:camera/camera.dart';

/// MediaPipe 추론 모드 정의
/// landmark: 손 랜드마크 감지, gesture: 제스처 인식
enum InferenceMode { landmark, gesture }

/// MediaPipe 추론 결과 구조체
class MediaPipeResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  const MediaPipeResult({
    required this.success,
    this.data,
    this.error,
  });

  /// 손 랜드마크 데이터 추출
  List<Map<String, double>> get landmarks {
    if (!success || data == null) return [];
    
    final result = data!['result'];
    if (result is! Map) return [];
    
    final landmarks = result['landmarks'];
    if (landmarks is List) {
      return landmarks.map((landmark) {
        if (landmark is Map) {
          return Map<String, double>.from(landmark.map(
            (key, value) => MapEntry(key.toString(), (value as num).toDouble())
          ));
        }
        return <String, double>{};
      }).toList();
    }
    return [];
  }

  /// 제스처 인식 결과 추출
  Map<String, dynamic> get gestureData {
    if (!success || data == null) return {};
    final result = data!['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {};
  }

  /// 손 감지 여부
  bool get isHandDetected {
    if (!success || data == null) return false;
    final result = data!['result'];
    if (result is Map) {
      return result['detected'] == true;
    }
    return false;
  }
}

/// 플랫폼별 MediaPipe 구현을 위한 추상 인터페이스
abstract class MediaPipeInterface {
  /// MediaPipe 모델 초기화
  Future<void> initialize();

  /// 특정 모드의 모델 로딩
  Future<bool> loadModel(InferenceMode mode);

  /// 손 랜드마크 감지 추론
  Future<MediaPipeResult> detectLandmarks({
    required CameraImage? image,
  });

  /// 제스처 인식 추론
  Future<MediaPipeResult> recognizeGesture({
    required CameraImage? image,
  });

  /// 리소스 정리
  Future<void> dispose();

  /// 현재 모델 로딩 상태
  bool get isModelLoaded;

  /// 현재 추론 모드
  InferenceMode get currentMode;
}

/// MediaPipe 설정 옵션
class MediaPipeConfig {
  /// 최대 감지할 손 개수
  final int numHands;
  
  /// 손 감지 최소 신뢰도
  final double minHandDetectionConfidence;
  
  /// 손 존재 최소 신뢰도
  final double minHandPresenceConfidence;
  
  /// 추적 최소 신뢰도
  final double minTrackingConfidence;

  const MediaPipeConfig({
    this.numHands = 2,
    this.minHandDetectionConfidence = 0.5,
    this.minHandPresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
  });
}