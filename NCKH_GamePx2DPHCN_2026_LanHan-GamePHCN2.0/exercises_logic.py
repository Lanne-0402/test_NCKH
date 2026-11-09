"""
Module xu ly logic nhan dien cu dong canh tay cho 5 bai tap phuc hoi chuc nang.
Tuan thu chat che JSON Contract 1.0.0 va Kich ban Game 2D Pixel PHCN So 01.
Tac gia: Nong Thi Hong Lan (AI & Computer Vision Backend)
"""

import math
import time
from typing import Dict, Any, List, Optional, Tuple


class LandmarkPoint:
    """Dai dien cho mot diem khop xuong sau khi da duoc loc nhieu."""
    __slots__ = ('x', 'y', 'z', 'visibility')

    def __init__(self, x: float, y: float, z: float, visibility: float = 1.0):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)
        self.visibility = float(visibility)


class EMAFilter:
    """Bo loc tin hieu Adaptive EMA."""
    SYMMETRIC_PAIRS = (
        (11, 12),  # Vai trai - Vai phai
        (13, 14),  # Khuyu trai - Khuyu phai
        (15, 16),  # Co tay trai - Co tay phai
        (17, 18),
        (19, 20),
        (21, 22),
        (23, 24),  # Hong trai - Hong phai
    )

    def __init__(self, alpha: float = 0.34, alpha_z: float = 0.16):
        self.alpha = alpha
        self.alpha_z = alpha_z
        self.prev_landmarks: Optional[List[LandmarkPoint]] = None
        self.last_raw_id: Optional[int] = None
        self.last_filtered_output: Optional[List[LandmarkPoint]] = None

    def _canonicalize_raw_landmarks(self, raw_landmarks) -> List[LandmarkPoint]:
        pts = [
            LandmarkPoint(lm.x, lm.y, lm.z, getattr(lm, 'visibility', 1.0))
            for lm in raw_landmarks
        ]
        if len(pts) < 25:
            return pts

        # 1. Kiem tra neu MediaPipe bi dao nguoc mat truoc/mat sau (lam Vai 11 va Vai 12 doi cho tren truc X):
        # Tren khung hinh da lat guong (cv2.flip(frame, 1)), khi nguoi tap dung quay mat vao camera:
        # lm[11] luon nam ben phai man hinh (x lon hon) so voi lm[12] (x nho hon).
        # Tuy nhien de tuong thich moi che do camera, ta so sanh voi huong chuan cua prev_landmarks
        # hoac chuan mac dinh cua anh lat guong (pts[11].x > pts[12].x).
        sh_dx = pts[11].x - pts[12].x
        expected_sign = 1.0
        if self.prev_landmarks and len(self.prev_landmarks) >= 25:
            prev_sh_dx = self.prev_landmarks[11].x - self.prev_landmarks[12].x
            if abs(prev_sh_dx) > 0.04:
                expected_sign = 1.0 if prev_sh_dx > 0 else -1.0

        if sh_dx * expected_sign < -0.02:
            # MediaPipe vua bi dao nguoc Left/Right do foreshortening -> hoan doi lai dung cap khop doi xung
            for idx_a, idx_b in self.SYMMETRIC_PAIRS:
                if idx_a < len(pts) and idx_b < len(pts):
                    pts[idx_a], pts[idx_b] = pts[idx_b], pts[idx_a]
            for pt in pts:
                pt.z = -pt.z

        # 2. Chong nhay cheo khuyu tay (13 <-> 14): Khuyu tay khong bao gio vuot cheo qua khuyu tay ben kia
        sh_sign = 1.0 if (pts[11].x - pts[12].x) >= 0 else -1.0
        el_dx = (pts[13].x - pts[14].x) * sh_sign
        if el_dx < -0.03:
            pts[13], pts[14] = pts[14], pts[13]

        return pts

    def filter(self, raw_landmarks) -> List[LandmarkPoint]:
        if not raw_landmarks:
            return []

        # Neu danh sach landmarks nay da duoc loc trong cung 1 vong lap frame thi tra ve ngay
        if id(raw_landmarks) == self.last_raw_id and self.last_filtered_output is not None:
            return self.last_filtered_output

        pts = self._canonicalize_raw_landmarks(raw_landmarks)

        if self.prev_landmarks is None or len(self.prev_landmarks) != len(pts):
            self.prev_landmarks = pts
            self.last_raw_id = id(pts)
            self.last_filtered_output = pts
            return pts

        smoothed: List[LandmarkPoint] = []
        for idx, (curr, prev) in enumerate(zip(pts, self.prev_landmarks)):
            curr_vis = curr.visibility
            dx = curr.x - prev.x
            dy = curr.y - prev.y
            dz = curr.z - prev.z
            dist_xy = math.hypot(dx, dy)

            # Gioi han buoc nhay dot ngot (Outlier / Spike Clamping) cho cac khop tay & vai
            if idx in (11, 12, 13, 14, 15, 16):
                max_xy = 0.085 if curr_vis >= 0.60 else 0.045
                if dist_xy > max_xy and dist_xy > 1e-6:
                    scale_xy = max_xy / dist_xy
                    dx *= scale_xy
                    dy *= scale_xy
                    dist_xy = max_xy
                max_z = 0.055 if curr_vis >= 0.60 else 0.030
                if abs(dz) > max_z:
                    dz = math.copysign(max_z, dz)

            # He so lam muot thich ung (Adaptive Alpha):
            # Khi khop it di chuyen (giu the / dung yen), giam alpha ca XY va Z de triet tieu rung giat;
            # khi khop dang di chuyen ro ret, tang alpha de phan hoi muot ma khong bi tre.
            if dist_xy < 0.010:
                eff_alpha_xy = 0.16
                eff_alpha_z = 0.08
            elif dist_xy < 0.030:
                eff_alpha_xy = 0.26
                eff_alpha_z = 0.12
            else:
                eff_alpha_xy = self.alpha
                eff_alpha_z = self.alpha_z

            if curr_vis < 0.45:
                eff_alpha_xy *= 0.45
                eff_alpha_z *= 0.45

            sm_x = prev.x + eff_alpha_xy * dx
            sm_y = prev.y + eff_alpha_xy * dy
            sm_z = prev.z + eff_alpha_z * dz
            sm_vis = 0.30 * curr_vis + 0.70 * prev.visibility
            smoothed.append(LandmarkPoint(sm_x, sm_y, sm_z, sm_vis))

        self.prev_landmarks = smoothed
        self.last_raw_id = id(smoothed)
        self.last_filtered_output = smoothed
        return smoothed

    def reset(self):
        self.prev_landmarks = None
        self.last_raw_id = None
        self.last_filtered_output = None


