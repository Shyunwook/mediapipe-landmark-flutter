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

/**
 * MediaPipe Vision 라이브러리 초기화
 */
async function initializeMediaPipeVision() {
  try {
    console.log('🚀 Initializing MediaPipe Vision...');
    
    // MediaPipe Vision FilesetResolver 초기화
    const visionWasmUrl = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm";
    vision = await window.MediaPipeTasksVision.FilesetResolver.forVisionTasks(visionWasmUrl);
    
    console.log('🔧 Vision FilesetResolver created with WASM URL:', visionWasmUrl);
    
    console.log('✅ MediaPipe Vision initialized successfully');
    return true;
  } catch (error) {
    console.error('❌ Failed to initialize MediaPipe Vision:', error);
    return false;
  }
}

/**
 * 손 랜드마크 감지 모델 로딩
 */
async function loadHandLandmarker() {
  try {
    console.log('🔄 Loading HandLandmarker model...');
    
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
    
    console.log('✅ HandLandmarker model loaded successfully');
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
    console.log('🔄 Loading GestureRecognizer model...');
    
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
    
    console.log('✅ GestureRecognizer model loaded successfully');
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
function detectHandLandmarks(imageData, width, height) {
  try {
    if (!handLandmarker) {
      throw new Error('HandLandmarker not loaded');
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
function recognizeGesture(imageData, width, height) {
  try {
    if (!gestureRecognizer) {
      throw new Error('GestureRecognizer not loaded');
    }
    
    // 이미지 데이터를 Canvas로 변환
    const canvas = createImageFromBytes(new Uint8Array(imageData), width, height);
    
    // MediaPipe 추론 실행
    const timestamp = Date.now();
    const results = gestureRecognizer.recognize(canvas, timestamp);
    
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

// Flutter에서 접근 가능하도록 전역 함수로 노출
window.initializeMediaPipeVision = initializeMediaPipeVision;
window.loadHandLandmarker = loadHandLandmarker;
window.loadGestureRecognizer = loadGestureRecognizer;
window.detectHandLandmarks = detectHandLandmarks;
window.recognizeGesture = recognizeGesture;
window.disposeMediaPipe = disposeMediaPipe;

// 콜백 방식 함수들도 노출
window.initializeMediaPipeVisionWithCallback = initializeMediaPipeVisionWithCallback;
window.loadHandLandmarkerWithCallback = loadHandLandmarkerWithCallback;
window.loadGestureRecognizerWithCallback = loadGestureRecognizerWithCallback;