"""
Ung dung Backend AI Nhan dien cu dong canh tay ho tro Phuc hoi chuc nang.
Giao tiep voi Godot Engine qua WebSocket (ws://127.0.0.1:8765) theo JSON Contract 1.0.0.
Su dung MediaPipe Tasks API (PoseLandmarker - Live Stream Mode) va OpenCV.
Tac gia: Nong Thi Hong Lan (AI & Computer Vision Backend)
"""

import asyncio
import atexit
import base64
import cv2
import json
import math
import os
import signal
import sys
import time
import websockets
import mediapipe as mp
from exercises_logic import ExercisesEvaluator, LandmarkPoint
from hand_service import HandService
from mongodb_service import start_mongodb_bridge_thread, stop_mongodb_bridge

def get_resource_path(relative_path: str) -> str:
    """Lay duong dan tuyet doi den file tai nguyen, ho tro ca chay truc tiep va khi dong goi qua PyInstaller."""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    base_dir = os.path.dirname(os.path.abspath(__file__))
    candidate = os.path.join(base_dir, relative_path)
    if os.path.exists(candidate):
        return candidate
    return relative_path

# ==========================================
# CAU HINH HE THONG
# ==========================================
HOST = "127.0.0.1"
PORT = 8765
MODEL_PATH = get_resource_path("pose_landmarker_full.task")
TARGET_FPS = 30
POSE_SEND_FPS = 15    # Tan so gui pose_frame sang Godot
CAMERA_SEND_FPS = 15  # Tan so gui camera_frame (video stream) sang Godot

# Khoi tao bo danh gia y khoa va bo dieu khien ban tay
evaluator = ExercisesEvaluator()
hand_service = HandService()

app_state = {
    "session_id": None,
    "current_exercise": None,
    "is_exercising": False,
    "connected_client": None,
    "last_tracking_code": "",
    "last_tracking_status_send_time": 0.0,
    "last_hand_active": False,
    "last_hand_inactive_send_time": 0.0,
    "message_sequence": 0,
    "last_active_landmarks": None,
    "last_landmarks_time": 0.0,
    "cached_hud_info": {
        "exercise_id": "CHO KET NOI GODOT",
        "movement_state": "READY",
        "rom_progress": 0.0,
        "hold_progress": 0.0,
        "feedback_code": "POSITION_OK",
    },
}

# Bien luu ket qua tu callback cua MediaPipe LiveStream
latest_result = None
latest_timestamp = 0

# ==========================================
# QUAN LY VONG DOI & GIAI PHONG TAI NGUYEN (GRACEFUL SHUTDOWN)
# ==========================================
is_shutting_down = False
_cleaned_up = False
_active_camera = None
_active_landmarker = None


def open_webcam(indices=(0, 1)):
    """Thu mo camera qua DirectShow (uu tien Windows) hoac backend mac dinh."""
    for idx in indices:
        if sys.platform.startswith("win"):
            cap = cv2.VideoCapture(idx, cv2.CAP_DSHOW)
            if cap.isOpened():
                ret, _ = cap.read()
                if ret:
                    return cap
                cap.release()
        cap = cv2.VideoCapture(idx)
        if cap.isOpened():
            ret, _ = cap.read()
            if ret:
                return cap
            cap.release()
    return None


def cleanup_resources():
    """Giai phong sach se toan bo tai nguyen: Camera, OpenCV, Socket, MongoDB."""
    global is_shutting_down, _active_camera, _active_landmarker, _cleaned_up
    is_shutting_down = True
    if _cleaned_up:
        return
    _cleaned_up = True
    print("\n[System] Dang thu hoi tai nguyen an toan (Graceful Cleanup)...")

    # 1. Giai phong Camera
    if _active_camera is not None:
        try:
            if _active_camera.isOpened():
                _active_camera.release()
            print("[System] Da giai phong Camera.")
        except Exception as exc:
            print(f"[System] Loi khi giai phong Camera: {exc}")
        _active_camera = None

    # 2. Dong cac cua so OpenCV
    try:
        cv2.destroyAllWindows()
    except Exception:
        pass

    # 3. Dong MediaPipe Landmarker
    if _active_landmarker is not None:
        try:
            _active_landmarker.close()
            print("[System] Da dong MediaPipe Landmarker.")
        except Exception:
            pass
        _active_landmarker = None

    # 4. Giai phong cong HTTP Bridge cua MongoDB (8766)
    try:
        stop_mongodb_bridge()
    except Exception as exc:
        print(f"[System] Loi khi giai phong MongoDB Bridge: {exc}")


