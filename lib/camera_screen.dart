import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'common/mediapipe_interface.dart';
import 'common/mediapipe_factory.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}


class _CameraScreenState extends State<CameraScreen> {
  /// 플랫폼별 MediaPipe 구현체
  late final MediaPipeInterface _mediaPipe;

  // === 카메라 관련 변수들 ===
  late List<CameraDescription> cameras;
  CameraController? _controller;

  // === 앱 상태 관리 변수들 ===
  bool _isModelLoaded = false; // MediaPipe 모델 로딩 완료 여부
  bool _isProcessing = false; // 현재 프레임 처리 중 여부
  bool _isRecording = false; // 촬영(추론) 진행 중 여부
  InferenceMode _inferenceMode = InferenceMode.landmark; // 현재 추론 모드

  // === 랜드마크 데이터 관리 ===
  List<Offset> _landmarks = []; // 현재 프레임의 랜드마크 좌표들
  List<Offset> _previousLandmarks = []; // 이전 프레임 랜드마크 (스무딩용)

  // === 화면 비율 계산 (동적으로 계산됨) ===
  double _screenWidth = 0.0; // 디바이스 화면 너비
  double _cameraRatio = 1.0; // 카메라 이미지 비율 (height/width)

  // === 제스처 인식 결과 저장 ===
  String _detectedGesture = ''; // 감지된 제스처 이름
  double _gestureConfidence = 0.0; // 제스처 인식 신뢰도 (0.0~1.0)

  // === 성능 측정 (30프레임 기준 원형 버퍼) ===
  DateTime? _frameStartTime;
  final List<int> _processingTimes = List.filled(30, 0);
  int _frameCount = 0;
  int _bufferIndex = 0;
  
  // === 웹 전용 변수 ===
  Timer? _webImageTimer;
  bool _isWebCapturing = false;

  @override
  void initState() {
    super.initState();
    _mediaPipe = MediaPipeFactory.create();
    _asyncInitState();
  }

  /// 앱 초기화: 카메라 설정 → MediaPipe 초기화 → 모델 로딩 순서로 진행
  Future<void> _asyncInitState() async {
    cameras = await availableCameras();
    await _initializeCamera();
    await _mediaPipe.initialize();
    await _loadModel();
    setState(() {}); // UI 업데이트
  }