class ExercisesEvaluator:
    """
    Bo danh gia y khoa va may trang thai cu dong (Movement State Machine).
    Xu ly ca 5 bai tap, che do do ROM (Calibration) va sinh su kien Repetition/Hold.
    """

    def __init__(self):
        self.filter = EMAFilter(alpha=0.32)

        # Cau hinh va trang thai cho tung bai tap
        self.exercise_states: Dict[str, Dict[str, Any]] = {
            "scapular_retraction": self._default_exercise_state(hold_ms=700),
            "wall_abduction_external_rotation": self._default_exercise_state(hold_ms=5000),
            "horizontal_shoulder_adduction": self._default_exercise_state(hold_ms=5000),
            "hands_behind_head": self._default_exercise_state(hold_ms=5000),
            "cross_body_shoulder_stretch": self._default_exercise_state(hold_ms=30000),
        }

        # Trang thai hieu chuan (Calibration - Dang 2 tay ngang vai T-Pose 90 do)
        self.calibration_active = False
        self.calib_exercise_id = "scapular_retraction"
        self.calib_target_side = "both"
        self.calib_duration_ms = 5000
        self.calib_start_time = 0.0
        self.calib_max_rom_left = 0.0
        self.calib_max_rom_right = 0.0
        self.calib_max_rom_combined = 0.0
        self.calib_last_emit_time = 0.0
        self.calibrated_global_max_rom = 0.0

        # Quan ly tam dung (Pause)
        self.is_paused = False

    def _default_exercise_state(self, hold_ms: int) -> Dict[str, Any]:
        return {
            "movement_state": "ready",  # ready, contracting, target_reached, holding, returning
            "rep_count": 0,
            "current_rep_id": "",
            "movement_start_time": 0.0,
            "active_motion_start_time": 0.0,
            "hold_start_time": 0.0,
            "last_hold_emit_time": 0.0,
            "hold_grace_start_time": 0.0,
            "target_rom_ratio": 0.85,
            "calibrated_max_rom": 0.0,
            "target_rom_value": 0.0,
            "hold_duration_ms": hold_ms,
            "min_movement_duration_ms": 1000,
            "max_movement_duration_ms": 6000,
            "target_side": "both",
            "active_stretch_side": "none",
            "last_rom_progress": 0.0,
            "last_hold_progress": 0.0,
            "peak_rom_achieved": 0.0,
        }

    # ==========================
    # TOAN HOC & VECTOR CO BAN
    # ==========================
    @staticmethod
    def calculate_angle(p1: LandmarkPoint, p2: LandmarkPoint, p3: LandmarkPoint) -> float:
        """
        Tinh goc tai dinh p2 tao boi p1-p2-p3 (do tu 0 den 180 do).
        """
        radians = math.atan2(p3.y - p2.y, p3.x - p2.x) - math.atan2(p1.y - p2.y, p1.x - p2.x)
        angle = abs(math.degrees(radians))
        if angle > 180.0:
            angle = 360.0 - angle
        return angle

    @staticmethod
    def calculate_angle_3d(p1: LandmarkPoint, p2: LandmarkPoint, p3: LandmarkPoint, z_scale: float = 1.0) -> float:
        """
        Tinh goc tai dinh p2 tao boi p1-p2-p3 trong khong gian 3D (do tu 0 den 180 do).
        Ho tro tham so z_scale (mac dinh 1.0; dat 0.55 khi cang tay huong thang vao camera
        de khu nhieu phong dai truc sau Z cua MediaPipe 2D webcam).
        """
        v1 = (p1.x - p2.x, p1.y - p2.y, (p1.z - p2.z) * z_scale)
        v2 = (p3.x - p2.x, p3.y - p2.y, (p3.z - p2.z) * z_scale)
        dot = v1[0]*v2[0] + v1[1]*v2[1] + v1[2]*v2[2]
        mag1 = math.sqrt(v1[0]**2 + v1[1]**2 + v1[2]**2)
        mag2 = math.sqrt(v2[0]**2 + v2[1]**2 + v2[2]**2)
        if mag1 < 1e-6 or mag2 < 1e-6:
            return 90.0
        cos_val = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return math.degrees(math.acos(cos_val))

    @staticmethod
    def calculate_2d_distance(p1: LandmarkPoint, p2: LandmarkPoint) -> float:
        """Khoang cach Euclid 2D giua 2 diem."""
        return math.sqrt((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2)

    @staticmethod
    def calculate_3d_distance(p1: LandmarkPoint, p2: LandmarkPoint) -> float:
        """Khoang cach Euclid 3D giua 2 diem."""
        return math.sqrt((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2 + (p1.z - p2.z) ** 2)

    def _get_patient_calib_factor(self, exercise_id: str) -> float:
        """
        Tinh he so nang luc van dong khop vai cua nguoi benh tu buoc Calibration (T-Pose 90 do).
        Giup ap dung ket qua Calibration va target_rom_ratio dong nhat cho ca 5 Map ma khong lech don vi.
        """
        st = self.exercise_states.get(exercise_id, {})
        calib_max = float(st.get("calibrated_max_rom", 0.0))
        if calib_max <= 15.0:
            calib_max = float(self.calibrated_global_max_rom)
        if calib_max > 20.0:
            # Chuan T-Pose dang ngang vai la 90.0 do
            return max(0.65, min(1.05, calib_max / 90.0))
        return 1.0

    def _scale_rom_with_calibration(self, exercise_id: str, raw_anatomical_rom: float) -> float:
        """
        Quy doi tien do giai phau thuan tuy (0.0 -> 1.0) sang rom_progress cua Game
        dua tren target_rom_ratio (cap do De/Vua/Kho) va calib_factor (Adaptive Angle).
        Dam bao khi Calibration dat 90 do hoan chinh (calib_factor = 1.0) hoac duoi 90 do,
        nguoi tap thuc hien dung dong tac deu tang muot ma len 100% (1.0).
        """
        st = self.exercise_states.get(exercise_id, {})
        target_ratio = float(st.get("target_rom_ratio", 0.78))
        target_ratio = max(0.65, min(0.90, target_ratio))
        calib_factor = self._get_patient_calib_factor(exercise_id)

        if exercise_id == "scapular_retraction":
            # Map 1 (Ep 2 ba vai ra sau): Dam bao khi Calibration dat 90 do hay < 90 do,
            # nguoi tap ep khuyu tay ve sau dung the deu dat muot ma 100% ROM, khong bao gio bi ket o 92%.
            effective_target = max(0.55, min(0.68, 0.62 + 0.12 * (target_ratio - 0.70)))
        else:
            effective_target = max(0.55, min(0.92, target_ratio * calib_factor))

        scaled = raw_anatomical_rom / effective_target
        if scaled >= 0.90:
            return 1.0
        return max(0.0, min(1.0, scaled / 0.90))

    # ==========================
    # CAU HINH PHIEN TAP & CALIBRATION
    # ==========================
    def configure_exercise(self, exercise_id: str, config: Dict[str, Any]):
        """Khoi tao/cap nhat cau hinh bai tap tu yeu cau cua Godot."""
        if exercise_id not in self.exercise_states:
            return

        st = self.exercise_states[exercise_id]
        st["movement_state"] = "ready"
        st["current_rep_id"] = ""
        st["completed_reps"] = 0
        st["target_rom_ratio"] = float(config.get("target_rom_ratio", 0.80))
        st["target_side"] = str(config.get("target_side", "both"))
        st["min_movement_duration_ms"] = int(config.get("minimum_movement_duration_ms", 1000))
        st["max_movement_duration_ms"] = int(config.get("maximum_movement_duration_ms", 6000))
        if "hold_duration_ms" in config:
            st["hold_duration_ms"] = int(config["hold_duration_ms"])
        if "calibrated_max_rom" in config and float(config["calibrated_max_rom"]) > 0:
            st["calibrated_max_rom"] = float(config["calibrated_max_rom"])
        elif self.calibrated_global_max_rom > 0:
            st["calibrated_max_rom"] = float(self.calibrated_global_max_rom)
        if "target_rom_value" in config and float(config["target_rom_value"]) > 0:
            st["target_rom_value"] = float(config["target_rom_value"])

        if exercise_id == "scapular_retraction":
            st["target_rom_ratio"] = max(0.72, min(0.85, float(config.get("target_rom_ratio", 0.78))))
            st["min_movement_duration_ms"] = 180
            st["hold_duration_ms"] = 700
            st["map1_smoothed_hold_rom"] = 0.0

        if exercise_id == "wall_abduction_external_rotation":
            st["target_rom_ratio"] = max(0.70, min(0.90, float(config.get("target_rom_ratio", 0.75))))
            st["min_movement_duration_ms"] = 550
            st["map2_smoothed_hold_rom"] = 0.0

        if exercise_id == "horizontal_shoulder_adduction":
            st["target_rom_ratio"] = max(0.70, min(0.90, float(config.get("target_rom_ratio", 0.75))))
            st["min_movement_duration_ms"] = 550
            st["map3_smoothed_hold_rom"] = 0.0

        if exercise_id == "hands_behind_head":
            st["target_rom_ratio"] = max(0.70, min(0.90, float(config.get("target_rom_ratio", 0.75))))
            st["min_movement_duration_ms"] = 550
            st["map4_smoothed_hold_rom"] = 0.0

        if exercise_id == "cross_body_shoulder_stretch":
            st["target_rom_ratio"] = max(0.70, min(0.90, float(config.get("target_rom_ratio", 0.75))))
            st["min_movement_duration_ms"] = 550
            st["active_stretch_side"] = "none"
            st["last_completed_side"] = "none"
            st["required_side"] = str(config.get("target_side", "both"))
            st["map5_smoothed_hold_rom"] = 0.0

        st["last_rom_progress"] = 0.0
        st["last_hold_progress"] = 0.0
        st["peak_rom_achieved"] = 0.0
        st["hold_grace_start_time"] = 0.0
        st["prep_delay_start_time"] = 0.0
        st["prep_hold_start_time"] = 0.0
        st["active_motion_start_time"] = 0.0
        self.is_paused = False

    def start_calibration(self, exercise_id: str, duration_ms: int = 5000, target_side: str = "both"):
        """Bat dau qua trinh hieu chuan do ROM toi da."""
        self.calibration_active = True
        self.calib_exercise_id = exercise_id
        self.calib_target_side = target_side
        self.calib_duration_ms = max(duration_ms, 1000)
        self.calib_start_time = time.time()
        self.calib_max_rom_left = 0.0
        self.calib_max_rom_right = 0.0
        self.calib_max_rom_combined = 0.0
        self.calib_last_emit_time = 0.0
        self.filter.reset()

    def stop_calibration(self):
        self.calibration_active = False

    def pause(self):
        self.is_paused = True

    def resume(self):
        self.is_paused = False

    def _next_rep_candidate_id(self, exercise_id: str) -> str:
        st = self.exercise_states[exercise_id]
        st["rep_count"] += 1
        rep_id = f"rep-{exercise_id}-{st['rep_count']:04d}"
        st["current_rep_id"] = rep_id
        return rep_id

    # ==========================
    # KIEM TRA VISIBILITY & POSE STATUS
    # ==========================
    def check_tracking_status(self, landmarks) -> Tuple[bool, str]:
        """
        Kiem tra nguoi choi co dung dung vi tri truoc camera khong.
        Tra ve (is_valid, feedback_code).
        Chi kiem tra cac diem vai/khuyu tay can thiet (11..16), cac diem khong dung trong thuat toan
        (nhu mat 0..10, ban tay 17..22, hong/chan 23..32, hoac co tay/khuyu tay bi che khuat khi bat cheo nguc)
        co the bi che khuat ma KHONG BAO GIO gay mat nhan dien (TRACKING_LOST).
        """
        if not landmarks or len(landmarks) < 17:
            return False, "TRACKING_LOST"

        l_sh = landmarks[11]
        r_sh = landmarks[12]
        l_el = landmarks[13]
        r_el = landmarks[14]
        l_wr = landmarks[15]
        r_wr = landmarks[16]

        if getattr(l_sh, 'visibility', 1.0) < 0.30 or getattr(r_sh, 'visibility', 1.0) < 0.30:
            return False, "SHOULDERS_NOT_VISIBLE"

        # Cho phep 1 bên khuyu tay hoac co tay bi che khuat khi 2 tay bat cheo ep sat truoc nguc (Map 5)
        # hoac khep sat truoc mat/sau dau (Map 3, Map 4):
        l_arm_vis = max(getattr(l_el, 'visibility', 1.0), getattr(l_wr, 'visibility', 1.0))
        r_arm_vis = max(getattr(r_el, 'visibility', 1.0), getattr(r_wr, 'visibility', 1.0))
        either_elbow_clear = max(getattr(l_el, 'visibility', 1.0), getattr(r_el, 'visibility', 1.0)) >= 0.25

        if l_arm_vis < 0.12 and not either_elbow_clear:
            return False, "LEFT_ARM_NOT_VISIBLE"

        if r_arm_vis < 0.12 and not either_elbow_clear:
            return False, "RIGHT_ARM_NOT_VISIBLE"

        # Kiem tra khoang cach va do lech tam
        shoulder_dist = self.calculate_2d_distance(l_sh, r_sh)
        center_x = (l_sh.x + r_sh.x) / 2.0

        if shoulder_dist > 0.45:
            return True, "MOVE_BACK"
        if shoulder_dist < 0.12:
            return True, "MOVE_CLOSER"
        if abs(center_x - 0.5) > 0.22:
            return True, "CENTER_YOUR_BODY"

        return True, "POSITION_OK"

    # ==========================
    # Calibration
    # ==========================
    def _evaluate_calibration_t_pose(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Calibration"""
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]
        l_hip, r_hip = lm[23], lm[24]

        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))

        # Xac dinh diem chuan truc doc than nguoi cho tung vai (ket hop truc hong va phuong thang dung)
        # giup phep do khong bi sai lech ngay ca khi ban lam viec che khuat mot phan hong
        l_down = LandmarkPoint(l_sh.x, l_sh.y + shoulder_width, l_sh.z)
        r_down = LandmarkPoint(r_sh.x, r_sh.y + shoulder_width, r_sh.z)
        if getattr(l_hip, 'visibility', 1.0) > 0.5 and getattr(r_hip, 'visibility', 1.0) > 0.5:
            l_ref = LandmarkPoint(0.4 * l_hip.x + 0.6 * l_down.x, 0.4 * l_hip.y + 0.6 * l_down.y, l_sh.z)
            r_ref = LandmarkPoint(0.4 * r_hip.x + 0.6 * r_down.x, 0.4 * r_hip.y + 0.6 * r_down.y, r_sh.z)
        else:
            l_ref = l_down
            r_ref = r_down

        # 1. Goc dang khop vai (Shoulder Abduction Angle) cua tay trai va tay phai
        l_upper_abd = self.calculate_angle(l_ref, l_sh, l_el)
        l_full_abd = self.calculate_angle(l_ref, l_sh, l_wr)
        l_abd_raw = 0.50 * l_upper_abd + 0.50 * l_full_abd

        r_upper_abd = self.calculate_angle(r_ref, r_sh, r_el)
        r_full_abd = self.calculate_angle(r_ref, r_sh, r_wr)
        r_abd_raw = 0.50 * r_upper_abd + 0.50 * r_full_abd

        # 2. Kiem tra do duoi thang cua khuyu tay (T-Pose yeu cau duoi thang canh tay sang 2 ben)
        l_el_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_el_angle = self.calculate_angle(r_sh, r_el, r_wr)

        # He so phat nhe neu nguoi choi gap khuyu tay (< 130 do) thay vi duoi thang sang ngang
        l_straight_factor = max(0.35, min(1.0, (l_el_angle - 75.0) / (135.0 - 75.0)))
        r_straight_factor = max(0.35, min(1.0, (r_el_angle - 75.0) / (135.0 - 75.0)))

        # 3. Kiem tra canh tay mo rong sang 2 ben (Lateral Spread) chu khong phai gio ra truoc mat
        l_lat_spread = abs(l_wr.x - l_sh.x) / shoulder_width
        r_lat_spread = abs(r_wr.x - r_sh.x) / shoulder_width
        l_spread_factor = max(0.30, min(1.0, l_lat_spread / 0.85))
        r_spread_factor = max(0.30, min(1.0, r_lat_spread / 0.85))

        # 4. Chuan hoa goc dang vai ve thang 0.0 -> 90.0 do (khi dang ngang vai 84 - 108 do -> dat chuan 90 do)
        def _normalize_t_angle(raw_deg: float, straight_f: float, spread_f: float) -> float:
            if raw_deg <= 15.0:
                return max(0.0, raw_deg * 0.5)
            # Neu nguoi choi gio qua cao tren dau (> 115 do), giam dan de nhac ha xuong ngang vai (90 do)
            if raw_deg > 110.0:
                effective_deg = max(60.0, 90.0 - (raw_deg - 110.0) * 0.6)
            elif raw_deg >= 83.0:
                # Vung ngang vai (83 -> 110 do) anh xa muot ve 88.0 -> 90.0 do
                effective_deg = 88.0 + min(2.0, (raw_deg - 83.0) * 0.2)
            else:
                effective_deg = (raw_deg - 15.0) / (83.0 - 15.0) * 88.0
            return round(max(0.0, min(90.0, effective_deg * straight_f * spread_f)), 1)

        l_rom_deg = _normalize_t_angle(l_abd_raw, l_straight_factor, l_spread_factor)
        r_rom_deg = _normalize_t_angle(r_abd_raw, r_straight_factor, r_spread_factor)
        combined_rom_deg = round((l_rom_deg + r_rom_deg) / 2.0, 1)

        is_t_pose_good = (l_rom_deg >= 65.0) and (r_rom_deg >= 65.0) and (l_el_angle >= 120.0) and (r_el_angle >= 120.0)
        feedback_code = "KEEP_POSITION" if is_t_pose_good else "OPEN_ARMS"

        return {
            "left_rom_value": l_rom_deg,
            "right_rom_value": r_rom_deg,
            "current_rom_value": combined_rom_deg,
            "rom_progress": round(combined_rom_deg / 90.0, 3),
            "form_valid": is_t_pose_good,
            "feedback_code": feedback_code,
        }

    # ==========================
    # Map 1
    # ==========================
    def _evaluate_map1_scapular_retraction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Map 1"""
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        # 1. KHOANG CACH 2D (x, y) GIUA 2 VAI LAM DON VI CHUAN HOA BAT BIEN
        shoulder_width = max(0.08, self.calculate_2d_distance(l_sh, r_sh))
        calib_factor = self._get_patient_calib_factor("scapular_retraction")

        # 2. XAC DINH HUONG KHUYU TAY HUONG XUONG DUOI VAI & DO HA THAP (2D x, y)
        l_el_drop = (l_el.y - l_sh.y) / shoulder_width
        r_el_drop = (r_el.y - r_sh.y) / shoulder_width
        avg_el_drop = (l_el_drop + r_el_drop) / 2.0
        elbows_pointing_down = (l_el.y > l_sh.y - 0.05 * shoulder_width) and (r_el.y > r_sh.y - 0.05 * shoulder_width)

        # Do roi cua co tay so voi khuyu tay (2D x, y)
        l_wr_drop = (l_wr.y - l_el.y) / shoulder_width
        r_wr_drop = (r_wr.y - r_el.y) / shoulder_width
        avg_wr_drop = (l_wr_drop + r_wr_drop) / 2.0

        # Khoang cach ngang giua 2 co tay va 2 khuyu tay (2D x, y)
        wrist_dist = self.calculate_2d_distance(l_wr, r_wr)
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        wrist_ratio = wrist_dist / shoulder_width
        elbow_ratio = elbow_dist / shoulder_width

        # Chieu dai hinh chieu 2D cua cang tay (tu khuyu den co tay) - chong gian lan trung diem
        l_forearm_2d = self.calculate_2d_distance(l_el, l_wr) / shoulder_width
        r_forearm_2d = self.calculate_2d_distance(r_el, r_wr) / shoulder_width
        eff_forearm_2d = 0.65 * min(l_forearm_2d, r_forearm_2d) + 0.35 * ((l_forearm_2d + r_forearm_2d) / 2.0)
        forearms_not_collapsed = (l_forearm_2d >= 0.08) and (r_forearm_2d >= 0.08)

        # Goc khuyu tay 2D (Vai - Khuyu - Co tay)
        l_el_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_el_angle = self.calculate_angle(r_sh, r_el, r_wr)
        avg_el_angle = (l_el_angle + r_el_angle) / 2.0

        # Kiem tra an toan co ban (khong gio cao qua dau, khong bat cheo tay qua nguc Map 5)
        hands_not_overhead = (l_wr.y > l_sh.y - 0.15 * shoulder_width) and (r_wr.y > r_sh.y - 0.15 * shoulder_width)
        mid_x = (l_sh.x + r_sh.x) / 2.0
        sh_sign = 1.0 if (l_sh.x - r_sh.x) >= 0 else -1.0
        no_arm_cross = (
            ((l_wr.x - mid_x) * sh_sign > -0.12 * shoulder_width) and
            ((r_wr.x - mid_x) * (-sh_sign) > -0.12 * shoulder_width)
        )
        wrists_separated = (0.24 <= wrist_ratio <= 1.95)

        # 3. DO SAU 3D (x, y, z): 2 KHUYU TAY LUI SAU SO VOI 2 DIEM VAI
        l_z_diff = l_el.z - l_sh.z
        r_z_diff = r_el.z - r_sh.z
        z_el_diff = 0.65 * max(l_z_diff, r_z_diff) + 0.35 * min(l_z_diff, r_z_diff)

        # =========================================================================
        # PHAN 1: NHAN DIEN DONG TAC 1 - DONG TAC CHUAN BI (HINH 1)
        # - De 2 tay xuoi xuong thoai mai hoac dua 2 tay ra truoc mat.
        # - Khong ep khuyu tay lui ra sau lung (z_el_diff <= 0.035).
        # =========================================================================
        is_arms_forward = (avg_el_angle >= 105.0) and (z_el_diff <= 0.035) and (l_wr.z < l_sh.z + 0.05)
        is_arms_relaxed_down = (avg_el_drop >= 0.28) and (avg_wr_drop >= 0.10) and (z_el_diff <= 0.035)
        is_prep_pose = hands_not_overhead and elbows_pointing_down and no_arm_cross and (is_arms_forward or is_arms_relaxed_down)

        if is_prep_pose:
            prep_score = 1.0
        else:
            # Diem tien ve 1.0 chi khi tay thuc su duoi thang/buong xuoi va khong ep lui sau
            # Tranh hien tuong tay dang gap 90 do ma prep_score nhay len 92%
            score_fwd = max(0.0, min(1.0, (avg_el_angle - 90.0) / (135.0 - 90.0)))
            score_unretracted = max(0.0, min(1.0, (0.02 - z_el_diff) / 0.04))
            prep_score = round(score_fwd * score_unretracted, 3)

        # =========================================================================
        # PHAN 2: NHAN DIEN DONG TAC 2 - DONG TAC GIU 0.7S (HINH 2)
        # - 2 khuyu tay ha thap xap xi 2/3 khoang cach 2 vai (calibrated): target_drop ~ 0.18 - 0.65 vai.
        # - Gap khuyu tay 90 do (thang goc voi than).
        # - Ep 2 khuyu tay lui ve phia sau lung (3D z_el_diff tang manh).
        # =========================================================================
        # a) Do ha thap khuyu tay so voi vai (2D x, y):
        # 2 khuyu tay ha thap xap xi 2/3 vai: dat diem toi da khi ha thap tu 0.18 vai tro len
        if avg_el_drop >= 0.18:
            score_drop = min(1.0, (avg_el_drop - 0.05) / 0.18)
        else:
            score_drop = max(0.0, avg_el_drop / 0.18)

        # Khoang cach 2D tu vai den khuyu tay (Chieu dai hinh chieu canh tay tren):
        l_el_sh_dist = self.calculate_2d_distance(l_sh, l_el) / shoulder_width
        r_el_sh_dist = self.calculate_2d_distance(r_sh, r_el) / shoulder_width
        avg_el_sh_dist = (l_el_sh_dist + r_el_sh_dist) / 2.0

        # DE XUAT 2: Khoang cach tu khuyu tay den vai phai xap xi bang 2/3 khoang cach giua 2 vai (2/3 ~ 0.667):
        target_arm_ratio = 2.0 / 3.0  # 0.667
        arm_ratio_diff = abs(avg_el_sh_dist - target_arm_ratio)
        score_arm_len = max(0.0, min(1.0, 1.0 - max(0.0, arm_ratio_diff - 0.08) / 0.25))

        # Goc gap khuyu tay 90 do ket hop dieu kien khoang cach khuyu - vai xap xi 2/3 vai:
        score_angle_raw = max(0.0, min(1.0, 1.0 - max(0.0, abs(avg_el_angle - 90.0) - 10.0) / 35.0))
        score_elbow_90 = score_angle_raw * (0.35 + 0.65 * score_arm_len)

        # c) Do sau 3D ep 2 khuyu tay ra sau lung:
        score_z_retraction = max(0.0, min(1.0, (z_el_diff - (-0.015)) / (0.035 - (-0.015))))

        # d) Chieu dai cang tay 2D khong bi trung diem:
        score_fa_valid = 1.0 if forearms_not_collapsed else 0.0

        # Form hop le cho dong tac giu:
        form_valid = (
            hands_not_overhead and
            elbows_pointing_down and
            no_arm_cross and
            wrists_separated and
            forearms_not_collapsed and
            (avg_el_drop >= 0.05) and
            (0.35 <= avg_el_sh_dist <= 0.95)
        )

        if not form_valid:
            raw_hold = 0.0
            hold_rom = 0.0
            current_rom_value = 0.0
        else:
            raw_hold = (
                0.45 * score_z_retraction +
                0.35 * score_elbow_90 +
                0.20 * score_drop
            ) * score_fa_valid
            hold_rom = self._scale_rom_with_calibration("scapular_retraction", raw_hold)
            current_rom_value = hold_rom * 90.0

        is_hold_pose = (
            (hold_rom >= 0.88 or (score_z_retraction >= 0.65 and score_elbow_90 >= 0.55 and score_drop >= 0.50))
            and form_valid
        )

        # ROM tong the: khi o the chuan bi xuat prep_score; khi dang ep xuat hold_rom
        rom_progress = hold_rom if (hold_rom > 0.15) else (1.0 if is_prep_pose else prep_score)

        return {
            "angles": {
                "elbow_angle": round(avg_el_angle, 1),
                "elbow_drop": round(avg_el_drop, 2),
                "elbow_shoulder_dist": round(avg_el_sh_dist, 2),
                "score_arm_len": round(score_arm_len, 2),
                "elbow_z_diff": round(z_el_diff, 3),
                "wrist_dist": round(wrist_ratio, 2),
                "elbow_dist": round(elbow_ratio, 2),
                "forearm_2d": round(eff_forearm_2d, 2),
                "score_drop": round(score_drop, 2),
                "score_elbow_90": round(score_elbow_90, 2),
                "score_z_retraction": round(score_z_retraction, 2),
                "prep_score": round(prep_score, 2),
                "hold_rom": round(hold_rom, 2),
            },
            "prep_score": round(prep_score, 3),
            "prep_rom": round(prep_score, 3),
            "is_prep_pose": is_prep_pose,
            "hold_rom": round(hold_rom, 3),
            "is_hold_pose": is_hold_pose,
            "form_valid": form_valid,
            "rom_progress": round(rom_progress, 3),
            "current_rom_value": round(current_rom_value, 1),
            "target_depth": 0.05,
        }

    # ==========================
    # Map 2
    # ==========================
    def _evaluate_map2_wall_abduction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Map 2"""
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        # Chieu rong 2 vai 2D (x, y) lam don vi chuan hoa bat bien theo khoang cach camera
        shoulder_width = max(0.08, self.calculate_2d_distance(l_sh, r_sh))
        shoulder_tilt = abs(l_sh.y - r_sh.y) / shoulder_width

        # Vector tham chieu doc than 2D (x, y) tu vai huong thang xuong duoi
        # (khong phu thuoc vao hip 23, 24 vi webcam thuong chi quay nua tren co the)
        l_down = LandmarkPoint(x=l_sh.x, y=l_sh.y + shoulder_width, z=0.0)
        r_down = LandmarkPoint(x=r_sh.x, y=r_sh.y + shoulder_width, z=0.0)

        # Vector tham chieu huong thang len tren tai khuyu tay 2D (x, y) de do do dung thang cua cang tay
        l_el_up = LandmarkPoint(x=l_el.x, y=l_el.y - shoulder_width, z=0.0)
        r_el_up = LandmarkPoint(x=r_el.x, y=r_el.y - shoulder_width, z=0.0)

        # --- CAC DAC TRUNG HINH HOC 2D (x, y) ---
        # 1. Goc dang canh tay 2D so voi truc doc than (Down - Vai - Khuyu)
        l_sh_angle = self.calculate_angle(l_down, l_sh, l_el)
        r_sh_angle = self.calculate_angle(r_down, r_sh, r_el)
        avg_sh_angle = (l_sh_angle + r_sh_angle) / 2.0

        # 2. Goc khuyu tay 2D (Vai - Khuyu - Co tay)
        l_el_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_el_angle = self.calculate_angle(r_sh, r_el, r_wr)
        avg_el_angle = (l_el_angle + r_el_angle) / 2.0

        # 3. Goc lech cua cang tay so voi phuong thang dung huong len (0 do = cang tay dung thang len tren)
        l_forearm_vert = self.calculate_angle(l_el_up, l_el, l_wr)
        r_forearm_vert = self.calculate_angle(r_el_up, r_el, r_wr)
        avg_forearm_vert = (l_forearm_vert + r_forearm_vert) / 2.0

        # 4. Khoang cach 2D va do cao tuong doi tren truc Y
        d_el_2d = self.calculate_2d_distance(l_el, r_el)
        d_wr_2d = self.calculate_2d_distance(l_wr, r_wr)
        elbow_ratio = d_el_2d / shoulder_width
        wrist_ratio = d_wr_2d / shoulder_width

        l_wrist_reach = (l_sh.y - l_wr.y) / shoulder_width
        r_wrist_reach = (r_sh.y - r_wr.y) / shoulder_width
        avg_wrist_reach = (l_wrist_reach + r_wrist_reach) / 2.0

        l_elbow_reach = (l_sh.y - l_el.y) / shoulder_width
        r_elbow_reach = (r_sh.y - r_el.y) / shoulder_width
        avg_elbow_reach = (l_elbow_reach + r_elbow_reach) / 2.0

        l_forearm_rise = (l_el.y - l_wr.y) / shoulder_width
        r_forearm_rise = (r_el.y - r_wr.y) / shoulder_width
        min_forearm_rise = min(l_forearm_rise, r_forearm_rise)

        wrists_above_elbows = (l_forearm_rise >= 0.25) and (r_forearm_rise >= 0.25)
        wrists_above_shoulders = (l_wrist_reach >= 0.20) and (r_wrist_reach >= 0.20)

        # =========================================================================
        # PHAN 1: NHAN DIEN DONG TAC 1 - DONG TAC CHUAN BI (HINH 1)
        # - Dung thang, canh tay dang vua (~60 - 108 do).
        # - Cang tay tao voi canh tay goc ~90 do (~62 - 112 do) va huong thang len tren.
        # =========================================================================
        def _band_score(val: float, low_zero: float, ideal_low: float, ideal_high: float, high_zero: float) -> float:
            if ideal_low <= val <= ideal_high:
                return 1.0
            if val < ideal_low:
                return max(0.0, (val - low_zero) / max(1e-5, ideal_low - low_zero))
            return max(0.0, (high_zero - val) / max(1e-5, high_zero - ideal_high))

        # a) Diem dang vua canh tay (chuan Hinh 1: ~80.1 do)
        l_sh_prep = _band_score(l_sh_angle, 25.0, 62.0, 106.0, 132.0)
        r_sh_prep = _band_score(r_sh_angle, 25.0, 62.0, 106.0, 132.0)
        score_sh_prep = 0.5 * (l_sh_prep + r_sh_prep)

        # b) Diem goc vuong 90 do giua cang tay va canh tay (chuan Hinh 1: ~81.7 do)
        l_el_prep = _band_score(l_el_angle, 40.0, 64.0, 108.0, 148.0)
        r_el_prep = _band_score(r_el_angle, 40.0, 64.0, 108.0, 148.0)
        score_el_prep = 0.5 * (l_el_prep + r_el_prep)

        # c) Diem cang tay huong thang len tren (chuan Hinh 1: forearm_rise ~0.68, forearm_vert ~3.9 do)
        rise_sc = max(0.0, min(1.0, (min_forearm_rise - 0.10) / (0.42 - 0.10)))
        vert_sc = max(0.0, min(1.0, (55.0 - max(l_forearm_vert, r_forearm_vert)) / (55.0 - 26.0)))
        score_up_prep = 0.55 * rise_sc + 0.45 * vert_sc

        # d) Diem mo rong 2 khuyu tay va 2 ban tay sang 2 ben (chong nhan nham voi dan tay sau gay Map 4)
        spread_el_sc = max(0.0, min(1.0, (elbow_ratio - 1.05) / (1.55 - 1.05)))
        spread_wr_sc = max(0.0, min(1.0, (wrist_ratio - 1.00) / (1.50 - 1.00)))
        score_spread_prep = 0.5 * (spread_el_sc + spread_wr_sc)

        raw_prep_score = score_sh_prep * (
            0.40 * score_el_prep +
            0.35 * score_up_prep +
            0.25 * score_spread_prep
        )

        is_prep_pose = (
            (shoulder_tilt <= 0.25) and
            wrists_above_elbows and
            wrists_above_shoulders and
            (58.0 <= l_sh_angle <= 110.0) and
            (58.0 <= r_sh_angle <= 110.0) and
            (62.0 <= l_el_angle <= 112.0) and
            (62.0 <= r_el_angle <= 112.0) and
            (l_forearm_rise >= 0.35) and
            (r_forearm_rise >= 0.35) and
            (l_forearm_vert <= 32.0) and
            (r_forearm_vert <= 32.0) and
            (-0.35 <= l_elbow_reach <= 0.28) and
            (-0.35 <= r_elbow_reach <= 0.28) and
            (elbow_ratio >= 1.45) and
            (wrist_ratio >= 1.35)
        )

        if is_prep_pose:
            prep_rom = 1.0
        else:
            prep_rom = round(min(0.92, max(0.0, raw_prep_score)), 3)

        # =========================================================================
        # PHAN 2: NHAN DIEN DONG TAC 2 - DONG TAC GIU 5 GIAY (HINH 2)
        # - Duoi cang tay va dang canh tay ve phia dau - giu 5 giay.
        # - ROM tang dan deu theo goc noi/duoi cua khuyu tay nguoi tap (tu 90 do len 180 do
        #   o bien do hieu chinh Calibration 90 do).
        #   Trong khong gian 2D MediaPipe (x, y):
        #   + Tai Hinh 1 (goc khuyu vuong 90 do): avg_el_angle ~ 81.7 - 86.0 do -> Quy doi = 90.0 do (0% ROM).
        #   + Tai Hinh 2 (duoi cang tay ve phia dau 180 do): avg_el_angle ~ 148.0 - 154.3 do -> Quy doi = 180.0 do (100% ROM).
        # =========================================================================
        ELBOW_2D_90_DEG = 86.0
        ELBOW_2D_180_DEG = 148.0

        l_el_ext_ratio = max(0.0, min(1.0, (l_el_angle - ELBOW_2D_90_DEG) / (ELBOW_2D_180_DEG - ELBOW_2D_90_DEG)))
        r_el_ext_ratio = max(0.0, min(1.0, (r_el_angle - ELBOW_2D_90_DEG) / (ELBOW_2D_180_DEG - ELBOW_2D_90_DEG)))
        elbow_ext_ratio = 0.5 * (l_el_ext_ratio + r_el_ext_ratio)

        # Goc khuyu tay quy doi chuan y khoa (90.0 do -> 180.0 do)
        clinical_el_angle = 90.0 + 90.0 * elbow_ext_ratio

        # Ap dung he so bien do hieu chinh Calibration (tai Calibration = 90 do -> calib_factor = 1.0 -> can du 90->180 do)
        calib_factor = self._get_patient_calib_factor("wall_abduction_external_rotation")
        target_ext_ratio = max(0.65, min(1.0, calib_factor))
        calibrated_elbow_rom = max(0.0, min(1.0, elbow_ext_ratio / target_ext_ratio))

        # Kiem tra huong dang canh tay ve phia dau 2D (x, y) de chong nhan nham T-pose (dang ngang) hoac ha tay xuong:
        # Khi duoi cang tay ve phia dau (Hinh 1 -> Hinh 2):
        # + avg_sh_angle tang tu ~80 do len ~135 - 152 do
        # + avg_elbow_reach tang tu ~-0.11 len ~+0.38 - +0.60
        # + avg_wrist_reach tang tu ~+0.57 len ~+1.10 - +1.31
        sh_overhead_ratio = max(0.0, min(1.0, (avg_sh_angle - 80.0) / ((134.0 * target_ext_ratio) - 80.0)))
        el_overhead_ratio = max(0.0, min(1.0, (avg_elbow_reach - (-0.12)) / ((0.38 * target_ext_ratio) - (-0.12))))
        wr_overhead_ratio = max(0.0, min(1.0, (avg_wrist_reach - 0.55) / ((1.10 * target_ext_ratio) - 0.55)))
        overhead_direction_ratio = (
            0.40 * sh_overhead_ratio +
            0.30 * el_overhead_ratio +
            0.30 * wr_overhead_ratio
        )

        # Dieu kien nghiem ngat loai bo tu the sai / lech hoan toan (chi dung 2D x, y):
        # - Co tay phai cao hon khuyu tay va cao hon vai
        # - Canh tay phai dang len (khong xuoi tay doc than)
        # - 2 ban tay khong dan chat sau gay (wrist_ratio >= 0.85) va khong dang ngang T-pose (wrist_reach phai >= 0.45)
        # - 2 tay phai van dong dong deu (khong chi gio 1 tay)
        arms_symmetric = (abs(l_el_angle - r_el_angle) <= 38.0) and (abs(l_sh_angle - r_sh_angle) <= 35.0)
        valid_overhead_trajectory = (
            (shoulder_tilt <= 0.28) and
            wrists_above_elbows and
            (l_wrist_reach >= 0.42) and
            (r_wrist_reach >= 0.42) and
            (l_sh_angle >= 62.0) and
            (r_sh_angle >= 62.0) and
            (wrist_ratio >= 0.85) and
            (elbow_ratio >= 0.95) and
            arms_symmetric
        )

        if not valid_overhead_trajectory or calibrated_elbow_rom <= 0.01:
            hold_rom = 0.0
            is_hold_pose = False
        else:
            # Neu nguoi tap duoi khuyu tay sang ngang (T-pose) ma khong dang canh tay ve phia dau
            # (overhead_direction_ratio thap hon nhieu so voi calibrated_elbow_rom), gioi han ROM ngay lap tuc:
            if overhead_direction_ratio < calibrated_elbow_rom - 0.22:
                raw_hold_rom = min(calibrated_elbow_rom, overhead_direction_ratio * 0.80)
            else:
                # Khi nguoi tap vua duoi cang tay vua dang canh tay ve phia dau dung chuan:
                # ROM tang dan deu tuyen tinh theo goc noi cua khuyu tay (90 -> 180 do)!
                raw_hold_rom = 0.78 * calibrated_elbow_rom + 0.22 * overhead_direction_ratio

            if raw_hold_rom >= 0.94:
                hold_rom = 1.0
            else:
                hold_rom = round(max(0.0, min(1.0, raw_hold_rom / 0.94)), 3)

            min_el_2d_hold = ELBOW_2D_90_DEG + (ELBOW_2D_180_DEG - ELBOW_2D_90_DEG) * (0.85 * target_ext_ratio)
            min_sh_2d_hold = 80.0 + (132.0 - 80.0) * (0.82 * target_ext_ratio)
            is_hold_pose = (
                (hold_rom >= 0.95) and
                (l_el_angle >= min_el_2d_hold) and
                (r_el_angle >= min_el_2d_hold) and
                (l_sh_angle >= min_sh_2d_hold) and
                (r_sh_angle >= min_sh_2d_hold) and
                (l_elbow_reach >= 0.20 * target_ext_ratio) and
                (r_elbow_reach >= 0.20 * target_ext_ratio) and
                (l_wrist_reach >= 0.92 * target_ext_ratio) and
                (r_wrist_reach >= 0.92 * target_ext_ratio) and
                (0.90 <= wrist_ratio <= 2.35)
            )
            if is_hold_pose:
                hold_rom = 1.0

        reach_score = 0.65 * avg_wrist_reach + 0.35 * avg_elbow_reach
        form_valid = is_prep_pose or valid_overhead_trajectory
        current_rom_value = round(clinical_el_angle, 1)

        return {
            "angles": {
                "prep_score": round(prep_rom, 2),
                "prep_rom": round(prep_rom, 2),
                "is_prep_pose": is_prep_pose,
                "reach_score": round(reach_score, 2),
                "avg_wrist_reach": round(avg_wrist_reach, 2),
                "avg_elbow_reach": round(avg_elbow_reach, 2),
                "avg_sh_angle": round(avg_sh_angle, 1),
                "avg_el_angle": round(avg_el_angle, 1),
                "clinical_el_angle": round(clinical_el_angle, 1),
                "avg_forearm_vert": round(avg_forearm_vert, 1),
                "elbow_ratio": round(elbow_ratio, 2),
                "wrist_ratio": round(wrist_ratio, 2),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": round(hold_rom, 3),
            "prep_score": prep_rom,
            "prep_rom": prep_rom,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "reach_score": reach_score,
            "current_rom_value": current_rom_value,
            "target_angle": 180.0,
        }

    # ==========================
    # Map 3
    # ==========================
    def _evaluate_map3_horizontal_shoulder_adduction(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Map 3"""
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        # 1. Khoang cach 2D (x, y) giua 2 ba vai, 2 khuyu tay va 2 co tay
        distance_shoulder = max(0.08, self.calculate_2d_distance(l_sh, r_sh))
        distance_elbow = self.calculate_2d_distance(l_el, r_el)
        distance_wrist = self.calculate_2d_distance(l_wr, r_wr)

        elbow_ratio = distance_elbow / distance_shoulder
        wrist_ratio = distance_wrist / distance_shoulder
        shoulder_tilt = abs(l_sh.y - r_sh.y) / distance_shoulder

        # 2. He so Calibration (do truoc khi tap, chuan 90 do -> calib_factor = 1.0)
        calib_factor = self._get_patient_calib_factor("horizontal_shoulder_adduction")
        calib_clamped = max(0.65, min(1.0, calib_factor))

        # 3. Do cao 2D (x, y) cua khuyu tay va co tay so voi diem vai
        sh_y_avg = (l_sh.y + r_sh.y) / 2.0
        el_y_avg = (l_el.y + r_el.y) / 2.0
        wr_y_avg = (l_wr.y + r_wr.y) / 2.0

        el_sh_y_diff = abs(el_y_avg - sh_y_avg) / distance_shoulder
        l_el_sh_diff = abs(l_sh.y - l_el.y) / distance_shoulder
        r_el_sh_diff = abs(r_sh.y - r_el.y) / distance_shoulder

        wrist_height_sh = (sh_y_avg - wr_y_avg) / distance_shoulder
        wrist_height_el = (el_y_avg - wr_y_avg) / distance_shoulder
        min_wr_sh_rise = min(l_sh.y - l_wr.y, r_sh.y - r_wr.y) / distance_shoulder

        # Xac dinh do vuon len/ha xuong cua khuyu tay so voi vai tren truc Y (cho ca 2 giai doan)
        l_elbow_reach = (l_sh.y - l_el.y) / distance_shoulder
        r_elbow_reach = (r_sh.y - r_el.y) / distance_shoulder
        avg_elbow_reach = (l_elbow_reach + r_elbow_reach) / 2.0

        max_elbow_drop = 0.32 + 0.25 * (1.0 - calib_clamped)
        max_elbow_rise = 0.30
        elbows_near_shoulder_level = (
            (-max_elbow_drop <= l_elbow_reach <= max_elbow_rise) and
            (-max_elbow_drop <= r_elbow_reach <= max_elbow_rise)
        )

        # 4. Xac dinh huong tu khuyu tay len ban tay huong thang len ben phia tren vai (2D x, y)
        l_forearm_rise = (l_el.y - l_wr.y) / distance_shoulder
        r_forearm_rise = (r_el.y - r_wr.y) / distance_shoulder
        min_forearm_rise = min(l_forearm_rise, r_forearm_rise)

        l_wrist_reach = (l_sh.y - l_wr.y) / distance_shoulder
        r_wrist_reach = (r_sh.y - r_wr.y) / distance_shoulder
        avg_wrist_reach = (l_wrist_reach + r_wrist_reach) / 2.0

        l_el_up = LandmarkPoint(x=l_el.x, y=l_el.y - distance_shoulder, z=0.0)
        r_el_up = LandmarkPoint(x=r_el.x, y=r_el.y - distance_shoulder, z=0.0)
        l_forearm_vert = self.calculate_angle(l_el_up, l_el, l_wr)
        r_forearm_vert = self.calculate_angle(r_el_up, r_el, r_wr)
        avg_forearm_vert = (l_forearm_vert + r_forearm_vert) / 2.0

        l_elbow_angle = self.calculate_angle(l_sh, l_el, l_wr)
        r_elbow_angle = self.calculate_angle(r_sh, r_el, r_wr)
        avg_el_angle = (l_elbow_angle + r_elbow_angle) / 2.0

        wrists_above_elbows = (l_forearm_rise >= 0.32) and (r_forearm_rise >= 0.32)
        wrists_above_shoulders = (l_wrist_reach >= 0.22) and (r_wrist_reach >= 0.22)
        forearms_pointing_up = (l_forearm_vert <= 42.0) and (r_forearm_vert <= 42.0)

        # Do can doi 2 tay so voi truc giua 2 vai tren truc X
        sh_mid_x = 0.5 * (l_sh.x + r_sh.x)
        el_mid_x = 0.5 * (l_el.x + r_el.x)
        wr_mid_x = 0.5 * (l_wr.x + r_wr.x)
        center_offset = max(abs(el_mid_x - sh_mid_x), abs(wr_mid_x - sh_mid_x)) / distance_shoulder

        # =========================================================================
        # PHAN 1: NHAN DIEN DONG TAC 1 - DONG TAC CHUAN BI (HINH 1)
        # Theo dung de xuat va phan tich co sinh hoc cua Lan:
        # 1. 2 khuyu tay khep lai xap xi duoi 1/2 khoang cach 2 diem vai (elbow_ratio <= 0.72, chuan <= 0.50)
        # 2. 2 khuyu tay co do cao xap xi bang diem vai (el_sh_y_diff <= 0.28)
        # 3. 2 diem co tay cao hon xap xi 1/2 khoang cach 2 vai (wrist_height_sh >= 0.40, wrist_height_el >= 0.40)
        # 4. 2 ban tay nam up khep vao nhau phia truoc (wrist_ratio <= 0.70)
        # Bat bien va mien nhiem 100% voi loi MediaPipe hoan doi diem co tay 15 <-> 16.
        # =========================================================================
        is_elbows_closed = (elbow_ratio <= 0.72)
        elbows_at_sh_level = (el_sh_y_diff <= 0.28) and (l_el_sh_diff <= 0.35) and (r_el_sh_diff <= 0.35)
        wrists_higher_than_shoulders = (wrist_height_sh >= 0.40) and (min_wr_sh_rise >= 0.25)
        wrists_higher_than_elbows = (wrist_height_el >= 0.40)
        is_wrists_closed = (wrist_ratio <= 0.70)

        is_prep_pose = (
            is_elbows_closed and
            elbows_at_sh_level and
            wrists_higher_than_shoulders and
            wrists_higher_than_elbows and
            is_wrists_closed and
            (shoulder_tilt <= 0.30)
        )

        score_elbow_close = max(0.0, min(1.0, (1.40 - elbow_ratio) / (1.40 - 0.50)))
        score_elbow_level = max(0.0, min(1.0, 1.0 - el_sh_y_diff / 0.30))
        score_wrist_up = max(0.0, min(1.0, (wrist_height_sh - 0.15) / (0.50 - 0.15)))
        score_close_wrist = max(0.0, min(1.0, (1.20 - wrist_ratio) / (1.20 - 0.40)))
        raw_prep_score = score_elbow_close * score_elbow_level * score_wrist_up * (0.60 + 0.40 * score_close_wrist)

        if is_prep_pose:
            prep_rom = 1.0
        else:
            prep_rom = round(min(0.95, max(0.0, raw_prep_score)), 3)

        # =========================================================================
        # PHAN 2: NHAN DIEN DONG TAC 2 - DONG TAC GIU 5 GIAY (HINH 2)
        # - Dang canh tay sang 2 ben (nhieu nhat co the) - giu 5 giay.
        # - ROM tang dan deu theo khoang cach 2D giua 2 khuyu tay:
        #   Tu khoang cach nho o the chuan bi (START_ELBOW_RATIO = 0.50)
        #   den xap xi gap doi khoang cach 2 ba vai (target_elbow_ratio ~ 2.00 * distance_shoulder,
        #   do xap xi phu thuoc vao Calibration khi do truoc khi tap; Hinh 2 thuc te = 2.40).
        # =========================================================================
        START_ELBOW_RATIO = 0.50
        # Khi Calibration dat 90 do (calib_clamped = 1.0) -> target_elbow_ratio = 2.00 (gap doi distance_shoulder)
        # Khi Calibration thap hon 90 do -> target_elbow_ratio giam tuong ung (tu 1.72 den 2.00)
        target_elbow_ratio = 2.00 * (0.72 + 0.28 * calib_clamped)

        raw_elbow_open_rom = max(
            0.0,
            min(1.0, (elbow_ratio - START_ELBOW_RATIO) / max(0.20, target_elbow_ratio - START_ELBOW_RATIO)),
        )

        # Kiem tra nghiem ngat tu the dung cua bai tap Map 3 trong suot qua trinh mo 2 khuyu tay:
        # 1. Khuyu tay phai xap xi ngang bang diem vai (elbows_near_shoulder_level -> canh tay ngang vai)
        #    -> Loai bo Map 1 (khuyu tay ha thap sat suon) va Map 2 (khuyu tay nhac cao tren dau > 0.28).
        # 2. Cang tay va ban tay phai huong thang len phia tren vai (wrists_above_elbows, wrists_above_shoulders, forearms_pointing_up)
        #    -> Ket hop voi canh tay ngang vai dam bao goc gap khuyu tay luon vuong ~90 do trong 3D ma khong bi suy bien
        #       khi khuyu tay di ngang qua diem vai tren mat phang 2D! Loai bo hoan toan T-pose va ha tay xuong.
        # 3. 2 ban tay phai mo rong sang 2 ben cung 2 khuyu tay (khong chum sau gay nhu Map 4)
        hands_open_with_elbows = (elbow_ratio < 1.05) or (wrist_ratio >= 0.65 * elbow_ratio)
        # 4. Hai tay mo doi xung sang 2 ben
        arms_symmetric = center_offset <= 0.38

        valid_open_trajectory = (
            (shoulder_tilt <= 0.30) and
            elbows_near_shoulder_level and
            wrists_above_elbows and
            wrists_above_shoulders and
            forearms_pointing_up and
            hands_open_with_elbows and
            arms_symmetric
        )

        if (not valid_open_trajectory) or (raw_elbow_open_rom <= 0.01):
            hold_rom = 0.0
            is_hold_pose = False
        else:
            if raw_elbow_open_rom >= 0.95:
                hold_rom = 1.0
            else:
                hold_rom = round(max(0.0, min(1.0, raw_elbow_open_rom / 0.95)), 3)

            is_hold_pose = (
                (hold_rom >= 0.95) and
                (elbow_ratio >= target_elbow_ratio * 0.92) and
                (wrist_ratio >= target_elbow_ratio * 0.75) and
                valid_open_trajectory
            )
            if is_hold_pose:
                hold_rom = 1.0

        chest_open_score = 0.55 * elbow_ratio + 0.45 * wrist_ratio
        form_valid = is_prep_pose or valid_open_trajectory

        return {
            "angles": {
                "prep_score": round(prep_rom, 2),
                "prep_rom": round(prep_rom, 2),
                "is_prep_pose": is_prep_pose,
                "chest_open_score": round(chest_open_score, 2),
                "elbow_ratio": round(elbow_ratio, 2),
                "wrist_ratio": round(wrist_ratio, 2),
                "target_elbow_ratio": round(target_elbow_ratio, 2),
                "avg_elbow_reach": round(avg_elbow_reach, 2),
                "avg_wrist_reach": round(avg_wrist_reach, 2),
                "avg_forearm_vert": round(avg_forearm_vert, 1),
                "avg_el_angle": round(avg_el_angle, 1),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": round(hold_rom, 3),
            "prep_score": prep_rom,
            "prep_rom": prep_rom,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "current_rom_value": round(elbow_ratio * 45.0, 1),
            "target_ratio": round(target_elbow_ratio, 2),
        }

    # ==========================
    # Map 4
    # ==========================
    def _evaluate_map4_hands_behind_head(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Map 4"""
        l_ear, r_ear = lm[7], lm[8]
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        # 1. Khoang cach 2D chuan hoa theo khoang cach 2 ba vai (distance_shoulder)
        shoulder_width = max(0.01, self.calculate_2d_distance(l_sh, r_sh))
        elbow_dist = self.calculate_2d_distance(l_el, r_el)
        wrist_dist = self.calculate_2d_distance(l_wr, r_wr)

        elbow_ratio = elbow_dist / shoulder_width
        wrist_ratio = wrist_dist / shoulder_width

        st_map4 = self.exercise_states.get("hands_behind_head", {})
        curr_state = st_map4.get("movement_state", "ready")

        # He so Calibration cua nguoi tap (0.0 -> 1.0, mac dinh ~0.75)
        calib_factor = self._get_patient_calib_factor("hands_behind_head")
        # Nguoi co ROM vai han che (calib_factor thap) duoc nới lỏng sai so do cao khuyu tay so voi tai
        ear_height_tol = 0.42 + (1.0 - min(1.0, calib_factor)) * 0.20  # ~0.42 -> 0.52 sw

        # 2. Xac dinh 2 diem tai (lm[7], lm[8]) tren mat phang 2D
        ears_visible = (l_ear.visibility >= 0.25) and (r_ear.visibility >= 0.25)
        if ears_visible:
            l_ear_y, r_ear_y = l_ear.y, r_ear.y
            l_ear_x, r_ear_x = l_ear.x, r_ear.x
        else:
            # Fallback 2D uoc luong vi tri tai tu vai neu camera tam thoi khuat diem tai
            l_ear_y = l_sh.y - 0.44 * shoulder_width
            r_ear_y = r_sh.y - 0.44 * shoulder_width
            l_ear_x = l_sh.x - 0.15 * shoulder_width
            r_ear_x = r_sh.x + 0.15 * shoulder_width

        # Do lech do cao 2D giua Khuyu tay va Tai: (ear.y - el.y) / sw
        # Gia tri ~ 0.0 nghia la khuyu tay ngang bang tai; > 0 la khuyu tay cao hon tai; < 0 la thap hon tai.
        # Hinh 1: L = +0.11, R = +0.13 (Avg = +0.12)
        # Hinh 2: L = +0.21, R = +0.12 (Avg = +0.17)
        l_el_ear_diff = (l_ear_y - l_el.y) / shoulder_width
        r_el_ear_diff = (r_ear_y - r_el.y) / shoulder_width
        avg_el_ear_diff = 0.5 * (l_el_ear_diff + r_el_ear_diff)

        # Do cao 2D cua Khuyu tay so voi Vai: (sh.y - el.y) / sw (duong khi khuyu tay cao hon vai)
        # Hinh 1: +0.56 | Hinh 2: +0.58 (phan biet ro voi Map 3 khi khuyu tay chi ngang vai ~ 0.0)
        l_el_sh_elev = (l_sh.y - l_el.y) / shoulder_width
        r_el_sh_elev = (r_sh.y - r_el.y) / shoulder_width
        avg_el_sh_elev = 0.5 * (l_el_sh_elev + r_el_sh_elev)

        # Kiem tra 2 khuyu tay ngang bang do cao voi 2 diem tai (co tinh den Calibration):
        # Khuyu tay phai nang cao hon vai va nam trong dai do cao cua tai [-ear_height_tol, +0.50]
        elbows_at_ear_height = (
            (l_el_ear_diff >= -ear_height_tol) and (l_el_ear_diff <= 0.52) and
            (r_el_ear_diff >= -ear_height_tol) and (r_el_ear_diff <= 0.52) and
            (avg_el_sh_elev >= 0.05) and
            (l_el_sh_elev >= -0.05) and (r_el_sh_elev >= -0.05)
        )

        # 3. Kiem tra 2 co tay (lm[15], lm[16]) nam ben canh 2 diem tai (lm[7], lm[8]) VA xu ly che khuat:
        # Khoang cach 2D tu co tay den tai cung ben (hoac tai gan nhat)
        l_wr_ear_dist = math.hypot(l_wr.x - l_ear_x, l_wr.y - l_ear_y) / shoulder_width
        r_wr_ear_dist = math.hypot(r_wr.x - r_ear_x, r_wr.y - r_ear_y) / shoulder_width

        # Co tay co bi che khuat sau dau hoac sau cang tay khong?
        # Tren Hinh 1: L_Wr vis = 0.48, R_Wr vis = 0.36
        # Tren Hinh 2: L_Wr vis = 0.07, R_Wr vis = 0.14 (bi che khuat hoan toan sau dau)
        l_wr_occluded = (l_wr.visibility < 0.35)
        r_wr_occluded = (r_wr.visibility < 0.35)

        # Khi co tay nhin thay ro: kiem tra co tay nam canh tai (khoang cach 2D <= 0.65 * sw, cao ngang vung dau/tai,
        # va khong duoi thang tay len troi nhu Map 2: (ear.y - wr.y)/sw <= 0.55)
        # Khi co tay bi che khuat sau dau (visibility < 0.35): neu khuyu tay dang o do cao ngang tai
        # va cang tay khong buong thap xuong duoi khuyu tay thi chap nhan co tay dang o sau dau!
        l_wrist_beside_ear = (
            (
                (l_wr_ear_dist <= 0.68) and
                ((l_ear_y - l_wr.y) / shoulder_width >= -0.38) and
                ((l_ear_y - l_wr.y) / shoulder_width <= 0.58)
            )
            if not l_wr_occluded
            else (elbows_at_ear_height and (l_wr.y <= l_el.y + 0.25 * shoulder_width))
        )
        r_wrist_beside_ear = (
            (
                (r_wr_ear_dist <= 0.68) and
                ((r_ear_y - r_wr.y) / shoulder_width >= -0.38) and
                ((r_ear_y - r_wr.y) / shoulder_width <= 0.58)
            )
            if not r_wr_occluded
            else (elbows_at_ear_height and (r_wr.y <= r_el.y + 0.25 * shoulder_width))
        )

        # Neu ca 2 co tay nhin thay ro, khoang cach 2D giua 2 co tay om sau dau phai hep (< 1.25 * sw)
        wrists_behind_head_valid = (
            l_wrist_beside_ear and r_wrist_beside_ear and
            (wrist_ratio <= 1.25 or l_wr_occluded or r_wr_occluded)
        )

        # Trong pha closing / holding (Hinh 2), 2 cang tay khep truoc mat che khuat manh 2 co tay sau dau:
        # Chi can 2 khuyu tay giu dung do cao ngang tai (elbows_at_ear_height) va khong duoi thang tay len troi
        if curr_state in ("closing", "holding"):
            not_hands_high_overhead = (
                ((l_ear_y - l_wr.y) / shoulder_width <= 0.65 if not l_wr_occluded else True) and
                ((r_ear_y - r_wr.y) / shoulder_width <= 0.65 if not r_wr_occluded else True)
            )
            form_valid = elbows_at_ear_height and not_hands_high_overhead
        else:
            form_valid = elbows_at_ear_height and wrists_behind_head_valid

        # =========================================================================
        # A. DONG TAC 1 - DONG TAC CHUAN BI (HINH 1):
        # - Canh tay dang 2 ben, cang tay 90 do huong len tren, 2 ban tay dua ra sau dau.
        # - Tren Hinh 1: elbow_ratio = 2.06, avg_el_ear_diff = +0.12, wr_ear_dist = 0.20.
        # =========================================================================
        # 1) Diem do cao 2 khuyu tay ngang 2 tai (dat 1.0 khi avg_el_ear_diff >= -0.25)
        ear_level_score = max(0.0, min(1.0, (avg_el_ear_diff + ear_height_tol + 0.15) / (0.35 + ear_height_tol)))

        # 2) Diem 2 co tay dat sau dau canh 2 tai
        if l_wr_occluded and r_wr_occluded:
            wrist_ear_score = 1.0 if elbows_at_ear_height else 0.0
        else:
            avg_wr_ear_dist = 0.5 * (
                (0.20 if l_wr_occluded else l_wr_ear_dist) +
                (0.20 if r_wr_occluded else r_wr_ear_dist)
            )
            wrist_ear_score = max(0.0, min(1.0, (0.75 - avg_wr_ear_dist) / (0.75 - 0.35)))

        # 3) Diem dang 2 khuyu tay sang 2 ben (dat 1.0 khi elbow_ratio >= 1.45; Hinh 1 = 2.06 -> 100%)
        open_el_score = max(0.0, min(1.0, (elbow_ratio - 1.00) / (1.45 - 1.00)))

        if elbows_at_ear_height and wrists_behind_head_valid:
            raw_prep = 0.25 * ear_level_score + 0.25 * wrist_ear_score + 0.50 * open_el_score
        elif elbows_at_ear_height:
            raw_prep = 0.35 * ear_level_score + 0.35 * open_el_score
        else:
            raw_prep = 0.0

        is_prep_pose = (
            elbows_at_ear_height and
            wrists_behind_head_valid and
            (elbow_ratio >= 1.40) and
            (raw_prep >= 0.85)
        )
        prep_rom = 1.0 if is_prep_pose else min(0.95, raw_prep)

        # =========================================================================
        # B. DONG TAC 2 - DONG TAC GIU 5 GIAY (HINH 2):
        # - Tu tu khep 2 canh tay ve phia duong giua (nhieu nhat co the) - giu 5 giay.
        # - ROM tang dan deu tuyen tinh khi khoang cach 2 khuyu tay giam tu lon (~1.75x vai)
        #   ve nho hon xap xi khoang cach 2 ba vai (< 1.0x distance_shoulder, tuy Calibration).
        # - Tren Hinh 2: elbow_ratio = 0.81 -> dat 100% ROM!
        # =========================================================================
        # Moc muc tieu (100% ROM) phu thuoc Calibration:
        # - Voi Calibration chuan (calib_factor = 0.75 -> 1.0): target_close_ratio ~ 0.90 - 0.95 (nho hon 1.0x vai, Hinh 2 = 0.81 dat 100%)
        # - Voi benh nhan han che van dong (calib_factor = 0.50): target_close_ratio ~ 1.02 (xap xi 1.0x vai)
        target_close_ratio = 1.08 - 0.16 * min(1.0, max(0.35, calib_factor))  # ~0.92..1.02
        start_close_ratio = max(1.95, target_close_ratio + 1.00)               # ~1.95..2.02 (ngay khi bat dau khep tu Hinh 1 = 2.06)

        if not form_valid:
            raw_hold_rom = 0.0
        else:
            # Tuyen tinh 100% theo do khep 2 khuyu tay: tu start_close_ratio (0%) ve target_close_ratio (100%)
            raw_hold_rom = max(0.0, min(1.0, (start_close_ratio - elbow_ratio) / max(0.25, start_close_ratio - target_close_ratio)))

        # Lam muot EMA cho hold_rom khi dang o trang thai closing de thanh ROM tang muot ma
        prev_smooth = st_map4.get("map4_smoothed_hold_rom", 0.0)
        if curr_state == "closing":
            smoothed_hold_rom = 0.45 * prev_smooth + 0.55 * raw_hold_rom
            st_map4["map4_smoothed_hold_rom"] = smoothed_hold_rom
        elif curr_state == "holding":
            smoothed_hold_rom = max(raw_hold_rom, prev_smooth * 0.90)
            st_map4["map4_smoothed_hold_rom"] = smoothed_hold_rom
        else:
            smoothed_hold_rom = raw_hold_rom
            st_map4["map4_smoothed_hold_rom"] = raw_hold_rom

        # Xu ly on dinh tuyet doi khi dang HOLDING 5 giay:
        if curr_state == "holding":
            if elbows_at_ear_height and (elbow_ratio <= target_close_ratio + 0.22):
                hold_rom = 1.0
                is_hold_pose = True
                form_valid = True
            elif elbows_at_ear_height and (elbow_ratio <= target_close_ratio + 0.35):
                hold_rom = max(0.65, smoothed_hold_rom)
                is_hold_pose = False
                form_valid = True
            else:
                hold_rom = smoothed_hold_rom
                is_hold_pose = False
        else:
            if not form_valid:
                hold_rom = 0.0
                is_hold_pose = False
            else:
                hold_rom = smoothed_hold_rom
                is_hold_pose = (
                    form_valid and
                    (elbow_ratio <= target_close_ratio + 0.03) and
                    (raw_hold_rom >= 0.95)
                )
                if is_hold_pose:
                    hold_rom = 1.0

        active_rom = prep_rom if curr_state == "ready" else hold_rom

        return {
            "angles": {
                "prep_score": round(prep_rom, 2),
                "is_prep_pose": is_prep_pose,
                "close_el_score": round(raw_hold_rom, 2),
                "elbow_ratio": round(elbow_ratio, 2),
                "wrist_ratio": round(wrist_ratio, 2),
                "avg_el_ear_diff": round(avg_el_ear_diff, 2),
                "l_wr_ear_dist": round(l_wr_ear_dist, 2),
                "r_wr_ear_dist": round(r_wr_ear_dist, 2),
                "target_close_ratio": round(target_close_ratio, 2),
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": round(active_rom, 3),
            "prep_score": prep_rom,
            "prep_rom": prep_rom,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "current_rom_value": round(raw_hold_rom * 90.0, 1),
            "target_ratio": round(target_close_ratio, 2),
        }

    # ==========================
    # Map 5
    # ==========================
    def _evaluate_map5_cross_body_stretch(self, lm: List[LandmarkPoint]) -> Dict[str, Any]:
        """Map 5"""
        l_sh, r_sh = lm[11], lm[12]
        l_el, r_el = lm[13], lm[14]
        l_wr, r_wr = lm[15], lm[16]

        # 1. Khoang cach 2D giua 2 ba vai (distance_shoulder) va do cao trung binh cua vai
        shoulder_width = max(0.05, self.calculate_2d_distance(l_sh, r_sh))
        sh_y_avg = 0.5 * (l_sh.y + r_sh.y)
        shoulder_tilt = abs(l_sh.y - r_sh.y) / shoulder_width

        st = self.exercise_states["cross_body_shoulder_stretch"]
        curr_state = st.get("movement_state", "ready")
        calib_factor = self._get_patient_calib_factor("cross_body_shoulder_stretch")

        # Nguong muc tieu khoang cach Khuyu tay ben nay -> Vai ben kia (tinh theo distance_shoulder):
        # - Khi Calibration dat chuan (calib_factor = 1.0): dat nguong 100% khi khoang cach <= 0.50 * distance_shoulder (1/2 vai)
        # - Khi Calibration thap hon: do xap xi duoc noi theo Calibration (0.50 -> 0.62 * distance_shoulder)
        target_el_sh_ratio = 0.50 + (1.0 - min(1.0, max(0.35, calib_factor))) * 0.18
        start_el_sh_ratio = 1.25

        # Sai so do cao 2D cua khuyu tay so voi vai (phu thuoc Calibration)
        el_height_tol = 0.42 + (1.0 - min(1.0, max(0.35, calib_factor))) * 0.18

        # Sai so khoang cach 2D cua co tay do (wr_support) toi vai cung ben va khuyu tay khac ben
        max_wr_same_sh = 0.68 + (1.0 - min(1.0, max(0.35, calib_factor))) * 0.12
        max_wr_opp_el = 0.96 + (1.0 - min(1.0, max(0.35, calib_factor))) * 0.12

        # =========================================================================
        # A. NHAN DIEN DONG TAC CHUAN BI (THA LONG 2 VAI TRUOC KHI KEO CANG)
        # =========================================================================
        d_r_el_l_sh_raw = self.calculate_2d_distance(r_el, l_sh) / shoulder_width
        d_l_el_r_sh_raw = self.calculate_2d_distance(l_el, r_sh) / shoulder_width

        shoulders_relaxed = (shoulder_tilt <= 0.35)
        elbows_not_overhead = (
            (l_el.y >= l_sh.y - 0.12 * shoulder_width) and
            (r_el.y >= r_sh.y - 0.12 * shoulder_width)
        )
        not_already_clamped = (d_r_el_l_sh_raw >= 0.72) and (d_l_el_r_sh_raw >= 0.72)

        tilt_score = max(0.0, min(1.0, (0.42 - shoulder_tilt) / 0.25))
        el_relax_score = 1.0 if elbows_not_overhead else 0.0
        raw_prep = 0.50 * tilt_score + 0.50 * el_relax_score

        is_prep_pose = shoulders_relaxed and elbows_not_overhead
        prep_rom = 1.0 if is_prep_pose else min(0.95, raw_prep)

        # =========================================================================
        # B. HAM DANH GIA 2D (x, y) CHO TUNG BEN TAY (PHAI VA TRAI)
        # =========================================================================
        def _eval_stretch_side(
            sh_stretch: LandmarkPoint,
            el_stretch: LandmarkPoint,
            wr_stretch: LandmarkPoint,
            sh_opp: LandmarkPoint,
            el_support: LandmarkPoint,
            wr_support: LandmarkPoint,
        ) -> Dict[str, Any]:
            # 1) Khoang cach 2D tu khuyu tay ben keo (el_stretch) den vai ben kia (sh_opp)
            d_el_opp_raw = self.calculate_2d_distance(el_stretch, sh_opp) / shoulder_width
            d_el_same_sh = self.calculate_2d_distance(el_stretch, sh_stretch) / shoulder_width

            # 2) Khoang cach 2D tu co tay do (wr_support) den vai cung ben (sh_opp) va khuyu tay khac ben (el_stretch)
            wr_sup_vis = getattr(wr_support, "visibility", 1.0)
            el_sup_vis = getattr(el_support, "visibility", 1.0)
            el_str_vis = getattr(el_stretch, "visibility", 1.0)

            d_wr_same_sh = self.calculate_2d_distance(wr_support, sh_opp) / shoulder_width
            d_wr_opp_el = self.calculate_2d_distance(wr_support, el_stretch) / shoulder_width

            # Xu ly che khuat:
            # Khi cang tay do (el_support -> wr_support) ep sat len khuyu tay ben keo (el_stretch) ngay truoc vai doi dien (sh_opp):
            # - Neu co tay do wr_support bi che khuat (visibility < 0.22), ta su dung them vi tri khuyu tay do el_support
            #   nam ngay duoi vai cung ben sh_opp de khong bi mat nhan dien.
            support_arm_raised = (
                (el_support.y >= sh_opp.y - 0.05 * shoulder_width) and
                (el_support.y <= sh_opp.y + 0.85 * shoulder_width) and
                (wr_support.y <= el_support.y + 0.18 * shoulder_width if wr_sup_vis >= 0.22 else True)
            )

            if wr_sup_vis >= 0.22:
                wr_near_same_sh = (d_wr_same_sh <= max_wr_same_sh)
                wr_near_opp_el = (d_wr_opp_el <= max_wr_opp_el)
            else:
                # Fallback 2D khi diem co tay do bi canh tay kia che khuat mot phan
                d_el_sup_sh = self.calculate_2d_distance(el_support, sh_opp) / shoulder_width
                d_el_sup_el_str = self.calculate_2d_distance(el_support, el_stretch) / shoulder_width
                wr_near_same_sh = (d_el_sup_sh <= 0.78)
                wr_near_opp_el = (d_el_sup_el_str <= 0.78)

            support_clamp_valid = support_arm_raised and wr_near_same_sh and wr_near_opp_el

            # Bu sai so che khuat 2D muot ma khi cang tay do che khuat dinh khuyu tay ben keo (nhu tren Hinh 1):
            # Khi co tay do wr_support dat sat vai cung ben (d_wr_same_sh <= 0.48) va khuyu tay ben keo
            # tien ve phia sh_opp, he so blend tang tuyen tinh tu 0.0 (tai d=0.95) len 0.55 (tai d<=0.68)
            # giup d_el_opp_eff giam deu tuyet doi khong co buoc nhay!
            if support_clamp_valid and (d_wr_same_sh <= 0.48) and (d_el_opp_raw <= 0.95):
                occ_blend = max(0.0, min(0.55, (0.95 - d_el_opp_raw) / (0.95 - 0.68) * 0.55))
                clamped_est = (1.0 - occ_blend) * d_el_opp_raw + occ_blend * d_wr_same_sh
                d_el_opp_eff = min(d_el_opp_raw, clamped_est)
            elif (el_str_vis < 0.25) and support_clamp_valid:
                d_el_opp_eff = min(d_el_opp_raw, d_wr_same_sh + 0.15)
            else:
                d_el_opp_eff = d_el_opp_raw

            # 3) Kiem tra do cao 2D cua khuyu tay ben keo (el_stretch.y) xap xi do cao cua diem vai (sh_y_avg)
            el_y_diff = (el_stretch.y - sh_y_avg) / shoulder_width
            elbow_at_shoulder_height = (-0.24 <= el_y_diff <= el_height_tol)

            # Chong nhan nham khi chi dang tay ngang nguc (T-pose) ma chua vat khuyu tay sang vai doi dien:
            # Khuyu tay ben keo phai tien ve phia vai doi dien (d_el_opp_eff <= 1.15)
            arm_crossed_chest = (d_el_opp_eff <= 1.15)

            # 4) Tinh ROM tang dan deu tuyen tinh theo khoang cach d_el_opp_eff:
            # Tu start_el_sh_ratio (1.25 * sw -> 0%) giam ve target_el_sh_ratio (<= 0.50 * sw -> 100%)
            cross_dist_score = max(
                0.0,
                min(1.0, (start_el_sh_ratio - d_el_opp_eff) / max(0.20, start_el_sh_ratio - target_el_sh_ratio)),
            )

            # Diem ho tro cua tay do (de ROM tang muot khi nguoi tap vua keo vua dua tay do len kep)
            score_wr_sh = max(0.0, min(1.0, (max_wr_same_sh + 0.30 - d_wr_same_sh) / 0.45))
            score_wr_el = max(0.0, min(1.0, (max_wr_opp_el + 0.30 - d_wr_opp_el) / 0.45))
            clamp_progress = 0.5 * (score_wr_sh + score_wr_el) if support_arm_raised else 0.0

            side_form_valid = elbow_at_shoulder_height and support_clamp_valid and arm_crossed_chest

            if not elbow_at_shoulder_height:
                side_rom = 0.0
            elif support_clamp_valid:
                # Khi tay do da dat dung vi tri kep (gan vai cung ben va khuyu tay khac ben):
                # ROM tang tuyen tinh 100% theo khoang cach khuyu tay ben nay -> vai ben kia!
                side_rom = cross_dist_score
            else:
                # Neu nguoi tap chi vat 1 tay qua nguc ma CHUA dung tay kia ep ngang nguc:
                # Khoa ROM toi da <= 0.30 de bat buoc phai dung tay kia kep giu!
                side_rom = min(0.30, 0.35 * cross_dist_score * clamp_progress)

            side_is_hold_pose = (
                side_form_valid and
                (d_el_opp_eff <= target_el_sh_ratio + 0.02) and
                (side_rom >= 0.95)
            )
            if side_is_hold_pose:
                side_rom = 1.0

            return {
                "d_el_opp_raw": d_el_opp_raw,
                "d_el_opp_eff": d_el_opp_eff,
                "d_el_same_sh": d_el_same_sh,
                "d_wr_same_sh": d_wr_same_sh,
                "d_wr_opp_el": d_wr_opp_el,
                "el_y_diff": el_y_diff,
                "elbow_at_shoulder_height": elbow_at_shoulder_height,
                "support_clamp_valid": support_clamp_valid,
                "form_valid": side_form_valid,
                "rom": side_rom,
                "is_hold_pose": side_is_hold_pose,
            }

        # Danh gia ben PHAI (Keo canh tay PHAI r_sh-r_el-r_wr sang vai TRAI l_sh, tay TRAI l_sh-l_el-l_wr do/kep)
        right_eval = _eval_stretch_side(r_sh, r_el, r_wr, l_sh, l_el, l_wr)
        # Danh gia ben TRAI (Keo canh tay TRAI l_sh-l_el-l_wr sang vai PHAI r_sh, tay PHAI r_sh-r_el-r_wr do/kep)
        left_eval = _eval_stretch_side(l_sh, l_el, l_wr, r_sh, r_el, r_wr)

        # =========================================================================
        # C. PHAN BIET TRAI - PHAI CHAT CHE & BAT BUOC DOI BEN GIUA HIEP 1 VA HIEP 2
        # =========================================================================
        target_side = st.get("target_side", "both")
        active_side = st.get("active_stretch_side", "none")
        last_completed_side = st.get("last_completed_side", "none")
        required_side = st.get("required_side", "both")

        # Neu Hiep 1 da hoan thanh 1 ben (last_completed_side in ["left", "right"]),
        # Hiep 2 BAT BUOC phai tap ben doi dien!
        if last_completed_side == "right":
            required_side = "left"
        elif last_completed_side == "left":
            required_side = "right"
        elif target_side in ("left", "right"):
            required_side = target_side
        else:
            required_side = "both"
        st["required_side"] = required_side

        # Xac dinh ben nguoi tap dang thuc hien tren camera
        if right_eval["rom"] > left_eval["rom"] + 0.05:
            detected_side = "right"
        elif left_eval["rom"] > right_eval["rom"] + 0.05:
            detected_side = "left"
        else:
            detected_side = "right" if right_eval["d_el_opp_eff"] <= left_eval["d_el_opp_eff"] else "left"

        wrong_side_detected = False
        if curr_state == "holding" and active_side in ("left", "right"):
            chosen_side = active_side
        elif required_side in ("left", "right"):
            chosen_side = required_side
            other_side = "left" if required_side == "right" else "right"
            other_eval = left_eval if other_side == "left" else right_eval
            req_eval = right_eval if required_side == "right" else left_eval
            # Neu nguoi choi co tinh tap lai ben cu cua Hiep 1:
            if (other_eval["rom"] >= 0.25) and (req_eval["rom"] < 0.20):
                wrong_side_detected = True
        else:
            chosen_side = detected_side

        chosen_eval = right_eval if chosen_side == "right" else left_eval

        # Lam muot EMA cho hold_rom trong pha contracting de thanh ROM tang muot ma
        raw_hold_rom = 0.0 if wrong_side_detected else chosen_eval["rom"]
        prev_smooth = st.get("map5_smoothed_hold_rom", 0.0)
        if curr_state == "contracting":
            smoothed_hold_rom = 0.40 * prev_smooth + 0.60 * raw_hold_rom
            st["map5_smoothed_hold_rom"] = smoothed_hold_rom
        elif curr_state == "holding":
            smoothed_hold_rom = max(raw_hold_rom, prev_smooth * 0.92)
            st["map5_smoothed_hold_rom"] = smoothed_hold_rom
        else:
            smoothed_hold_rom = raw_hold_rom
            st["map5_smoothed_hold_rom"] = raw_hold_rom

        # Xu ly on dinh trong suot 30 giay HOLDING:
        if curr_state == "holding":
            # Trong khi giu 30s: mien la khuyu tay ben keo van o ngang vung vai/nguc
            # va van nam gan vai doi dien (d_el_opp_eff <= target_el_sh_ratio + 0.28) va tay do khong buong xuong
            still_holding_valid = (
                (not wrong_side_detected) and
                chosen_eval["elbow_at_shoulder_height"] and
                (chosen_eval["d_el_opp_eff"] <= target_el_sh_ratio + 0.28) and
                (chosen_eval["d_wr_same_sh"] <= max_wr_same_sh + 0.22)
            )
            if still_holding_valid:
                hold_rom = 1.0
                is_hold_pose = True
                form_valid = True
            else:
                hold_rom = smoothed_hold_rom
                is_hold_pose = False
                form_valid = False
        else:
            if wrong_side_detected:
                hold_rom = 0.0
                is_hold_pose = False
                form_valid = False
            else:
                form_valid = chosen_eval["form_valid"]
                is_hold_pose = chosen_eval["is_hold_pose"]
                hold_rom = 1.0 if is_hold_pose else smoothed_hold_rom

        if (hold_rom >= 0.30) and (curr_state in ("ready", "contracting")) and (not wrong_side_detected):
            st["active_stretch_side"] = chosen_side

        active_rom = prep_rom if curr_state == "ready" else hold_rom

        return {
            "angles": {
                "prep_score": round(prep_rom, 2),
                "is_prep_pose": is_prep_pose,
                "d_el_opp_raw": round(chosen_eval["d_el_opp_raw"], 2),
                "d_el_opp_eff": round(chosen_eval["d_el_opp_eff"], 2),
                "target_el_sh_ratio": round(target_el_sh_ratio, 2),
                "d_wr_same_sh": round(chosen_eval["d_wr_same_sh"], 2),
                "d_wr_opp_el": round(chosen_eval["d_wr_opp_el"], 2),
                "el_y_diff": round(chosen_eval["el_y_diff"], 2),
                "elbow_at_shoulder_height": chosen_eval["elbow_at_shoulder_height"],
                "support_clamp_valid": chosen_eval["support_clamp_valid"],
                "active_side": chosen_side,
                "required_side": required_side,
                "wrong_side_detected": wrong_side_detected,
                "hold_rom": round(hold_rom, 2),
                "is_hold_pose": is_hold_pose,
            },
            "form_valid": form_valid,
            "rom_progress": round(active_rom, 3),
            "prep_score": prep_rom,
            "prep_rom": prep_rom,
            "is_prep_pose": is_prep_pose,
            "hold_rom": hold_rom,
            "is_hold_pose": is_hold_pose,
            "wrong_side_detected": wrong_side_detected,
            "current_rom_value": round(raw_hold_rom * 90.0, 1),
            "target_dist": round(target_el_sh_ratio * shoulder_width, 3),
            "active_side": chosen_side,
            "required_side": required_side,
        }

    # ==========================
    # XU LY CALIBRATION (DO ROM TONG QUAT BANG DONG TAC DANG TAY SANG 2 BEN - T-POSE)
    # ==========================
    def process_calibration(self, raw_landmarks) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        """
        Xu ly do ROM theo thoi gian thuc bang dong tac Dang 2 tay sang 2 ben ngang vai (T-Pose 0 -> 90 do).
        Tra ve: (calibration_progress_payload, calibration_completed_payload)
        """
        if not self.calibration_active:
            return None, None

        lm = self.filter.filter(raw_landmarks)
        is_tracking_ok, feedback = self.check_tracking_status(lm)

        now = time.time()
        elapsed_ms = int((now - self.calib_start_time) * 1000)
        progress = min(1.0, elapsed_ms / float(self.calib_duration_ms))

        # Tinh ROM hien tai: Mac dinh su dung dong tac Dang tay sang 2 ben (T-Pose)
        # de do bien do khop vai tong quat (0 -> 90 do) ap dung chuan hoa cho ca 5 Map.
        current_val = 0.0
        left_val = 0.0
        right_val = 0.0
        if is_tracking_ok:
            if self.calib_exercise_id in ("scapular_retraction", "t_pose_abduction", ""):
                m = self._evaluate_calibration_t_pose(lm)
                current_val = float(m["current_rom_value"])
                left_val = float(m.get("left_rom_value", current_val))
                right_val = float(m.get("right_rom_value", current_val))
            elif self.calib_exercise_id == "wall_abduction_external_rotation":
                m = self._evaluate_map2_wall_abduction(lm)
                current_val = float(m["current_rom_value"])
                left_val = current_val
                right_val = current_val
            elif self.calib_exercise_id == "horizontal_shoulder_adduction":
                m = self._evaluate_map3_horizontal_shoulder_adduction(lm)
                current_val = float(m["current_rom_value"])
                left_val = current_val
                right_val = current_val
            elif self.calib_exercise_id == "hands_behind_head":
                m = self._evaluate_map4_hands_behind_head(lm)
                current_val = float(m["current_rom_value"])
                left_val = current_val
                right_val = current_val
            elif self.calib_exercise_id == "cross_body_shoulder_stretch":
                m = self._evaluate_map5_cross_body_stretch(lm)
                current_val = float(m["current_rom_value"])
                left_val = current_val
                right_val = current_val

            # Cap nhat dinh ROM toi da (trai, phai va trung binh 2 ben)
            self.calib_max_rom_left = max(self.calib_max_rom_left, left_val)
            self.calib_max_rom_right = max(self.calib_max_rom_right, right_val)
            self.calib_max_rom_combined = max(self.calib_max_rom_combined, current_val)

        # Tao event calibration_progress dinh ky (moi 250ms)
        progress_msg = None
        if now - self.calib_last_emit_time >= 0.25:
            self.calib_last_emit_time = now
            if not is_tracking_ok:
                calib_fb = feedback
            elif current_val >= 35.0 or self.calib_max_rom_combined >= 55.0:
                calib_fb = "KEEP_POSITION"
            else:
                calib_fb = "OPEN_ARMS"

            progress_msg = {
                "exercise_id": self.calib_exercise_id,
                "progress": round(progress, 2),
                "elapsed_ms": elapsed_ms,
                "duration_ms": self.calib_duration_ms,
                "tracking_valid": is_tracking_ok,
                "current_rom_value": round(current_val, 1),
                "rom_unit": "degree",
                "feedback_code": calib_fb,
            }

        # Hoan tat calibration
        completed_msg = None
        if progress >= 1.0:
            self.calibration_active = False
            rec_ratio = 0.85
            rec_target = round(self.calib_max_rom_combined * rec_ratio, 2)

            # Luu bien do ROM tong quat (0 -> 90 do) de ap dung chuan hoa cho tat ca 5 Map
            if self.calib_max_rom_combined > 5.0:
                self.calibrated_global_max_rom = self.calib_max_rom_combined
                for ex_id, ex_st in self.exercise_states.items():
                    ex_st["calibrated_max_rom"] = self.calib_max_rom_combined
                    ex_st["target_rom_value"] = round(self.calib_max_rom_combined * ex_st.get("target_rom_ratio", rec_ratio), 2)

            completed_msg = {
                "exercise_id": self.calib_exercise_id,
                "success": bool(self.calib_max_rom_combined > 5.0),
                "measurement_kind": "normalized_t_pose",
                "valid_elapsed_ms": self.calib_duration_ms,
                "duration_ms": self.calib_duration_ms,
                "valid_sample_count": 30,
                "sample_quality": 1.0,
                "target_side": self.calib_target_side,
                "max_rom": {
                    "left": round(self.calib_max_rom_left, 1),
                    "right": round(self.calib_max_rom_right, 1),
                    "combined": round(self.calib_max_rom_combined, 1),
                    "unit": "degree",
                },
                "confidence": 0.95 if is_tracking_ok else 0.40,
                "recommended_target_ratio": rec_ratio,
                "recommended_target_value": rec_target,
                "feedback_code": "CALIBRATION_COMPLETED" if self.calib_max_rom_combined > 5.0 else "CALIBRATION_LOW_CONFIDENCE",
            }

        return progress_msg, completed_msg

    # ==========================
    # MAY TRANG THAI PHIEN TAP CHINH (EXERCISE STATE MACHINE)
    # ==========================
    def process_frame(self, exercise_id: str, raw_landmarks) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
        """
        Ham trung tam: Danh gia pose hien tai, cap nhat state machine,
        va sinh cac su kien rep_completed, hold_progress, rep_rejected...
        Tra ve: (pose_metrics, list_of_events)
        """
        events: List[Dict[str, Any]] = []

        if exercise_id not in self.exercise_states or not raw_landmarks:
            return {}, events

        st = self.exercise_states[exercise_id]

        # Loc nhieu qua EMA
        lm = self.filter.filter(raw_landmarks)
        is_tracking_ok, feedback = self.check_tracking_status(lm)

        # 1. Tinh metrics cu the cho tung bai (luon tinh ke ca khi is_paused de cap nhat the chuan bi & UI muot ma)
        if exercise_id == "scapular_retraction":
            eval_data = self._evaluate_map1_scapular_retraction(lm)
        elif exercise_id == "wall_abduction_external_rotation":
            eval_data = self._evaluate_map2_wall_abduction(lm)
        elif exercise_id == "horizontal_shoulder_adduction":
            eval_data = self._evaluate_map3_horizontal_shoulder_adduction(lm)
        elif exercise_id == "hands_behind_head":
            eval_data = self._evaluate_map4_hands_behind_head(lm)
        elif exercise_id == "cross_body_shoulder_stretch":
            eval_data = self._evaluate_map5_cross_body_stretch(lm)
        else:
            return {}, events

        now = time.time()
        rom_prog = eval_data.get("rom_progress", 0.0)
        form_valid = eval_data["form_valid"] and is_tracking_ok
        st["peak_rom_achieved"] = max(st["peak_rom_achieved"], rom_prog)

        hold_duration_ms = st["hold_duration_ms"]
        is_hold_exercise = hold_duration_ms > 0

        current_state = st["movement_state"]
        feedback_code = feedback if not is_tracking_ok else ("POSITION_OK" if form_valid else "TARGET_NOT_REACHED")
        hold_prog = 0.0

        # Xu ly thong minh khi phien tap tam hoan nhan rep (is_paused = True:
        # vi du khi da dang lan o Map 1, tuong dang ep o Map 3, nhan vat dang chay 5s tren bac da o Map 4, hoac nghi giua hiep):
        # Cho phep nguoi choi ha tay ve the chuan bi (Hinh 1) va san sang ngay, nhung khong phat rep_completed som.
        if self.is_paused:
            is_prep = eval_data.get("is_prep_pose", False)
            prep_sc = eval_data.get("prep_score", 0.0)
            if exercise_id == "scapular_retraction":
                if current_state in ("returning", "holding", "contracting") and (is_prep or eval_data.get("hold_rom", 0.0) <= 0.25):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["map1_smoothed_hold_rom"] = 0.0
                paused_rom = eval_data.get("prep_rom", prep_sc)
                paused_fb = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"
            elif exercise_id == "wall_abduction_external_rotation":
                avg_el_reach = eval_data.get("angles", {}).get("avg_elbow_reach", 0.0)
                if current_state in ("returning", "holding", "raising") and (is_prep or avg_el_reach <= 0.18 or eval_data.get("hold_rom", 0.0) <= 0.25):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["map2_smoothed_hold_rom"] = 0.0
                paused_rom = eval_data.get("prep_rom", prep_sc)
                paused_fb = "PREP_POSITION"
            elif exercise_id == "horizontal_shoulder_adduction":
                el_r = eval_data.get("angles", {}).get("elbow_ratio", 1.0)
                if current_state in ("returning", "holding", "opening") and (el_r <= 0.90 or is_prep or eval_data.get("hold_rom", 0.0) <= 0.25):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["map3_smoothed_hold_rom"] = 0.0
                paused_rom = eval_data.get("prep_rom", prep_sc)
                paused_fb = "PREP_POSITION"
            elif exercise_id == "hands_behind_head":
                el_r = eval_data.get("angles", {}).get("elbow_ratio", 1.0)
                if current_state in ("returning", "holding", "closing") and (el_r >= 1.35 or is_prep or eval_data.get("hold_rom", 0.0) <= 0.25):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_closing_rom"] = 0.0
                    st["map4_smoothed_hold_rom"] = 0.0
                paused_rom = eval_data.get("prep_rom", prep_sc)
                paused_fb = "PREP_POSITION"
            else:
                if current_state in ("returning", "holding", "contracting") and (is_prep or eval_data.get("hold_rom", 0.0) <= 0.25):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["active_stretch_side"] = "none"
                    st["map5_smoothed_hold_rom"] = 0.0
                paused_rom = eval_data.get("prep_rom", prep_sc)
                paused_fb = "PREP_POSITION"

            return {
                "angles": eval_data.get("angles", {}),
                "exercise": {
                    "exercise_id": exercise_id,
                    "movement_state": st["movement_state"],
                    "form_valid": form_valid,
                    "rom_progress": round(paused_rom, 2),
                    "hold_progress": 0.0,
                    "movement_duration_ms": 0,
                    "quality": 0.92 if form_valid else 0.50,
                    "feedback_code": paused_fb,
                },
            }, events

        # 2. May trang thai cu dong (State Machine)
        if exercise_id == "scapular_retraction":
            # Map 1
            prep_rom = eval_data.get("prep_rom", eval_data.get("prep_score", 0.0))
            is_prep_pose = eval_data.get("is_prep_pose", False)
            hold_rom = eval_data.get("hold_rom", 0.0)
            is_hold_pose = eval_data.get("is_hold_pose", False)
            angles_info = eval_data.get("angles", {})

            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0
            if "active_motion_start_time" not in st:
                st["active_motion_start_time"] = 0.0
            if "map1_smoothed_hold_rom" not in st:
                st["map1_smoothed_hold_rom"] = 0.0

            HOLD_TARGET_MS = 700

            if current_state == "ready":
                hold_prog = 0.0
                st["map1_smoothed_hold_rom"] = 0.0
                # Giai doan 1: Nhan dien dong tac chuan bi (Hinh 1)
                rom_effective = 1.0 if is_prep_pose else prep_rom
                rom_prog = rom_effective
                eval_data["rom_progress"] = rom_prog

                fb_ready = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"
                if is_prep_pose and rom_effective >= 1.0:
                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # Khi nguoi tap vao dung tu the chuan bi (on dinh >= 0.20s), ROM ghi nhan 100%
                    # va chuyen ngay sang nhan dien dong tac giu (contracting)
                    if (now - st["prep_hold_start_time"]) >= 0.20:
                        st["movement_state"] = "contracting"
                        st["movement_start_time"] = now
                        st["active_motion_start_time"] = 0.0
                        st["prep_hold_start_time"] = 0.0
                        st["map1_smoothed_hold_rom"] = 0.0
                        st["peak_rom_achieved"] = 0.0
                        st["motion_onset_rom"] = 0.0
                        st["low_rom_timestamp"] = now
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "MOVEMENT_STARTED",
                        })
                        feedback_code = "CONTINUE_MOVEMENT"
                    else:
                        feedback_code = fb_ready
                else:
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = fb_ready

            elif current_state == "contracting":
                hold_prog = 0.0
                # Ghi nhan muc ROM thap nhat (< 0.12) lam moc de danh gia hien tuong tang dot ngot
                if rom_prog <= 0.12:
                    st["low_rom_timestamp"] = now
                    st["motion_onset_rom"] = rom_prog

                # Giai doan 2: Nhan dien dong tac giu (Hinh 2)
                # ROM tang dan deu theo khuyu tay ha thap va ep lui sau
                alpha_hold = 0.65 if hold_rom >= st["map1_smoothed_hold_rom"] else 0.35
                st["map1_smoothed_hold_rom"] = alpha_hold * hold_rom + (1.0 - alpha_hold) * st["map1_smoothed_hold_rom"]
                if (hold_rom >= 0.88) or is_hold_pose:
                    st["map1_smoothed_hold_rom"] = 1.0
                elif hold_rom <= 0.04 and st["map1_smoothed_hold_rom"] <= 0.07:
                    st["map1_smoothed_hold_rom"] = 0.0

                rom_prog = round(st["map1_smoothed_hold_rom"], 3)
                eval_data["rom_progress"] = rom_prog
                st["peak_rom_achieved"] = max(st.get("peak_rom_achieved", 0.0), rom_prog)

                # Khi ROM cham 100% (hoac dat chuan Hinh 2):
                if ((rom_prog >= 1.0) or (is_hold_pose and hold_rom >= 0.88)) and form_valid:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0

                    # DE XUAT 1: Chi khi ROM tang 1 cach dot ngot tu duoi 10 len 100 (< 180ms)
                    # moi phat canh bao MOVEMENT_TOO_FAST. Nguoi tap dang giu hoac co ep binh thuong
                    # se khong bao gio bi phat nham.
                    time_from_low = now - st.get("low_rom_timestamp", 0.0)
                    onset_rom = st.get("motion_onset_rom", 0.0)
                    is_abrupt_surge = (onset_rom <= 0.12) and (time_from_low < 0.18) and (st.get("low_rom_timestamp", 0.0) > 0.0)

                    if is_abrupt_surge:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "movement_too_fast",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": int(time_from_low * 1000),
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": 0,
                            "quality": 0.35,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        st["movement_state"] = "returning"
                        st["map1_smoothed_hold_rom"] = 0.0
                        st["fast_warning_until"] = now + 1.2
                    else:
                        st["movement_state"] = "holding"
                        st["hold_start_time"] = now
                        st["last_hold_emit_time"] = now
                        st["hold_grace_start_time"] = 0.0
                        st["motion_onset_rom"] = 1.0
                        st["low_rom_timestamp"] = 0.0
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "target_reached",
                            "rep_candidate_id": rep_id,
                            "quality": 0.95,
                            "feedback_code": "TARGET_REACHED",
                        })
                        events.append({
                            "event": "hold_started",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": HOLD_TARGET_MS,
                            "feedback_code": "HOLD_STARTED",
                        })
                        feedback_code = "KEEP_POSITION"

                elif (now - st["movement_start_time"] >= 1.2) and is_prep_pose and (st["map1_smoothed_hold_rom"] <= 0.15):
                    # Nguoi tap chu dong dua tay ve lai the chuan bi
                    st["movement_state"] = "ready"
                    st["map1_smoothed_hold_rom"] = 0.0
                    feedback_code = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"
                else:
                    feedback_code = "CONTINUE_MOVEMENT"

            elif current_state == "holding":
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(HOLD_TARGET_MS))

                is_pose_dropped = (hold_rom < 0.40) or (not form_valid)
                if is_pose_dropped:
                    if st.get("hold_grace_start_time", 0.0) == 0.0:
                        st["hold_grace_start_time"] = now
                    grace_elapsed = now - st["hold_grace_start_time"]
                else:
                    st["hold_grace_start_time"] = 0.0
                    grace_elapsed = 0.0

                # Chi huy giu khi nguoi choi thuc su buong tay keo dai lien tuc tren 0.35 giay (350ms)
                # (Chong triet de rung giat 1-2 frames cua MediaPipe Landmark khi dang giu yen)
                if is_pose_dropped and grace_elapsed >= 0.35:
                    st["hold_grace_start_time"] = 0.0
                    events.append({
                        "event": "hold_interrupted",
                        "rep_candidate_id": st["current_rep_id"],
                        "hold_target_ms": HOLD_TARGET_MS,
                        "feedback_code": "HOLD_INTERRUPTED",
                    })
                    feedback_code = "TARGET_NOT_REACHED"
                    st["movement_state"] = "returning"
                else:
                    st["map1_smoothed_hold_rom"] = 1.0
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    feedback_code = "KEEP_POSITION"

                    if (now - st.get("last_hold_emit_time", 0.0) >= 0.12) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": HOLD_TARGET_MS,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # SAU KHI GIU DU 0.7 GIAY (HOLD_TARGET_MS = 700ms):
                    # Nhan vat moi thuc hien hanh dong pha da!
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)

                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": HOLD_TARGET_MS,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.98,
                            "feedback_code": "REP_VALID",
                        })

                        # Yeu cau nguoi tap dua tay ve the chuan bi (Hinh 1) cho lan tap tiep theo
                        st["movement_state"] = "returning"
                        st["map1_smoothed_hold_rom"] = 0.0
                        st["peak_rom_achieved"] = 0.0
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "RELEASE_POSITION"

            elif current_state == "returning":
                hold_prog = 0.0
                st["map1_smoothed_hold_rom"] = 0.0
                eval_data["rom_progress"] = 1.0 if is_prep_pose else prep_rom

                # KHI NGUOI TAP THUC SU DUA TAY VE THE CHUAN BI (HINH 1):
                # (is_prep_pose == True, hoac tay duoi el_angle >= 115 do va z_diff <= 0.025)
                el_angle = angles_info.get("elbow_angle", 0.0)
                z_diff = angles_info.get("elbow_z_diff", 0.0)
                is_back_to_prep = is_prep_pose or (el_angle >= 115.0 and z_diff <= 0.025)
                if is_back_to_prep:
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "READY_FOR_NEXT_REP" if st.get("completed_reps", 0) > 0 else "POSITION_OK"
                else:
                    feedback_code = "RELEASE_POSITION"

                if now < st.get("fast_warning_until", 0.0):
                    feedback_code = "MOVEMENT_TOO_FAST"

        elif exercise_id == "wall_abduction_external_rotation":
            # Map 2
            prep_rom = eval_data.get("prep_rom", eval_data["prep_score"])
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            reach_score = eval_data["reach_score"]
            angles_info = eval_data.get("angles", {})

            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0
            if "active_motion_start_time" not in st:
                st["active_motion_start_time"] = 0.0
            if "map2_smoothed_hold_rom" not in st:
                st["map2_smoothed_hold_rom"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                st["map2_smoothed_hold_rom"] = 0.0
                # Giai doan 1: Nhan dien dong tac chuan bi (Hinh 1)
                rom_effective = 1.0 if is_prep_pose else prep_rom
                rom_prog = rom_effective
                eval_data["rom_progress"] = rom_prog

                if is_prep_pose and rom_effective >= 1.0:
                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # Khi nguoi tap vao dung tu the chuan bi (on dinh >= 0.20s), ROM ghi nhan 100%
                    # va chuyen ngay sang nhan dien dong tac giu (raising)
                    if (now - st["prep_hold_start_time"]) >= 0.20:
                        st["movement_state"] = "raising"
                        st["movement_start_time"] = now
                        st["active_motion_start_time"] = 0.0
                        st["prep_hold_start_time"] = 0.0
                        st["map2_smoothed_hold_rom"] = 0.0
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        feedback_code = "REACH_OVERHEAD"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "raising":
                hold_prog = 0.0
                # Giai doan 2: Nhan dien dong tac giu (Hinh 2)
                # ROM tang dan deu theo goc noi cua khuyu tay (tu 90 do len 180 do)
                alpha_hold = 0.75 if hold_rom >= st["map2_smoothed_hold_rom"] else 0.40
                st["map2_smoothed_hold_rom"] = alpha_hold * hold_rom + (1.0 - alpha_hold) * st["map2_smoothed_hold_rom"]
                if (hold_rom >= 0.92) or is_hold_pose:
                    st["map2_smoothed_hold_rom"] = 1.0
                elif hold_rom <= 0.04 and st["map2_smoothed_hold_rom"] <= 0.07:
                    st["map2_smoothed_hold_rom"] = 0.0

                rom_prog = round(st["map2_smoothed_hold_rom"], 3)
                eval_data["rom_progress"] = rom_prog

                # Ghi nhan thoi diem bat dau mo goc khuyu tay roi khoi Hinh 1 de kiem soat toc do (Rhythm Control)
                if hold_rom < 0.05:
                    st["active_motion_start_time"] = 0.0
                elif st.get("active_motion_start_time", 0.0) == 0.0:
                    st["active_motion_start_time"] = now

                # Khi ROM cham 100% (hoac dat chuan Hinh 2):
                if (rom_prog >= 1.0) or (is_hold_pose and hold_rom >= 0.95):
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    active_start = st.get("active_motion_start_time") or st["movement_start_time"]
                    move_duration_ms = int((now - active_start) * 1000)
                    min_move_ms = int(st.get("min_movement_duration_ms", 550))

                    # Rhythm Control: Neu giat tay qua nhanh (< 750ms) -> canh bao MOVEMENT_TOO_FAST
                    if move_duration_ms < min_move_ms:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "movement_too_fast",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": move_duration_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": 0,
                            "quality": 0.35,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        st["movement_state"] = "returning"
                        st["active_motion_start_time"] = 0.0
                        st["map2_smoothed_hold_rom"] = 0.0
                        st["fast_warning_until"] = now + 3.0
                    else:
                        st["movement_state"] = "holding"
                        st["hold_start_time"] = now
                        st["last_hold_emit_time"] = now
                        st["hold_grace_start_time"] = 0.0
                        st["active_motion_start_time"] = 0.0
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "target_reached",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "TARGET_REACHED",
                        })
                        events.append({
                            "event": "hold_started",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_STARTED",
                        })
                        feedback_code = "HOLD_STARTED"
                elif (angles_info.get("avg_sh_angle", 0.0) < 55.0) and (angles_info.get("avg_wrist_reach", 0.0) < 0.20):
                    # Neu nguoi tap ha xuoi han 2 tay xuong -> quay ve ready de vao lai the chuan bi Hinh 1
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map2_smoothed_hold_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                else:
                    feedback_code = "REACH_OVERHEAD"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) KHI ROM CHAM 100%
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Khi nguoi tap duy tri tu the giu Hinh 2 (hold_rom >= 0.45), giu ROM hien thi o muc 100% (1.0)
                if hold_rom >= 0.45:
                    rom_prog = 1.0
                else:
                    rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                if hold_rom < 0.45:
                    # Neu ha tay xuong duoi nguong giu: dem thoi gian an han 0.9s chong nhieu
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    if (now - st["hold_grace_start_time"]) >= 0.90:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st["peak_rom_achieved"], 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "ready"
                        st["hold_grace_start_time"] = 0.0
                        st["map2_smoothed_hold_rom"] = 0.0
                        feedback_code = "HOLD_INTERRUPTED"
                else:
                    # Van giu tot tu the Hinh 2 -> Reset grace va cap nhat tien do giu 5 giay
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Khi giu du 5 giay (100% hold) -> Hoan thanh 1 lan tap -> Nhan vat day tang da!
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 0.98,
                            "feedback_code": "REP_VALID",
                        })
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        st["map2_smoothed_hold_rom"] = 0.0
                        feedback_code = "LIFT_SUCCESS"

            elif current_state == "returning":
                if now < st.get("fast_warning_until", 0.0):
                    feedback_code = "MOVEMENT_TOO_FAST"
                else:
                    feedback_code = "RETURN_TO_PREP"
                    if is_prep_pose:
                        st["movement_state"] = "ready"
                        feedback_code = "PREP_POSITION"

                # Khi nguoi tap ha tay tro ve vi tri ban dau (Hinh 1 hoac ha thap khuyu tay xuong):
                if is_prep_pose or (hold_rom <= 0.25) or (angles_info.get("avg_elbow_reach", 1.0) <= 0.18):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map2_smoothed_hold_rom"] = 0.0
                    feedback_code = "PREP_POSITION"

        elif exercise_id == "horizontal_shoulder_adduction":
            # Map 3
            prep_rom = eval_data.get("prep_rom", eval_data["prep_score"])
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            angles_info = eval_data.get("angles", {})
            elbow_ratio = angles_info.get("elbow_ratio", 1.0)
            wrist_ratio = angles_info.get("wrist_ratio", 1.0)

            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0
            if "active_motion_start_time" not in st:
                st["active_motion_start_time"] = 0.0
            if "map3_smoothed_hold_rom" not in st:
                st["map3_smoothed_hold_rom"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                st["map3_smoothed_hold_rom"] = 0.0
                # Giai doan 1: Nhan dien dong tac chuan bi (Hinh 1: khep 2 khuyu tay & 2 ban tay up vao nhau)
                rom_effective = 1.0 if is_prep_pose else prep_rom
                rom_prog = rom_effective
                eval_data["rom_progress"] = rom_prog

                # Ghi nhan moc bat dau dong tac chuan bi khi o muc ROM thap (<= 0.15) de danh gia nhip do
                if rom_prog <= 0.15:
                    st["prep_onset_time"] = now
                    st["prep_onset_rom"] = rom_prog

                if is_prep_pose and rom_effective >= 1.0:
                    # Kiem tra nhip do thuc hien dong tac chuan bi theo yeu cau cua Lan:
                    # Khong cho phep thuc hien qua nhanh (tang vot tu <= 15% len 100% trong < 0.8s)
                    prep_onset_t = st.get("prep_onset_time", 0.0)
                    prep_onset_r = st.get("prep_onset_rom", 0.0)
                    prep_duration = now - prep_onset_t
                    is_prep_too_fast = (prep_onset_t > 0.0) and (prep_onset_r <= 0.15) and (prep_duration < 0.80)

                    if is_prep_too_fast:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        st["fast_warning_until"] = now + 1.2
                        rep_id = st.get("current_rep_id") or self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_too_fast",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": int(prep_duration * 1000),
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": 0,
                            "quality": 0.35,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                    else:
                        # Thoa man tu the chuan bi -> LAP TUC chuyen sang trang thai cho dong tac giu (opening)
                        st["movement_state"] = "opening"
                        st["movement_start_time"] = now
                        st["active_motion_start_time"] = 0.0
                        st["prep_hold_start_time"] = 0.0
                        st["map3_smoothed_hold_rom"] = 0.0
                        st["motion_onset_rom"] = 0.0
                        st["low_rom_timestamp"] = now
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        feedback_code = "OPEN_ARMS"
                else:
                    feedback_code = "PREP_POSITION"

            elif current_state == "opening":
                hold_prog = 0.0
                # Giai doan 2: Nhan dien dong tac giu (Hinh 2: dang 2 canh tay sang 2 ben)
                # ROM tang dan deu theo khoang cach 2 khuyu tay (tu nho den xap xi gap doi distance_shoulder)
                alpha_hold = 0.75 if hold_rom >= st["map3_smoothed_hold_rom"] else 0.40
                st["map3_smoothed_hold_rom"] = alpha_hold * hold_rom + (1.0 - alpha_hold) * st["map3_smoothed_hold_rom"]
                if (hold_rom >= 0.95) or is_hold_pose:
                    st["map3_smoothed_hold_rom"] = 1.0
                elif hold_rom <= 0.04 and st["map3_smoothed_hold_rom"] <= 0.07:
                    st["map3_smoothed_hold_rom"] = 0.0

                rom_prog = round(st["map3_smoothed_hold_rom"], 3)
                eval_data["rom_progress"] = rom_prog

                # Ghi nhan muc ROM thap nhat o the opening
                if hold_rom <= 0.12:
                    st["low_rom_timestamp"] = now
                    st["motion_onset_rom"] = hold_rom

                # Khi ROM cham 100% (khoang cach 2 khuyu tay dat xap xi gap doi distance_shoulder theo Calibration):
                if (rom_prog >= 1.0) or (is_hold_pose and hold_rom >= 0.95):
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0

                    # Kiem tra giat mo tay an gian dot ngot (< 250ms)
                    low_rom_t = st.get("low_rom_timestamp", 0.0)
                    onset_r = st.get("motion_onset_rom", 0.0)
                    time_from_low = now - low_rom_t
                    is_abrupt_open = (onset_r <= 0.12) and (time_from_low < 0.25) and (low_rom_t > 0.0)

                    if is_abrupt_open:
                        feedback_code = "MOVEMENT_TOO_FAST"
                        st["fast_warning_until"] = now + 1.2
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "movement_too_fast",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": int(time_from_low * 1000),
                            "max_rom_ratio": round(st.get("peak_rom_achieved", 1.0), 2),
                            "hold_duration_ms": 0,
                            "quality": 0.35,
                            "feedback_code": "MOVEMENT_TOO_FAST",
                        })
                        st["movement_state"] = "returning"
                        st["active_motion_start_time"] = 0.0
                        st["map3_smoothed_hold_rom"] = 0.0
                    else:
                        st["movement_state"] = "holding"
                        st["hold_start_time"] = now
                        st["last_hold_emit_time"] = now
                        st["hold_grace_start_time"] = 0.0
                        st["active_motion_start_time"] = 0.0
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "target_reached",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "TARGET_REACHED",
                        })
                        events.append({
                            "event": "hold_started",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_STARTED",
                        })
                        feedback_code = "HOLD_STARTED"
                elif (angles_info.get("avg_wrist_reach", 0.0) < 0.10) and (angles_info.get("avg_elbow_reach", 0.0) < -0.45):
                    # Neu nguoi tap ha xuoi han 2 tay xuong -> quay ve ready de vao lai the chuan bi Hinh 1
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map3_smoothed_hold_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                else:
                    feedback_code = "OPEN_ARMS"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) KHI ROM CHAM 100%
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Khi nguoi tap duy tri tu the giu Hinh 2: ghim ROM o 100%
                if hold_rom >= 0.40 or is_hold_pose:
                    rom_prog = 1.0
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"
                else:
                    rom_prog = max(0.40, hold_rom)
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    if (now - st["hold_grace_start_time"]) >= 1.0:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        events.append({
                            "event": "rep_rejected",
                            "rep_candidate_id": rep_id,
                            "duration_ms": hold_elapsed_ms,
                            "max_rom_ratio": round(st.get("peak_rom_achieved", 1.0), 2),
                            "hold_duration_ms": hold_elapsed_ms,
                            "quality": 0.45,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "opening"
                        st["hold_grace_start_time"] = 0.0
                        st["map3_smoothed_hold_rom"] = hold_rom
                        feedback_code = "HOLD_INTERRUPTED"
                    else:
                        feedback_code = "KEEP_POSITION"

                eval_data["rom_progress"] = rom_prog

                if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0 and st["movement_state"] == "holding":
                    st["last_hold_emit_time"] = now
                    events.append({
                        "event": "hold_progress",
                        "rep_candidate_id": st["current_rep_id"],
                        "hold_elapsed_ms": hold_elapsed_ms,
                        "hold_target_ms": hold_duration_ms,
                        "hold_progress": round(hold_prog, 2),
                        "feedback_code": "KEEP_POSITION",
                    })

                # Khi giu du 5 giay (100% hold) -> Hoan thanh 1 lan tap -> Nhan vat day buc tuong!
                if hold_prog >= 1.0 and st["movement_state"] == "holding":
                    rep_id = st["current_rep_id"]
                    st["completed_reps"] = st.get("completed_reps", 0) + 1
                    total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                    events.append({
                        "event": "hold_completed",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_COMPLETED",
                    })
                    events.append({
                        "event": "rep_completed",
                        "rep_candidate_id": rep_id,
                        "duration_ms": total_duration_ms,
                        "max_rom_ratio": 1.0,
                        "hold_duration_ms": hold_duration_ms,
                        "quality": 1.0,
                        "feedback_code": "REP_VALID",
                    })
                    st["movement_state"] = "returning"
                    st["hold_grace_start_time"] = 0.0
                    st["map3_smoothed_hold_rom"] = 0.0
                    feedback_code = "PUSH_SUCCESS"

            elif current_state == "returning":
                hold_prog = 0.0
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                if now < st.get("fast_warning_until", 0.0):
                    feedback_code = "MOVEMENT_TOO_FAST"
                else:
                    feedback_code = "RETURN_TO_PREP"

                # Khi nguoi choi khep tay tro ve the chuan bi (Hinh 1 hoac elbow_ratio <= 0.75):
                if is_prep_pose or (elbow_ratio <= 0.75) or (hold_rom <= 0.20):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map3_smoothed_hold_rom"] = 0.0
                    st["prep_onset_time"] = 0.0
                    st["prep_onset_rom"] = 0.0
                    feedback_code = "PREP_POSITION"

        elif exercise_id == "hands_behind_head":
            # Map 4
            prep_rom = eval_data.get("prep_rom", eval_data["prep_score"])
            is_prep_pose = eval_data["is_prep_pose"]
            hold_rom = eval_data["hold_rom"]
            is_hold_pose = eval_data["is_hold_pose"]
            elbow_ratio = eval_data.get("angles", {}).get("elbow_ratio", 1.0)
            target_close_ratio = eval_data.get("angles", {}).get("target_close_ratio", 0.96)

            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0
            if "active_motion_start_time" not in st:
                st["active_motion_start_time"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                if is_prep_pose:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0

                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # On dinh the chuan bi (Hinh 1) 0.35s voi ROM = 100% -> chuyen sang nhan dien Dong tac giu (Hinh 2)
                    if (now - st["prep_hold_start_time"]) >= 0.35:
                        st["movement_state"] = "closing"
                        st["movement_start_time"] = now
                        st["active_motion_start_time"] = 0.0
                        st["prep_hold_start_time"] = 0.0
                        st["peak_closing_rom"] = 0.0
                        st["map4_smoothed_hold_rom"] = 0.0
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        events.append({
                            "event": "feedback",
                            "feedback_code": "CLOSE_ELBOWS",
                        })
                        feedback_code = "CLOSE_ELBOWS"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    rom_prog = prep_rom
                    eval_data["rom_progress"] = rom_prog
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "closing":
                hold_prog = 0.0

                # Ghi nhan thoi diem bat dau khep 2 khuyu tay khoi the chuan bi
                if hold_rom < 0.12:
                    st["active_motion_start_time"] = 0.0
                elif st.get("active_motion_start_time", 0.0) == 0.0:
                    st["active_motion_start_time"] = now

                # Thanh ROM tang dan deu tuyen tinh theo do khep 2 khuyu tay ve duong giua
                if is_hold_pose or (hold_rom >= 0.95 and form_valid):
                    rom_prog = 1.0
                else:
                    rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog

                # Khi ROM cham 100% (Hinh 2) -> chuyen sang giu 5 giay (5000ms)
                if is_hold_pose or (hold_rom >= 0.95 and form_valid):
                    st["movement_state"] = "holding"
                    st["peak_closing_rom"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["hold_start_time"] = now
                    st["last_hold_emit_time"] = now
                    st["hold_grace_start_time"] = 0.0
                    rep_id = st["current_rep_id"]
                    events.append({
                        "event": "target_reached",
                        "rep_candidate_id": rep_id,
                        "feedback_code": "TARGET_REACHED",
                    })
                    events.append({
                        "event": "hold_started",
                        "rep_candidate_id": rep_id,
                        "hold_target_ms": hold_duration_ms,
                        "feedback_code": "HOLD_STARTED",
                    })
                    feedback_code = "HOLD_STARTED"
                elif not form_valid and (elbow_ratio < 0.45) and (now - st["movement_start_time"] > 1.5):
                    # Nguoi tap ha buong tay xuong duoi -> quay ve chuan bi
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_closing_rom"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map4_smoothed_hold_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "PREP_POSITION",
                    })
                else:
                    feedback_code = "CLOSE_ELBOWS"

            elif current_state == "holding":
                # TRANG THAI GIU 5 GIAY (HINH 2) - ON DINH TUYET DOI
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Khi dang giu (holding): mien la 2 khuyu tay van khep va ngang tai (hold_rom >= 0.55)
                # thi giu nguyen ROM = 100% va dem nguoc 5 giay muot ma!
                if is_hold_pose or (hold_rom >= 0.55 and form_valid):
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    # Phat hold_progress dinh ky moi 150ms de Godot dieu khien thanh tien do muot ma
                    if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Neu giu du 5 giay (100% hold) -> Hoan thanh 1 rep, nhan vat nhay len mot bac
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        st["completed_reps"] = st.get("completed_reps", 0) + 1
                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 0.98,
                            "feedback_code": "JUMP_SUCCESS",
                        })
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "JUMP_SUCCESS"
                else:
                    # Neu nguoi tap mo toang tay ra lai hoac ha tay xuong qua 1.0 giay -> quay ve 'closing' de khep lai
                    rom_prog = hold_rom
                    eval_data["rom_progress"] = rom_prog
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    if (now - st["hold_grace_start_time"]) >= 1.0:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        st["movement_state"] = "closing"
                        st["hold_grace_start_time"] = 0.0
                        feedback_code = "CLOSE_ELBOWS"
                    else:
                        feedback_code = "KEEP_POSITION"

            elif current_state == "returning":
                if now < st.get("fast_warning_until", 0.0):
                    feedback_code = "MOVEMENT_TOO_FAST"
                else:
                    feedback_code = "RETURN_TO_PREP"
                    if is_prep_pose:
                        st["movement_state"] = "ready"
                        feedback_code = "PREP_POSITION"

                # Khi nguoi choi mo 2 khuyu tay tro ve vi tri ban dau (Hinh 1 hoac elbow_ratio >= 1.35):
                if is_prep_pose or (elbow_ratio >= 1.35) or (hold_rom <= 0.20):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_closing_rom"] = 0.0
                    st["active_motion_start_time"] = 0.0
                    st["map4_smoothed_hold_rom"] = 0.0
                    feedback_code = "PREP_POSITION"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "PREP_POSITION",
                    })

        else:
            # Map 5
            prep_rom = eval_data.get("prep_rom", eval_data.get("prep_score", 0.0))
            is_prep_pose = eval_data.get("is_prep_pose", False)
            hold_rom = eval_data.get("hold_rom", 0.0)
            is_hold_pose = eval_data.get("is_hold_pose", False)
            wrong_side = eval_data.get("wrong_side_detected", False)
            active_side = eval_data.get("active_side", "right")
            d_el_opp_eff = eval_data.get("angles", {}).get("d_el_opp_eff", 1.2)
            support_clamp_valid = eval_data.get("angles", {}).get("support_clamp_valid", False)

            if "prep_hold_start_time" not in st:
                st["prep_hold_start_time"] = 0.0

            if current_state == "ready":
                hold_prog = 0.0
                if is_prep_pose:
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    if st["prep_hold_start_time"] == 0.0:
                        st["prep_hold_start_time"] = now

                    # On dinh tu the chuan bi 0.35s -> chuyen sang nhan dien dong tac keo cang & giu
                    if (now - st["prep_hold_start_time"]) >= 0.35:
                        st["movement_state"] = "contracting"
                        st["movement_start_time"] = now
                        st["prep_hold_start_time"] = 0.0
                        st["hold_grace_start_time"] = 0.0
                        st["map5_smoothed_hold_rom"] = 0.0
                        rep_id = self._next_rep_candidate_id(exercise_id)
                        events.append({
                            "event": "movement_started",
                            "rep_candidate_id": rep_id,
                            "feedback_code": "PREP_COMPLETED",
                        })
                        feedback_code = "CONTINUE_MOVEMENT"
                    else:
                        feedback_code = "PREP_POSITION"
                else:
                    rom_prog = prep_rom
                    eval_data["rom_progress"] = rom_prog
                    st["prep_hold_start_time"] = 0.0
                    feedback_code = "PREP_POSITION"

            elif current_state == "contracting":
                hold_prog = 0.0
                if wrong_side:
                    rom_prog = 0.0
                    eval_data["rom_progress"] = 0.0
                    feedback_code = "SWITCH_ARM_SIDE"
                    events.append({
                        "event": "feedback",
                        "feedback_code": "SWITCH_ARM_SIDE",
                    })
                else:
                    if is_hold_pose or (hold_rom >= 0.95 and form_valid):
                        rom_prog = 1.0
                    else:
                        rom_prog = hold_rom
                    eval_data["rom_progress"] = rom_prog

                    # Khi ROM cham 100% (khoang cach khuyu tay - vai doi dien dat nguong <= 0.50*sw va tay do kep dung):
                    if is_hold_pose or (hold_rom >= 0.95 and form_valid):
                        st["movement_state"] = "holding"
                        st["active_stretch_side"] = active_side
                        st["hold_start_time"] = now
                        st["last_hold_emit_time"] = now
                        st["hold_grace_start_time"] = 0.0
                        st["peak_rom_achieved"] = 1.0
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "target_reached",
                            "rep_candidate_id": rep_id,
                            "active_side": active_side,
                            "feedback_code": "TARGET_REACHED",
                        })
                        events.append({
                            "event": "hold_started",
                            "rep_candidate_id": rep_id,
                            "active_side": active_side,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_STARTED",
                        })
                        feedback_code = "HOLD_STARTED"
                    elif (d_el_opp_eff <= 0.85) and (not support_clamp_valid):
                        feedback_code = "CLAMP_WITH_OTHER_HAND"
                    else:
                        feedback_code = "CONTINUE_MOVEMENT"

            elif current_state == "holding":
                hold_elapsed_ms = int((now - st["hold_start_time"]) * 1000)
                hold_prog = min(1.0, hold_elapsed_ms / float(hold_duration_ms))

                # Mien la nguoi tap van duy tri tu the keo cang & kep tay (form_valid hoac hold_rom >= 0.55)
                if is_hold_pose or (hold_rom >= 0.55 and form_valid):
                    rom_prog = 1.0
                    eval_data["rom_progress"] = 1.0
                    st["hold_grace_start_time"] = 0.0
                    feedback_code = "KEEP_POSITION"

                    # Phat hold_progress dinh ky moi 150ms LIEN TUC giup UI Godot chay muot ma
                    if (now - st["last_hold_emit_time"] >= 0.15) and hold_prog < 1.0:
                        st["last_hold_emit_time"] = now
                        events.append({
                            "event": "hold_progress",
                            "rep_candidate_id": st["current_rep_id"],
                            "active_side": st.get("active_stretch_side", active_side),
                            "hold_elapsed_ms": hold_elapsed_ms,
                            "hold_target_ms": hold_duration_ms,
                            "hold_progress": round(hold_prog, 2),
                            "feedback_code": "KEEP_POSITION",
                        })

                    # Neu giu du 30 giay quy dinh (hold_prog >= 1.0)
                    if hold_prog >= 1.0:
                        rep_id = st["current_rep_id"]
                        completed_side = st.get("active_stretch_side", active_side)
                        if completed_side not in ("left", "right"):
                            completed_side = active_side
                        st["last_completed_side"] = completed_side
                        st["required_side"] = "left" if completed_side == "right" else "right"
                        st["completed_reps"] = st.get("completed_reps", 0) + 1

                        total_duration_ms = int((now - st["movement_start_time"]) * 1000)
                        events.append({
                            "event": "hold_completed",
                            "rep_candidate_id": rep_id,
                            "active_side": completed_side,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_COMPLETED",
                        })
                        events.append({
                            "event": "rep_completed",
                            "rep_candidate_id": rep_id,
                            "active_side": completed_side,
                            "next_required_side": st["required_side"],
                            "duration_ms": total_duration_ms,
                            "max_rom_ratio": 1.0,
                            "hold_duration_ms": hold_duration_ms,
                            "quality": 1.0,
                            "feedback_code": "REP_VALID",
                        })
                        feedback_code = "REP_VALID"
                        st["movement_state"] = "returning"
                        st["hold_grace_start_time"] = 0.0
                        st["map5_smoothed_hold_rom"] = 0.0
                        st["active_stretch_side"] = "none"
                else:
                    rom_prog = hold_rom
                    eval_data["rom_progress"] = rom_prog
                    if st["hold_grace_start_time"] == 0.0:
                        st["hold_grace_start_time"] = now

                    # Neu buong tay qua 1.5 giay -> bao HOLD_INTERRUPTED va quay ve 'contracting' de keo lai
                    if (now - st["hold_grace_start_time"]) >= 1.5:
                        rep_id = st["current_rep_id"]
                        events.append({
                            "event": "hold_interrupted",
                            "rep_candidate_id": rep_id,
                            "hold_target_ms": hold_duration_ms,
                            "feedback_code": "HOLD_INTERRUPTED",
                        })
                        feedback_code = "HOLD_INTERRUPTED"
                        st["movement_state"] = "contracting"
                        st["hold_grace_start_time"] = 0.0
                        st["map5_smoothed_hold_rom"] = 0.0
                        st["active_stretch_side"] = "none"
                    else:
                        feedback_code = "KEEP_POSITION"

            elif current_state == "returning":
                hold_prog = 0.0
                rom_prog = hold_rom
                eval_data["rom_progress"] = rom_prog
                feedback_code = "RETURN_TO_PREP"

                # Khi nguoi choi tha long tay ve tu the chuan bi (d_el_opp_eff >= 0.85 hoac hold_rom <= 0.25):
                if is_prep_pose and ((d_el_opp_eff >= 0.85) or (hold_rom <= 0.25)):
                    st["movement_state"] = "ready"
                    st["prep_hold_start_time"] = 0.0
                    st["peak_rom_achieved"] = 0.0
                    st["hold_grace_start_time"] = 0.0
                    st["map5_smoothed_hold_rom"] = 0.0
                    st["active_stretch_side"] = "none"
                    feedback_code = "PREP_POSITION"

        st["last_rom_progress"] = rom_prog
        st["last_hold_progress"] = hold_prog

        # 3. Dong goi pose_frame metrics
        movement_duration_ms = 0
        if st["movement_start_time"] > 0:
            movement_duration_ms = int((now - st["movement_start_time"]) * 1000)

        pose_metrics = {
            "angles": eval_data["angles"],
            "exercise": {
                "exercise_id": exercise_id,
                "movement_state": st["movement_state"],
                "form_valid": form_valid,
                "rom_progress": round(rom_prog, 2),
                "hold_progress": round(hold_prog, 2),
                "movement_duration_ms": movement_duration_ms,
                "quality": 0.92 if form_valid else 0.50,
                "feedback_code": feedback_code,
            },
        }

        return pose_metrics, events