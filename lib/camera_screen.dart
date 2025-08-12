import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final channel = MethodChannel('channel_Mediapipe');

  late List<CameraDescription> cameras;
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  bool _isRecording = false;
  List<Offset> _landmarks = [];

  CameraController? _controller;

  Uint8List? _preprocessedImageData;

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
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
    }
  }

  Future<void> _loadModel() async {
    try {
      await channel.invokeMethod('load');
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
                          ..._landmarks.map(
                            (mark) => LandMarks(position: mark),
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
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
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
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
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
          ),
        ],
      ),
    );
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final imageBytes = _cameraImageToBytes(image);

      final result = await channel.invokeMethod('inference', {
        'imageData': imageBytes,
        'width': image.width,
        'height': image.height,
      });

      if ((result['result']['landmarks'] as List).isNotEmpty) {
        _landmarks = (result['result']['landmarks'] as List)
            .map((mark) => Offset(mark['x'] * 393 / 224, mark['y'] * 524 / 224))
            .toList();
      } else {
        _landmarks.clear();
      }
      setState(() {});

      setState(() {
        _preprocessedImageData = result['processedImageData'];
      });
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Uint8List _cameraImageToBytes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
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
}

class LandMarks extends StatelessWidget {
  final Offset position;

  const LandMarks({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.white, blurRadius: 2, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}
