BO AM THANH PLACEHOLDER - GAME PHCN
Am thanh tong hop thu tuc, tu tao; khong dung nhac hay ban ghi cua ben thu ba.
Da gan vao gameplay qua AudioManager va GameplayAudio.
Menu co nhac rieng; moi map co nhac va SFX theo su kien.
Settings dieu khien Master (nhac + SFX). Pause dung nhac va SFX hanh dong.
Nhac -14 dB; SFX hanh dong -7 dB; SFX giu -13 dB; UI -8 dB.
Dinh dang: WAV PCM 16-bit, mono, 22050 Hz. Peak toi da khoang -4.7 dBFS.
Khong thay the danh gia am luong thuc te tren loa/tai nghe.

music/: 5 theme map + menu. Moi track 32 beat (17.8-30 giay).
map_01: duong rung, nhip deu; map_02: nang da, cham va tram;
map_03: day tuong, nhip chac; map_04: leo bac, nhanh va sang;
map_05: thien, mem va cham; menu: nhe, trung tinh.
Loop nhac va am giu tu the duoc bat trong code tren ban sao AudioStreamWAV;
khong can chinh Import. SFX con lai phat mot lan.

sfx/: UI hover/click/back/confirm; countdown_tick; exercise_start;
pause; tracking_lost; exercise_retry; rep_success; session_complete;
map_01_charge/rock_break; map_02_lift/stone_settle/lift_success;
map_03_wall_push; map_04_jump/land; map_05_breath.
SFX la one-shot, khong loop. Breath co the kich hoat theo nhip thien.

THAY AM THANH SAU NAY:
1. Giu nguyen ten va thu muc, thay WAV bang WAV that; Godot se reimport.
2. Neu chuyen sang OGG, cap nhat resource/duong dan noi gan audio.
3. Nhac nen nen co diem loop lien mach; SFX nen ngan, khong bi clipping.
4. Nen tach bus Music/SFX khi tich hop de chinh am luong rieng.
5. Khong nen dung am thanh tracking_lost qua thuong xuyen khi BE chua on dinh.

tools/audio/generate_placeholders.py: ma nguon tao lai bo nay vao THU MUC MOI.
Chay: python tools/audio/generate_placeholders.py <thu_muc_dich_chua_ton_tai>