def _signal_handler(sig, _frame):
    """Bat su kien SIGINT (Ctrl+C) hoac SIGTERM de kich hoat Shutdown trật tự."""
    global is_shutting_down
    if not is_shutting_down:
        print(f"\n[System] Nhan tin hieu ngat ({sig}). Dang dong ung dung...")
        is_shutting_down = True


try:
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)
    if hasattr(signal, "SIGBREAK"):
        signal.signal(signal.SIGBREAK, _signal_handler)
except Exception:
    pass

atexit.register(cleanup_resources)


def update_result(result, output_image, timestamp_ms):
    """Callback thuc thi tu thread noi bo cua MediaPipe."""
    global latest_result, latest_timestamp
    latest_result = result
    latest_timestamp = timestamp_ms


def make_message(msg_type: str, payload: dict, session_id: str = None) -> dict:
    """Dong goi goi tin dung chuan JSON Contract 1.0.0."""
    app_state["message_sequence"] += 1
    now_ms = int(time.time() * 1000)
    return {
        "contract_version": "1.0.0",
        "type": msg_type,
        "message_id": f"msg-{now_ms}-{app_state['message_sequence']:05d}",
        "session_id": session_id if session_id else app_state["session_id"],
        "timestamp_ms": now_ms,
        "source": "backend",
        "payload": payload,
    }


async def send_to_godot(msg_dict: dict, timeout: float = 0.05):
    """Gui goi tin JSON sang Godot an toan voi timeout chong block camera loop."""
    client = app_state["connected_client"]
    if client:
        try:
            await asyncio.wait_for(client.send(json.dumps(msg_dict)), timeout=timeout)
        except asyncio.TimeoutError:
            pass  # Drop packet khi client buffer bi nghen de bao toan camera loop khong bi freeze
        except (websockets.exceptions.ConnectionClosed, websockets.exceptions.ConnectionClosedOK):
            app_state["connected_client"] = None


# ==========================================
# WEBSOCKET SERVER HANDLER
# ==========================================
async def websocket_handler(websocket):
    print(f"[WebSocket] Godot da ket noi tu: {websocket.remote_address}")
    app_state["connected_client"] = websocket

    # 1. Gui server_hello ngay khi Godot ket noi
    server_hello = make_message("server_hello", {
        "backend_version": "0.1.0",
        "pose_engine": "mediapipe",
        "camera_available": True,
        "supported_exercises": [
            "scapular_retraction",
            "wall_abduction_external_rotation",
            "horizontal_shoulder_adduction",
            "hands_behind_head",
            "cross_body_shoulder_stretch",
        ],
        "supported_features": [
            "pose_tracking",
            "joint_angles",
            "calibration",
            "movement_speed_validation",
            "hold_validation",
            "hand_control",
        ],
    })
    await websocket.send(json.dumps(server_hello))
    print("[WebSocket] Da gui server_hello cho Godot.")

    try:
        async for raw_message in websocket:
            try:
                data = json.loads(raw_message)
            except json.JSONDecodeError:
                continue

            msg_type = data.get("type")
            payload = data.get("payload", {})
            session_id = data.get("session_id")

            if msg_type == "client_hello":
                frontend_app = payload.get("application", "unknown")
                print(f"[WebSocket] Nhan client_hello tu Frontend: {frontend_app}")

            elif msg_type == "start_calibration":
                ex_id = payload.get("exercise_id", "scapular_retraction")
                dur_ms = payload.get("duration_ms", 5000)
                side = payload.get("target_side", "both")
                app_state["session_id"] = session_id
                evaluator.start_calibration(ex_id, dur_ms, side)
                print(f"[WebSocket] Bat dau Calibration: {ex_id} trong {dur_ms}ms (Ben: {side})")

            elif msg_type == "start_exercise":
                ex_id = payload.get("exercise_id", "scapular_retraction")
                app_state["session_id"] = session_id
                app_state["current_exercise"] = ex_id
                app_state["is_exercising"] = True
                evaluator.configure_exercise(ex_id, payload)
                print(f"[WebSocket] Bat dau bai tap: {ex_id} | Session: {session_id}")

            elif msg_type == "pause_exercise":
                evaluator.pause()
                print("[WebSocket] Tam dung bai tap.")

            elif msg_type == "resume_exercise":
                evaluator.resume()
                print("[WebSocket] Tiep tuc bai tap.")

            elif msg_type == "stop_exercise":
                app_state["is_exercising"] = False
                evaluator.stop_calibration()
                print(f"[WebSocket] Dung bai tap. Ly do: {payload.get('reason', 'unspecified')}")

    except websockets.exceptions.ConnectionClosed:
        print("[WebSocket] Godot da ngat ket noi.")
    finally:
        if app_state["connected_client"] == websocket:
            app_state["connected_client"] = None
        app_state["is_exercising"] = False
        evaluator.stop_calibration()


