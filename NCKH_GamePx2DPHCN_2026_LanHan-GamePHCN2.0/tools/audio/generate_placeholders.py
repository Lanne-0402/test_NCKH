"""Original procedural placeholder audio. Standard library only; refuses overwrites."""
import math, random, wave, struct, pathlib, sys
SR = 22050
rng = random.Random(20261016)
root = pathlib.Path(sys.argv[1])
if root.exists():
    raise SystemExit("Output folder already exists; refusing to overwrite.")
root.mkdir(parents=True)
TAU = math.tau
def write(name, samples):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max(abs(v) for v in samples) or 1
    gain = min(1, 0.58 / peak)
    # Short edge fades avoid pops when triggered or looped.
    fade = min(220, len(samples)//4)
    for i in range(fade):
        samples[i] *= i/fade
        samples[-1-i] *= i/fade
    with wave.open(str(path), "wb") as out:
        out.setparams((1,2,SR,0,"NONE","not compressed"))
        out.writeframes(b"".join(struct.pack("<h", round(max(-1,min(1,v*gain))*32767)) for v in samples))
def freq(note):
    return 440*2**((note-69)/12)
def note(buf, start, duration, midi, amp, soft=False):
    f=freq(midi)
    n=int(duration*SR)
    for j in range(n):
        idx=int(start*SR)+j
        if idx>=len(buf): break
        t=j/SR
        env=min(1,t/0.025)*min(1,(duration-t)/0.09)
        tone=math.sin(TAU*f*t)
        if not soft: tone+=0.22*math.sin(TAU*f*2*t)+0.08*math.sin(TAU*f*3*t)
        buf[idx]+=amp*env*math.exp(-t*(1.2 if soft else 3))*tone
tracks=[
("map_01_forest_path",96,[62,65,69,72,69,65,67,69],50,False),
("map_02_stone_lift",80,[57,60,64,67,64,60,62,64],45,False),
("map_03_wall_push",100,[60,63,67,70,67,63,65,67],48,False),
("map_04_cliff_climb",108,[62,67,69,74,72,69,67,69],50,False),
("map_05_meditation",64,[69,72,76,79,76,72,74,72],45,True),
("menu_theme",80,[62,65,69,74,72,69,65,67],50,True)]
for name,bpm,melody,bass,soft in tracks:
    beat=60/bpm
    buf=[0.0]*round(32*beat*SR)
    for b in range(32):
        note(buf,b*beat,beat*0.92,melody[b%8],0.16,soft)
        if b%4==0:
            note(buf,b*beat,beat*3.9,bass+(5 if (b//8)%2 else 0),0.12,True)
            note(buf,b*beat,beat*3.5,bass+19,0.055,True)
        if not soft and b%2==0:
            for j in range(int(.09*SR)):
                idx=round(b*beat*SR)+j
                t=j/SR
                if idx<len(buf): buf[idx]+=.08*math.exp(-t*50)*math.sin(TAU*(110*t-220*t*t))
    write("music/"+name+"_loop.wav",buf)
def effect(name,duration,f0=400,f1=600,noise=0.0,amp=.3):
    buf=[]
    for i in range(round(duration*SR)):
        t=i/SR
        u=t/duration
        env=min(1,t/.008)*(1-u)**2
        phase=TAU*(f0*t+(f1-f0)*t*t/(2*duration))
        buf.append(amp*env*((1-noise)*math.sin(phase)+noise*rng.uniform(-1,1)))
    write("sfx/"+name+".wav",buf)
for args in [
("ui_hover",.07,650,780,0,.13),("ui_click",.12,500,330,0,.22),
("ui_back",.16,480,260,0,.2),("ui_confirm",.25,520,900,0,.22),
("countdown_tick",.18,720,720,0,.22),("exercise_start",.5,500,1050,0,.25),
("tracking_lost",.4,390,260,0,.18),("exercise_retry",.3,330,250,0,.18),
("map_01_charge",.55,120,440,.12,.28),("map_01_rock_break",.65,100,35,.8,.5),
("map_02_lift",.9,110,240,.18,.28),("map_02_stone_settle",.35,95,40,.6,.36),
("map_03_wall_push",.9,95,60,.65,.28),("map_04_jump",.25,180,650,0,.3),
("map_04_land",.22,130,40,.45,.3),("map_05_breath",2.0,220,240,.8,.12),
("pause",.18,440,330,0,.18)]:
    effect(*args)
for name,notes in [("rep_success",[72,76,79]),("session_complete",[60,64,67,72]),("map_02_lift_success",[64,69,76])]:
    buf=[0.0]*round(1.4*SR)
    for i,n in enumerate(notes): note(buf,i*.18,.6,n,.27,True)
    write("sfx/"+name+".wav",buf)
readme="""BO AM THANH PLACEHOLDER - GAME PHCN
Am thanh tong hop thu tuc, tu tao; khong dung nhac hay ban ghi cua ben thu ba.
Chi de thu nghiem. Chua duoc gan vao gameplay.
Dinh dang: WAV PCM 16-bit, mono, 22050 Hz. Peak toi da khoang -4.7 dBFS.
Khong thay the danh gia am luong thuc te tren loa/tai nghe.

music/: 5 theme map + menu. Moi track 32 beat (17.8-30 giay).
map_01: duong rung, nhip deu; map_02: nang da, cham va tram;
map_03: day tuong, nhip chac; map_04: leo bac, nhanh va sang;
map_05: thien, mem va cham; menu: nhe, trung tinh.
Hau to _loop la muc dich su dung. Khi gan vao Godot, bat Loop
trong Import cho nhac, reimport; SFX de Loop Off.

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

generate_placeholders.py: ma nguon tao lai bo nay vao THU MUC MOI.
Chay: python generate_placeholders.py <thu_muc_dich_chua_ton_tai>
"""
(root/"README.txt").write_text(readme,encoding="utf-8")
for p in sorted(root.rglob("*.wav")):
    with wave.open(str(p),"rb") as w:
        assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getnframes()>0
        print(p.relative_to(root),round(w.getnframes()/w.getframerate(),2),"seconds")
print("PASS: all WAV headers and lengths validated.")

