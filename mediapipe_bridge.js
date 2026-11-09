/**
 * Cầu nối MediaPipe Tasks Vision JS & Camera HTML5 cho Web Game Phục Hồi Chức Năng 2D.
 * Chạy xử lý trực tiếp trên trình duyệt máy khách (Client-side Edge Computing).
 * Đạt tốc độ 30-35 FPS với độ trễ < 15ms mà không cần gửi video lên máy chủ.
 */

window.GamePHCN_Bridge = {
    isCameraActive: false,
    isModelLoaded: false,
    latestLandmarks: null,
    currentExerciseId: "scapular_retraction",
    lastFrameTime: 0,
    fps: 0,
    videoElement: null,
    canvasElement: null,
    canvasCtx: null,
    poseLandmarker: null,

    // Cấu hình Render Cloud API mặc định
    cloudApiUrl: "https://gamephcn-api.onrender.com",
    apiKey: "rehab_pixel_game",

    /**
     * Khởi tạo Camera và MediaPipe Tasks Vision
     */
    async init(videoElementId, canvasElementId) {
        this.videoElement = document.getElementById(videoElementId);
        this.canvasElement = document.getElementById(canvasElementId);
        if (this.canvasElement) {
            this.canvasCtx = this.canvasElement.getContext("2d");
        }

        console.log("[Bridge] Đang khởi động MediaPipe Vision Tasks API...");
        try {
            // Nạp MediaPipe Tasks Vision từ CDN
            const vision = await import("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm/vision_bundle.mjs");
            const { PoseLandmarker, FilesetResolver } = vision;

            const wasmFileset = await FilesetResolver.forVisionTasks(
                "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm"
            );

            this.poseLandmarker = await PoseLandmarker.createFromOptions(wasmFileset, {
                baseOptions: {
                    modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task",
                    delegate: "GPU",
                },
                runningMode: "VIDEO",
                numPoses: 1,
                minPoseDetectionConfidence: 0.5,
                minPosePresenceConfidence: 0.5,
                minTrackingConfidence: 0.5,
            });

            this.isModelLoaded = true;
            console.log("[Bridge] Khởi tạo mô hình AI MediaPipe thành công (Chế độ tăng tốc GPU)!");
            await this.startCamera();
        } catch (err) {
            console.error("[Bridge] Lỗi khởi tạo MediaPipe: ", err);
            // Fallback chế độ CPU nếu thiết bị không hỗ trợ GPU delegate
            try {
                const vision = await import("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm/vision_bundle.mjs");
                const { PoseLandmarker, FilesetResolver } = vision;
                const wasmFileset = await FilesetResolver.forVisionTasks(
                    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm"
                );
                this.poseLandmarker = await PoseLandmarker.createFromOptions(wasmFileset, {
                    baseOptions: {
                        modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task",
                        delegate: "CPU",
                    },
                    runningMode: "VIDEO",
                    numPoses: 1,
                });
                this.isModelLoaded = true;
                console.log("[Bridge] Khởi tạo mô hình AI MediaPipe thành công (Chế độ CPU Fallback)!");
                await this.startCamera();
            } catch (fallbackErr) {
                console.error("[Bridge] Fallback thất bại: ", fallbackErr);
            }
        }
    },

    /**
     * Bật Webcam bảo mật của trình duyệt
     */
    async startCamera() {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            alert("Trình duyệt của bạn không hỗ trợ truy cập Camera!");
            return;
        }

        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    width: { ideal: 640 },
                    height: { ideal: 480 },
                    facingMode: "user",
                },
                audio: false,
            });

            if (this.videoElement) {
                this.videoElement.srcObject = stream;
                this.videoElement.addEventListener("loadeddata", () => {
                    this.isCameraActive = true;
                    console.log("[Bridge] Camera Webcam đã hoạt động!");
                    this.startPredictionLoop();
                });
            }
        } catch (err) {
            console.error("[Bridge] Không thể truy cập Webcam: ", err);
        }
    },

    /**
     * Vòng lặp nhận diện thời gian thực (30 FPS)
     */
    startPredictionLoop() {
        const renderLoop = () => {
            if (this.isCameraActive && this.poseLandmarker && this.videoElement.readyState >= 2) {
                const now = performance.now();
                if (now - this.lastFrameTime >= 30) { // ~30 FPS
                    const results = this.poseLandmarker.detectForVideo(this.videoElement, now);
                    this.processResults(results);
                    this.lastFrameTime = now;
                }
            }
            requestAnimationFrame(renderLoop);
        };
        requestAnimationFrame(renderLoop);
    },

    /**
     * Xử lý kết quả tọa độ khung xương & vẽ Canvas Preview
     */
    processResults(results) {
        if (!results || !results.landmarks || results.landmarks.length === 0) {
            this.latestLandmarks = null;
            return;
        }

        this.latestLandmarks = results.landmarks[0]; // 33 điểm mốc 3D

        // Vẽ khung xương lên Canvas nếu có
        if (this.canvasCtx && this.canvasElement) {
            this.canvasCtx.clearRect(0, 0, this.canvasElement.width, this.canvasElement.height);
            // Lật gương hình vẽ
            this.canvasCtx.save();
            this.canvasCtx.scale(-1, 1);
            this.canvasCtx.translate(-this.canvasElement.width, 0);

            // Vẽ các điểm khớp quan trọng (Vai 11, 12; Khuỷu 13, 14; Cổ tay 15, 16)
            const pts = this.latestLandmarks;
            const w = this.canvasElement.width;
            const h = this.canvasElement.height;

            const drawJoint = (idx, color) => {
                if (pts[idx]) {
                    this.canvasCtx.beginPath();
                    this.canvasCtx.arc(pts[idx].x * w, pts[idx].y * h, 5, 0, 2 * Math.PI);
                    this.canvasCtx.fillStyle = color;
                    this.canvasCtx.fill();
                }
            };

            const drawBone = (idx1, idx2, color) => {
                if (pts[idx1] && pts[idx2]) {
                    this.canvasCtx.beginPath();
                    this.canvasCtx.moveTo(pts[idx1].x * w, pts[idx1].y * h);
                    this.canvasCtx.lineTo(pts[idx2].x * w, pts[idx2].y * h);
                    this.canvasCtx.strokeStyle = color;
                    this.canvasCtx.lineWidth = 3;
                    this.canvasCtx.stroke();
                }
            };

            // Vẽ cánh tay
            drawBone(11, 12, "#00E5FF"); // Vai trái - Vai phải
            drawBone(11, 13, "#76FF03"); // Vai trái - Khuỷu trái
            drawBone(13, 15, "#76FF03"); // Khuỷu trái - Cổ tay trái
            drawBone(12, 14, "#FF9100"); // Vai phải - Khuỷu phải
            drawBone(14, 16, "#FF9100"); // Khuỷu phải - Cổ tay phải

            drawJoint(11, "#00E5FF");
            drawJoint(12, "#00E5FF");
            drawJoint(13, "#76FF03");
            drawJoint(14, "#FF9100");
            drawJoint(15, "#FFFF00");
            drawJoint(16, "#FFFF00");

            this.canvasCtx.restore();
        }
    },

    /**
     * Hàm được gọi từ Godot GDScript (qua JavaScriptBridge) để lấy góc đo mới nhất
     */
    getBridgePoseData() {
        if (!this.latestLandmarks) {
            return JSON.stringify({ tracking: false });
        }

        const pts = this.latestLandmarks;
        return JSON.stringify({
            tracking: true,
            landmarks_count: pts.length,
            left_shoulder: { x: pts[11].x, y: pts[11].y, z: pts[11].z },
            right_shoulder: { x: pts[12].x, y: pts[12].y, z: pts[12].z },
            left_elbow: { x: pts[13].x, y: pts[13].y, z: pts[13].z },
            right_elbow: { x: pts[14].x, y: pts[14].y, z: pts[14].z },
            left_wrist: { x: pts[15].x, y: pts[15].y, z: pts[15].z },
            right_wrist: { x: pts[16].x, y: pts[16].y, z: pts[16].z },
        });
    }
};
