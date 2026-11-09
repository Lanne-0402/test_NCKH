"""
Module hand_service.py - Xu ly va toi uu con tro dieu khien ban tay tu PoseLandmarker.
Phuc vu dieu khien UI khong cham (Touchless UI) cho Game 2D Pixel Phuc hoi chuc nang.
Tac gia: Nong Thi Hong Lan (AI Backend)
"""

import math
from typing import Dict, Any, List, Optional, Tuple


class HandService:
    """
    Dich vu tinh toan toa do con tro ban tay tren man hinh tu khung xuong PoseLandmarker.
    Dac diem:
    - Anh xa vung chuyen dong thoai mai truoc nguc X in [0.35, 0.65], Y in [0.30, 0.70] -> [0.0, 1.0].
    - Giam 1/4 do nhay (Sensitivity = 0.75) de con tro dam chac, phu hop benh nhan lon tuoi/run tay.
    - Bo loc thich ung Adaptive EMA: min muot khi di chuyen cham, tuc thoi khi di chuyen nhanh.
    - Co che Deadzone Triet tieu troi tuyet doi (Zero-Drift): khoa cung con tro khi dung yen de nap Dwell 1.5s.
    - Hysteresis giu tay chu dong (Active Hand), tranh nhay chop choi giua tay trai va phai.
    """

    # Vung chuyen dong thoai mai truoc nguc
    BOX_X_MIN = 0.35
    BOX_X_MAX = 0.65
    BOX_Y_MIN = 0.30
    BOX_Y_MAX = 0.70

    # He so do nhay (giam xuong 0.58 de con tro dam chac, khong bi qua nhay)
    SENSITIVITY = 0.58

    # Nguong triet tieu troi tuyet doi (Zero-Drift Deadzone) tang len 0.016 de khoa cung khi dung yen
    DEADZONE_DIST = 0.016

    # Landmarks index tu MediaPipe Pose (33 points)
    LEFT_SHOULDER = 11
    RIGHT_SHOULDER = 12
    LEFT_WRIST = 15
    RIGHT_WRIST = 16
    LEFT_INDEX = 19
    RIGHT_INDEX = 20
    LEFT_HIP = 23
    RIGHT_HIP = 24

    def __init__(self):
        self.active_side: Optional[str] = None  # "left" hoac "right"
        self.cursor_x: float = 0.5
        self.cursor_y: float = 0.5
        self.is_active: bool = False
        self.confidence: float = 0.0
        self.last_target_x: float = 0.5
        self.last_target_y: float = 0.5

    def reset(self):
        """Reset trang thai con tro."""
        self.active_side = None
        self.is_active = False
        self.cursor_x = 0.5
        self.cursor_y = 0.5
        self.confidence = 0.0

    def _get_point_pos(self, landmarks, idx: int) -> Tuple[float, float, float]:
        """Lay toa do x, y va visibility cua mot landmark an toan."""
        if not landmarks or idx >= len(landmarks):
            return 0.0, 0.0, 0.0
        pt = landmarks[idx]
        return float(pt.x), float(pt.y), float(getattr(pt, 'visibility', 1.0))

    def _select_hand(self, landmarks) -> Optional[Tuple[str, float, float, float]]:
        """
        Xac dinh ban tay chu dong (tay duoc nhac len truoc nguc).
        Tra ve (side, x, y, confidence) hoac None neu ca hai tay deu ha thap.
        """
        # Lay toa do hip de lam moc do cao
        _, l_hip_y, _ = self._get_point_pos(landmarks, self.LEFT_HIP)
        _, r_hip_y, _ = self._get_point_pos(landmarks, self.RIGHT_HIP)
        hip_y = (l_hip_y + r_hip_y) / 2.0 if (l_hip_y > 0 and r_hip_y > 0) else 0.80

        # Lay diem dai dien tay trai (uu tien ngón trỏ 19, fallback cổ tay 15)
        l_idx_x, l_idx_y, l_idx_v = self._get_point_pos(landmarks, self.LEFT_INDEX)
        l_wri_x, l_wri_y, l_wri_v = self._get_point_pos(landmarks, self.LEFT_WRIST)
        if l_idx_v >= 0.4:
            l_x, l_y, l_v = l_idx_x, l_idx_y, l_idx_v
        else:
            l_x, l_y, l_v = l_wri_x, l_wri_y, l_wri_v

        # Lay diem dai dien tay phai (uu tien ngón trỏ 20, fallback cổ tay 16)
        r_idx_x, r_idx_y, r_idx_v = self._get_point_pos(landmarks, self.RIGHT_INDEX)
        r_wri_x, r_wri_y, r_wri_v = self._get_point_pos(landmarks, self.RIGHT_WRIST)
        if r_idx_v >= 0.4:
            r_x, r_y, r_v = r_idx_x, r_idx_y, r_idx_v
        else:
            r_x, r_y, r_v = r_wri_x, r_wri_y, r_wri_v

        # Dieu kien mot tay duoc coi la dang nhac len dieu khien:
        # 1. Visibility >= 0.35
        # 2. y < hip_y - 0.05 va y <= 0.78 (khong buong thong xuong dui/hong)
        l_eligible = (l_v >= 0.35) and (l_y <= 0.78) and (l_y < hip_y - 0.05)
        r_eligible = (r_v >= 0.35) and (r_y <= 0.78) and (r_y < hip_y - 0.05)

        if not l_eligible and not r_eligible:
            return None

        # Hysteresis: Neu tay da chon truoc do van hop le thi tiep tuc duy tri
        if self.active_side == "left" and l_eligible:
            return "left", l_x, l_y, l_v
        if self.active_side == "right" and r_eligible:
            return "right", r_x, r_y, r_v

        # Neu chua chon hoac tay cu da ha: Chon tay duoc nhac cao hon (y nho hon)
        if l_eligible and r_eligible:
            if l_y < r_y:
                return "left", l_x, l_y, l_v
            else:
                return "right", r_x, r_y, r_v
        elif l_eligible:
            return "left", l_x, l_y, l_v
        else:
            return "right", r_x, r_y, r_v

    def process(self, landmarks) -> Dict[str, Any]:
        """
        Xu ly khung xuong hien tai va tinh toan toa do con tro ban tay.
        Tra ve dict phu hop goi tin hand_control gui sang Godot:
        {
            "active": bool,
            "cursor_x": float,
            "cursor_y": float,
            "confidence": float
        }
        """
        if not landmarks:
            self.is_active = False
            return {
                "active": False,
                "cursor_x": round(self.cursor_x, 4),
                "cursor_y": round(self.cursor_y, 4),
                "confidence": 0.0,
            }

        hand_info = self._select_hand(landmarks)
        if hand_info is None:
            self.is_active = False
            self.active_side = None
            return {
                "active": False,
                "cursor_x": round(self.cursor_x, 4),
                "cursor_y": round(self.cursor_y, 4),
                "confidence": 0.0,
            }

        side, raw_x, raw_y, conf = hand_info
        self.active_side = side
        self.confidence = conf
        self.is_active = True

        # 1. Tinh do lech tuong doi so voi tam vung thoai mai truoc nguc (Tam: 0.50, 0.50)
        # Nua do rong vung: (0.65 - 0.35) / 2 = 0.15
        # Nua do cao vung: (0.70 - 0.30) / 2 = 0.20
        box_center_x = (self.BOX_X_MIN + self.BOX_X_MAX) / 2.0
        box_center_y = (self.BOX_Y_MIN + self.BOX_Y_MAX) / 2.0
        box_half_w = (self.BOX_X_MAX - self.BOX_X_MIN) / 2.0
        box_half_h = (self.BOX_Y_MAX - self.BOX_Y_MIN) / 2.0

        rel_dx = (raw_x - box_center_x) / box_half_w
        rel_dy = (raw_y - box_center_y) / box_half_h

        # 2. Anh xa vao toan man hinh [0.0, 1.0] kem giam 1/4 do nhay (SENSITIVITY = 0.75)
        # Khi S = 0.75, bien do dich chuyen se dam va on dinh hon 25%, tranh rung giat
        target_x = 0.50 + (rel_dx * 0.50 * self.SENSITIVITY)
        target_y = 0.50 + (rel_dy * 0.50 * self.SENSITIVITY)

        target_x = max(0.0, min(1.0, target_x))
        target_y = max(0.0, min(1.0, target_y))

        # 3. Triet tieu troi tuyet doi (Zero-Drift Deadzone)
        # Neu khoang dich chuyen rat nho (vi rung sinh ly cua ban tay khi co gang giu yen)
        # -> Khoa cung toa do tai cho de nap Dwell 1.5s cuc ky on dinh!
        dist = math.hypot(target_x - self.cursor_x, target_y - self.cursor_y)

        if dist < self.DEADZONE_DIST:
            # Khoa troi hoan toan (Zero drift)
            filtered_x = self.cursor_x
            filtered_y = self.cursor_y
        else:
            # 4. Bo loc Adaptive EMA lam muot chuyen dong
            # Di chuyen cham: alpha = 0.22 (sieu em, muot ma)
            # Di chuyen nhanh: alpha tang len den 0.65 (bam tay tuc thoi, khong lag)
            if dist < 0.04:
                alpha = 0.16
            else:
                alpha = min(0.55, 0.16 + (dist - 0.04) * 6.0)

            filtered_x = (alpha * target_x) + ((1.0 - alpha) * self.cursor_x)
            filtered_y = (alpha * target_y) + ((1.0 - alpha) * self.cursor_y)

        self.cursor_x = filtered_x
        self.cursor_y = filtered_y
        self.last_target_x = target_x
        self.last_target_y = target_y

        return {
            "active": True,
            "cursor_x": round(self.cursor_x, 4),
            "cursor_y": round(self.cursor_y, 4),
            "confidence": round(self.confidence, 2),
        }
