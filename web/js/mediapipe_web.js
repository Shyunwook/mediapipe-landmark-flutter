/**
 * MediaPipe Web SDK를 위한 JavaScript 래퍼 함수들
 * Flutter Web에서 dart:js를 통해 호출됨
 */

// MediaPipe 인스턴스 저장
let handLandmarker = null;
let gestureRecognizer = null;
let vision = null;

// 재사용 가능한 Canvas 엘리먼트
let reusableCanvas = null;

// 웹 카메라 관련
let videoElement = null;
let captureCanvas = null;
let lastFrameTime = 0;
const FRAME_INTERVAL = 150; // 150ms 간격으로 프레임 캡처

/**
 * MediaPipe Vision 라이브러리 초기화
 */
async function initializeMediaPipeVision() {
  try {
    console.log('🚀 Initializing MediaPipe Vision...');
    
    // MediaPipe TasksVision이 로드되었는지 확인
    if (!window.MediaPipeTasksVision || !window.MediaPipeTasksVision.FilesetResolver) {
      throw new Error('MediaPipeTasksVision not available');
    }
    
    const fileset = window.MediaPipeTasksVision.FilesetResolver;
    
    // Mock 구현인지 확인
    try {
      const testResult = await fileset.forVisionTasks('test');
      if (testResult && testResult.mockFileset) {
        vision = testResult;
        window.vision = vision;
        window.visionInitialized = true;
        return true;
      }
    } catch (e) {
      // 실제 MediaPipe인 경우 WASM 로딩 진행
    }
    
    // 실제 MediaPipe 구현인 경우 여러 WASM CDN URL 시도
    const wasmUrls = [
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm",
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.11/wasm", 
      "https://unpkg.com/@mediapipe/tasks-vision@0.10.14/wasm",
      "https://cdn.skypack.dev/@mediapipe/tasks-vision@0.10.14/wasm"
    ];
    
    let lastError = null;
    
    for (const wasmUrl of wasmUrls) {
      try {
        vision = await window.MediaPipeTasksVision.FilesetResolver.forVisionTasks(wasmUrl);
        window.vision = vision;
        window.visionInitialized = true;
        console.log(`✅ Vision initialized with: ${wasmUrl}`);
        return true;
      } catch (error) {
        lastError = error;
        continue;
      }
    }
    
    // 모든 실제 WASM URL이 실패한 경우 mock으로 fallback
    console.warn('⚠️ All real WASM URLs failed, falling back to mock');
    vision = await window.MediaPipeTasksVision.FilesetResolver.forVisionTasks('mock://wasm');
    window.vision = vision;
    window.visionInitialized = true;
    return true;
  } catch (error) {
    console.error('❌ Failed to initialize MediaPipe Vision:', error);
    window.visionInitializationFailed = true;
    return false;
  }
}

/**
 * 동기식 Vision 초기화 호출 (Flutter와의 호환성을 위해)
 */
function initializeMediaPipeVisionSync() {
  // 전역 상태 초기화
  window.visionInitialized = false;
  window.visionInitializationFailed = false;
  
  // 비동기 초기화 시작
  initializeMediaPipeVision().then(() => {
    // 초기화 완료
  }).catch(error => {
    console.error('❌ Vision initialization failed:', error);
    window.visionInitializationFailed = true;
  });
  
  return 'started';
}

/**
 * 대체 Vision 초기화 (더 단순한 접근법)
 */
async function initializeMediaPipeVisionFallback() {
  try {
    console.log('🔄 Attempting fallback MediaPipe Vision initialization...');
    
    // MediaPipe TasksVision이 로드되었는지 확인
    if (!window.MediaPipeTasksVision || !window.MediaPipeTasksVision.FilesetResolver) {
      throw new Error('MediaPipeTasksVision not available for fallback');
    }
    
    // 단순한 초기화 시도 (CDN URL 없이)
    try {
      console.log('🔧 Trying direct vision initialization...');
      vision = window.MediaPipeTasksVision.FilesetResolver;
      window.vision = vision;
      window.visionInitialized = true;
      console.log('✅ Fallback vision initialized (direct FilesetResolver)');
      return true;
    } catch (e) {
      console.warn('⚠️ Direct initialization failed:', e.message);
    }
    
    // Mock fallback
    console.log('🔧 Using mock fallback...');
    vision = await window.MediaPipeTasksVision.FilesetResolver.forVisionTasks('mock://fallback');
    window.vision = vision;
    window.visionInitialized = true;
    console.log('✅ Mock fallback vision initialized');
    return true;
    
  } catch (error) {
    console.error('❌ Fallback vision initialization failed:', error);
    window.visionInitializationFailed = true;
    return false;
  }
}

