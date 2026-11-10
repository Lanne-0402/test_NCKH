"""
API Trung gian (Render Web Service) kết nối Game Phục Hồi Chức Năng 2D với MongoDB Atlas Cloud.
Bảo mật tuyệt đối thông tin xác thực Database thông qua Biến Môi Trường (Environment Variables).
"""

import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from fastapi import FastAPI, HTTPException, Header, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import pymongo
from pymongo import MongoClient

# ========================================================
# CẤU HÌNH BIẾN MÔI TRƯỜNG & DATABASE
# ========================================================
MONGO_URI = os.environ.get("MONGO_URI", "").strip()
DEFAULT_DB_NAME = os.environ.get("MONGO_DB", "rehab_pixel_game").strip()
API_KEY = os.environ.get("API_KEY", "rehab_pixel_game").strip()
PORT = int(os.environ.get("PORT", "10000"))

app = FastAPI(
    title="GamePHCN 2D - Cloud Database Bridge API",
    description="REST API Gateway kết nối an toàn Web Game với MongoDB Atlas Cloud",
    version="2.0.0",
)

# Cấu hình CORS: Cho phép truy cập từ GitHub Pages, localhost và môi trường test
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Hoặc cấu hình domain cụ thể: ["https://lanne-0402.github.io"]
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Quản lý kết nối MongoDB Pooling
_mongo_client: Optional[MongoClient] = None


def get_database():
    global _mongo_client
    if not MONGO_URI:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="MONGO_URI chua duoc cau hinh tren Render Environment Variables!",
        )
    if _mongo_client is None:
        try:
            _mongo_client = MongoClient(
                MONGO_URI,
                serverSelectionTimeoutMS=5000,
                maxPoolSize=20,
            )
            # Khởi tạo Index tối ưu tra cứu
            db = _mongo_client[DEFAULT_DB_NAME]
            db["patient_profiles"].create_index([("patient_id", 1)], unique=True)
            db["exercise_sessions"].create_index([("session_id", 1)], unique=True)
            db["exercise_sessions"].create_index([("patient_id", 1)])
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Loi ket noi MongoDB Atlas: {str(exc)}",
            )
    return _mongo_client[DEFAULT_DB_NAME]


# ========================================================
# DATA SCHEMAS
# ========================================================
class PatientProfilePayload(BaseModel):
    patient_id: str
    patient_name: Optional[str] = "Người tập"
    max_rom_angle: Optional[float] = 0.0
    levels: Optional[Dict[str, Any]] = {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1}
    rom_history: Optional[List[Dict[str, Any]]] = []
    sessions: Optional[List[Dict[str, Any]]] = []
    generation: Optional[int] = 0
    updated_at_utc: Optional[str] = None


class ResetPayload(BaseModel):
    expected_generation: Optional[int] = 0


