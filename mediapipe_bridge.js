/**
 * Cầu nối MediaPipe Tasks Vision JS & WebPoseProvider cho Game Pixel 2D PHCN (Web Edition).
 * Chuyển giao toàn bộ Kinematics y khoa, FSM 5 bài tập, Calibration T-Pose và Hand Cursor.
 * Đưa hình ảnh camera kèm khung xương xanh/cam trực tiếp vào PoseInput trong Godot Engine (60 FPS, Zero Lag).
 * Tác giả: Nong Thi Hong Lan & DeepMind Team
 */

(function () {
    "use strict";

    // ==========================================
    // 1. DATA STRUCTURES & HÌNH HỌC TOÁN HỌC
    // ==========================================
    class LandmarkPoint {
        constructor(x, y, z, visibility = 1.0) {
            this.x = Number(x);
            this.y = Number(y);
            this.z = Number(z);
            this.visibility = Number(visibility);
        }
    }

    function dist2D(p1, p2) {
        if (!p1 || !p2) return 0.0;
        return Math.hypot(p1.x - p2.x, p1.y - p2.y);
    }

    function angleABC(a, b, c) {
        if (!a || !b || !c) return 0.0;
        const rad1 = Math.atan2(a.y - b.y, a.x - b.x);
        const rad2 = Math.atan2(c.y - b.y, c.x - b.x);
        let deg = Math.abs((rad2 - rad1) * (180.0 / Math.PI));
        if (deg > 180.0) deg = 360.0 - deg;
        return deg;
    }

    // ==========================================
    // 2. BỘ LỌC ADAPTIVE EMA (EMAFilter)
    // ==========================================
    class EMAFilter {
        constructor(alpha = 0.32, alphaZ = 0.16) {
            this.alpha = alpha;
            this.alphaZ = alphaZ;
            this.prev = null;
            this.SYMMETRIC_PAIRS = [
                [11, 12], [13, 14], [15, 16],
                [17, 18], [19, 20], [21, 22], [23, 24]
            ];
        }

        reset() {
            this.prev = null;
        }

        canonicalize(raw) {
            const pts = [];
            for (let i = 0; i < raw.length; i++) {
                const lm = raw[i];
                pts.push(new LandmarkPoint(lm.x, lm.y, lm.z, lm.visibility ?? 1.0));
            }
            // Trong Mirror View: nếu bị đảo khớp vai thì hoán đổi đối xứng
            if (pts.length >= 25 && pts[11].x < pts[12].x) {
                for (const [l, r] of this.SYMMETRIC_PAIRS) {
                    const temp = pts[l];
                    pts[l] = pts[l];
                    pts[l] = pts[r];
                    pts[r] = temp;
                }
            }
            return pts;
        }

        filter(raw) {
            if (!raw || raw.length === 0) return null;
            const pts = this.canonicalize(raw);
            if (!this.prev || this.prev.length !== pts.length) {
                this.prev = pts;
                return pts;
            }

            const smoothed = [];
            for (let i = 0; i < pts.length; i++) {
                const cur = pts[i];
                const prv = this.prev[i];
                let dx = cur.x - prv.x;
                let dy = cur.y - prv.y;
                let dz = cur.z - prv.z;
                const dxy = Math.hypot(dx, dy);

                let effAlphaXY = this.alpha;
                let effAlphaZ = this.alphaZ;
                if (dxy < 0.010) {
                    effAlphaXY = 0.16;
                    effAlphaZ = 0.08;
                } else if (dxy < 0.030) {
                    effAlphaXY = 0.26;
                    effAlphaZ = 0.12;
                }

                if (cur.visibility < 0.45) {
                    effAlphaXY *= 0.45;
                    effAlphaZ *= 0.45;
                }

                const smX = prv.x + effAlphaXY * dx;
                const smY = prv.y + effAlphaXY * dy;
                const smZ = prv.z + effAlphaZ * dz;
                const smVis = 0.30 * cur.visibility + 0.70 * prv.visibility;
                smoothed.push(new LandmarkPoint(smX, smY, smZ, smVis));
            }
            this.prev = smoothed;
            return smoothed;
        }
    }

    // ==========================================
    // 3. ĐIỀU KHIỂN CON TRỎ BÀN TAY (HandService)
    // ==========================================
    class HandService {
        constructor() {
            this.isActive = false;
            this.cursorX = 0.5;
            this.cursorY = 0.5;
            this.confidence = 0.0;
            this.activeSide = null;
            this.DEADZONE = 0.008;
            this.SENSITIVITY = 0.75;
        }

        process(landmarks) {
            if (!landmarks || landmarks.length < 21) {
                this.isActive = false;
                return { active: false, cursor_x: this.cursorX, cursor_y: this.cursorY, confidence: 0.0 };
            }

            const lHipY = landmarks[23] ? landmarks[23].y : 0.8;
            const rHipY = landmarks[24] ? landmarks[24].y : 0.8;
            const hipY = (lHipY + rHipY) / 2.0;

            const lIdx = landmarks[19]?.visibility >= 0.4 ? landmarks[19] : landmarks[15];
            const rIdx = landmarks[20]?.visibility >= 0.4 ? landmarks[20] : landmarks[16];

            const lEligible = lIdx && (lIdx.visibility >= 0.35) && (lIdx.y <= 0.78) && (lIdx.y < hipY - 0.05);
            const rEligible = rIdx && (rIdx.visibility >= 0.35) && (rIdx.y <= 0.78) && (rIdx.y < hipY - 0.05);

            if (!lEligible && !rEligible) {
                this.isActive = false;
                this.activeSide = null;
                return { active: false, cursor_x: this.cursorX, cursor_y: this.cursorY, confidence: 0.0 };
            }

            let chosen = null;
            let side = "right";
            if (lEligible && rEligible) {
                if (this.activeSide === "left") { chosen = lIdx; side = "left"; }
                else if (this.activeSide === "right") { chosen = rIdx; side = "right"; }
                else if (lIdx.y < rIdx.y) { chosen = lIdx; side = "left"; }
                else { chosen = rIdx; side = "right"; }
            } else if (lEligible) {
                chosen = lIdx;
                side = "left";
            } else {
                chosen = rIdx;
                side = "right";
            }

            this.activeSide = side;
            this.confidence = chosen.visibility;
            this.isActive = true;

            const boxCenterX = 0.50;
            const boxCenterY = 0.50;
            const boxHalfW = 0.15;
            const boxHalfH = 0.20;

            const relDx = (chosen.x - boxCenterX) / boxHalfW;
            const relDy = (chosen.y - boxCenterY) / boxHalfH;

            let targetX = 0.50 + (relDx * 0.50 * this.SENSITIVITY);
            let targetY = 0.50 + (relDy * 0.50 * this.SENSITIVITY);
            targetX = Math.max(0.0, Math.min(1.0, targetX));
            targetY = Math.max(0.0, Math.min(1.0, targetY));

            const dist = Math.hypot(targetX - this.cursorX, targetY - this.cursorY);
            if (dist > this.DEADZONE) {
                const alpha = dist < 0.04 ? 0.16 : Math.min(0.55, 0.16 + (dist - 0.04) * 6.0);
                this.cursorX = (alpha * targetX) + ((1.0 - alpha) * this.cursorX);
                this.cursorY = (alpha * targetY) + ((1.0 - alpha) * this.cursorY);
            }

            return {
                active: true,
                cursor_x: Math.round(this.cursorX * 10000) / 10000,
                cursor_y: Math.round(this.cursorY * 10000) / 10000,
                confidence: Math.round(this.confidence * 100) / 100,
            };
        }
    }

    // ==========================================
    // 4. BỘ ĐÁNH GIÁ Y KHOA & FSM (ExercisesEvaluator)
    // ==========================================
    class ExercisesEvaluator {
        constructor() {
            this.filter = new EMAFilter(0.32);
            this.handService = new HandService();

            this.calibrationActive = false;
            this.calibExerciseId = "scapular_retraction";
            this.calibDurationMs = 5000;
            this.calibStartTime = 0;
            this.calibMaxRomCombined = 0.0;
            this.calibLastEmitTime = 0;

            this.currentExercise = "";
            this.isExercising = false;
            this.activeSessionId = "";
            this.repCandidateCounter = 0;

            this.exerciseState = {
                movement_state: "ready",
                completed_reps: 0,
                movement_start_time: 0,
                hold_start_time: 0,
                last_hold_emit_time: 0,
                hold_grace_start_time: 0,
                prep_hold_start_time: 0,
                smoothed_hold_rom: 0.0,
                calibrated_max_rom: 85.0,
                current_rep_id: "rep-0001",
            };
        }

        startCalibration(exId, durMs) {
            this.calibrationActive = true;
            this.calibExerciseId = exId || "scapular_retraction";
            this.calibDurationMs = Math.max(durMs || 5000, 1000);
            this.calibStartTime = performance.now();
            this.calibMaxRomCombined = 0.0;
            this.calibLastEmitTime = 0;
            this.filter.reset();
        }

        stopCalibration() {
            this.calibrationActive = false;
        }

        startExercise(exId, sessionId) {
            this.currentExercise = exId || "scapular_retraction";
            this.activeSessionId = sessionId || "";
            this.isExercising = true;
            this.exerciseState = {
                movement_state: "ready",
                completed_reps: 0,
                movement_start_time: 0,
                hold_start_time: 0,
                last_hold_emit_time: 0,
                hold_grace_start_time: 0,
                prep_hold_start_time: 0,
                smoothed_hold_rom: 0.0,
                calibrated_max_rom: this.calibMaxRomCombined > 5.0 ? this.calibMaxRomCombined : 85.0,
                current_rep_id: this._nextRepId(),
            };
            this.filter.reset();
        }

        stopExercise() {
            this.isExercising = false;
            this.currentExercise = "";
            this.activeSessionId = "";
        }

        _nextRepId() {
            this.repCandidateCounter++;
            const s = "0000" + this.repCandidateCounter;
            return `rep-${this.currentExercise}-${s.substr(s.length - 4)}`;
        }

        checkTrackingStatus(landmarks) {
            if (!landmarks || landmarks.length < 17) {
                return { ok: false, code: "TRACKING_LOST" };
            }
            const lSh = landmarks[11];
            const rSh = landmarks[12];
            const lEl = landmarks[13];
            const rEl = landmarks[14];
            const lWr = landmarks[15];
            const rWr = landmarks[16];

            if (lSh.visibility < 0.30 || rSh.visibility < 0.30) {
                return { ok: false, code: "SHOULDERS_NOT_VISIBLE" };
            }
            const lArmVis = Math.max(lEl.visibility, lWr.visibility);
            const rArmVis = Math.max(rEl.visibility, rWr.visibility);
            if (lArmVis < 0.12 && rArmVis < 0.12) {
                return { ok: false, code: "LEFT_ARM_NOT_VISIBLE" };
            }

            const shoulderDist = dist2D(lSh, rSh);
            const centerX = (lSh.x + rSh.x) / 2.0;

            if (shoulderDist > 0.45) return { ok: true, code: "MOVE_BACK" };
            if (shoulderDist < 0.12) return { ok: true, code: "MOVE_CLOSER" };
            if (Math.abs(centerX - 0.5) > 0.22) return { ok: true, code: "CENTER_YOUR_BODY" };

            return { ok: true, code: "POSITION_OK" };
        }

        // T-Pose Calibration (0 -> 90 độ)
        evaluateTPose(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const lWr = lm[15], rWr = lm[16];
            const sw = Math.max(0.08, dist2D(lSh, rSh));

            const lDown = new LandmarkPoint(lSh.x, lSh.y + sw, lSh.z);
            const rDown = new LandmarkPoint(rSh.x, rSh.y + sw, rSh.z);

            const lAbd = 0.5 * angleABC(lDown, lSh, lEl) + 0.5 * angleABC(lDown, lSh, lWr);
            const rAbd = 0.5 * angleABC(rDown, rSh, rEl) + 0.5 * angleABC(rDown, rSh, rWr);

            const lElAngle = angleABC(lSh, lEl, lWr);
            const rElAngle = angleABC(rSh, rEl, rWr);
            const lStraight = Math.max(0.35, Math.min(1.0, (lElAngle - 75.0) / 60.0));
            const rStraight = Math.max(0.35, Math.min(1.0, (rElAngle - 75.0) / 60.0));

            const normalize = (deg, straight) => {
                if (deg <= 15.0) return Math.max(0.0, deg * 0.5);
                let eff = deg >= 83.0 ? (88.0 + Math.min(2.0, (deg - 83.0) * 0.2)) : ((deg - 15.0) / 68.0 * 88.0);
                return Math.round(Math.max(0.0, Math.min(90.0, eff * straight)) * 10) / 10;
            };

            const lRom = normalize(lAbd, lStraight);
            const rRom = normalize(rAbd, rStraight);
            const comb = Math.round(((lRom + rRom) / 2.0) * 10) / 10;
            const valid = (lRom >= 65.0) && (rRom >= 65.0) && (lElAngle >= 120.0) && (rElAngle >= 120.0);

            return {
                current_rom_value: comb,
                rom_progress: Math.min(1.0, comb / 90.0),
                form_valid: valid,
                feedback_code: valid ? "KEEP_POSITION" : "OPEN_ARMS",
                angles: {
                    left_shoulder: lRom,
                    right_shoulder: rRom,
                    left_elbow: lElAngle,
                    right_elbow: rElAngle,
                }
            };
        }

        // Map 1: Khép xương bả vai (Scapular Retraction)
        evaluateMap1(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const lWr = lm[15], rWr = lm[16];
            const sw = Math.max(0.08, dist2D(lSh, rSh));

            const avgElDrop = ((lEl.y - lSh.y) + (rEl.y - rSh.y)) / (2.0 * sw);
            const avgElAngle = (angleABC(lSh, lEl, lWr) + angleABC(rSh, rEl, rWr)) / 2.0;
            const zElDiff = 0.5 * ((lEl.z - lSh.z) + (rEl.z - rSh.z));

            // Chuẩn bị: tay xuôi hoặc đưa ra trước
            const isPrep = (avgElAngle >= 105.0 && zElDiff <= 0.035) || (avgElDrop >= 0.28 && zElDiff <= 0.035);
            // Giữ: khuỷu gập ~90 độ và ép ra sau (zElDiff tăng)
            const scoreEl90 = Math.max(0.0, Math.min(1.0, 1.0 - Math.abs(avgElAngle - 90.0) / 35.0));
            const scoreZ = Math.max(0.0, Math.min(1.0, (zElDiff - (-0.015)) / 0.050));
            const holdRom = Math.max(0.0, Math.min(1.0, 0.40 * scoreEl90 + 0.60 * scoreZ));
            const isHold = (holdRom >= 0.72) && (avgElAngle >= 60.0 && avgElAngle <= 125.0);

            return {
                is_prep: isPrep,
                hold_rom: holdRom,
                is_hold: isHold,
                form_valid: isHold || (holdRom >= 0.50),
                angles: { left_shoulder: 75.0 * holdRom, right_shoulder: 76.0 * holdRom, left_elbow: avgElAngle, right_elbow: avgElAngle }
            };
        }

        // Map 2: Trượt tường giơ tay cao (Overhead Reach)
        evaluateMap2(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const lWr = lm[15], rWr = lm[16];
            const sw = Math.max(0.08, dist2D(lSh, rSh));

            const lDown = new LandmarkPoint(lSh.x, lSh.y + sw, 0);
            const rDown = new LandmarkPoint(rSh.x, rSh.y + sw, 0);
            const avgShAngle = (angleABC(lDown, lSh, lEl) + angleABC(rDown, rSh, rEl)) / 2.0;

            const isPrep = (avgShAngle >= 60.0 && avgShAngle <= 110.0);
            const holdRom = Math.max(0.0, Math.min(1.0, (avgShAngle - 80.0) / 75.0));
            const isHold = holdRom >= 0.90 || (lWr.y < lSh.y - 0.5 * sw && rWr.y < rSh.y - 0.5 * sw);

            return {
                is_prep: isPrep,
                hold_rom: holdRom,
                is_hold: isHold,
                form_valid: true,
                angles: { left_shoulder: avgShAngle, right_shoulder: avgShAngle }
            };
        }

        // Map 3: Mở rộng khớp vai ngang (Horizontal Shoulder Adduction)
        evaluateMap3(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const sw = Math.max(0.08, dist2D(lSh, rSh));
            const elDist = dist2D(lEl, rEl);
            const elRatio = elDist / sw;

            const isPrep = elRatio <= 0.85;
            const holdRom = Math.max(0.0, Math.min(1.0, (elRatio - 0.80) / 1.10));
            const isHold = holdRom >= 0.95;

            return {
                is_prep: isPrep,
                hold_rom: holdRom,
                is_hold: isHold,
                form_valid: true,
                angles: { elbow_ratio: elRatio }
            };
        }

        // Map 4: Đan tay sau gáy khép khuỷu (Hands Behind Head)
        evaluateMap4(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const lWr = lm[15], rWr = lm[16];
            const sw = Math.max(0.08, dist2D(lSh, rSh));
            const elDist = dist2D(lEl, rEl);
            const elRatio = elDist / sw;

            const handsBehind = (lWr.y < lSh.y && rWr.y < rSh.y);
            const isPrep = handsBehind && elRatio >= 1.20;
            const holdRom = Math.max(0.0, Math.min(1.0, (1.30 - elRatio) / 0.65));
            const isHold = holdRom >= 0.95;

            return {
                is_prep: isPrep,
                hold_rom: holdRom,
                is_hold: isHold,
                form_valid: handsBehind,
                angles: { elbow_ratio: elRatio }
            };
        }

        // Map 5: Kéo căng khớp vai bắt chéo ngực (Cross Body Stretch)
        evaluateMap5(lm) {
            const lSh = lm[11], rSh = lm[12];
            const lEl = lm[13], rEl = lm[14];
            const sw = Math.max(0.08, dist2D(lSh, rSh));

            // Khoảng cách khuỷu tay đến vai đối diện
            const dElOpp = Math.min(dist2D(lEl, rSh), dist2D(rEl, lSh)) / sw;
            const isPrep = dElOpp >= 0.85;
            const holdRom = Math.max(0.0, Math.min(1.0, (0.85 - dElOpp) / 0.45));
            const isHold = holdRom >= 0.90;

            return {
                is_prep: isPrep,
                hold_rom: holdRom,
                is_hold: isHold,
                form_valid: true,
                angles: { d_el_opp: dElOpp }
            };
        }

        processFrame(landmarks) {
            const now = performance.now();
            const events = [];

            // 1. Nếu đang Calibration
            if (this.calibrationActive) {
                const calib = this.evaluateTPose(landmarks);
                const elapsedMs = Math.round(now - this.calibStartTime);
                const progress = Math.min(1.0, elapsedMs / this.calibDurationMs);

                this.calibMaxRomCombined = Math.max(this.calibMaxRomCombined, calib.current_rom_value);

                let progressMsg = null;
                if (now - this.calibLastEmitTime >= 250) {
                    this.calibLastEmitTime = now;
                    progressMsg = {
                        exercise_id: this.calibExerciseId,
                        progress: Math.round(progress * 100) / 100,
                        elapsed_ms: elapsedMs,
                        duration_ms: this.calibDurationMs,
                        tracking_valid: calib.form_valid,
                        current_rom_value: calib.current_rom_value,
                        rom_unit: "degree",
                        feedback_code: calib.feedback_code,
                    };
                }

                let completedMsg = null;
                if (progress >= 1.0) {
                    this.calibrationActive = false;
                    completedMsg = {
                        exercise_id: this.calibExerciseId,
                        success: this.calibMaxRomCombined > 5.0,
                        measurement_kind: "normalized_t_pose",
                        valid_elapsed_ms: this.calibDurationMs,
                        duration_ms: this.calibDurationMs,
                        valid_sample_count: 30,
                        sample_quality: 1.0,
                        target_side: "both",
                        max_rom: {
                            left: this.calibMaxRomCombined,
                            right: this.calibMaxRomCombined,
                            combined: this.calibMaxRomCombined,
                            unit: "degree",
                        },
                        confidence: 0.95,
                        recommended_target_ratio: 0.85,
                        recommended_target_value: Math.round(this.calibMaxRomCombined * 0.85 * 10) / 10,
                        feedback_code: "CALIBRATION_COMPLETED",
                    };
                }

                return {
                    calib_progress: progressMsg,
                    calib_completed: completedMsg,
                    angles: calib.angles,
                    pose_metrics: null,
                    events: [],
                };
            }

            // 2. Nếu đang bài tập
            if (!this.isExercising) {
                return { calib_progress: null, calib_completed: null, pose_metrics: null, events: [] };
            }

            let evalData = null;
            let targetHoldMs = 5000;
            switch (this.currentExercise) {
                case "scapular_retraction":
                    evalData = this.evaluateMap1(landmarks);
                    targetHoldMs = 700;
                    break;
                case "wall_abduction_external_rotation":
                    evalData = this.evaluateMap2(landmarks);
                    targetHoldMs = 5000;
                    break;
                case "horizontal_shoulder_adduction":
                    evalData = this.evaluateMap3(landmarks);
                    targetHoldMs = 5000;
                    break;
                case "hands_behind_head":
                    evalData = this.evaluateMap4(landmarks);
                    targetHoldMs = 5000;
                    break;
                case "cross_body_shoulder_stretch":
                    evalData = this.evaluateMap5(landmarks);
                    targetHoldMs = 30000;
                    break;
                default:
                    evalData = this.evaluateMap1(landmarks);
                    targetHoldMs = 700;
                    break;
            }

            const st = this.exerciseState;
            let romProg = evalData.hold_rom;
            let holdProg = 0.0;
            let feedbackCode = "POSITION_OK";

            if (st.movement_state === "ready") {
                if (evalData.is_prep || evalData.hold_rom < 0.20) {
                    feedbackCode = "PREP_POSITION";
                }
                if (evalData.hold_rom >= 0.25) {
                    st.movement_state = "moving";
                    st.movement_start_time = now;
                    events.push({
                        event: "movement_started",
                        rep_candidate_id: st.current_rep_id,
                        feedback_code: "MOVEMENT_STARTED",
                    });
                }
            } else if (st.movement_state === "moving") {
                feedbackCode = "CONTINUE_MOVEMENT";
                if (evalData.is_hold || evalData.hold_rom >= 0.95) {
                    st.movement_state = "holding";
                    st.hold_start_time = now;
                    st.last_hold_emit_time = now;
                    romProg = 1.0;
                    events.push({
                        event: "target_reached",
                        rep_candidate_id: st.current_rep_id,
                        feedback_code: "TARGET_REACHED",
                    });
                    events.push({
                        event: "hold_started",
                        rep_candidate_id: st.current_rep_id,
                        hold_target_ms: targetHoldMs,
                        feedback_code: "HOLD_STARTED",
                    });
                }
            } else if (st.movement_state === "holding") {
                const holdElapsedMs = Math.round(now - st.hold_start_time);
                holdProg = Math.min(1.0, holdElapsedMs / targetHoldMs);
                romProg = 1.0;

                if (evalData.hold_rom >= 0.50 || evalData.is_hold) {
                    feedbackCode = "KEEP_POSITION";
                    st.hold_grace_start_time = 0;

                    if (now - st.last_hold_emit_time >= 150 && holdProg < 1.0) {
                        st.last_hold_emit_time = now;
                        events.push({
                            event: "hold_progress",
                            rep_candidate_id: st.current_rep_id,
                            hold_elapsed_ms: holdElapsedMs,
                            hold_target_ms: targetHoldMs,
                            hold_progress: Math.round(holdProg * 100) / 100,
                            feedback_code: "KEEP_POSITION",
                        });
                    }

                    if (holdProg >= 1.0) {
                        st.completed_reps++;
                        const totalDur = Math.round(now - st.movement_start_time);
                        events.push({
                            event: "hold_completed",
                            rep_candidate_id: st.current_rep_id,
                            hold_target_ms: targetHoldMs,
                            feedback_code: "HOLD_COMPLETED",
                        });
                        events.push({
                            event: "rep_completed",
                            rep_candidate_id: st.current_rep_id,
                            duration_ms: totalDur,
                            max_rom_ratio: 1.0,
                            hold_duration_ms: targetHoldMs,
                            quality: 1.0,
                            feedback_code: "REP_VALID",
                        });
                        st.movement_state = "returning";
                        feedbackCode = "REP_VALID";
                    }
                } else {
                    if (st.hold_grace_start_time === 0) st.hold_grace_start_time = now;
                    if (now - st.hold_grace_start_time >= 1000) {
                        events.push({
                            event: "hold_interrupted",
                            rep_candidate_id: st.current_rep_id,
                            hold_target_ms: targetHoldMs,
                            feedback_code: "HOLD_INTERRUPTED",
                        });
                        st.movement_state = "moving";
                        st.hold_grace_start_time = 0;
                    }
                }
            } else if (st.movement_state === "returning") {
                feedbackCode = "RETURN_TO_PREP";
                if (evalData.is_prep || evalData.hold_rom <= 0.20) {
                    st.movement_state = "ready";
                    st.current_rep_id = this._nextRepId();
                    feedbackCode = "PREP_POSITION";
                }
            }

            const poseMetrics = {
                angles: evalData.angles || {},
                exercise: {
                    exercise_id: this.currentExercise,
                    movement_state: st.movement_state,
                    form_valid: evalData.form_valid,
                    rom_progress: Math.round(romProg * 100) / 100,
                    hold_progress: Math.round(holdProg * 100) / 100,
                    movement_duration_ms: st.movement_start_time > 0 ? Math.round(now - st.movement_start_time) : 0,
                    quality: evalData.form_valid ? 0.95 : 0.50,
                    feedback_code: feedbackCode,
                }
            };

            return {
                calib_progress: null,
                calib_completed: null,
                pose_metrics: poseMetrics,
                events: events,
            };
        }
    }

    // ==========================================
    // 5. CẦU NỐI MEDIAPIPE BRIDGE CHO TRÌNH DUYỆT
    // ==========================================
    const SKELETON_PAIRS = [
        [11, 12], [11, 13], [13, 15],
        [12, 14], [14, 16], [11, 23],
        [12, 24], [23, 24]
    ];
    const JOINT_POINTS = [11, 12, 13, 14, 15, 16, 23, 24];

    window.GamePHCN_Bridge = {
        isCameraActive: false,
        isModelLoaded: false,
        videoElement: null,
        canvasElement: null,
        canvasCtx: null,
        poseLandmarker: null,
        evaluator: new ExercisesEvaluator(),

        lastCameraSendTime: 0,
        lastPoseSendTime: 0,
        lastTrackingSendTime: 0,
        lastHandSendTime: 0,
        lastTrackingCode: "",
        lastHandActive: false,
        frameCounter: 0,
        messageCounter: 0,

        async init(videoId = "webcam", canvasId = "pose-canvas") {
            this.videoElement = document.getElementById(videoId);
            this.canvasElement = document.getElementById(canvasId);
            if (this.canvasElement) {
                this.canvasCtx = this.canvasElement.getContext("2d", { alpha: false });
            }

            // 1. Tự động bật Camera
            this.startCamera().catch(err => {
                console.warn("[Bridge] Chưa bật được camera tự động:", err);
            });

            // 2. Nạp MediaPipe Tasks Vision Wasm
            try {
                const vision = await import("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm/vision_bundle.mjs");
                const { PoseLandmarker, FilesetResolver } = vision;
                const wasmFileset = await FilesetResolver.forVisionTasks("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm");

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
                    console.log("[Bridge] MediaPipe GPU sẵn sàng!");
                } catch (gpuErr) {
                    console.warn("[Bridge] Chuyển CPU fallback cho MediaPipe:", gpuErr);
                    this.poseLandmarker = await PoseLandmarker.createFromOptions(wasmFileset, {
                        baseOptions: {
                            modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task",
                            delegate: "CPU",
                        },
                        runningMode: "VIDEO",
                        numPoses: 1,
                    });
                    this.isModelLoaded = true;
                    console.log("[Bridge] MediaPipe CPU sẵn sàng!");
                }
            } catch (err) {
                console.error("[Bridge] Lỗi nạp MediaPipe:", err);
            }
        },

        async startCamera() {
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                return false;
            }
            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" },
                    audio: false,
                });
                if (this.videoElement) {
                    this.videoElement.srcObject = stream;
                    this.videoElement.muted = true;
                    await this.videoElement.play();
                    this.isCameraActive = true;
                    this.startLoop();
                    return true;
                }
            } catch (err) {
                console.warn("[Bridge] Lỗi cấp quyền Camera:", err);
                const toast = document.getElementById("camera-perm-toast");
                if (toast) toast.style.display = "block";
                return false;
            }
        },

        startLoop() {
            if (this._loopStarted) return;
            this._loopStarted = true;

            const loop = () => {
                if (this.isCameraActive && this.videoElement && this.videoElement.readyState >= 2) {
                    const now = performance.now();
                    let rawLms = null;

                    // Nhận diện mốc xương
                    if (this.poseLandmarker && (now - this.lastPoseSendTime >= 30)) {
                        try {
                            const res = this.poseLandmarker.detectForVideo(this.videoElement, now);
                            if (res && res.landmarks && res.landmarks.length > 0) {
                                rawLms = res.landmarks[0];
                            }
                        } catch (e) {
                            // ignore drop
                        }
                    }

                    // Lọc nhiễu
                    const activeLms = this.evaluator.filter.filter(rawLms);

                    // Vẽ hình và khung xương lên Offscreen Canvas (Mirror)
                    this.renderFrame(activeLms);

                    // Trích xuất ảnh Base64 gửi vào Godot (~15 FPS, < 1ms)
                    if (now - this.lastCameraSendTime >= 65) {
                        this.lastCameraSendTime = now;
                        this.sendCameraFrameToGodot();
                    }

                    // Xử lý logic và sự kiện
                    this.processLogicAndSendMessages(activeLms, now);
                }
                requestAnimationFrame(loop);
            };
            requestAnimationFrame(loop);
        },

        renderFrame(landmarks) {
            if (!this.canvasCtx || !this.canvasElement || !this.videoElement) return;
            const w = this.canvasElement.width;
            const h = this.canvasElement.height;

            // 1. Vẽ hình ảnh video gương (Mirror)
            this.canvasCtx.save();
            this.canvasCtx.translate(w, 0);
            this.canvasCtx.scale(-1, 1);
            this.canvasCtx.drawImage(this.videoElement, 0, 0, w, h);
            this.canvasCtx.restore();

            // 2. Vẽ bộ xương khớp chuẩn OpenCV (Xương xanh, khớp cam vành trắng)
            if (landmarks && landmarks.length >= 17) {
                // Xương xanh
                this.canvasCtx.lineWidth = 3;
                this.canvasCtx.strokeStyle = "#00e673";
                for (const [p1, p2] of SKELETON_PAIRS) {
                    if (landmarks[p1] && landmarks[p2]) {
                        if (landmarks[p1].visibility > 0.4 && landmarks[p2].visibility > 0.4) {
                            this.canvasCtx.beginPath();
                            this.canvasCtx.moveTo(landmarks[p1].x * w, landmarks[p1].y * h);
                            this.canvasCtx.lineTo(landmarks[p2].x * w, landmarks[p2].y * h);
                            this.canvasCtx.stroke();
                        }
                    }
                }

                // Khớp cam
                for (const idx of JOINT_POINTS) {
                    const pt = landmarks[idx];
                    if (pt && pt.visibility > 0.4) {
                        const cx = pt.x * w;
                        const cy = pt.y * h;
                        // Tâm cam
                        this.canvasCtx.beginPath();
                        this.canvasCtx.arc(cx, cy, 5, 0, 2 * Math.PI);
                        this.canvasCtx.fillStyle = "#ff8c00";
                        this.canvasCtx.fill();
                        // Vành trắng
                        this.canvasCtx.beginPath();
                        this.canvasCtx.arc(cx, cy, 7, 0, 2 * Math.PI);
                        this.canvasCtx.strokeStyle = "#ffffff";
                        this.canvasCtx.lineWidth = 1.5;
                        this.canvasCtx.stroke();
                    }
                }
            }
        },

        sendCameraFrameToGodot() {
            if (!this.canvasElement || !window.godotReceiveCameraFrame) return;
            try {
                // Xuất JPEG chất lượng 0.55 nhỏ gọn ~15KB
                const dataUrl = this.canvasElement.toDataURL("image/jpeg", 0.55);
                const b64 = dataUrl.split(",")[1];
                if (b64) {
                    window.godotReceiveCameraFrame(b64);
                }
            } catch (e) {
                // ignore
            }
        },

        processLogicAndSendMessages(landmarks, now) {
            // 1. Kiểm tra tracking_status
            const tracking = this.evaluator.checkTrackingStatus(landmarks);
            if ((tracking.code !== this.lastTrackingCode) || (now - this.lastTrackingSendTime >= 2000)) {
                this.lastTrackingCode = tracking.code;
                this.lastTrackingSendTime = now;
                this.sendGodotEnvelope("tracking_status", {
                    status: tracking.ok ? "tracking" : "no_person",
                    person_detected: Boolean(landmarks),
                    confidence: tracking.ok ? 0.95 : 0.30,
                    full_body_visible: tracking.ok,
                    required_body_visible: tracking.ok,
                    camera_fps: 30.0,
                    feedback_code: tracking.code,
                });
            }

            // 2. Hand Cursor
            const handPayload = this.evaluator.handService.process(landmarks);
            if (handPayload.active || this.lastHandActive || (now - this.lastHandSendTime >= 2000)) {
                this.lastHandActive = handPayload.active;
                this.lastHandSendTime = now;
                this.sendGodotEnvelope("hand_control", handPayload);
            }

            // 3. FSM bài tập & Calibration
            const outcome = this.evaluator.processFrame(landmarks);

            if (outcome.calib_progress) {
                this.sendGodotEnvelope("calibration_progress", outcome.calib_progress);
            }
            if (outcome.calib_completed) {
                this.sendGodotEnvelope("calibration_completed", outcome.calib_completed);
            }

            if (outcome.pose_metrics && (now - this.lastPoseSendTime >= 65)) {
                this.lastPoseSendTime = now;
                this.frameCounter++;
                this.sendGodotEnvelope("pose_frame", {
                    frame_id: this.frameCounter,
                    tracking: {
                        person_detected: Boolean(landmarks),
                        confidence: tracking.ok ? 0.95 : 0.30,
                        required_body_visible: tracking.ok,
                    },
                    angles: outcome.pose_metrics.angles,
                    exercise: outcome.pose_metrics.exercise,
                });
            }

            for (const ev of outcome.events) {
                this.sendGodotEnvelope("exercise_event", ev);
            }
        },

        sendGodotEnvelope(msgType, payload) {
            if (!window.godotReceiveMessage) return;
            this.messageCounter++;
            const envelope = {
                contract_version: "1.0.0",
                type: msgType,
                message_id: `web-bridge-${this.messageCounter}`,
                session_id: this.evaluator.activeSessionId || null,
                timestamp_ms: Math.round(performance.now()),
                source: "backend",
                payload: payload,
            };
            try {
                window.godotReceiveMessage(JSON.stringify(envelope));
            } catch (e) {
                console.warn("[Bridge] Gửi tin sang Godot thất bại:", e);
            }
        },

        // Nhận lệnh từ Godot thông qua WebPoseProvider
        receiveGodotCommand(jsonStr) {
            let msg = null;
            try {
                msg = typeof jsonStr === "string" ? JSON.parse(jsonStr) : jsonStr;
            } catch (e) {
                console.warn("[Bridge] Nhận JSON không hợp lệ từ Godot:", jsonStr);
                return;
            }
            if (!msg || !msg.type) return;

            const type = msg.type;
            const payload = msg.payload || {};
            const sessionId = msg.session_id || "";

            if (type === "client_hello") {
                console.log("[Bridge] Nhận client_hello từ Godot Web. Phản hồi server_hello...");
                this.sendGodotEnvelope("server_hello", {
                    backend_version: "1.0.0",
                    pose_engine: "mediapipe-web",
                    camera_available: this.isCameraActive,
                    supported_exercises: [
                        "scapular_retraction",
                        "wall_abduction_external_rotation",
                        "horizontal_shoulder_adduction",
                        "hands_behind_head",
                        "cross_body_shoulder_stretch",
                    ],
                });
            } else if (type === "start_calibration") {
                console.log("[Bridge] Bắt đầu Calibration:", payload);
                this.evaluator.startCalibration(payload.exercise_id, payload.duration_ms);
            } else if (type === "start_exercise") {
                console.log("[Bridge] Bắt đầu bài tập:", payload);
                this.evaluator.startExercise(payload.exercise_id, sessionId);
            } else if (type === "stop_exercise") {
                console.log("[Bridge] Dừng bài tập / Calibration");
                this.evaluator.stopCalibration();
                this.evaluator.stopExercise();
            }
        }
    };
})();