/**
 * 손 랜드마크 감지 모델 로딩
 */
async function loadHandLandmarker() {
  try {
    if (!vision) {
      throw new Error('MediaPipe Vision not initialized');
    }
    
    handLandmarker = await window.MediaPipeTasksVision.HandLandmarker.createFromOptions(
      vision, 
      {
        baseOptions: {
          modelAssetPath: "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
        },
        numHands: 2,
        runningMode: "VIDEO",
        minHandDetectionConfidence: 0.5,
        minHandPresenceConfidence: 0.5,
        minTrackingConfidence: 0.5
      }
    );
    
    return true;
  } catch (error) {
    console.error('❌ Failed to load HandLandmarker:', error);
    return false;
  }
}

/**
 * 제스처 인식 모델 로딩
 */
async function loadGestureRecognizer() {
  try {
    if (!vision) {
      throw new Error('MediaPipe Vision not initialized');
    }
    
    gestureRecognizer = await window.MediaPipeTasksVision.GestureRecognizer.createFromOptions(
      vision,
      {
        baseOptions: {
          modelAssetPath: "https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task"
        },
        numHands: 2,
        runningMode: "VIDEO",
        minHandDetectionConfidence: 0.5,
        minHandPresenceConfidence: 0.5,
        minTrackingConfidence: 0.5
      }
    );
    
    return true;
  } catch (error) {
    console.error('❌ Failed to load GestureRecognizer:', error);
    return false;
  }
}

/**
 * 재사용 가능한 Canvas 엘리먼트 생성/반환
 */
function getReusableCanvas(width, height) {
  if (!reusableCanvas) {
    reusableCanvas = document.createElement('canvas');
  }
  
  if (reusableCanvas.width !== width || reusableCanvas.height !== height) {
    reusableCanvas.width = width;
    reusableCanvas.height = height;
  }
  
  return reusableCanvas;
}

/**
 * Uint8Array 이미지 데이터를 Canvas로 변환
 * Flutter에서 전송된 YUV420 Y plane 데이터를 처리
 */
function createImageFromBytes(imageData, width, height) {
  const canvas = getReusableCanvas(width, height);
  const ctx = canvas.getContext('2d');
  
  // ImageData 객체 생성 (RGBA 형태로 변환)
  const imgData = ctx.createImageData(width, height);
  const data = imgData.data;
  
  // Y plane (grayscale) 데이터를 RGBA로 변환
  for (let i = 0; i < imageData.length; i++) {
    const y = imageData[i];
    const pixelIndex = i * 4;
    
    // RGBA 설정 (R=G=B=Y, A=255)
    data[pixelIndex] = y;     // R
    data[pixelIndex + 1] = y; // G
    data[pixelIndex + 2] = y; // B
    data[pixelIndex + 3] = 255; // A
  }
  
  // Canvas에 이미지 데이터 그리기
  ctx.putImageData(imgData, 0, 0);
  
  return canvas;
}

/**
 * 손 랜드마크 감지 수행
 */
async function detectHandLandmarksAsync(imageData, width, height) {
  try {
    // HandLandmarker가 로드되지 않았다면 자동으로 로드
    if (!handLandmarker) {
      const loaded = await loadHandLandmarker();
      if (!loaded) {
        throw new Error('Failed to auto-load HandLandmarker');
      }
    }
    
    // 이미지 데이터를 Canvas로 변환
    const canvas = createImageFromBytes(new Uint8Array(imageData), width, height);
    
    // MediaPipe 추론 실행
    const timestamp = Date.now();
    const results = handLandmarker.detectForVideo(canvas, timestamp);
    
    // 결과를 Flutter 호환 형식으로 변환
    const landmarks = [];
    if (results.landmarks && results.landmarks.length > 0) {
      // 첫 번째 손의 랜드마크만 사용
      const firstHandLandmarks = results.landmarks[0];
      for (const landmark of firstHandLandmarks) {
        landmarks.push({
          x: landmark.x,
          y: landmark.y,
          z: landmark.z || 0.0
        });
      }
    }
    
    // 좌/우손 분류 신뢰도
    let handednessConfidence = 0.0;
    if (results.handedness && results.handedness.length > 0 && results.handedness[0].length > 0) {
      handednessConfidence = results.handedness[0][0].score;
    }
    
    return JSON.stringify({
      success: true,
      result: {
        landmarks: landmarks,
        confidence: handednessConfidence,
        detected: landmarks.length > 0,
        validLandmarks: landmarks.length,
        presenceConfidence: handednessConfidence
      }
    });
    
  } catch (error) {
    console.error('Hand landmark detection error:', error);
    return JSON.stringify({
      success: false,
      error: error.message
    });
  }
}

