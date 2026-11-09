"""
Dich vu ket noi MongoDB (MongoDB Atlas Cloud / MongoDB Compass Local)
cho Game Pixel 2D Phuc hoi chuc nang & Web App.

Chuc nang:
1. Tu dong khoi chay cung main.py (tren cong HTTP 127.0.0.1:8766) hoac chay doc lap:
       python mongodb_service.py
2. Nhan du lieu JSON tu Godot Engine (Global.gd) va luu truc tiep vao MongoDB
   theo 2 collection:
   - patient_profiles: Ho so nguoi tap (_id = patient_id), tien do 5 Map, va
     chuoi rom_history (goc ROM tang dan qua cac ngay tap de ve bieu do duong).
   - exercise_sessions: Lich su chi tiet tung buoi tap (_id = session_id).
3. Cung cap REST API (co bat san CORS) de Web App (React/Vue/Next.js/HTML)
   co the truy van truc tiep danh sach nguoi benh va bieu do ROM.
"""

import json
import os
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

MONGO_BRIDGE_HOST = "127.0.0.1"
MONGO_BRIDGE_PORT = 8766
DEFAULT_DB_NAME = "rehab_pixel_game"
CONFIG_FILE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cloud_config.json")
LEGACY_CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mongodb_config.json")

try:
    from pymongo import MongoClient
    from pymongo.errors import PyMongoError
    PYMONGO_AVAILABLE = True
except ImportError:
    MongoClient = None
    PyMongoError = Exception
    PYMONGO_AVAILABLE = False

_client_lock = threading.Lock()
_cached_client = None
_cached_uri = ""


def load_saved_mongo_config() -> dict:
    """Doc cau hinh MongoDB URI tu cloud_config.json, env hoac legacy config."""
    cfg = {
        "mongodb_uri": os.environ.get("MONGODB_URI", "mongodb://localhost:27017"),
        "database_name": os.environ.get("MONGODB_DB", DEFAULT_DB_NAME),
    }
    target_path = CONFIG_FILE_PATH if os.path.exists(CONFIG_FILE_PATH) else (
        LEGACY_CONFIG_PATH if os.path.exists(LEGACY_CONFIG_PATH) else None
    )
    if target_path:
        try:
            with open(target_path, "r", encoding="utf-8") as f:
                saved = json.load(f)
                if isinstance(saved, dict):
                    if saved.get("mongodb_uri"):
                        cfg["mongodb_uri"] = str(saved["mongodb_uri"]).strip()
                    if saved.get("database_name"):
                        cfg["database_name"] = str(saved["database_name"]).strip()
        except Exception as exc:
            print(f"[MongoDB] Khong doc duoc {os.path.basename(target_path)}: {exc}")
    return cfg


def save_mongo_config(mongodb_uri: str, database_name: str) -> None:
    """Luu cau hinh MongoDB URI xuong cloud_config.json (ngoai Git)."""
    try:
        with open(CONFIG_FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "mongodb_uri": mongodb_uri,
                    "database_name": database_name or DEFAULT_DB_NAME,
                    "updated_at_utc": datetime.now(timezone.utc).isoformat(),
                },
                f,
                indent=2,
                ensure_ascii=False,
            )
    except Exception as exc:
        print(f"[MongoDB] Khong the luu cloud_config.json: {exc}")


def get_mongo_database(override_uri: str = "", override_db: str = ""):
    """Lay ket noi toi database MongoDB (co cache ket noi va thiet lap unique index)."""
    global _cached_client, _cached_uri

    if not PYMONGO_AVAILABLE:
        raise RuntimeError(
            "Chua cai thu vien pymongo. Hay chay lenh: pip install pymongo dnspython"
        )

    cfg = load_saved_mongo_config()
    uri = (override_uri or cfg["mongodb_uri"] or "mongodb://localhost:27017").strip()
    db_name = (override_db or cfg["database_name"] or DEFAULT_DB_NAME).strip()

    if not (uri.startswith("mongodb://") or uri.startswith("mongodb+srv://")):
        uri = "mongodb://localhost:27017"

    with _client_lock:
        if _cached_client is None or _cached_uri != uri:
            if _cached_client is not None:
                try:
                    _cached_client.close()
                except Exception:
                    pass
            _cached_client = MongoClient(uri, serverSelectionTimeoutMS=4500)
            _cached_uri = uri
            save_mongo_config(uri, db_name)

        db = _cached_client[db_name]
        try:
            db["exercise_sessions"].create_index([("session_id", 1)], unique=True)
            db["patient_profiles"].create_index([("patient_id", 1)], unique=True)
        except Exception:
            pass
        return db


