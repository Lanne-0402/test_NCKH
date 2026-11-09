-- =============================================================================
-- SCHEMA CƠ SỞ DỮ LIỆU ONLINE (SUPABASE POSTGRESQL) CHO GAME PIXEL 2D PHCN & WEB APP
-- Đề tài NCKH: Nghiên cứu phát triển ứng dụng game Pixel 2D tích hợp AI nhận diện
--              cử động cánh tay hỗ trợ tập luyện phục hồi chức năng
-- Hướng dẫn:
--   1. Tạo project miễn phí tại https://supabase.com
--   2. Mở mục "SQL Editor" -> Dán toàn bộ nội dung file này -> Nhấn "Run".
--   3. Vào "Project Settings" -> "API" -> Copy "Project URL" và "anon public key"
--      dán vào mục "Cấu hình DB Online" trong màn hình Báo cáo của Game Godot
--      (hoặc biến môi trường của Web App).
-- =============================================================================

-- 1. Bảng lưu hồ sơ tiến độ và lịch sử biên độ vai (ROM) theo ngày của từng người tập
CREATE TABLE IF NOT EXISTS public.patient_profiles (
    patient_id TEXT PRIMARY KEY,
    patient_name TEXT NOT NULL DEFAULT 'Người tập',
    max_rom_angle NUMERIC(5, 1) NOT NULL DEFAULT 0.0,
    levels JSONB NOT NULL DEFAULT '{"1": 1, "2": 1, "3": 1, "4": 1, "5": 1}'::jsonb,
    rom_history JSONB NOT NULL DEFAULT '[]'::jsonb,
    sessions JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Bảng lưu chi tiết từng buổi tập (phục vụ truy vấn thống kê nhanh trên Web App)
CREATE TABLE IF NOT EXISTS public.exercise_sessions (
    session_id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL REFERENCES public.patient_profiles(patient_id) ON DELETE CASCADE,
    patient_name TEXT NOT NULL DEFAULT 'Người tập',
    map_id SMALLINT NOT NULL DEFAULT 1,
    difficulty SMALLINT NOT NULL DEFAULT 1,
    exercise_id TEXT NOT NULL DEFAULT '',
    rom_angle NUMERIC(5, 1) NOT NULL DEFAULT 0.0,
    valid_reps INTEGER NOT NULL DEFAULT 0,
    rejected_reps INTEGER NOT NULL DEFAULT 0,
    stability SMALLINT NOT NULL DEFAULT 0,
    evaluation TEXT NOT NULL DEFAULT '',
    bonus_points INTEGER NOT NULL DEFAULT 0,
    started_at_utc TEXT NOT NULL DEFAULT '',
    completed_at_utc TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index tăng tốc truy vấn lịch sử theo ID người bệnh trên Web App
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_patient_id
    ON public.exercise_sessions(patient_id, created_at DESC);

-- 3. Bật Row Level Security (RLS) và cấp quyền truy cập REST API cho Game & Web App
ALTER TABLE public.patient_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read/write patient_profiles" ON public.patient_profiles;
CREATE POLICY "Allow public read/write patient_profiles"
    ON public.patient_profiles
    FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read/write exercise_sessions" ON public.exercise_sessions;
CREATE POLICY "Allow public read/write exercise_sessions"
    ON public.exercise_sessions
    FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);