# ========================================================
# API ENDPOINTS
# ========================================================
@app.get("/")
@app.get("/health")
@app.get("/api/health")
def health_check():
    """Health check endpoint phục vụ Render ping và kiểm tra trạng thái DB."""
    try:
        db = get_database()
        db.command("ping")
        return {
            "ok": True,
            "status": "ONLINE",
            "provider": "MongoDB Atlas Cloud",
            "database": db.name,
            "server_time_utc": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        return {
            "ok": False,
            "status": "DISCONNECTED",
            "error": str(exc),
            "hint": "Kiem tra MONGO_URI trong Render Dashboard -> Environment Variables",
        }


@app.get("/api/patients")
def get_all_patients():
    """Lấy danh sách tất cả hồ sơ người bệnh (phục vụ Chế độ Bác sĩ / NCKH)."""
    db = get_database()
    patients = list(db["patient_profiles"].find({}, {"_id": 0}).sort("updated_at_utc", -1))
    return {"ok": True, "count": len(patients), "patients": patients}


@app.get("/api/patients/{patient_id}")
def get_patient_profile(patient_id: str):
    """Lấy chi tiết hồ sơ 1 bệnh nhân theo ID kèm chuỗi lịch sử ROM."""
    db = get_database()
    doc = db["patient_profiles"].find_one(
        {"$or": [{"patient_id": patient_id}, {"_id": patient_id}]},
        {"_id": 0},
    )
    if not doc:
        return JSONResponse(
            status_code=404,
            content={"ok": False, "error": "PATIENT_NOT_FOUND", "patient_id": patient_id},
        )
    return doc


@app.post("/api/patients")
@app.put("/api/patients")
@app.post("/api/patients/{patient_id}")
@app.put("/api/patients/{patient_id}")
def save_patient_profile(payload: PatientProfilePayload, patient_id: Optional[str] = None):
    """Lưu/Cập nhật hồ sơ bệnh nhân và đồng bộ lịch sử buổi tập."""
    target_id = patient_id or payload.patient_id
    if not target_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Thieu patient_id trong yeu cau!",
        )

    db = get_database()
    now_iso = datetime.now(timezone.utc).isoformat()
    recent_sessions = payload.sessions[-15:] if payload.sessions else []

    doc = {
        "_id": target_id,
        "patient_id": target_id,
        "patient_name": payload.patient_name or f"Bệnh nhân {target_id}",
        "max_rom_angle": float(payload.max_rom_angle or 0.0),
        "levels": payload.levels or {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
        "rom_history": payload.rom_history or [],
        "sessions": recent_sessions,
        "generation": payload.generation or 0,
        "updated_at_utc": payload.updated_at_utc or now_iso,
    }

    db["patient_profiles"].update_one(
        {"_id": target_id},
        {"$set": doc},
        upsert=True,
    )

    # Đồng bộ các buổi tập chi tiết vào collection exercise_sessions
    synced_sessions_count = 0
    if payload.sessions:
        for s in payload.sessions:
            if isinstance(s, dict) and s.get("session_id"):
                sid = str(s["session_id"]).strip()
                s_doc = dict(s)
                s_doc["_id"] = sid
                s_doc["session_id"] = sid
                s_doc["patient_id"] = target_id
                if "updated_at_utc" not in s_doc:
                    s_doc["updated_at_utc"] = now_iso
                db["exercise_sessions"].update_one(
                    {"_id": sid},
                    {"$set": s_doc},
                    upsert=True,
                )
                synced_sessions_count += 1

    return {
        "ok": True,
        "patient_id": target_id,
        "profile": doc,
        "synced_sessions": synced_sessions_count,
        "database": db.name,
        "collection": "patient_profiles",
        "message": "Dong bo Cloud MongoDB Atlas thanh cong!",
    }


@app.post("/api/sessions")
def save_single_session(session_payload: Dict[str, Any]):
    """Lưu 1 buổi tập riêng lẻ vào collection exercise_sessions."""
    db = get_database()
    sid = str(session_payload.get("session_id", "")).strip()
    if not sid:
        sid = f"sess_{int(datetime.now(timezone.utc).timestamp()*1000)}"
        session_payload["session_id"] = sid
    session_payload["_id"] = sid
    if "updated_at_utc" not in session_payload:
        session_payload["updated_at_utc"] = datetime.now(timezone.utc).isoformat()
    db["exercise_sessions"].update_one({"_id": sid}, {"$set": session_payload}, upsert=True)
    return {"ok": True, "session_id": sid, "saved": True}


@app.post("/api/patients/{patient_id}/reset")
@app.put("/api/patients/{patient_id}/reset")
def reset_patient_profile(patient_id: str, payload: Optional[ResetPayload] = None):
    """Làm mới dữ liệu của một bệnh nhân để bắt đầu đợt đo thử nghiệm mới."""
    db = get_database()
    expected_gen = (payload.expected_generation if payload else 0) or 0
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

    return {
        "ok": True,
        "patient_id": patient_id,
        "action": "reset",
        "generation": new_gen,
    }


@app.get("/api/sessions/{patient_id}")
def get_patient_sessions(patient_id: str):
    """Lấy toàn bộ lịch sử các buổi tập của 1 bệnh nhân để làm báo cáo khoa học."""
    db = get_database()
    sessions = list(
        db["exercise_sessions"]
        .find({"patient_id": patient_id}, {"_id": 0})
        .sort("completed_at_utc", -1)
        .limit(100)
    )
    return {"ok": True, "patient_id": patient_id, "sessions": sessions}
