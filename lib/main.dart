import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mediapipe_channeling_test/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Enable hardware acceleration.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SchedulerBinding.instance.scheduleWarmUpFrame();
  });

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CameraScreen());
  }
}