# ==========================================
# VE SKELETON VA HUD TREN OPEN CV (BONUS)
# ==========================================
SKELETON_PAIRS = [
    (11, 12),  # Hai vai
    (11, 13), (13, 15),  # Tay trai
    (12, 14), (14, 16),  # Tay phai
    (11, 23), (12, 24),  # Than nguoi
    (23, 24),  # Hai hong
]

FEEDBACK_VN_MAP = {
    "POSITION_OK": "Vi tri thich hop",
    "MOVE_BACK": "Hay lui lai mot chut",
    "MOVE_CLOSER": "Hay tien gan camera hon",
    "CENTER_YOUR_BODY": "Hay dung vao giua khung hinh",
    "SHOULDERS_NOT_VISIBLE": "Khong thay ro hai vai",
    "LEFT_ARM_NOT_VISIBLE": "Tay trai bi khuat",
    "RIGHT_ARM_NOT_VISIBLE": "Tay phai bi khuat",
    "KEEP_POSITION": "Dang giu tu the...",
    "CONTINUE_MOVEMENT": "Tiep tuc dong tac...",
    "TARGET_REACHED": "Da dat bien do! Giu tu the",
    "HOLD_STARTED": "Bat dau giu tu the...",
    "HOLD_PROGRESS": "Dang duy tri giu the...",
    "HOLD_COMPLETED": "Hoan thanh giu the!",
    "HOLD_INTERRUPTED": "Tu the bi gian doan!",
    "RELEASE_POSITION": "Da pha da! Dua tay ve truoc (ROM < 40%) de chuan bi",
    "READY_FOR_NEXT_REP": "San sang! Ep chat hai ba vai ra sau de chem da",
    "PREP_POSITION": "Vao the chuan bi (chu U vuong goc)",
    "PREP_COMPLETED": "Da vao the chuan bi! Tu tu vuon tay...",
    "TRANSITION_DELAY_3": "Tu tu vuon tay len cao: 3s...",
    "TRANSITION_DELAY_2": "Tu tu vuon tay len cao: 2s...",
    "TRANSITION_DELAY_1": "Tu tu vuon tay len cao: 1s...",
    "REACH_OVERHEAD": "Hay vuon 2 tay len cao tren dau!",
    "OPEN_ARMS": "Dang 2 canh tay sang 2 ben!",
    "CLOSE_ELBOWS": "Khep 2 khuyu tay ve phia truoc mat!",
    "LIFT_SUCCESS": "Tuyet voi! Da day thanh cong tang da!",
    "PUSH_SUCCESS": "Tuyet voi! Da day lui 2 buc tuong!",
    "JUMP_SUCCESS": "Tuyet voi! Da nhay len bac tiep theo!",
    "RETURN_TO_PREP": "Mo 2 khuyu tay sang 2 ben de chuan bi lan tiep theo",
    "MOVEMENT_TOO_FAST": "Cu dong qua nhanh! Hay ep cham va giu tu the",
    "REP_VALID": "Dong tac hop le! Rat tot",
    "CALIBRATION_COMPLETED": "Hieu chuan bien do thanh cong!",
    "TRACKING_LOST": "Khong nhan dien duoc nguoi",
}


def draw_skeleton(frame, landmarks):
    """Chi ve bo xuong khop AI len frame camera (khong ve HUD banner de len mat)."""
    if not landmarks:
        return
    h, w, _ = frame.shape
    for p1_idx, p2_idx in SKELETON_PAIRS:
        if p1_idx < len(landmarks) and p2_idx < len(landmarks):
            p1 = landmarks[p1_idx]
            p2 = landmarks[p2_idx]
            if getattr(p1, 'visibility', 1.0) > 0.4 and getattr(p2, 'visibility', 1.0) > 0.4:
                pt1 = (int(p1.x * w), int(p1.y * h))
                pt2 = (int(p2.x * w), int(p2.y * h))
                cv2.line(frame, pt1, pt2, (0, 230, 115), 3, cv2.LINE_AA)

    for idx in [11, 12, 13, 14, 15, 16, 23, 24]:
        if idx < len(landmarks):
            pt = landmarks[idx]
            if getattr(pt, 'visibility', 1.0) > 0.4:
                center = (int(pt.x * w), int(pt.y * h))
                cv2.circle(frame, center, 6, (0, 140, 255), -1, cv2.LINE_AA)
                cv2.circle(frame, center, 8, (255, 255, 255), 2, cv2.LINE_AA)


