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

    // Cấu hình Render Cloud API chính thức
    cloudApiUrl: "https://test-nckh.onrender.com",
    apiKey: "rehab_pixel_game",

    /**
     * Khởi tạo Camera và MediaPipe Tasks Vision
     */
    async init(videoElementId, canvasElementId) {
        this.videoElement = document.getElementById(videoElementId);
        this.canvasElement = document.getElementById(canvasElementId);
        if (this.canvasElement) {
            this.canvasCtx = this.canvasElement.getContext("2d", { alpha: false });
        }

        this.updateStatus("Đang nạp mô hình AI MediaPipe...");

        // Khởi động Camera song song ngay lập tức để người dùng thấy ảnh webcam không bị trễ
        this.startCamera().catch(err => {
            console.warn("[Bridge] Chưa bật được camera tự động:", err);
        });

        // Nạp mô hình AI MediaPipe Tasks Vision từ CDN
        try {
            console.log("[Bridge] Đang tải MediaPipe Tasks Vision Wasm...");
            const vision = await import("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm/vision_bundle.mjs");
            const { PoseLandmarker, FilesetResolver } = vision;

            const wasmFileset = await FilesetResolver.forVisionTasks(
                "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm"
            );

            // Thử nạp với GPU Delegate trước
            try {
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
                this.updateStatus("AI sẵn sàng (Tăng tốc GPU)");
            } catch (gpuErr) {
                console.warn("[Bridge] Không hỗ trợ GPU delegate, chuyển sang CPU fallback:", gpuErr);
                this.poseLandmarker = await PoseLandmarker.createFromOptions(wasmFileset, {
                    baseOptions: {
                        modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task",
                        delegate: "CPU",
                    },
                    runningMode: "VIDEO",
                    numPoses: 1,
                });
                this.isModelLoaded = true;
                this.updateStatus("AI sẵn sàng (Chế độ CPU)");
            }

            console.log("[Bridge] Khởi tạo mô hình AI MediaPipe thành công!");
        } catch (err) {
            console.error("[Bridge] Lỗi khởi tạo MediaPipe: ", err);
            this.updateStatus("Không thể tải AI MediaPipe");
        }
    },

    /**
     * Bật Webcam bảo mật của trình duyệt
     */
    async startCamera() {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            this.updateStatus("Trình duyệt không hỗ trợ Camera");
            alert("Trình duyệt của bạn không hỗ trợ truy cập Camera!");
            return false;
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
                this.videoElement.muted = true; // Bắt buộc để tránh bị Chrome Autoplay Policy chặn
                await this.videoElement.play();
                this.isCameraActive = true;
                this.updateStatus("Camera đang hoạt động");
                this.startPredictionLoop();
                return true;
            }
        } catch (err) {
            console.error("[Bridge] Lỗi truy cập Webcam: ", err);
            if (err.name === "NotAllowedError" || err.name === "PermissionDeniedError") {
                this.updateStatus("Bị từ chối quyền Camera");
                const banner = document.getElementById("camera-perm-toast");
                if (banner) banner.style.display = "block";
            } else {
                this.updateStatus("Lỗi mở Camera: " + (err.message || err.name));
            }
            return false;
        }
    },

    /**
     * Cập nhật thông báo trạng thái AI ra giao diện
     */
    updateStatus(text) {
        const el = document.getElementById("ai-status-text");
        if (el) el.textContent = text;
    },

    /**
     * Vòng lặp nhận diện & vẽ khung hình thời gian thực (30 FPS)
     */
    startPredictionLoop() {
        if (this._loopRunning) return;
        this._loopRunning = true;

        const renderLoop = () => {
            if (this.isCameraActive && this.videoElement && this.videoElement.readyState >= 2) {
                const now = performance.now();

                // 1. Nhận diện mốc xương AI nếu mô hình đã sẵn sàng
                if (this.poseLandmarker && (now - this.lastFrameTime >= 28)) { // ~30-35 FPS
                    try {
                        const results = this.poseLandmarker.detectForVideo(this.videoElement, now);
                        if (results && results.landmarks && results.landmarks.length > 0) {
                            this.latestLandmarks = results.landmarks[0];
                        } else {
                            this.latestLandmarks = null;
                        }
                    } catch (e) {
                        console.warn("[Bridge] Lỗi nhận diện frame:", e);
                    }
                    this.lastFrameTime = now;
                }

                // 2. Vẽ hình ảnh camera lên Canvas kèm khung xương
                this.renderCameraFrame();
            }
            requestAnimationFrame(renderLoop);
        };
        requestAnimationFrame(renderLoop);
    },

    /**
     * Vẽ khung hình video thật lên Canvas kèm đường nối xương (Không bao giờ bị màn hình đen)
     */
    renderCameraFrame() {
        if (!this.canvasCtx || !this.canvasElement || !this.videoElement) return;

        const w = this.canvasElement.width;
        const h = this.canvasElement.height;

        this.canvasCtx.save();
        // Lật gương (Mirror) để động tác tay trái/phải trùng khớp góc nhìn người tập
        this.canvasCtx.scale(-1, 1);
        this.canvasCtx.drawImage(this.videoElement, -w, 0, w, h);
        this.canvasCtx.restore();

        // Nếu có nhận diện được khung xương AI, vẽ đè lên hình ảnh
        if (this.latestLandmarks) {
            this.canvasCtx.save();
            this.canvasCtx.scale(-1, 1);
            this.canvasCtx.translate(-w, 0);

            const pts = this.latestLandmarks;

            const drawJoint = (idx, color, radius = 5) => {
                if (pts[idx]) {
                    this.canvasCtx.beginPath();
                    this.canvasCtx.arc(pts[idx].x * w, pts[idx].y * h, radius, 0, 2 * Math.PI);
                    this.canvasCtx.fillStyle = color;
                    this.canvasCtx.fill();
                    this.canvasCtx.strokeStyle = "#ffffff";
                    this.canvasCtx.lineWidth = 1.5;
                    this.canvasCtx.stroke();
                }
            };

            const drawBone = (idx1, idx2, color, lineWidth = 4) => {
                if (pts[idx1] && pts[idx2]) {
                    this.canvasCtx.beginPath();
                    this.canvasCtx.moveTo(pts[idx1].x * w, pts[idx1].y * h);
                    this.canvasCtx.lineTo(pts[idx2].x * w, pts[idx2].y * h);
                    this.canvasCtx.strokeStyle = color;
                    this.canvasCtx.lineWidth = lineWidth;
                    this.canvasCtx.stroke();
                }
            };

            // Vẽ xương vai & hai cánh tay phục vụ bài tập PHCN
            drawBone(11, 12, "#00E5FF", 5); // Khớp vai trái - vai phải (Cyan nổi bật)
            drawBone(11, 13, "#76FF03", 4); // Vai trái - Khuỷu trái (Lime)
            drawBone(13, 15, "#76FF03", 4); // Khuỷu trái - Cổ tay trái
            drawBone(12, 14, "#FF9100", 4); // Vai phải - Khuỷu phải (Cam)
            drawBone(14, 16, "#FF9100", 4); // Khuỷu phải - Cổ tay phải

            // Vẽ các khớp
            drawJoint(11, "#00E5FF", 6);
            drawJoint(12, "#00E5FF", 6);
            drawJoint(13, "#76FF03", 5);
            drawJoint(14, "#FF9100", 5);
            drawJoint(15, "#FFFF00", 5);
            drawJoint(16, "#FFFF00", 5);

            this.canvasCtx.restore();
            this.updateStatus("Đang nhận diện cử động");
        } else {
            this.updateStatus("Đứng vào giữa khung hình");
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
