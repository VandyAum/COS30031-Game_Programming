"""Cut the recorded shots to the narration and mix the final video.

    python3 tools/video/assemble.py <render log> <avi dir> <narration audio> <out.mp4>

Each shot logs "DIRECTOR begin narration=T frame=N": movie frame N shows
narration time T, and every later frame is 1/30 s further on. The timeline
below says which shot covers which stretch of narration (cut at the
speaker handovers), optionally borrowing frames from another narration
time (the after-action report is reused under 2:14).

AI-assisted (Claude Opus 5.5). Prompt used: "Take the narration transcript
and record gameplay video to sync alongside it."
"""
import re
import subprocess
import sys
from pathlib import Path

FPS = 30
GAME_AUDIO_DB = -15      # game sounds sit under the voices

# (shot, narration from, narration to, source narration time for 'from' if borrowed)
TIMELINE = [
    ("showcase",       0.0,   99.7, None),
    ("challenge",     99.7,  134.0, None),
    ("showcase",     134.0,  138.2, 92.0),     # after-action report again
    ("challenge",    138.2,  154.0, None),
    ("core",         154.0,  195.0, None),
    ("physics",      195.0,  212.0, None),
    ("cards_physics", 212.0, 246.8, None),
    ("physics2",     246.8,  253.6, None),
    ("cards_modular", 253.6, 276.4, None),
    ("modular",      276.4,  300.4, None),
    ("feedback",     300.4,  356.4, None),
    ("delivery",     356.4,  376.0, None),
]


def begins(log: str) -> dict:
    out, shot = {}, None
    for line in Path(log).read_text().splitlines():
        if line.startswith("=== "):
            shot = line[4:].strip()
        m = re.search(r"DIRECTOR begin narration=([\d.]+) frame=(\d+)", line)
        if m and shot:
            out[shot] = (float(m.group(1)), int(m.group(2)))
    return out


def run(cmd):
    print(" ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True)


def main():
    log, avi_dir, narration, out = sys.argv[1:5]
    avi_dir = Path(avi_dir)
    work = avi_dir / "parts"
    work.mkdir(exist_ok=True)
    starts = begins(log)
    parts = []
    for i, (shot, t0, t1, src) in enumerate(TIMELINE):
        b_time, b_frame = starts[shot]
        first = b_frame + round(((src if src is not None else t0) - b_time) * FPS)
        frames = round((t1 - t0) * FPS)
        part = work / f"{i:02d}_{shot}.mkv"
        # Frame-exact cut (select by frame number), audio cut to the same span.
        run(["ffmpeg", "-v", "error", "-y", "-i", avi_dir / f"{shot}.avi",
             "-filter_complex",
             f"[0:v]select='between(n,{first},{first + frames - 1})',setpts=N/{FPS}/TB[v];"
             f"[0:a]atrim=start={first / FPS}:duration={frames / FPS},asetpts=PTS-STARTPTS,"
             f"aresample=48000,aformat=channel_layouts=stereo[a]",
             "-map", "[v]", "-map", "[a]", "-r", str(FPS),
             "-c:v", "libx264", "-crf", "16", "-preset", "fast", "-pix_fmt", "yuv420p",
             "-c:a", "pcm_s16le", part])
        parts.append(part)
    listing = work / "list.txt"
    listing.write_text("".join(f"file '{p.resolve()}'\n" for p in parts))
    joined = work / "joined.mkv"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    # Narration on top, game audio ducked underneath.
    run(["ffmpeg", "-v", "error", "-y", "-i", joined, "-i", narration,
         "-filter_complex",
         f"[0:a]volume={GAME_AUDIO_DB}dB[g];[1:a]aresample=48000,aformat=channel_layouts=stereo[n];"
         "[g][n]amix=inputs=2:duration=first:normalize=0[a]",
         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", out])


if __name__ == "__main__":
    main()