class MongoBridgeRequestHandler(BaseHTTPRequestHandler):
    """Xu ly cac request REST API tu Godot Game hoac Web App."""

    def log_message(self, format_str, *args):
        # Giu log gon gang tren terminal
        print(f"[MongoDB API] {self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")

    def _send_json(self, status_code: int, data: dict) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization, X-Mongo-URI, X-Mongo-DB",
        )
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw) if raw else {}

    def _extract_mongo_headers(self) -> tuple[str, str]:
        uri = (self.headers.get("X-Mongo-URI") or "").strip()
        db_name = (self.headers.get("X-Mongo-DB") or "").strip()
        return uri, db_name

    def do_OPTIONS(self):
        self._send_json(200, {"ok": True})

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        uri_hdr, db_hdr = self._extract_mongo_headers()

        try:
            db = get_mongo_database(uri_hdr, db_hdr)

            # 1. GET /api/health
            if path == "/api/health" or path == "":
                db.command("ping")
                self._send_json(200, {
                    "ok": True,
                    "provider": "mongodb",
                    "database": db.name,
                })
                return

            # 2. GET /api/patients -> Danh sach tat ca ho so benh nhan (cho Web App)
            if path == "/api/patients":
                docs = list(db["patient_profiles"].find({}, {"_id": 0}).sort("updated_at_utc", -1))
                self._send_json(200, {"ok": True, "patients": docs})
                return

            # 3. GET /api/patients/<patient_id> -> Lay ho so 1 benh nhan theo ID
            if path.startswith("/api/patients/"):
                patient_id = unquote(path.split("/api/patients/", 1)[1]).strip()
                doc = db["patient_profiles"].find_one({"patient_id": patient_id}, {"_id": 0})
                if doc is None:
                    doc = db["patient_profiles"].find_one({"_id": patient_id}, {"_id": 0})
                if doc is None:
                    self._send_json(404, {"ok": False, "error": "PATIENT_NOT_FOUND", "patient_id": patient_id})
                else:
                    self._send_json(200, doc)
                return

            # 4. GET /api/sessions/<patient_id> -> Lay danh sach buoi tap cua 1 benh nhan
            if path.startswith("/api/sessions/"):
                patient_id = unquote(path.split("/api/sessions/", 1)[1]).strip()
                sessions = list(
                    db["exercise_sessions"]
                    .find({"patient_id": patient_id}, {"_id": 0})
                    .sort("completed_at_utc", -1)
                    .limit(100)
                )
                self._send_json(200, {"ok": True, "patient_id": patient_id, "sessions": sessions})
                return

            self._send_json(404, {"ok": False, "error": "ENDPOINT_NOT_FOUND"})

        except Exception as exc:
            print(f"[MongoDB Error] GET {self.path}: {exc}")
            self._send_json(500, {"ok": False, "error": str(exc)})

    def do_POST(self):
        self._handle_write()

    def do_PUT(self):
        self._handle_write()

    def _handle_write(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        uri_hdr, db_hdr = self._extract_mongo_headers()

        try:
            payload = self._read_json_body()
            db = get_mongo_database(uri_hdr, db_hdr)

            # 1. POST/PUT /api/patients/<patient_id>/reset
            if path.startswith("/api/patients/") and path.endswith("/reset"):
                patient_id = unquote(path.split("/api/patients/", 1)[1].split("/reset", 1)[0]).strip()
                if patient_id:
                    expected_gen = int(payload.get("expected_generation", 0))
                    new_gen = expected_gen + 1
                    db["patient_profiles"].update_one(
                        {"_id": patient_id},
                        {"$set": {
                            "patient_name": f"Bệnh nhân {patient_id}",
                            "max_rom_angle": 0.0,
                            "levels": {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
                            "rom_history": [],
                            "sessions": [],
                            "generation": new_gen,
                            "updated_at_utc": datetime.now(timezone.utc).isoformat(),
                        }},
                        upsert=True,
                    )
                    db["exercise_sessions"].delete_many({"patient_id": patient_id})
                    self._send_json(200, {
                        "ok": True,
                        "patient_id": patient_id,
                        "action": "reset",
                        "generation": new_gen,
                    })
                    return

            # 2. POST/PUT /api/patients hoac /api/patients/<patient_id>
            if path == "/api/patients" or path.startswith("/api/patients/"):
                patient_id = str(payload.get("patient_id", "")).strip()
                if not patient_id and path.startswith("/api/patients/"):
                    patient_id = unquote(path.split("/api/patients/", 1)[1]).strip()
                if not patient_id:
                    self._send_json(400, {"ok": False, "error": "MISSING_PATIENT_ID"})
                    return

                raw_sessions = payload.get("sessions", [])
                recent_sessions = raw_sessions[-15:] if isinstance(raw_sessions, list) else []

                doc = {
                    "_id": patient_id,
                    "patient_id": patient_id,
                    "patient_name": str(payload.get("patient_name", f"Người tập {patient_id}")),
                    "max_rom_angle": float(payload.get("max_rom_angle", 0.0)),
                    "levels": payload.get("levels", {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1}),
                    "rom_history": payload.get("rom_history", []),
                    "sessions": recent_sessions,
                    "updated_at_utc": str(
                        payload.get("updated_at_utc", datetime.now(timezone.utc).isoformat())
                    ),
                }
                db["patient_profiles"].update_one(
                    {"_id": patient_id},
                    {"$set": doc},
                    upsert=True,
                )

                # Dong bo tat ca cac buoi tap vao collection exercise_sessions (Idempotent Upsert)
                for s in (raw_sessions if isinstance(raw_sessions, list) else []):
                    if isinstance(s, dict) and s.get("session_id"):
                        sid = str(s["session_id"]).strip()
                        if sid:
                            s_doc = dict(s)
                            s_doc["_id"] = sid
                            s_doc["session_id"] = sid
                            s_doc["patient_id"] = patient_id
                            if "updated_at_utc" not in s_doc:
                                s_doc["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
                            db["exercise_sessions"].update_one(
                                {"_id": sid},
                                {"$set": s_doc},
                                upsert=True,
                            )

                self._send_json(200, {
                    "ok": True,
                    "patient_id": patient_id,
                    "database": db.name,
                    "collection": "patient_profiles",
                })
                return

            # 2. POST /api/sessions -> Luu 1 buoi tap moi hoan thanh (Idempotent Upsert theo _id = session_id)
            if path == "/api/sessions":
                session_id = str(payload.get("session_id", "")).strip()
                patient_id = str(payload.get("patient_id", "BN001")).strip()
                if not session_id:
                    self._send_json(400, {"ok": False, "error": "MISSING_SESSION_ID"})
                    return

                s_doc = dict(payload)
                s_doc["_id"] = session_id
                s_doc["session_id"] = session_id
                s_doc["patient_id"] = patient_id
                if "updated_at_utc" not in s_doc:
                    s_doc["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
                db["exercise_sessions"].update_one(
                    {"_id": session_id},
                    {"$set": s_doc},
                    upsert=True,
                )
                self._send_json(200, {
                    "ok": True,
                    "session_id": session_id,
                    "patient_id": patient_id,
                    "database": db.name,
                    "collection": "exercise_sessions",
                })
                return

            # 3. POST /api/seed -> Khoi tao san 10 ho so benh nhan mau (BN001 - BN010)
            if path == "/api/seed":
                res = seed_sample_patients_to_mongo(uri_hdr, db_hdr)
                self._send_json(200, res)
                return

            self._send_json(404, {"ok": False, "error": "ENDPOINT_NOT_FOUND"})

        except Exception as exc:
            print(f"[MongoDB Error] {self.command} {self.path}: {exc}")
            self._send_json(500, {"ok": False, "error": str(exc)})


_bridge_server_instance = None


SAMPLE_PATIENTS = [
    {"id": "BN001", "name": "Nguyễn Văn An", "note": "Viêm chu vai thể đông cứng", "base_rom": 52.0, "gain": 34.0},
    {"id": "BN002", "name": "Trần Thị Bình", "note": "Phục hồi chức năng sau mổ chóp xoay", "base_rom": 45.0, "gain": 33.5},
    {"id": "BN003", "name": "Lê Hoàng Cường", "note": "Cứng khớp vai sau bất động khớp", "base_rom": 55.0, "gain": 33.0},
    {"id": "BN004", "name": "Phạm Thị Dung", "note": "Hội chứng cấn mỏm cùng vai", "base_rom": 42.0, "gain": 32.0},
    {"id": "BN005", "name": "Hoàng Văn Em", "note": "Thoái hóa khớp vai tuổi già", "base_rom": 50.0, "gain": 32.5},
    {"id": "BN006", "name": "Vũ Thị Hoa", "note": "Đông cứng khớp vai giai đoạn 2", "base_rom": 38.0, "gain": 32.0},
    {"id": "BN007", "name": "Đặng Văn Giang", "note": "Viêm gân cơ nhị đầu cánh tay", "base_rom": 58.0, "gain": 31.0},
    {"id": "BN008", "name": "Bùi Thị Hạnh", "note": "Phục hồi sau nội soi khớp vai", "base_rom": 48.0, "gain": 32.0},
    {"id": "BN009", "name": "Ngô Văn Hùng", "note": "Cứng khớp vai sau tai biến nhẹ", "base_rom": 35.0, "gain": 30.5},
    {"id": "BN010", "name": "Đỗ Thị Mai", "note": "Viêm bao hoạt dịch dưới mỏm cùng", "base_rom": 53.0, "gain": 32.0},
]


def seed_sample_patients_to_mongo(override_uri: str = "", override_db: str = "") -> dict:
    """Khoi tao san 10 ho so nguoi tap (BN001 - BN010) va 70 buoi tap mau cho NCKH."""
    db = get_mongo_database(override_uri, override_db)
    now_ts = int(datetime.now(timezone.utc).timestamp())
    demo_maps = [1, 2, 3, 4, 5, 2, 4]
    map_ex_names = [
        "scapular_retraction",
        "wall_abduction_external_rotation",
        "horizontal_shoulder_adduction",
        "hands_behind_head",
        "cross_body_shoulder_stretch"
    ]

    total_patients = 0
    total_sessions = 0

    for p in SAMPLE_PATIENTS:
        pid = p["id"]
        pname = p["name"]
        base_r = float(p["base_rom"])
        gain_r = float(p["gain"])

        p_rom_history = []
        p_sessions = []

        for i in range(7):
            day_ts = now_ts - (6 - i) * 86400
            day_dt = datetime.fromtimestamp(day_ts, tz=timezone.utc)
            date_str = day_dt.strftime("%Y-%m-%d")
            rom_val = round(base_r + (gain_r * i / 6.0), 1)

            p_rom_history.append({
                "date": date_str,
                "rom_angle": rom_val,
                "source": "calibration",
                "patient_id": pid,
                "updated_at_utc": f"{date_str}T09:00:00Z",
            })

            map_id = demo_maps[i]
            diff_lvl = 1 if i < 2 else (2 if i < 5 else 3)
            s_id = f"demo-{pid}-d{i+1}"
            s_entry = {
                "_id": s_id,
                "session_id": s_id,
                "patient_id": pid,
                "patient_name": pname,
                "map_id": map_id,
                "difficulty": diff_lvl,
                "started_at_utc": f"{date_str}T09:05:00Z",
                "completed_at_utc": f"{date_str}T09:15:00Z",
                "stability": 3 if i >= 3 else 2,
                "stability_enabled": True,
                "evaluation": "HOÀN HẢO" if i >= 3 else "HOÀN THÀNH",
                "exercise_id": map_ex_names[map_id - 1],
                "valid_reps": 20 if map_id == 1 else (2 if map_id == 5 else 10),
                "rejected_reps": max(0, 2 - int(i / 2)),
                "phase_count": 2,
                "rom_angle": rom_val,
            }
            p_sessions.append(s_entry)

            # Upsert vao collection exercise_sessions
            db["exercise_sessions"].update_one(
                {"_id": s_id},
                {"$set": s_entry},
                upsert=True
            )
            total_sessions += 1

        prof_doc = {
            "_id": pid,
            "patient_id": pid,
            "patient_name": pname,
            "medical_note": p.get("note", ""),
            "max_rom_angle": round(base_r + gain_r, 1),
            "levels": {"1": 3, "2": 3, "3": 3, "4": 2, "5": 2},
            "rom_history": p_rom_history,
            "sessions": p_sessions,
            "updated_at_utc": datetime.now(timezone.utc).isoformat(),
        }

        db["patient_profiles"].update_one(
            {"_id": pid},
            {"$set": prof_doc},
            upsert=True
        )
        total_patients += 1

    return {
        "ok": True,
        "message": f"Đã khởi tạo thành công {total_patients} hồ sơ người bệnh (BN001-BN010) và {total_sessions} buổi tập vào MongoDB!",
        "database": db.name,
        "total_patients": total_patients,
        "total_sessions": total_sessions,
    }


CLEAN_PATIENT_IDS = [f"BN{i:03d}" for i in range(1, 11)]


def init_clean_patients_in_mongo(override_uri: str = "", override_db: str = "") -> dict:
    """Khoi tao san 10 ho so ID trong (BN001 - BN010) san sang nhan du lieu that cho NCKH."""
    db = get_mongo_database(override_uri, override_db)
    for pid in CLEAN_PATIENT_IDS:
        doc = {
            "_id": pid,
            "patient_id": pid,
            "patient_name": f"Bệnh nhân {pid}",
            "max_rom_angle": 0.0,
            "levels": {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
            "rom_history": [],
            "sessions": [],
            "updated_at_utc": datetime.now(timezone.utc).isoformat(),
        }
        db["patient_profiles"].update_one({"_id": pid}, {"$set": doc}, upsert=True)
    return {
        "ok": True,
        "message": f"Đã khởi tạo sẵn 10 mã ID trống (BN001 - BN010) trên MongoDB '{db.name}' sẵn sàng cho thử nghiệm thực tế!",
        "database": db.name,
        "patient_ids": CLEAN_PATIENT_IDS,
    }


def start_mongodb_bridge_thread(host: str = MONGO_BRIDGE_HOST, port: int = MONGO_BRIDGE_PORT) -> None:
    """Khoi chay HTTP REST Bridge cho MongoDB trong 1 daemon thread (khong chan main.py)."""
    global _bridge_server_instance
    if _bridge_server_instance is not None:
        return

    def _run_server():
        global _bridge_server_instance
        try:
            ThreadingHTTPServer.allow_reuse_address = True
            server = ThreadingHTTPServer((host, port), MongoBridgeRequestHandler)
            server.daemon_threads = True
            _bridge_server_instance = server
            status = "SAN SANG" if PYMONGO_AVAILABLE else "CHUA CAI PYMONGO (pip install pymongo dnspython)"
            print(f"[MongoDB Bridge] Server REST API dang chay tai: http://{host}:{port} | Trang thai: {status}")
            server.serve_forever()
        except OSError as exc:
            print(f"[MongoDB Bridge] Cong {port} dang duoc su dung hoac khong mo duoc: {exc}")
        except Exception as exc:
            print(f"[MongoDB Bridge] Loi khoi dong: {exc}")

    thread = threading.Thread(target=_run_server, name="MongoDBBridgeThread", daemon=True)
    thread.start()


def stop_mongodb_bridge() -> None:
    """Dong server MongoDB HTTP va giai phong cong socket an toan."""
    global _bridge_server_instance
    if _bridge_server_instance is not None:
        try:
            print("[MongoDB Bridge] Dang giai phong cong HTTP Bridge...")
            _bridge_server_instance.shutdown()
            _bridge_server_instance.server_close()
            print("[MongoDB Bridge] Da giai phong cong thanh cong.")
        except Exception as exc:
            print(f"[MongoDB Bridge] Loi khi giai phong server: {exc}")
        finally:
            _bridge_server_instance = None


if __name__ == "__main__":
    import sys
    print("=" * 65)
    print("  KHOI CHAY DOC LAP MONGODB REST API SERVICE (GAME & WEB APP)")
    print(f"  Endpoint: http://{MONGO_BRIDGE_HOST}:{MONGO_BRIDGE_PORT}/api/patients")
    print("=" * 65)
    if not PYMONGO_AVAILABLE:
        print("  [!] CANH BAO: Ban chua cai pymongo. Hay chay lenh:")
        print("      pip install pymongo dnspython")
        sys.exit(1)

    if "--init" in sys.argv:
        print("[MongoDB] Dang khoi tao 10 ma ID benh nhan trong (BN001 - BN010) san sang cho thu nghiem...")
        res = init_clean_patients_in_mongo()
        print("[MongoDB Ket qua]:", res["message"])
        sys.exit(0)

    if "--seed" in sys.argv:
        print("[MongoDB] Dang khoi tao 10 ho so benh nhan mau (BN001 - BN010)...")
        res = seed_sample_patients_to_mongo()
        print("[MongoDB Ket qua]:", res["message"])
        sys.exit(0)

    if "--test" in sys.argv:
        print("[MongoDB] Dang kiem tra ket noi toi MongoDB...")
        try:
            db = get_mongo_database()
            db.command("ping")
            print(f"[MongoDB Ket qua]: Ket noi THANH CONG toi database '{db.name}'!")
        except Exception as exc:
            print(f"[MongoDB Ket qua]: Loi ket noi: {exc}")
        sys.exit(0)

    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer((MONGO_BRIDGE_HOST, MONGO_BRIDGE_PORT), MongoBridgeRequestHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[MongoDB Bridge] Da dung server.")
    finally:
        server.server_close()
