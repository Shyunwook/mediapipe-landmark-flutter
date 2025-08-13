import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum InferenceMode { landmark, gesture }

class _CameraScreenState extends State<CameraScreen> {
  final channel = MethodChannel('channel_Mediapipe');

  late List<CameraDescription> cameras;
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  bool _isRecording = false;
  List<Offset> _landmarks = [];
  List<Offset> _previousLandmarks = []; // 이전 프레임 랜드마크 저장

  InferenceMode _inferenceMode = InferenceMode.landmark; // 기본값은 landmark

  // 제스처 정보 저장 변수들
  String _detectedGesture = '';
  double _gestureConfidence = 0.0;

  CameraController? _controller;

  // 성능 측정을 위한 변수들 (원형 버퍼 최적화)
  DateTime? _frameStartTime;
  final List<int> _processingTimes = List.filled(30, 0); // 고정 크기 원형 버퍼
  int _frameCount = 0;
  int _bufferIndex = 0;

  @override
  void initState() {
    super.initState();

    _asyncInitState();
  }

  Future<void> _asyncInitState() async {
    cameras = await availableCameras();
    await _initializeCamera();
    await _loadModel();

    setState(() {});
  }

  Future<void> _initializeCamera() async {
    if (cameras.isNotEmpty) {
      _controller = CameraController(
        cameras[1],
        ResolutionPreset.low,
        enableAudio: false,
      );

      await _controller!.initialize();
    }
  }

  Future<void> _loadModel() async {
    try {
      String methodName = _inferenceMode == InferenceMode.landmark
          ? 'load_landmark'
          : 'load_gesture';
      await channel.invokeMethod(methodName);
      setState(() {
        _isModelLoaded = true;
      });
    } catch (e) {
      debugPrint("Error loading model : $e");
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
                          CameraPreview(_controller!),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: LandmarkPainter(_landmarks),
                              size: Size.infinite,
                            ),
                          ),
                        ],
                      ),

                      /// 전처리 이미지 확인 창
                      // if (_preprocessedImageData != null)
                      //   Align(
                      //     alignment: Alignment.topRight,
                      //     child: Container(
                      //       width: 100,
                      //       height: 100 * _controller!.value.aspectRatio,

                      //       child: Image.memory(_preprocessedImageData!),
                      //     ),
                      //   ),
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
                          // 모드 변경 시 제스처 정보 초기화
                          _detectedGesture = '';
                          _gestureConfidence = 0.0;
                        });
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

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;

    // 프레임 처리 시작 시간 기록
    _frameStartTime = DateTime.now();
    _frameCount++;

    setState(() {
      _isProcessing = true;
    });

    try {
      final imageBytes = _cameraImageToBytes(image);

      // 선택된 모드에 따라 다른 method 호출
      String methodName = _inferenceMode == InferenceMode.landmark
          ? 'inference_landmark'
          : 'inference_gesture';

      final result = await channel.invokeMethod(methodName, {
        'imageData': imageBytes,
        'width': image.width,
        'height': image.height,
      });

      // 선택된 모드에 따라 다른 파싱 로직 적용
      if (_inferenceMode == InferenceMode.landmark) {
        _processLandmarkResult(result);
      } else {
        _processGestureResult(result);
      }

      // 처리 완료 시간 기록 및 성능 로깅
      if (_frameStartTime != null) {
        final processingTime = DateTime.now()
            .difference(_frameStartTime!)
            .inMilliseconds;

        // 원형 버퍼에 저장 (O(1) 연산)
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

  Uint8List _cameraImageToBytes(CameraImage image) {
    // [STEP 2] YUV420에서 첫 번째 plane(Y)만 사용하여 성능 최적화
    // Y plane은 휘도 정보만 포함하지만 hand landmark 검출에 충분함
    return image.planes[0].bytes;
  }

  void _startImageStream() {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.startImageStream((CameraImage image) {
        if (!_isProcessing && _isModelLoaded && _isRecording) {
          _processImage(image);
        }
      });
    }
  }

  void _stopImageStream() {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.stopImageStream();
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _startImageStream();
    } else {
      _stopImageStream();
    }
  }

  // Landmark 결과 파싱 (기존 방식)
  void _processLandmarkResult(Map result) {
    if ((result['result']['landmarks'] as List).isNotEmpty) {
      // BuildContext 안전성 체크
      if (!mounted) return;
      // iOS에서 정규화된 좌표(0.0-1.0)를 직접 화면 크기에 곱함

      final newLandmarks = (result['result']['landmarks'] as List)
          .map((mark) => Offset(mark['x'] * 393, mark['y'] * 480))
          .toList();

      // 좌표 스무딩 적용 (in-place 연산으로 메모리 할당 최적화)
      if (_previousLandmarks.isNotEmpty &&
          _previousLandmarks.length == newLandmarks.length) {
        // 기존 _landmarks 배열을 재사용하여 in-place로 계산
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
    } else {
      _landmarks.clear();
      _previousLandmarks.clear();
    }
  }

  // Gesture 결과 파싱 (새로운 방식)
  void _processGestureResult(Map result) {
    if ((result['result']['landmarks'] as List).isNotEmpty) {
      // BuildContext 안전성 체크
      if (!mounted) return;

      // gesture recognition에서 landmarks는 3차원 배열 [hand][landmark][coordinate]
      final landmarksArray = result['result']['landmarks'] as List;
      if (landmarksArray.isNotEmpty) {
        // 첫 번째 손의 랜드마크만 사용
        final firstHandLandmarks = landmarksArray[0] as List;
        // iOS에서 정규화된 좌표(0.0-1.0)를 직접 화면 크기에 곱함 (landmark와 동일한 방식)
        final newLandmarks = firstHandLandmarks
            .map((mark) => Offset(mark['x'] * 393, mark['y'] * 480))
            .toList();

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
        if (result['result']['gestures'] != null) {
          final gestures = result['result']['gestures'] as List;
          if (gestures.isNotEmpty) {
            setState(() {
              _detectedGesture = gestures[0]['categoryName'] ?? '';
              _gestureConfidence = (gestures[0]['score'] ?? 0.0).toDouble();
            });
            debugPrint('감지된 제스처: $_detectedGesture (신뢰도: $_gestureConfidence)');
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
      _landmarks.clear();
      _previousLandmarks.clear();
      // 랜드마크가 없을 때도 제스처 정보 초기화
      setState(() {
        _detectedGesture = '';
        _gestureConfidence = 0.0;
      });
    }
  }
}

// 최적화된 랜드마크 렌더링 (성능 개선)
class LandmarkPainter extends CustomPainter {
  final List<Offset> landmarks;
  static Paint? _cachedPaint;
  static Paint? _cachedShadowPaint;

  LandmarkPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    // Paint 객체 캐싱으로 객체 생성 오버헤드 제거
    _cachedPaint ??= Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..isAntiAlias = false; // 안티앨리어싱 비활성화로 성능 향상

    _cachedShadowPaint ??= Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    // 배치 렌더링 최적화
    for (final landmark in landmarks) {
      // 그림자 효과
      canvas.drawCircle(landmark, 6.5, _cachedShadowPaint!);
      // 메인 원
      canvas.drawCircle(landmark, 5.5, _cachedPaint!);
    }
  }

  @override
  bool shouldRepaint(LandmarkPainter oldDelegate) {
    // 항상 다시 그리기 (디버깅용)
    return true;
  }
}
