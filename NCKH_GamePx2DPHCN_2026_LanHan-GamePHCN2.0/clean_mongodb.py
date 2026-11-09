"""
Cong cu kiem tra va lam sach Database tren MongoDB Atlas Cloud cho Game PHCN 2D.
Chay lenh:
    python clean_mongodb.py
"""

import sys
import json
import os
from datetime import datetime, timezone

try:
    import pymongo
except ImportError:
    print("[!] Chua cai pymongo. Hay chay: pip install pymongo dnspython")
    sys.exit(1)


def get_connection_uri() -> str:
    # 1. Uu tien bien moi truong MONGODB_URI
    env_uri = os.environ.get("MONGODB_URI", "").strip()
    if env_uri.startswith("mongodb://") or env_uri.startswith("mongodb+srv://"):
        return env_uri

    # 2. Doc tu file cau hinh cuc bo tren may
    cfg_paths = [
        "cloud_config.json",
        os.path.expandvars(r"%APPDATA%\Godot\app_userdata\New Game Project\cloud_config.json"),
        "mongodb_config.json"
    ]
    for p in cfg_paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    uri = str(data.get("url") or data.get("mongodb_uri", "")).strip()
                    if uri.startswith("mongodb://") or uri.startswith("mongodb+srv://"):
                        return uri
            except Exception:
                pass

    # 3. Yeu cau nguoi dung nhap truc tiep (An toan, khong hardcode credential)
    print("\nKhong tim thay file cau hinh chua URI. Vui long nhap chuoi ket noi MongoDB Atlas:")
    user_uri = input("MongoDB URI: ").strip()
    return user_uri


def main():
    uri = get_connection_uri()
    if not (uri.startswith("mongodb://") or uri.startswith("mongodb+srv://")):
        print("[LOI] Chuoi ket noi URI khong hop le! Phai bat dau bang mongodb:// hoac mongodb+srv://")
        sys.exit(1)

    # An bot mat khau khi hien thi tren man hinh
    masked_uri = uri
    if "@" in uri and "://" in uri:
        prefix, rest = uri.split("://", 1)
        creds, host = rest.split("@", 1)
        masked_uri = f"{prefix}://***:***@{host}"

    print("=" * 65)
    print("  CONG CU KIEM TRA & DON SACH DATABASE MONGODB ATLAS CLOUD")
    print("=" * 65)
    print(f"Connecting to: {masked_uri}")

    try:
        client = pymongo.MongoClient(uri, serverSelectionTimeoutMS=8000)
        db_names = client.list_database_names()
        print("\n[OK] Ket noi thanh cong toi MongoDB Atlas!")
        print(f"-> Danh sach database tren Cluster: {db_names}")

        target_db = client["rehab_pixel_game"]
        cols = target_db.list_collection_names()
        print(f"-> Collections hien co trong database 'rehab_pixel_game': {cols if cols else '[RONG - Chua co bang nao]'}")

        for c_name in cols:
            count = target_db[c_name].count_documents({})
            print(f"   * Bảng '{c_name}': {count} ban ghi (documents)")

        print("\n" + "-" * 65)
        print("BAN CO MUON LAM SACH & KHOI TAO SAN 10 HO SO ID TRONG (BN001 - BN010) KHONG?")
        print("Nhap 'yes' va an Enter de thuc hien:")
        confirm = input("> ").strip().lower()

        if confirm in ["yes", "y"]:
            for c_name in cols:
                try:
                    target_db[c_name].drop()
                    print(f"[OK] Da xoa collection: '{c_name}'")
                except Exception:
                    del_res = target_db[c_name].delete_many({})
                    print(f"[OK] Da xoa {del_res.deleted_count} ban ghi trong: '{c_name}'")

            print("\n-> Dang khoi tao 10 ma ID benh nhan trong (BN001 - BN010)...")
            for i in range(1, 11):
                pid = f"BN{i:03d}"
                target_db["patient_profiles"].update_one(
                    {"_id": pid},
                    {"$set": {
                        "patient_id": pid,
                        "patient_name": f"Bệnh nhân {pid}",
                        "max_rom_angle": 0.0,
                        "levels": {"1": 1, "2": 1, "3": 1, "4": 1, "5": 1},
                        "rom_history": [],
                        "sessions": [],
                        "updated_at_utc": datetime.now(timezone.utc).isoformat()
                    }},
                    upsert=True
                )
            print("[HOAN TAT 100%] Da khoi tao thanh cong 10 ma ID benh nhan trong tren MongoDB Atlas!")
            print("Database 'rehab_pixel_game' bay gio da san sang cho nguoi that thu nghiem.")
        else:
            print("[HUY] Khong thay doi gi tren database.")

    except Exception as exc:
        print(f"[LOI] {exc}")


if __name__ == "__main__":
    main()
