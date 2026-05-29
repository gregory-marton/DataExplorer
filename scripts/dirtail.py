#!/usr/bin/env python3
import sys, time, threading
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import psutil

WATCH_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
POLL_INTERVAL = 0.25       # seconds between reads / writer checks
READ_CHUNK = 8192
GRACE_SECONDS = 1.0        # wait after writers disappear before closing stream

def pids_writing_path(path):
    pids = set()
    target = str(Path(path).resolve())
    for p in psutil.process_iter(['pid', 'open_files']):
        try:
            ofs = p.info.get('open_files') or []
            for fo in ofs:
                if fo.path == target:
                    pids.add(p.info['pid'])
                    break
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return pids

def follow_while_writers(path):
    path = Path(path)
    try:
        f = path.open('rb')
    except FileNotFoundError:
        return
    pos = 0
    print(f"\n=== START {path} ===", flush=True)
    last_writer_seen = time.time()
    try:
        while True:
            f.seek(pos)
            data = f.read(READ_CHUNK)
            if data:
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
                pos = f.tell()
                last_writer_seen = time.time()
                continue

            # re-check which pids currently have the file open
            writers = pids_writing_path(path)
            if writers:
                last_writer_seen = time.time()
                time.sleep(POLL_INTERVAL)
                continue

            # no writers right now — allow a short grace period in case of quick reopen
            if time.time() - last_writer_seen < GRACE_SECONDS:
                time.sleep(POLL_INTERVAL)
                continue

            # final check: file hasn't grown in the brief pause
            f.seek(pos)
            if f.read(1):
                f.seek(pos)
                continue
            break
    finally:
        try:
            f.close()
        except Exception:
            pass
    print(f"\n=== END {path} ===", flush=True)

class NewFileHandler(FileSystemEventHandler):
    def __init__(self):
        self.threads = {}
    def on_created(self, event):
        if event.is_directory: return
        path = Path(event.src_path)
        if path in self.threads and self.threads[path].is_alive(): return
        t = threading.Thread(target=follow_while_writers, args=(path,), daemon=True)
        self.threads[path] = t
        t.start()

if __name__ == "__main__":
    obs = Observer()
    handler = NewFileHandler()
    obs.schedule(handler, str(WATCH_DIR), recursive=False)

    # start following existing files that currently have writers
    for p in WATCH_DIR.iterdir():
        if not p.is_file(): continue
        if pids_writing_path(p):
            t = threading.Thread(target=follow_while_writers, args=(p,), daemon=True)
            handler.threads[p] = t
            t.start()

    obs.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        obs.stop()
    obs.join()
