import 'package:flutter/foundation.dart';
import 'mediapipe_interface.dart';
import '../native/mediapipe_native.dart';
import '../web/mediapipe_web.dart';

/// 플랫폼별 MediaPipe 구현체 팩토리
class MediaPipeFactory {
  /// 현재 플랫폼에 맞는 MediaPipe 인스턴스 생성
  static MediaPipeInterface create({
    MediaPipeConfig config = const MediaPipeConfig(),
  }) {
    if (kIsWeb) {
      return MediaPipeWeb(config: config);
    } else {
      return MediaPipeNative(config: config);
    }
  }
}