/**
 * 제스처 인식 수행
 */
async function recognizeGestureAsync(imageData, width, height) {
  try {
    // GestureRecognizer가 로드되지 않았다면 자동으로 로드
    if (!gestureRecognizer) {
      console.log('🔄 Auto-loading GestureRecognizer...');
      const loaded = await loadGestureRecognizer();
      if (!loaded) {
        throw new Error('Failed to auto-load GestureRecognizer');
      }
    }
    
    // 이미지 데이터를 Canvas로 변환
    const canvas = createImageFromBytes(new Uint8Array(imageData), width, height);
    
    // MediaPipe 추론 실행
    const timestamp = Date.now();
    const results = gestureRecognizer.recognizeForVideo(canvas, timestamp);
    
    // 제스처 결과 파싱
    const gestures = [];
    if (results.gestures && results.gestures.length > 0) {
      for (const handGestures of results.gestures) {
        for (const gesture of handGestures) {
          gestures.push({
            categoryName: gesture.categoryName,
            score: gesture.score
          });
        }
      }
    }
    
    // 좌/우손 분류 결과
    const handedness = [];
    if (results.handedness && results.handedness.length > 0) {
      for (const handHandedness of results.handedness) {
        for (const hand of handHandedness) {
          handedness.push({
            categoryName: hand.categoryName,
            score: hand.score
          });
        }
      }
    }
    
    // 랜드마크 결과 (3차원 배열 형태)
    const landmarks = [];
    if (results.landmarks && results.landmarks.length > 0) {
      for (const handLandmarks of results.landmarks) {
        const handLandmarkData = [];
        for (const landmark of handLandmarks) {
          handLandmarkData.push({
            x: landmark.x,
            y: landmark.y,
            z: landmark.z || 0.0
          });
        }
        landmarks.push(handLandmarkData);
      }
    }
    
    // 월드 랜드마크 결과
    const worldLandmarks = [];
    if (results.worldLandmarks && results.worldLandmarks.length > 0) {
      for (const handWorldLandmarks of results.worldLandmarks) {
        const handWorldLandmarkData = [];
        for (const worldLandmark of handWorldLandmarks) {
          handWorldLandmarkData.push({
            x: worldLandmark.x,
            y: worldLandmark.y,
            z: worldLandmark.z || 0.0
          });
        }
        worldLandmarks.push(handWorldLandmarkData);
      }
    }
    
    return JSON.stringify({
      success: true,
      result: {
        gestures: gestures,
        handedness: handedness,
        landmarks: landmarks,
        worldLandmarks: worldLandmarks,
        detected: gestures.length > 0 || landmarks.length > 0
      }
    });
    
  } catch (error) {
    console.error('Gesture recognition error:', error);
    return JSON.stringify({
      success: false,
      error: error.message
    });
  }
}

/**
 * 웹 카메라 비디오 엘리먼트 찾기 및 설정
 */
function setupWebCamera() {
  try {
    // Flutter 카메라 플러그인이 생성한 video 엘리먼트 찾기
    const videos = document.querySelectorAll('video');
    
    for (const video of videos) {
      if (video.srcObject && video.readyState >= 2) {
        videoElement = video;
        break;
      }
    }
    
    if (!videoElement) {
      return false;
    }
    
    // 캡처용 Canvas 생성
    if (!captureCanvas) {
      captureCanvas = document.createElement('canvas');
    }
    
    return true;
  } catch (error) {
    console.error('❌ Failed to setup web camera:', error);
    return false;
  }
}

/**
 * 웹 카메라에서 현재 프레임 캡처
 */
function captureVideoFrame() {
  try {
    // 프레임 캡처 throttling
    const currentTime = Date.now();
    if (currentTime - lastFrameTime < FRAME_INTERVAL) {
      return null; // 너무 빈번한 캡처 방지
    }
    lastFrameTime = currentTime;
    
    if (!videoElement || !captureCanvas) {
      if (!setupWebCamera()) {
        return null;
      }
    }
    
    // 비디오가 준비되지 않았으면 null 반환
    if (videoElement.readyState < 2) {
      return null;
    }
    
    // Canvas 크기를 비디오 크기에 맞춤
    const width = videoElement.videoWidth || videoElement.clientWidth;
    const height = videoElement.videoHeight || videoElement.clientHeight;
    
    if (width === 0 || height === 0) {
      return null;
    }
    
    captureCanvas.width = width;
    captureCanvas.height = height;
    
    // 비디오 프레임을 Canvas에 그리기
    const ctx = captureCanvas.getContext('2d');
    ctx.drawImage(videoElement, 0, 0, width, height);
    
    // ImageData 추출
    const imageData = ctx.getImageData(0, 0, width, height);
    // 로그 출력 최적화 (매 10번째마다만 출력)
    if (Math.random() < 0.1) {
      console.log(`📸 Captured frame: ${width}x${height}, data length: ${imageData.data.length}`);
    }
    
    return {
      width: width,
      height: height,
      data: imageData.data
    };
  } catch (error) {
    console.error('❌ Failed to capture video frame:', error);
    return null;
  }
}

