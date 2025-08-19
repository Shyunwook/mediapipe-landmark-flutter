import 'dart:js' as js;
import 'dart:convert';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../common/mediapipe_interface.dart';

/// MediaPipe 동작 모드
enum MediaPipeMode {
  loading,        // 초기 로딩 중
  fullMediaPipe,  // 완전한 MediaPipe 동작
  manualLoading,  // Vision 초기화는 실패했지만 SDK 로드됨, 수동 모델 로딩
  stubMode,       // Mock 데이터 모드
}

/// 웹 플랫폼용 MediaPipe 구현체
class MediaPipeWeb implements MediaPipeInterface {
  /// MediaPipe 설정
  final MediaPipeConfig config;

  /// 현재 모델 로딩 상태
  bool _isModelLoaded = false;

  /// 현재 추론 모드
  InferenceMode _currentMode = InferenceMode.landmark;
  
  /// MediaPipe 모드 상태
  MediaPipeMode _currentMediaPipeMode = MediaPipeMode.loading;
  
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
            
            // Vision 초기화 시도 (재시도 로직 포함)
            try {
              bool initSuccess = false;
              int retryCount = 0;
              const maxRetries = 2;
              
              while (!initSuccess && retryCount <= maxRetries) {
                if (retryCount > 0) {
                  debugPrint('🔄 Retrying MediaPipe Vision initialization (attempt ${retryCount + 1}/${maxRetries + 1})...');
                  await Future.delayed(Duration(seconds: 2 * retryCount)); // 백오프 지연
                }
                
                initSuccess = await _initializeVision();
                
                if (initSuccess) {
                  debugPrint('✅ MediaPipe Vision initialized successfully - FULL MEDIAPIPE MODE');
                  _currentMediaPipeMode = MediaPipeMode.fullMediaPipe;
                  _isStubMode = false;
                  return;
                } else {
                  retryCount++;
                  if (retryCount <= maxRetries) {
                    debugPrint('⚠️ Vision initialization failed, will retry in ${2 * retryCount} seconds...');
                  }
                }
              }
              
              // 모든 재시도 실패 - fallback 시도
              debugPrint('❌ MediaPipe Vision initialization failed after ${maxRetries + 1} attempts');
              debugPrint('🔄 Attempting fallback initialization method...');
              
              final fallbackSuccess = await _initializeVisionFallback();
              if (fallbackSuccess) {
                debugPrint('✅ Fallback initialization successful - FULL MEDIAPIPE MODE');
                _currentMediaPipeMode = MediaPipeMode.fullMediaPipe;
                _isStubMode = false;
                return;
              }
              
              debugPrint('❌ Fallback initialization also failed');
              debugPrint('🔧 Switching to MANUAL LOADING MODE (SDK available, manual model loading)');
              _currentMediaPipeMode = MediaPipeMode.manualLoading;
              _isStubMode = false;
              return;
              
            } catch (e) {
              debugPrint('❌ MediaPipe Vision initialization error: $e');
              debugPrint('🔧 Switching to MANUAL LOADING MODE (SDK available, manual model loading)');
              _currentMediaPipeMode = MediaPipeMode.manualLoading;
              _isStubMode = false;
              return;
            }
          }
        }
        
        if (mediaError != null) {
          debugPrint('⚠️ MediaPipe SDK loading failed: $mediaError');
          debugPrint('🔄 Switching to STUB MODE (mock data)');
          _currentMediaPipeMode = MediaPipeMode.stubMode;
          _isStubMode = true;
          return;
        }
      }
      
      // 타임아웃
      debugPrint('⏰ MediaPipe SDK loading timeout');
      debugPrint('🔄 Switching to STUB MODE (mock data)');
      _currentMediaPipeMode = MediaPipeMode.stubMode;
      _isStubMode = true;
      
    } catch (e) {
      debugPrint('❌ MediaPipe Web initialization failed: $e');
      debugPrint('🔄 Switching to STUB MODE (mock data)');
      _currentMediaPipeMode = MediaPipeMode.stubMode;
      _isStubMode = true;
    }
  }

  /// MediaPipe Vision 초기화
  Future<bool> _initializeVision() async {
    try {
      // JavaScript 함수 존재 여부 확인
      if (!js.context.hasProperty('initializeMediaPipeVisionSync')) {
        debugPrint('❌ JavaScript initialization function not found');
        return false;
      }
      
      // 상태 초기화 및 초기화 시작
      js.context['visionInitialized'] = false;
      js.context['visionInitializationFailed'] = false;
      js.context['vision'] = null;
      
      final initResult = js.context.callMethod('initializeMediaPipeVisionSync');
      if (initResult != 'started') {
        debugPrint('❌ Failed to start vision initialization');
        return false;
      }
      
      // 초기화 완료 대기 (최대 20초)
      for (int i = 0; i < 200; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        final visionInitialized = js.context['visionInitialized'];
        final visionFailed = js.context['visionInitializationFailed'];
        final visionReady = js.context['vision'] != null;
        final mediaError = js.context['MediaPipeError'];
        
        // 주기적 상태 로그 (5초마다)
        if (i % 50 == 0) {
          debugPrint('Vision status: initialized=$visionInitialized, failed=$visionFailed');
        }
        
        // 성공 확인
        if (visionInitialized == true && visionReady) {
          debugPrint('✅ MediaPipe Vision initialized successfully');
          return true;
        }
        
        // 실패 확인
        if (visionFailed == true || (mediaError != null && mediaError != false)) {
          debugPrint('❌ MediaPipe Vision initialization failed');
          return false;
        }
      }
      
      debugPrint('⏰ Vision initialization timeout');
      return false;
    } catch (e) {
      debugPrint('❌ Vision initialization error: $e');
      return false;
    }
  }

  /// Fallback Vision 초기화 메서드
  Future<bool> _initializeVisionFallback() async {
    try {
      debugPrint('🔄 Starting fallback MediaPipe Vision initialization...');
      
      // Fallback 함수 존재 여부 확인
      final hasFallbackFunction = js.context.hasProperty('initializeMediaPipeVisionFallback');
      if (!hasFallbackFunction) {
        debugPrint('❌ Fallback function not available');
        return false;
      }
      
      // 상태 초기화
      js.context['visionInitialized'] = false;
      js.context['visionInitializationFailed'] = false;
      
      // Fallback 함수 호출 (async)
      final fallbackResult = await js.context.callMethod('initializeMediaPipeVisionFallback');
      debugPrint('🎯 Fallback initialization result: $fallbackResult');
      
      // 결과 확인을 위한 짧은 대기
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        final visionInitialized = js.context['visionInitialized'];
        final visionFailed = js.context['visionInitializationFailed'];
        final visionReady = js.context['vision'] != null;
        
        if (visionInitialized == true && visionReady) {
          debugPrint('✅ Fallback MediaPipe Vision initialized and ready');
          return true;
        }
        
        if (visionFailed == true) {
          debugPrint('❌ Fallback MediaPipe Vision initialization failed');
          return false;
        }
      }
      
      debugPrint('⏰ Fallback initialization timeout');
      return false;
      
    } catch (e) {
      debugPrint('❌ Fallback initialization error: $e');
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
      debugPrint('🔍 detectLandmarks called - mode: $_currentMediaPipeMode, image: ${image != null ? 'available' : 'null'}');
      
      if (_currentMediaPipeMode == MediaPipeMode.stubMode) {
        debugPrint('📍 Using STUB MODE for landmark detection');
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

      // MediaPipe 모드 (Full 또는 Manual Loading)
      if (_currentMediaPipeMode == MediaPipeMode.fullMediaPipe) {
        debugPrint('🚀 Using FULL MEDIAPIPE MODE for landmark detection');
      } else {
        debugPrint('🔧 Using MANUAL LOADING MODE for landmark detection');
      }
      
      if (image == null) {
        debugPrint('🎥 Camera image is null, capturing real video frame...');
        
        try {
          // 웹 카메라에서 실시간 프레임 캡처
          final frameData = js.context.callMethod('captureVideoFrame');
          
          if (frameData == null) {
            // 프레임 캡처 실패 시 빈 결과 반환
            return const MediaPipeResult(
              success: true,
              data: {
                'result': {
                  'landmarks': [],
                  'detected': false,
                  'confidence': 0.0,
                  'validLandmarks': 0,
                }
              },
            );
          }
          
          // 캡처된 프레임 정보 추출
          final width = frameData['width'];
          final height = frameData['height'];
          
          // RGBA를 grayscale로 변환
          final grayscaleData = js.context.callMethod('convertToGrayscale', [frameData]);
          
          // MediaPipe 처리
          js.context.callMethod('detectHandLandmarks', [
            grayscaleData,
            width,
            height,
          ]);
          
        } catch (e) {
          debugPrint('❌ Error capturing video frame: $e');
          // 에러 시 빈 결과 반환
          return const MediaPipeResult(
            success: true,
            data: {
              'result': {
                'landmarks': [],
                'detected': false,
                'confidence': 0.0,
                'validLandmarks': 0,
              }
            },
          );
        }
      }
      
      // image가 있는 경우에만 기존 로직 실행
      dynamic callResult = 'pending';
      if (image != null) {
        final imageBytes = image.planes[0].bytes;
        
        // JavaScript 함수 호출 (동기식 wrapper 사용)
        callResult = js.context.callMethod('detectHandLandmarks', [
          imageBytes,
          image.width,
          image.height,
        ]);
      }
      
      if (callResult.toString() == 'pending') {
        // 비동기 처리 완료를 기다림 (최대 5초)
        String? resultJson;
        for (int i = 0; i < 50; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          
          final result = js.context['lastDetectionResult'];
          if (result != null) {
            resultJson = result.toString();
            // 결과를 읽었으므로 전역 변수 초기화
            js.context['lastDetectionResult'] = null;
            break;
          }
        }
        
        if (resultJson == null) {
          throw Exception('Detection timeout - no result from JavaScript');
        }
        
        final result = json.decode(resultJson);
        
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
      } else {
        // 즉시 결과가 반환된 경우 (오류 등)
        final result = json.decode(callResult.toString());
        
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
      if (_currentMediaPipeMode == MediaPipeMode.stubMode) {
        debugPrint('📍 Using STUB MODE for gesture recognition');
        // Stub 모드: 테스트용 제스처 데이터 반환
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

      // MediaPipe 모드 (Full 또는 Manual Loading)
      if (_currentMediaPipeMode == MediaPipeMode.fullMediaPipe) {
        debugPrint('🚀 Using FULL MEDIAPIPE MODE for gesture recognition');
      } else {
        debugPrint('🔧 Using MANUAL LOADING MODE for gesture recognition');
      }
      
      if (image == null) {
        debugPrint('🎥 Camera image is null, capturing real video frame for gesture...');
        
        try {
          // 웹 카메라에서 실시간 프레임 캡처
          final frameData = js.context.callMethod('captureVideoFrame');
          
          if (frameData != null) {
            final width = frameData['width'];
            final height = frameData['height'];
            
            // RGBA를 grayscale로 변환
            final grayscaleData = js.context.callMethod('convertToGrayscale', [frameData]);
            
            // MediaPipe 처리
            js.context.callMethod('recognizeGesture', [
              grayscaleData,
              width,
              height,
            ]);
          }
        } catch (e) {
          debugPrint('❌ Error capturing video frame for gesture: $e');
        }
      }
      
      // image가 있는 경우에만 기존 로직 실행
      dynamic callResult = 'pending'; // 기본값 설정
      if (image != null) {
        final imageBytes = image.planes[0].bytes;
        
        // JavaScript 함수 호출 (동기식 wrapper 사용)
        callResult = js.context.callMethod('recognizeGesture', [
          imageBytes,
          image.width,
          image.height,
        ]);
      }
      
      if (callResult.toString() == 'pending') {
        // 비동기 처리 완료를 기다림 (최대 5초)
        String? resultJson;
        for (int i = 0; i < 50; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          
          final result = js.context['lastGestureResult'];
          if (result != null) {
            resultJson = result.toString();
            // 결과를 읽었으므로 전역 변수 초기화
            js.context['lastGestureResult'] = null;
            break;
          }
        }
        
        if (resultJson == null) {
          throw Exception('Gesture recognition timeout - no result from JavaScript');
        }
        
        final result = json.decode(resultJson);
        
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
      } else {
        // 즉시 결과가 반환된 경우 (오류 등)
        final result = json.decode(callResult.toString());
        
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