def draw_hud_banner(frame, fps: float, exercise_info: dict):
    """Ve khung Banner HUD phia tren cho man hinh OpenCV desktop."""
    # 3. Ve khung Banner HUD phia tren
    overlay = frame.copy()
    cv2.rectangle(overlay, (15, 15), (420, 175), (20, 25, 30), -1)
    cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)
    cv2.rectangle(frame, (15, 15), (420, 175), (0, 200, 150), 2)

    # Thong tin Text
    ex_id = exercise_info.get("exercise_id", "Cho ket noi Godot...")
    state = exercise_info.get("movement_state", "READY").upper()
    fb_code = exercise_info.get("feedback_code", "POSITION_OK")
    if state == "CALIBRATING":
        calib_text = {
            "OPEN_ARMS": "Hay dang thang 2 tay sang 2 ben ngang vai (chu T - 90 do)!",
            "KEEP_POSITION": "Dang do bien do khop vai... Hay dang tay cao nhat co the!",
            "CALIBRATION_COMPLETED": "Hieu chuan bien do T-Pose thanh cong!",
        }
        fb_text = calib_text.get(fb_code, FEEDBACK_VN_MAP.get(fb_code, fb_code))
    elif ex_id == "hands_behind_head":
        map4_text = {
            "PREP_POSITION": "Vao the chuan bi: 2 tay om sau dau, mo rong khuyu",
            "PREP_COMPLETED": "Da vao the chuan bi! Chuan bi khep khuyu tay",
            "TRANSITION_DELAY_3": "Tu tu khep 2 khuyu tay ve truoc mat: 3s...",
            "TRANSITION_DELAY_2": "Tu tu khep 2 khuyu tay ve truoc mat: 2s...",
            "TRANSITION_DELAY_1": "Tu tu khep 2 khuyu tay ve truoc mat: 1s...",
            "CLOSE_ELBOWS": "Khep 2 khuyu tay ve phia truoc mat de nhay!",
            "HOLD_STARTED": "Giu the khep khuyu tay 5s - chuan bi nhay!",
            "KEEP_POSITION": "Dang duy tri the khep khuyu tay...",
            "JUMP_SUCCESS": "Tuyet voi! Da nhay len bac tiep theo!",
            "RETURN_TO_PREP": "Mo 2 khuyu tay sang 2 ben de chuan bi lan tiep theo",
        }
        fb_text = map4_text.get(fb_code, FEEDBACK_VN_MAP.get(fb_code, fb_code))
    elif ex_id == "horizontal_shoulder_adduction":
        map3_text = {
            "PREP_POSITION": "Vao the chuan bi (khep 2 khuyu truoc nguc)",
            "PREP_COMPLETED": "Da vao the chuan bi! Tu tu dang tay...",
            "TRANSITION_DELAY_3": "Tu tu dang 2 tay sang 2 ben: 3s...",
            "TRANSITION_DELAY_2": "Tu tu dang 2 tay sang 2 ben: 2s...",
            "TRANSITION_DELAY_1": "Tu tu dang 2 tay sang 2 ben: 1s...",
            "OPEN_ARMS": "Dang rong 2 canh tay sang 2 ben!",
        }
        fb_text = map3_text.get(fb_code, FEEDBACK_VN_MAP.get(fb_code, fb_code))
    elif ex_id == "cross_body_shoulder_stretch":
        map5_text = {
            "PREP_POSITION": "Tha long 2 vai can bang de vao tu the chuan bi",
            "PREP_COMPLETED": "Da chuan bi! Keo canh tay qua nguc va dung tay kia kep giu",
            "POSITION_OK": "Dung thang truoc camera, san sang keo cang",
            "CONTINUE_MOVEMENT": "Keo khuyu tay sat vai doi dien & dung tay kia kep giu...",
            "CLAMP_WITH_OTHER_HAND": "Hay dung cang tay/co tay con lai kep sat khuyu tay vao nguc!",
            "SWITCH_ARM_SIDE": "Ban da tap tay nay! Hay doi sang keo cang ben tay doi dien!",
            "TARGET_REACHED": "Dat do cang 100%! Bat dau thien giu the 30 giay",
            "HOLD_STARTED": "Dang thien giu the keo cang 30s...",
            "KEEP_POSITION": "Duy tri the thien keo cang 30s...",
            "HOLD_COMPLETED": "Hoan thanh 30 giay thien keo cang! +100 diem thuong",
            "HOLD_INTERRUPTED": "Tu the bi gian doan! Thu lai cham rai",
            "RETURN_TO_PREP": "Tha long 2 tay ve tu the chuan bi",
            "REP_VALID": "Tuyet voi! Da hoan thanh hiep keo cang!",
        }
        fb_text = map5_text.get(fb_code, FEEDBACK_VN_MAP.get(fb_code, fb_code))
    elif ex_id == "scapular_retraction":
        map1_text = {
            "POSITION_OK": "Dung thang truoc camera, san sang ep ba vai",
            "CONTINUE_MOVEMENT": "Co ep hai ba vai ra sau...",
            "TARGET_REACHED": "Dat bien do! Giu the ep ba vai 0.7s de chem da!",
            "HOLD_STARTED": "Giu the ep ba vai 0.7s de chem da!",
            "KEEP_POSITION": "Dang ep chat ba vai... Giu nguyen tu the!",
            "HOLD_COMPLETED": "Tuyet voi! Da chem vo tang da!",
            "MOVEMENT_TOO_FAST": "Cu dong qua nhanh! Hay ep cham va giu tu the",
            "RELEASE_POSITION": "Dua 2 tay ve truoc (ROM < 40%) de mo khoa luot moi",
            "READY_FOR_NEXT_REP": "San sang! Co ep 2 ba vai ra sau va giu 0.7s de chem da",
            "REP_VALID": "Tuyet voi! Da chem tan tang da!",
        }
        fb_text = map1_text.get(fb_code, FEEDBACK_VN_MAP.get(fb_code, fb_code))
    else:
        fb_text = FEEDBACK_VN_MAP.get(fb_code, fb_code)
    rom_prog = exercise_info.get("rom_progress", 0.0)
    hold_prog = exercise_info.get("hold_progress", 0.0)

    cv2.putText(frame, "PHCN AI VISION - MEDIAPIPE FULL", (25, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 200), 2, cv2.LINE_AA)
    cv2.putText(frame, f"FPS: {fps:.1f} | Bai tap: {ex_id}", (25, 65),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1, cv2.LINE_AA)
    cv2.putText(frame, f"Trang thai: {state}", (25, 90),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 215, 0), 2, cv2.LINE_AA)
    cv2.putText(frame, f">> {fb_text}", (25, 115),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (100, 240, 255), 1, cv2.LINE_AA)

    # Thanh tien do ROM / Hold
    bar_x, bar_y, bar_w, bar_h = 25, 130, 370, 18
    cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_w, bar_y + bar_h), (80, 80, 80), 2)

    active_prog = hold_prog if hold_prog > 0 else rom_prog
    fill_w = int(bar_w * max(0.0, min(1.0, active_prog)))
    if hold_prog > 0:
        bar_color = (0, 220, 255)
    elif "DELAY" in state or "PREP" in state:
        bar_color = (0, 165, 255)
    elif state == "RETURNING":
        bar_color = (0, 165, 255)
    else:
        bar_color = (0, 230, 115) if active_prog >= 0.99 else (255, 180, 0)
    cv2.rectangle(frame, (bar_x + 2, bar_y + 2), (bar_x + fill_w, bar_y + bar_h - 2), bar_color, -1)

    if hold_prog > 0:
        if ex_id == "cross_body_shoulder_stretch":
            prog_label = f"THIEN GIU THE: {int(hold_prog * 100)}% ({int(hold_prog * 30)}s/30s)"
        else:
            prog_label = f"HOLD: {int(hold_prog * 100)}% | ROM: {int(rom_prog * 100)}%"
    elif "DELAY" in state:
        prog_label = f"CHUYEN THE: {fb_text}"
    elif state == "RETURNING":
        prog_label = f"HA TAY VE THE CHUAN BI (<40%)"
    else:
        prog_label = f"ROM: {int(rom_prog * 100)}%"
    cv2.putText(frame, prog_label, (bar_x + 30, bar_y + 14),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (20, 20, 20), 1, cv2.LINE_AA)


