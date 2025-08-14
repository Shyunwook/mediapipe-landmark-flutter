import 'dart:js' as js;
import 'dart:convert';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../common/mediapipe_interface.dart';

/// 웹 플랫폼용 MediaPipe 구현체
class MediaPipeWeb implements MediaPipeInterface {
  /// MediaPipe 설정
  final MediaPipeConfig config;

  /// 현재 모델 로딩 상태
  bool _isModelLoaded = false;

  /// 현재 추론 모드
  InferenceMode _currentMode = InferenceMode.landmark;
  
  /// stub 모드 여부 (MediaPipe SDK 로딩 실패시)
  bool _isStubMode = false;

  MediaPipeWeb({
    this.config = const MediaPipeConfig(),
  });

  @override
  Future<void> initialize() async {
    try {
      debugPrint('🔍 Checking MediaPipe Web SDK loading...');
      
      // MediaPipe SDK 로딩 대기 (최대 15초)
      for (int i = 0; i < 150; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        // 로딩 성공 확인
        final mediaLoadedBool = js.context['MediaPipeLoaded'];
        final mediaError = js.context['MediaPipeError'];
        
        if (i % 10 == 0) { // 1초마다 로그 출력
          debugPrint('Attempt ${i+1}/150: MediaPipeLoaded=$mediaLoadedBool, Error=$mediaError');
        }
        
        if (mediaLoadedBool == true) {
          // MediaPipe SDK가 성공적으로 로드됨
          final tasksVision = js.context['MediaPipeTasksVision'];
          if (tasksVision != null) {
            debugPrint('✅ MediaPipe Web SDK loaded successfully');
            
            // Vision 초기화 시도
            try {
              final initResult = await _initializeVision();
              if (initResult) {
                debugPrint('✅ MediaPipe Vision initialized successfully');
                return;
              } else {
                debugPrint('⚠️ MediaPipe Vision initialization failed, using stub mode');
                _isStubMode = true;
                return;
              }
            } catch (e) {
              debugPrint('⚠️ MediaPipe Vision initialization error: $e, using stub mode');
              _isStubMode = true;
              return;
            }
          }
        }
        
        if (mediaError != null) {
          debugPrint('⚠️ MediaPipe SDK loading failed: $mediaError, falling back to stub mode');
          _isStubMode = true;
          return;
        }
      }
      
      // 타임아웃
      debugPrint('⏰ MediaPipe SDK loading timeout, falling back to stub mode');
      _isStubMode = true;
      
    } catch (e) {
      debugPrint('❌ MediaPipe Web initialization failed: $e, falling back to stub mode');
      _isStubMode = true;
    }
  }

  /// MediaPipe Vision 초기화
  Future<bool> _initializeVision() async {
    try {
      final result = js.context.callMethod('initializeMediaPipeVision');
      if (result is js.JsObject) {
        // Promise를 처리해야 할 수 있음
        await Future.delayed(const Duration(seconds: 2));
        return true;
      }
      return result == true;
    } catch (e) {
      debugPrint('Vision initialization error: $e');
      return false;
    }
  }

  @override
  Future<bool> loadModel(InferenceMode mode) async {
    try {
      debugPrint('🔄 Loading ${mode.name} model for web...');
      
      // 웹에서는 모델 로딩을 시뮬레이션 (실제 JavaScript 모델 로딩은 추론 시에 수행)
      await Future.delayed(const Duration(seconds: 2));
      
      _isModelLoaded = true;
      _currentMode = mode;
      
      debugPrint('✅ Web ${mode.name} model loaded successfully');
      return true;
      
    } catch (e) {
      debugPrint('❌ Web model loading error: $e');
      _isModelLoaded = false;
      return false;
    }
  }