  /// 카메라 초기화 (전면 카메라 우선, 저해상도 설정)
  Future<void> _initializeCamera() async {
    if (cameras.isNotEmpty) {
      // 전면 카메라 찾기 (웹에서는 첫 번째가 전면일 수 있음)
      CameraDescription selectedCamera;
      
      if (kIsWeb) {
        // 웹: 첫 번째 카메라 사용 (보통 전면 카메라)
        selectedCamera = cameras.first;
      } else {
        // 모바일: 전면 카메라 찾기, 없으면 첫 번째 카메라
        try {
          selectedCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first,
          );
        } catch (e) {
          selectedCamera = cameras.first;
        }
      }
      
      _controller = CameraController(
        selectedCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.low, // 웹은 medium 권장
        enableAudio: false, // 오디오 비활성화
      );
      await _controller!.initialize();
    }
  }

  /// 현재 추론 모드에 맞는 MediaPipe 모델 로딩
  Future<void> _loadModel() async {
    try {
      final success = await _mediaPipe.loadModel(_inferenceMode);
      setState(() {
        _isModelLoaded = success;
      });
      
      if (!success) {
        debugPrint("Failed to load ${_inferenceMode.name} model");
      }
    } catch (e) {
      debugPrint("Error loading model: $e");
      setState(() {
        _isModelLoaded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hand Landmark Detection'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          Expanded(
            child: _controller == null
                ? Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      Stack(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return CameraPreview(_controller!);
                            },
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: LandmarkPainter(_landmarks),
                              size: Size.infinite,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          // 제스처 정보 표시 영역 (Gesture 모드일 때만 표시)
          if (_inferenceMode == InferenceMode.gesture && _isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gesture, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _detectedGesture.isEmpty
                        ? '제스처를 감지 중...'
                        : '감지된 제스처: $_detectedGesture (${(_gestureConfidence * 100).toStringAsFixed(1)}%)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 모드 선택 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('추론 모드: ', style: TextStyle(fontSize: 16)),
                    SegmentedButton<InferenceMode>(
                      segments: const [
                        ButtonSegment<InferenceMode>(
                          value: InferenceMode.landmark,
                          label: Text('Landmark'),
                        ),
                        ButtonSegment<InferenceMode>(
                          value: InferenceMode.gesture,
                          label: Text('Gesture'),
                        ),
                      ],
                      selected: {_inferenceMode},
                      onSelectionChanged: (Set<InferenceMode> selected) {
                        if (_isRecording) {
                          // 녹화 중일 때는 모드 변경 불가
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('녹화 중에는 모드를 변경할 수 없습니다.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _inferenceMode = selected.first;
                          _isModelLoaded = false;
                        });
                        // 모드 변경 시 모든 랜드마크와 제스처 정보 초기화
                        _clearAllLandmarks();
                        _loadModel();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 기존 컨트롤 버튼들
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isModelLoaded ? Icons.check_circle : Icons.error,
                          color: _isModelLoaded ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isModelLoaded ? 'Model Ready' : 'Loading...',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _toggleRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording
                            ? Colors.red
                            : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                          const SizedBox(width: 8),
                          Text(
                            _isRecording ? '중단' : '촬영 시작',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 카메라 프레임을 MediaPipe로 전송하여 추론 수행
  /// 성능 최적화: 중복 처리 방지, 비동기 처리, 성능 측정
  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return; // 중복 처리 방지

    // 성능 측정 시작
    _frameStartTime = DateTime.now();
    _frameCount++;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. 화면 비율 계산 (동적으로 디바이스에 맞춤)
      _screenWidth = MediaQuery.of(context).size.width;

      // 2. 플랫폼별 카메라 비율 계산
      if (kIsWeb) {
        // Web: 카메라 원본 비율 사용
        _cameraRatio = image.height.toDouble() / image.width.toDouble();
      } else if (Platform.isAndroid) {
        // Android: 이미지 회전 후 비율 (320/240 = 1.33)
        _cameraRatio = image.width.toDouble() / image.height.toDouble();
      } else {
        // iOS: 원래 비율 (240/320 = 0.75)
        _cameraRatio = image.height.toDouble() / image.width.toDouble();
      }

      // 3. MediaPipe 추론 실행
      MediaPipeResult result;
      if (_inferenceMode == InferenceMode.landmark) {
        result = await _mediaPipe.detectLandmarks(image: image);
      } else {
        result = await _mediaPipe.recognizeGesture(image: image);
      }

      // 4. 결과 파싱 및 UI 업데이트
      if (result.success) {
        if (_inferenceMode == InferenceMode.landmark) {
          _processLandmarkResult(result);
        } else {
          _processGestureResult(result);
        }
      } else {
        debugPrint("MediaPipe inference failed: ${result.error}");
      }

      // 5. 성능 측정 (30프레임 평균)
      if (_frameStartTime != null) {
        final processingTime = DateTime.now()
            .difference(_frameStartTime!)
            .inMilliseconds;

        _processingTimes[_bufferIndex] = processingTime;
        _bufferIndex = (_bufferIndex + 1) % 30;

        if (_frameCount % 30 == 0) {
          final avgTime = _processingTimes.reduce((a, b) => a + b) / 30;
          final fps = 1000 / avgTime;
          debugPrint(
            "🔥 성능 측정 (최근 30프레임): 평균 처리시간=${avgTime.toStringAsFixed(1)}ms, FPS=${fps.toStringAsFixed(1)}",
          );
        }
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }


  /// 카메라 스트림 시작: 실시간 프레임 처리
  void _startImageStream() {
    if (_controller != null && _controller!.value.isInitialized) {
      if (kIsWeb) {
        // 웹: 이미지 스트림 미지원, 타이머로 스냅샷 촬영
        _webImageTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
          // 중복 캡처 방지 및 기본 조건 확인
          if (!_isProcessing && _isModelLoaded && _isRecording && !_isWebCapturing) {
            _isWebCapturing = true;
            try {
              final XFile imageFile = await _controller!.takePicture();
              await _processWebImage(imageFile);
            } catch (e) {
              debugPrint('Web image capture error: $e');
            } finally {
              _isWebCapturing = false;
            }
          }
        });
      } else {
        // 모바일: 기존 이미지 스트림 사용
        _controller!.startImageStream((CameraImage image) {
          if (!_isProcessing && _isModelLoaded && _isRecording) {
            _processImage(image);
          }
        });
      }
    }
  }

  /// 카메라 스트림 중지
  void _stopImageStream() {
    if (kIsWeb) {
      // 웹: 타이머 중지 및 캡처 상태 초기화
      _webImageTimer?.cancel();
      _webImageTimer = null;
      _isWebCapturing = false;
    } else {
      // 모바일: 이미지 스트림 중지
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.stopImageStream();
      }
    }
  }

  /// 촬영 시작/중단 토글 버튼 핸들러
  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _startImageStream(); // 촬영 시작
    } else {
      _stopImageStream(); // 촬영 중단
      _clearAllLandmarks(); // 화면에서 랜드마크 제거
    }
  }

  /// 모든 랜드마크와 제스처 정보 초기화
  /// 사용 시점: 촬영 중단, 모드 변경, 랜드마크 미감지시
  void _clearAllLandmarks() {
    _landmarks.clear();
    _previousLandmarks.clear();
    setState(() {
      _detectedGesture = '';
      _gestureConfidence = 0.0;
    });
  }

  /// 손 랜드마크 감지 결과 처리
  /// MediaPipe 정규화 좌표(0~1)를 화면 픽셀 좌표로 변환
  void _processLandmarkResult(MediaPipeResult result) {
    // 촬영 중이 아니면 처리하지 않음 (비동기 처리 타이밍 이슈 방지)
    if (!_isRecording) return;

    if (result.landmarks.isNotEmpty) {
      // 위젯이 dispose된 경우 처리 중단
      if (!mounted) return;

      final landmarks = result.landmarks;

      // 1. 정규화 좌표를 화면 좌표로 변환
      final newLandmarks = landmarks.map((mark) {
        double x = mark['x'] ?? 0.0; // 0.0 ~ 1.0
        double y = mark['y'] ?? 0.0; // 0.0 ~ 1.0

        // 2. 플랫폼별 좌표 보정
        if (kIsWeb || (!kIsWeb && Platform.isAndroid)) {
          x = 1 - x; // 웹과 Android: 좌우 반전 보정 (미러 모드)
        }

        // 3. 화면 크기에 맞춰 스케일링
        return Offset(
          x * _screenWidth, // x 좌표
          y * _screenWidth * _cameraRatio, // y 좌표 (비율 적용)
        );
      }).toList();

      // 4. 좌표 스무딩 (떨림 방지)
      if (_previousLandmarks.isNotEmpty &&
          _previousLandmarks.length == newLandmarks.length) {
        // 이전 프레임과 현재 프레임을 가중평균하여 부드러운 움직임 생성
        if (_landmarks.length != newLandmarks.length) {
          _landmarks = List.filled(newLandmarks.length, Offset.zero);
        }
        for (int i = 0; i < newLandmarks.length; i++) {
          _landmarks[i] = Offset(
            newLandmarks[i].dx * 0.7 +
                _previousLandmarks[i].dx * 0.3, // 70% 현재 + 30% 이전
            newLandmarks[i].dy * 0.7 + _previousLandmarks[i].dy * 0.3,
          );
        }
      } else {
        // 첫 프레임이거나 랜드마크 개수가 변경된 경우 그대로 사용
        _landmarks = newLandmarks;
      }

      // 5. 다음 프레임을 위해 현재 랜드마크 저장
      _previousLandmarks = List.from(_landmarks);
    } else {
      // 랜드마크가 감지되지 않은 경우 모든 정보 초기화
      _clearAllLandmarks();
    }
  }

  /// 제스처 인식 결과 처리
  /// 랜드마크 + 제스처 정보를 동시에 처리하여 UI 업데이트
  void _processGestureResult(MediaPipeResult result) {
    // 촬영 중이 아니면 처리하지 않음 (비동기 처리 타이밍 이슈 방지)
    if (!_isRecording) return;

    final gestureData = result.gestureData;
    if ((gestureData['landmarks'] as List? ?? []).isNotEmpty) {
      // BuildContext 안전성 체크
      if (!mounted) return;

      // gesture recognition에서 landmarks는 3차원 배열 [hand][landmark][coordinate]
      final landmarksArray = gestureData['landmarks'] as List;
      if (landmarksArray.isNotEmpty) {
        // 첫 번째 손의 랜드마크만 사용
        final firstHandLandmarks = landmarksArray[0] as List;
        // MediaPipe 정규화 좌표를 CameraPreview 크기에 맞게 변환
        final newLandmarks = firstHandLandmarks.map((mark) {
          double x = mark['x'] ?? 0.0;
          double y = mark['y'] ?? 0.0;

          // 플랫폼별 좌표 보정
          if (kIsWeb || (!kIsWeb && Platform.isAndroid)) {
            x = 1 - x; // 웹과 Android: 좌우 반전 보정 (미러 모드)
          }

          return Offset(
            x * _screenWidth, // x * 화면너비
            y * _screenWidth * _cameraRatio, // y * 화면너비 * 카메라비율
          );
        }).toList();

        // 좌표 스무딩 적용
        if (_previousLandmarks.isNotEmpty &&
            _previousLandmarks.length == newLandmarks.length) {
          if (_landmarks.length != newLandmarks.length) {
            _landmarks = List.filled(newLandmarks.length, Offset.zero);
          }
          for (int i = 0; i < newLandmarks.length; i++) {
            _landmarks[i] = Offset(
              newLandmarks[i].dx * 0.7 + _previousLandmarks[i].dx * 0.3,
              newLandmarks[i].dy * 0.7 + _previousLandmarks[i].dy * 0.3,
            );
          }
        } else {
          _landmarks = newLandmarks;
        }

        _previousLandmarks = List.from(_landmarks);

        // Gesture 정보 UI 업데이트
        if (gestureData['gestures'] != null) {
          final gestures = gestureData['gestures'] as List;
          if (gestures.isNotEmpty) {
            setState(() {
              _detectedGesture = gestures[0]['categoryName'] ?? '';
              _gestureConfidence = (gestures[0]['score'] ?? 0.0).toDouble();
            });
          }
        } else {
          // 제스처가 감지되지 않은 경우
          setState(() {
            _detectedGesture = '';
            _gestureConfidence = 0.0;
          });
        }
      }
    } else {
      _clearAllLandmarks();
    }
  }

  /// 웹용 이미지 처리 함수 (XFile 기반)
  Future<void> _processWebImage(XFile imageFile) async {
    if (_isProcessing) return;

    _frameStartTime = DateTime.now();
    _frameCount++;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 화면 비율 계산
      _screenWidth = MediaQuery.of(context).size.width;
      _cameraRatio = 0.75; // 웹 카메라 기본 비율

      // MediaPipe 추론 실행 (웹에서는 stub 모드로 시뮬레이션)
      MediaPipeResult result;
      if (_inferenceMode == InferenceMode.landmark) {
        // 웹에서는 null 이미지로 호출 (MediaPipeWeb에서 stub 모드 처리)
        result = await _mediaPipe.detectLandmarks(image: _createDummyCameraImage());
      } else {
        result = await _mediaPipe.recognizeGesture(image: _createDummyCameraImage());
      }

      // 결과 처리
      if (result.success) {
        if (_inferenceMode == InferenceMode.landmark) {
          _processLandmarkResult(result);
        } else {
          _processGestureResult(result);
        }
      } else {
        debugPrint("MediaPipe inference failed: ${result.error}");
      }

      // 성능 측정
      if (_frameStartTime != null) {
        final processingTime = DateTime.now()
            .difference(_frameStartTime!)
            .inMilliseconds;

        _processingTimes[_bufferIndex] = processingTime;
        _bufferIndex = (_bufferIndex + 1) % 30;

        if (_frameCount % 30 == 0) {
          final avgTime = _processingTimes.reduce((a, b) => a + b) / 30;
          final fps = 1000 / avgTime;
          debugPrint(
            "🌐 웹 성능 (최근 30프레임): 평균 처리시간=${avgTime.toStringAsFixed(1)}ms, FPS=${fps.toStringAsFixed(1)}",
          );
        }
      }
    } catch (e) {
      debugPrint("Web image processing error: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 웹에서 사용할 더미 CameraImage 생성
  /// 주의: 이것은 실제 CameraImage가 아닌 웹에서의 테스트용 null 처리입니다.
  CameraImage? _createDummyCameraImage() {
    // 웹에서는 실제 CameraImage를 생성할 수 없으므로 null을 반환
    // 대신 JavaScript에서 직접 비디오 프레임을 캡처합니다.
    return null;
  }

  @override
  void dispose() {
    _webImageTimer?.cancel(); // 웹 타이머 정리
    _isWebCapturing = false;  // 캡처 상태 초기화
    _mediaPipe.dispose();
    _controller?.dispose();
    super.dispose();
  }
}

/// 랜드마크 시각화 CustomPainter (성능 최적화 적용)
/// 손의 21개 랜드마크를 빨간 원으로 화면에 그림
class LandmarkPainter extends CustomPainter {
  final List<Offset> landmarks;

  // Paint 객체 정적 캐싱 (메모리 최적화)
  static Paint? _cachedPaint; // 메인 랜드마크용
  static Paint? _cachedShadowPaint; // 그림자 효과용

  LandmarkPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    // Paint 객체 지연 초기화 및 캐싱
    _cachedPaint ??= Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..isAntiAlias = false; // 성능 향상을 위한 안티앨리어싱 비활성화

    _cachedShadowPaint ??= Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    // 모든 랜드마크를 순서대로 그리기
    for (final landmark in landmarks) {
      // 1. 흰색 그림자 (가시성 향상)
      canvas.drawCircle(landmark, 6.5, _cachedShadowPaint!);
      // 2. 빨간색 메인 원
      canvas.drawCircle(landmark, 5.5, _cachedPaint!);
    }
  }

  @override
  bool shouldRepaint(LandmarkPainter oldDelegate) {
    // 랜드마크가 변경될 때마다 다시 그리기
    return true;
  }
}