def draw_hud_and_skeleton(frame, landmarks, fps: float, exercise_info: dict):
    """Ve ca bo xuong khop va thong so thoi gian thuc len man hinh camera OpenCV."""
    draw_skeleton(frame, landmarks)
    draw_hud_banner(frame, fps, exercise_info)


# ==========================================
# LUONG XU LY CAMERA CHINH (MAIN CAMERA LOOP)
# ==========================================
async def process_camera():
    global is_shutting_down, _active_camera, _active_landmarker

    if not os.path.exists(MODEL_PATH):
        print(f"[Loi] Khong tim thay file model: {MODEL_PATH}")
        return

    # Khoi tao MediaPipe PoseLandmarker
    base_options = mp.tasks.BaseOptions(model_asset_path=MODEL_PATH)
    options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=mp.tasks.vision.RunningMode.LIVE_STREAM,
        num_poses=1,
        result_callback=update_result,
        min_pose_detection_confidence=0.6,
        min_pose_presence_confidence=0.6,
        min_tracking_confidence=0.6,
    )
    landmarker = mp.tasks.vision.PoseLandmarker.create_from_options(options)
    _active_landmarker = landmarker
    print(f"[MediaPipe] Da tai thanh cong mo hinh: {MODEL_PATH}")

    # Thu mo Camera khoi dau
    cap = open_webcam()
    if cap is None:
        print("[Canh bao] Khong the ket noi Webcam luc khoi dong. Dang cho nguoi dung cam camera...")
        while not is_shutting_down:
            if app_state["connected_client"]:
                err_msg = make_message("tracking_status", {
                    "status": "camera_disconnected",
                    "person_detected": False,
                    "confidence": 0.0,
                    "full_body_visible": False,
                    "required_body_visible": False,
                    "camera_fps": 0.0,
                    "feedback_code": "CAMERA_DISCONNECTED",
                })
                await send_to_godot(err_msg)
            await asyncio.sleep(2.0)
            cap = open_webcam()
            if cap is not None:
                print("[Camera] Da ket noi duoc Webcam!")
                break
        if is_shutting_down:
            return

    _active_camera = cap

    frame_interval = 1.0 / TARGET_FPS
    pose_send_interval = 1.0 / POSE_SEND_FPS
    camera_send_interval = 1.0 / CAMERA_SEND_FPS
    last_pose_send_time = 0.0
    last_camera_send_time = 0.0
    frame_count = 0

    fps_start_time = time.time()
    fps_frame_count = 0
    current_fps = 30.0

    print("[Camera] Bat dau luong hinh anh Webcam...")
    consecutive_drop_count = 0
    MAX_CONSECUTIVE_DROPS = 30  # ~1.0s lien tuc o 30 FPS

    while not is_shutting_down:
        loop_start = time.time()
        success, frame = cap.read() if (cap and cap.isOpened()) else (False, None)
        if not success or frame is None:
            consecutive_drop_count += 1
            if consecutive_drop_count < MAX_CONSECUTIVE_DROPS:
                await asyncio.sleep(0.033)
                continue

            # Mat tin hieu camera -> Kich hoat Auto-Recovery
            print(f"[Camera] Canh bao: Mat tin hieu Webcam ({consecutive_drop_count} frames). Tien hanh Auto-Recovery...")
            reconnected = False
            for retry_idx in range(1, 4):
                if is_shutting_down:
                    break
                print(f"[Camera] Thu ket noi lai camera (Lan {retry_idx}/3)...")
                if cap:
                    try:
                        cap.release()
                    except Exception:
                        pass
                await asyncio.sleep(1.5)
                new_cap = open_webcam()
                if new_cap is not None:
                    cap = new_cap
                    _active_camera = cap
                    consecutive_drop_count = 0
                    reconnected = True
                    print(f"[Camera] Ket noi lai thanh cong o lan thu {retry_idx}!")
                    break

            if reconnected:
                if app_state["connected_client"]:
                    recover_msg = make_message("tracking_status", {
                        "status": "tracking",
                        "person_detected": False,
                        "confidence": 0.0,
                        "full_body_visible": False,
                        "required_body_visible": False,
                        "camera_fps": 0.0,
                        "feedback_code": "CAMERA_RECONNECTED",
                    })
                    await send_to_godot(recover_msg)
                continue

            # Sau 3 lan thu that bai -> Gui thong bao CAMERA_DISCONNECTED sang Godot
            print("[Camera] Mat ket noi Webcam hoan toan. Gui CAMERA_DISCONNECTED sang Godot...")
            if app_state["connected_client"]:
                disconnect_msg = make_message("tracking_status", {
                    "status": "camera_disconnected",
                    "person_detected": False,
                    "confidence": 0.0,
                    "full_body_visible": False,
                    "required_body_visible": False,
                    "camera_fps": 0.0,
                    "feedback_code": "CAMERA_DISCONNECTED",
                })
                await send_to_godot(disconnect_msg)

            # Vong lap tham do nen (Background Auto-Recovery Polling) moi 2.5 giay
            while not is_shutting_down:
                await asyncio.sleep(2.5)
                if app_state["connected_client"]:
                    await send_to_godot(make_message("tracking_status", {
                        "status": "camera_disconnected",
                        "person_detected": False,
                        "confidence": 0.0,
                        "full_body_visible": False,
                        "required_body_visible": False,
                        "camera_fps": 0.0,
                        "feedback_code": "CAMERA_DISCONNECTED",
                    }))
                new_cap = open_webcam()
                if new_cap is not None:
                    cap = new_cap
                    _active_camera = cap
                    consecutive_drop_count = 0
                    print("[Camera] Webcam da duoc cam lai! Tu dong phuc hoi he thong.")
                    if app_state["connected_client"]:
                        await send_to_godot(make_message("tracking_status", {
                            "status": "tracking",
                            "person_detected": False,
                            "confidence": 0.0,
                            "full_body_visible": False,
                            "required_body_visible": False,
                            "camera_fps": 0.0,
                            "feedback_code": "CAMERA_RECONNECTED",
                        }))
                    break
            continue

        consecutive_drop_count = 0

        # Lat hinh anh ngang (Mirror view) giup nguoi tap tu nhien nhu soi guong
        frame = cv2.flip(frame, 1)
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        timestamp_ms = int(time.time() * 1000)

        # Chay MediaPipe detect async
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        landmarker.detect_async(mp_image, timestamp_ms)

        # Tinh FPS thuc te
        fps_frame_count += 1
        if time.time() - fps_start_time >= 1.0:
            current_fps = fps_frame_count / (time.time() - fps_start_time)
            fps_frame_count = 0
            fps_start_time = time.time()

        now = time.time()
        active_landmarks = None

        if latest_result and latest_result.pose_landmarks:
            raw_lms = latest_result.pose_landmarks[0]
            active_landmarks = evaluator.filter.filter(raw_lms)
            app_state["last_active_landmarks"] = active_landmarks
            app_state["last_landmarks_time"] = now
        elif (now - app_state.get("last_landmarks_time", 0.0)) < 0.25:
            # Dung landmarks truoc do neu MediaPipe bi rot 1 frame (tranh nhap nhay 0%)
            active_landmarks = app_state.get("last_active_landmarks")

        hud_info = app_state["cached_hud_info"]

        # 1. Kiem tra va gui tracking_status dinh ky
        is_tracking_ok, tracking_code = evaluator.check_tracking_status(active_landmarks)
        if app_state["connected_client"]:
            if (tracking_code != app_state["last_tracking_code"]) or (now - app_state["last_tracking_status_send_time"] >= 2.0):
                app_state["last_tracking_code"] = tracking_code
                app_state["last_tracking_status_send_time"] = now
                tracking_msg = make_message("tracking_status", {
                    "status": "tracking" if is_tracking_ok else "no_person",
                    "person_detected": bool(active_landmarks is not None),
                    "confidence": 0.95 if is_tracking_ok else 0.30,
                    "full_body_visible": is_tracking_ok,
                    "required_body_visible": is_tracking_ok,
                    "camera_fps": round(current_fps, 1),
                    "feedback_code": tracking_code,
                })
                await send_to_godot(tracking_msg)

        # 1.5. Xu ly dieu khien con tro ban tay (Adaptive Throttle)
        hand_payload = hand_service.process(active_landmarks)
        hand_active = hand_payload.get("active", False)

        if app_state["connected_client"]:
            should_send_hand = False
            if hand_active:
                should_send_hand = True
                app_state["last_hand_active"] = True
            elif app_state.get("last_hand_active", False):
                # Vua ha tay xuong -> gui ngay goi tin inactive de Frontend an con tro
                should_send_hand = True
                app_state["last_hand_active"] = False
                app_state["last_hand_inactive_send_time"] = now
            elif (now - app_state.get("last_hand_inactive_send_time", 0.0)) >= 2.0:
                # Dinh ky dong bo trang thai inactive
                should_send_hand = True
                app_state["last_hand_inactive_send_time"] = now

            if should_send_hand:
                hand_msg = make_message("hand_control", hand_payload)
                await send_to_godot(hand_msg)

        # 2. Xu ly Calibration (neu dang duoc yeu cau)
        if evaluator.calibration_active:
            prog_payload, comp_payload = evaluator.process_calibration(active_landmarks)
            hud_info["exercise_id"] = f"CALIBRATION: {evaluator.calib_exercise_id}"
            hud_info["movement_state"] = "CALIBRATING"

            if prog_payload:
                hud_info["rom_progress"] = prog_payload.get("progress", 0.0)
                hud_info["feedback_code"] = prog_payload.get("feedback_code", "KEEP_POSITION")
                await send_to_godot(make_message("calibration_progress", prog_payload))

            if comp_payload:
                hud_info["feedback_code"] = comp_payload.get("feedback_code", "CALIBRATION_COMPLETED")
                await send_to_godot(make_message("calibration_completed", comp_payload))
                print(f"[Calibration] Hoan thanh: {comp_payload}")

        # 3. Xu ly Phien tap bai tap (neu dang exercising)
        elif app_state["is_exercising"] and app_state["current_exercise"]:
            ex_id = app_state["current_exercise"]
            hud_info["exercise_id"] = ex_id

            pose_metrics, events = evaluator.process_frame(ex_id, active_landmarks)

            if pose_metrics:
                hud_info["movement_state"] = pose_metrics["exercise"]["movement_state"]
                hud_info["rom_progress"] = pose_metrics["exercise"]["rom_progress"]
                hud_info["hold_progress"] = pose_metrics["exercise"]["hold_progress"]
                hud_info["feedback_code"] = pose_metrics["exercise"]["feedback_code"]
                app_state["cached_hud_info"] = hud_info

                # Gui pose_frame dinh ky ~15 FPS
                if now - last_pose_send_time >= pose_send_interval:
                    last_pose_send_time = now
                    frame_count += 1
                    pose_frame = make_message("pose_frame", {
                        "frame_id": frame_count,
                        "tracking": {
                            "person_detected": bool(active_landmarks is not None),
                            "confidence": 0.95 if is_tracking_ok else 0.30,
                            "required_body_visible": is_tracking_ok,
                        },
                        "angles": pose_metrics.get("angles", {}),
                        "exercise": pose_metrics.get("exercise", {}),
                    })
                    await send_to_godot(pose_frame)

            # Gui tat ca su kien (rep_completed, hold_progress, rep_rejected...) ngay lap tuc
            for ev in events:
                event_payload = {
                    "exercise_id": ex_id,
                }
                event_payload.update(ev)
                event_msg = make_message("exercise_event", event_payload)
                await send_to_godot(event_msg)
                print(f"[Event -> Godot] {ev.get('event')} | Code: {ev.get('feedback_code')} | RepID: {ev.get('rep_candidate_id')}")

        # 4. Gui luong camera preview sang Godot (chi ve Skeleton truc quan, khong ve HUD banner de len mat)
        # Giu dung ty le goc cua camera, khong ep cung 16:9 lam meo hay keo gian ngang nguoi choi
        h_orig, w_orig = frame.shape[:2]
        target_w = 480
        target_h = max(240, int(target_w * (h_orig / float(w_orig))))

        if app_state["connected_client"] and (now - last_camera_send_time >= camera_send_interval):
            last_camera_send_time = now
            preview_for_godot = frame.copy()
            draw_skeleton(preview_for_godot, active_landmarks)
            preview_frame = cv2.resize(preview_for_godot, (target_w, target_h))
            success_enc, encoded_jpg = cv2.imencode('.jpg', preview_frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
            if success_enc:
                b64_image = base64.b64encode(encoded_jpg).decode('ascii')
                cam_msg = make_message("camera_frame", {
                    "image": b64_image,
                    "width": target_w,
                    "height": target_h,
                })
                await send_to_godot(cam_msg)

        # 5. Man hinh OpenCV desktop: ve day du ca Skeleton va HUD banner thong so phuc vu debug tren PC
        draw_hud_and_skeleton(frame, active_landmarks, current_fps, hud_info)

        cv2.imshow("Nghien cuu Game PHCN - AI Arm Tracking (Esc to Exit)", frame)
        if (cv2.waitKey(1) & 0xFF) == 27:
            print("[Camera] Nguoi dung nhan Esc de thoat.")
            is_shutting_down = True
            break

        # Tinh thoi gian nghi cua vong lap de on dinh FPS
        elapsed = time.time() - loop_start
        sleep_time = max(0.001, frame_interval - elapsed)
        await asyncio.sleep(sleep_time)

    if cap and cap.isOpened():
        cap.release()
    cv2.destroyAllWindows()


# ==========================================
# MAIN ENTRY POINT
# ==========================================
async def main():
    print("=" * 60)
    print("  KHOI DONG SERVER NHAN DIEN CU DONG CANH TAY PHCN")
    print("  Tuan thu JSON Contract 1.0.0 | Godot <-> Python/MediaPipe")
    print("=" * 60)
    start_mongodb_bridge_thread()
    server = await websockets.serve(websocket_handler, HOST, PORT, reuse_address=True)
    print(f"[WebSocket] Server dang lang nghe tai: ws://{HOST}:{PORT}")
    try:
        await process_camera()
    except asyncio.CancelledError:
        pass
    except Exception as exc:
        print(f"[System] Ngoai le trong tien trinh chinh: {exc}")
    finally:
        cleanup_resources()
        server.close()
        await server.wait_closed()
        print("[System] Server WebSocket va toan bo tai nguyen da duoc giai phong sach se.")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[System] Chuong trinh ket thuc boi nguoi dung (KeyboardInterrupt).")
    finally:
        cleanup_resources()