/**
 * ImageData를 MediaPipe용 grayscale로 변환
 */
function convertToGrayscale(imageData) {
  const rgbaData = imageData.data;
  const grayscaleData = new Uint8Array(imageData.width * imageData.height);
  
  for (let i = 0; i < rgbaData.length; i += 4) {
    // RGB to grayscale using luminance formula
    const gray = Math.round(
      0.299 * rgbaData[i] +     // R
      0.587 * rgbaData[i + 1] + // G
      0.114 * rgbaData[i + 2]   // B
    );
    grayscaleData[i / 4] = gray;
  }
  
  return grayscaleData;
}

/**
 * 리소스 정리
 */
function disposeMediaPipe() {
  if (handLandmarker) {
    handLandmarker.close();
    handLandmarker = null;
  }
  
  if (gestureRecognizer) {
    gestureRecognizer.close();
    gestureRecognizer = null;
  }
  
  // 웹 카메라 리소스 정리
  videoElement = null;
  captureCanvas = null;
  
  console.log('🧹 MediaPipe resources cleaned up');
}

/**
 * 콜백 방식 래퍼 함수들 (Flutter dart:js와의 호환성을 위해)
 */

function initializeMediaPipeVisionWithCallback(successCallback, errorCallback) {
  initializeMediaPipeVision()
    .then(result => successCallback(result))
    .catch(error => errorCallback(error.message || error.toString()));
}

function loadHandLandmarkerWithCallback(successCallback, errorCallback) {
  loadHandLandmarker()
    .then(result => successCallback(result))
    .catch(error => errorCallback(error.message || error.toString()));
}

function loadGestureRecognizerWithCallback(successCallback, errorCallback) {
  loadGestureRecognizer()
    .then(result => successCallback(result))
    .catch(error => errorCallback(error.message || error.toString()));
}

/**
 * Flutter에서 호출할 수 있는 동기식 wrapper 함수들
 */
function detectHandLandmarksSync(imageData, width, height) {
  // 비동기 함수를 직접 호출하여 결과를 저장
  detectHandLandmarksAsync(imageData, width, height).then(result => {
    window.lastDetectionResult = result;
  }).catch(error => {
    window.lastDetectionResult = JSON.stringify({
      success: false,
      error: error.message
    });
  });
  
  // 즉시 'pending' 반환
  return 'pending';
}

function recognizeGestureSync(imageData, width, height) {
  // 비동기 함수를 직접 호출하여 결과를 저장
  recognizeGestureAsync(imageData, width, height).then(result => {
    window.lastGestureResult = result;
  }).catch(error => {
    window.lastGestureResult = JSON.stringify({
      success: false,
      error: error.message
    });
  });
  
  // 즉시 'pending' 반환
  return 'pending';
}

// Flutter에서 접근 가능하도록 전역 함수로 노출
window.initializeMediaPipeVision = initializeMediaPipeVision;
window.initializeMediaPipeVisionSync = initializeMediaPipeVisionSync;
window.initializeMediaPipeVisionFallback = initializeMediaPipeVisionFallback;
window.loadHandLandmarker = loadHandLandmarker;
window.loadGestureRecognizer = loadGestureRecognizer;
window.detectHandLandmarks = detectHandLandmarksSync;
window.recognizeGesture = recognizeGestureSync;
window.disposeMediaPipe = disposeMediaPipe;

// 웹 카메라 관련 함수들
window.setupWebCamera = setupWebCamera;
window.captureVideoFrame = captureVideoFrame;
window.convertToGrayscale = convertToGrayscale;

// 콜백 방식 함수들도 노출
window.initializeMediaPipeVisionWithCallback = initializeMediaPipeVisionWithCallback;
window.loadHandLandmarkerWithCallback = loadHandLandmarkerWithCallback;
window.loadGestureRecognizerWithCallback = loadGestureRecognizerWithCallback;