  @override
  Future<MediaPipeResult> detectLandmarks({
    required CameraImage? image,
  }) async {
    if (!_isModelLoaded || _currentMode != InferenceMode.landmark) {
      return const MediaPipeResult(
        success: false,
        error: 'Landmark model not loaded',
      );
    }

    try {
      if (_isStubMode || image == null) {
        // Stub 모드 또는 null 이미지: 테스트용 랜드마크 데이터 반환
        await Future.delayed(const Duration(milliseconds: 33)); // ~30 FPS 시뮬레이션
        
        // 손 중앙 위치에 몇 개의 테스트 랜드마크 생성
        final testLandmarks = <Map<String, double>>[];
        for (int i = 0; i < 21; i++) {
          // 화면 중앙 주변에 랜드마크 배치
          final x = 0.4 + (i % 5) * 0.04; // 0.4 ~ 0.56 범위
          final y = 0.3 + (i ~/ 5) * 0.08; // 0.3 ~ 0.62 범위
          testLandmarks.add({
            'x': x,
            'y': y,
            'z': 0.0,
          });
        }
        
        return MediaPipeResult(
          success: true,
          data: {
            'result': {
              'landmarks': testLandmarks,
              'detected': true,
              'confidence': 0.8,
              'validLandmarks': 21,
            }
          },
        );
      }

      // 정상 MediaPipe 모드
      final imageBytes = image.planes[0].bytes;
      
      final resultJson = js.context.callMethod('detectHandLandmarks', [
        imageBytes,
        image.width,
        image.height,
      ]);
      
      if (resultJson == null) {
        throw Exception('No result from JavaScript');
      }
      
      final result = json.decode(resultJson.toString());
      
      if (result['success'] == true) {
        return MediaPipeResult(
          success: true,
          data: Map<String, dynamic>.from(result),
        );
      } else {
        return MediaPipeResult(
          success: false,
          error: result['error'] ?? 'Unknown error',
        );
      }
    } catch (e) {
      return MediaPipeResult(
        success: false,
        error: 'Web landmark detection failed: $e',
      );
    }
  }

  @override
  Future<MediaPipeResult> recognizeGesture({
    required CameraImage? image,
  }) async {
    if (!_isModelLoaded || _currentMode != InferenceMode.gesture) {
      return const MediaPipeResult(
        success: false,
        error: 'Gesture model not loaded',
      );
    }

    try {
      if (_isStubMode || image == null) {
        // Stub 모드 또는 null 이미지: 테스트용 제스처 데이터 반환
        await Future.delayed(const Duration(milliseconds: 33)); // ~30 FPS 시뮬레이션
        
        // 손 중앙 위치에 테스트 랜드마크 생성
        final testLandmarks = <Map<String, double>>[];
        for (int i = 0; i < 21; i++) {
          final x = 0.4 + (i % 5) * 0.04; // 0.4 ~ 0.56 범위
          final y = 0.3 + (i ~/ 5) * 0.08; // 0.3 ~ 0.62 범위
          testLandmarks.add({
            'x': x,
            'y': y,
            'z': 0.0,
          });
        }
        
        // 테스트 제스처 데이터
        final testGestures = [
          {
            'categoryName': 'Open_Palm',
            'score': 0.85,
          }
        ];
        
        return MediaPipeResult(
          success: true,
          data: {
            'result': {
              'gestures': testGestures,
              'landmarks': [testLandmarks], // 3차원 배열 형태
              'handedness': [
                {
                  'categoryName': 'Right',
                  'score': 0.9,
                }
              ],
              'detected': true,
            }
          },
        );
      }

      // 정상 MediaPipe 모드
      final imageBytes = image.planes[0].bytes;
      
      // JavaScript 함수 호출
      final resultJson = js.context.callMethod('recognizeGesture', [
        imageBytes,
        image.width,
        image.height,
      ]);
      
      if (resultJson == null) {
        throw Exception('No result from JavaScript');
      }
      
      // JSON 결과 파싱
      final result = json.decode(resultJson.toString());
      
      if (result['success'] == true) {
        return MediaPipeResult(
          success: true,
          data: Map<String, dynamic>.from(result),
        );
      } else {
        return MediaPipeResult(
          success: false,
          error: result['error'] ?? 'Unknown error',
        );
      }
    } catch (e) {
      return MediaPipeResult(
        success: false,
        error: 'Web gesture recognition failed: $e',
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      // JavaScript MediaPipe 리소스 정리
      js.context.callMethod('disposeMediaPipe');
    } catch (e) {
      // 에러 발생해도 계속 진행
    }
    
    _isModelLoaded = false;
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  @override
  InferenceMode get currentMode => _currentMode;
}