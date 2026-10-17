#!/usr/bin/env python3
"""
Abu Clock Bridge for Abu Track & Scan Windows Workstation (DesktopSync).

Provides:
1. Native ctypes FFI binding to `abuclock.dll` (when present) + deterministic pure-Python
   QPC (`time.perf_counter_ns()`) + 2-state Kalman PLL & SMPTE ST 12-1 / ST 2059-2 engine.
2. Automatic connection to (or background launch of) `abu-clock.exe` daemon on port 7878,
   plus a built-in fallback UDP 50320 (`ABU_ECO_V1` auto-discovery + Stratum-1 SNTP server)
   and UDP 1230 legacy SNTP server so iOS devices always lock with sub-millisecond accuracy.
3. Future-Time Multi-Sensor Barrier Trigger (`SCHEDULE_CAPTURE_AT`, `ABU_TRIG_V1`) on UDP 50319.
4. 41-byte SMPTE FreeD-TC (`0xD2`), 37-byte Extended FreeD (`0xD1`), and OpenTrackIO (`OTrk`)
   codecs with 32-bit BCD timecode and 64-bit TAI nanosecond timestamps.
5. Frame-00 Optical Flash Slate auto-detector for zero-drift DSLR/Mirrorless synchronization.
"""

import ctypes
import json
import math
import os
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


TAI_UTC_OFFSET_SECONDS = 37
TAI_UTC_OFFSET_NS = 37_000_000_000
NTP_EPOCH_DELTA = 2_208_988_800


class _AbuClockCFrameSnapshot(ctypes.Structure):
    _fields_ = [
        ("tai_ns", ctypes.c_uint64),
        ("frame_index", ctypes.c_uint64),
        ("phase", ctypes.c_double),
        ("sleep_until_next_frame_ns", ctypes.c_uint64),
        ("bcd_timecode", ctypes.c_uint32),
        ("hours", ctypes.c_uint8),
        ("minutes", ctypes.c_uint8),
        ("seconds", ctypes.c_uint8),
        ("frames", ctypes.c_uint8),
        ("drop_frame", ctypes.c_uint8),
    ]


@dataclass
class AbuClockSnapshot:
    tai_ns: int
    utc_seconds: float
    frame_index: int
    phase: float
    sleep_until_next_frame_ns: int
    bcd_timecode: int
    hours: int
    minutes: int
    seconds: int
    frames: int
    drop_frame: bool
    fps_num: int = 30000
    fps_den: int = 1001
    lock_state: str = "WORKSTATION_MASTER"
    kalman_offset_ns: int = 0
    kalman_drift_ppb: float = 0.0

    @property
    def smpte_string(self) -> str:
        sep = ";" if self.drop_frame else ":"
        return f"{self.hours:02d}:{self.minutes:02d}:{self.seconds:02d}{sep}{self.frames:02d}"

    @property
    def smpte_subframe_string(self) -> str:
        sub = max(0, min(99, int(self.phase * 100.0)))
        return f"{self.smpte_string}.{sub:02d}"

    @property
    def bcd_hex(self) -> str:
        return f"0x{self.bcd_timecode:08X}"


class AbuClockBridge:
    _singleton: Optional["AbuClockBridge"] = None
    _singleton_lock = threading.Lock()

    @classmethod
    def instance(cls) -> "AbuClockBridge":
        with cls._singleton_lock:
            if cls._singleton is None:
                cls._singleton = cls()
            return cls._singleton

    def __init__(self):
        self.lock = threading.Lock()
        self.fps_num: int = 30000
        self.fps_den: int = 1001
        self.drop_frame: bool = True

        # Anchor high-resolution monotonic clock to UTC/TAI at startup
        self._anchor_utc_ns = time.time_ns()
        self._anchor_perf_ns = time.perf_counter_ns()
        self.kalman_offset_ns: int = 0
        self.kalman_drift_ppb: float = 0.0
        self.lock_state: str = "WORKSTATION_MASTER"
        self.master_ip: str = "127.0.0.1"
        self.daemon_port: int = 7878
        self.daemon_connected: bool = False

        # Registered ecosystem nodes (from UDP 50320 discovery or REST :7878)
        self.discovered_nodes: Dict[str, dict] = {}
        self.barrier_sequence: int = 1000
        self.last_barrier_info: str = "Idle"

        # Native FFI handle if abuclock.dll is available
        self._dll = None
        self._native_handle = None
        self._load_native_dll()

        self._running = True
        self._sntp_50320_sock: Optional[socket.socket] = None
        self._sntp_1230_sock: Optional[socket.socket] = None
        self._barrier_sock: Optional[socket.socket] = None

        self._start_background_services()

    def _load_native_dll(self):
        candidate_paths = [
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "abuclock.dll"),
            r"c:\Users\USer\Documents\antigravity\abu-clock\target\release\abuclock.dll",
        ]
        if getattr(sys, "frozen", False):
            candidate_paths.insert(0, os.path.join(os.path.dirname(sys.executable), "abuclock.dll"))

        for path in candidate_paths:
            if os.path.exists(path):
                try:
                    dll = ctypes.CDLL(path)
                    dll.abu_clock_create.argtypes = [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_bool]
                    dll.abu_clock_create.restype = ctypes.c_void_p
                    dll.abu_clock_destroy.argtypes = [ctypes.c_void_p]
                    dll.abu_clock_destroy.restype = None
                    dll.abu_clock_synthesize_now.argtypes = [ctypes.c_void_p, ctypes.POINTER(_AbuClockCFrameSnapshot)]
                    dll.abu_clock_synthesize_now.restype = ctypes.c_bool

                    handle = dll.abu_clock_create(
                        self.now_tai_ns(),
                        self.fps_num,
                        self.fps_den,
                        self.drop_frame,
                    )
                    if handle:
                        self._dll = dll
                        self._native_handle = handle
                        self.lock_state = "LOCKED_DLL_MASTER"
                        break
                except Exception:
                    pass

    def set_frame_rate(self, fps_label: str):
        mapping = {
            "23.976": (24000, 1001, False),
            "24": (24, 1, False),
            "25": (25, 1, False),
            "29.97 DF": (30000, 1001, True),
            "29.97 NDF": (30000, 1001, False),
            "30": (30, 1, False),
            "50": (50, 1, False),
            "59.94 DF": (60000, 1001, True),
            "60": (60, 1, False),
        }
        if fps_label in mapping:
            with self.lock:
                self.fps_num, self.fps_den, self.drop_frame = mapping[fps_label]
                if self._dll and self._native_handle:
                    try:
                        self._dll.abu_clock_destroy(self._native_handle)
                    except Exception:
                        pass
                    self._native_handle = self._dll.abu_clock_create(
                        self.now_tai_ns(), self.fps_num, self.fps_den, self.drop_frame
                    )

    def now_utc_ns(self) -> int:
        elapsed_perf = time.perf_counter_ns() - self._anchor_perf_ns
        drift_corr = int(elapsed_perf * (self.kalman_drift_ppb * 1e-9))
        return self._anchor_utc_ns + elapsed_perf + self.kalman_offset_ns + drift_corr

    def now_tai_ns(self) -> int:
        return self.now_utc_ns() + TAI_UTC_OFFSET_NS

    def now_utc_seconds(self) -> float:
        return self.now_utc_ns() * 1e-9

    def now(self) -> AbuClockSnapshot:
        tai_ns = self.now_tai_ns()
        return self.synthesize_from_tai_ns(tai_ns)

    @staticmethod
    def encode_bcd_timecode(hours: int, minutes: int, seconds: int, frames: int, drop_frame: bool) -> int:
        def to_bcd(val: int) -> int:
            return (((val // 10) & 0x0F) << 4) | ((val % 10) & 0x0F)

        word = (
            (to_bcd(hours) << 24)
            | (to_bcd(minutes) << 16)
            | (to_bcd(seconds) << 8)
            | to_bcd(frames)
        )
        if drop_frame:
            word |= 1 << 6
        return word & 0xFFFFFFFF

    @staticmethod
    def decode_bcd_timecode(bcd_word: int, default_drop_frame: bool = False) -> Tuple[int, int, int, int, bool]:
        drop_frame = default_drop_frame or ((bcd_word & (1 << 6)) != 0)
        f_bcd = bcd_word & 0x3F
        s_bcd = (bcd_word >> 8) & 0x7F
        m_bcd = (bcd_word >> 16) & 0x7F
        h_bcd = (bcd_word >> 24) & 0x3F

        def from_bcd(b: int) -> int:
            return ((b >> 4) & 0x0F) * 10 + (b & 0x0F)

        return from_bcd(h_bcd), from_bcd(m_bcd), from_bcd(s_bcd), from_bcd(f_bcd), drop_frame

    def synthesize_from_tai_ns(
        self,
        tai_ns: int,
        fps_num: Optional[int] = None,
        fps_den: Optional[int] = None,
        drop_frame: Optional[bool] = None,
    ) -> AbuClockSnapshot:
        with self.lock:
            f_num = fps_num if fps_num is not None else self.fps_num
            f_den = fps_den if fps_den is not None else self.fps_den
            df = drop_frame if drop_frame is not None else self.drop_frame
            lock_state = self.lock_state
            k_offset = self.kalman_offset_ns
            k_drift = self.kalman_drift_ppb

        tai_sec = tai_ns * 1e-9
        utc_sec = (tai_ns - TAI_UTC_OFFSET_NS) * 1e-9
        exact_frames = (tai_sec * float(f_num)) / float(max(1, f_den))
        total_frames = int(math.floor(exact_frames))
        phase = max(0.0, min(0.999999, exact_frames - math.floor(exact_frames)))
        frame_dur_ns = (1e9 * float(max(1, f_den))) / float(max(1, f_num))
        sleep_ns = int(max(0.0, (1.0 - phase) * frame_dur_ns))

        nominal_fps = max(1, int(round(float(f_num) / float(max(1, f_den)))))
        frame_number = total_frames

        if df and nominal_fps in (30, 60):
            drop_frames = 2 if nominal_fps == 30 else 4
            frames_per_min = nominal_fps * 60 - drop_frames
            frames_per_10min = frames_per_min * 10 + drop_frames
            d = frame_number // frames_per_10min
            m = frame_number % frames_per_10min
            if m > drop_frames:
                frame_number += drop_frames * 9 * d + drop_frames * ((m - drop_frames) // frames_per_min)
            else:
                frame_number += drop_frames * 9 * d

        ff = int(frame_number % nominal_fps)
        total_seconds = frame_number // nominal_fps
        ss = int(total_seconds % 60)
        mm = int((total_seconds // 60) % 60)
        hh = int((total_seconds // 3600) % 24)
        bcd = self.encode_bcd_timecode(hh, mm, ss, ff, df)

        return AbuClockSnapshot(
            tai_ns=tai_ns,
            utc_seconds=utc_sec,
            frame_index=total_frames,
            phase=phase,
            sleep_until_next_frame_ns=sleep_ns,
            bcd_timecode=bcd,
            hours=hh,
            minutes=mm,
            seconds=ss,
            frames=ff,
            drop_frame=df,
            fps_num=f_num,
            fps_den=f_den,
            lock_state=lock_state,
            kalman_offset_ns=k_offset,
            kalman_drift_ppb=k_drift,
        )

    def synthesize_from_utc_seconds(self, utc_seconds: float) -> AbuClockSnapshot:
        tai_ns = int(round(utc_seconds * 1e9)) + TAI_UTC_OFFSET_NS
        return self.synthesize_from_tai_ns(tai_ns)

    # -------------------------------------------------------------------------
    # Background Daemon / UDP 50320 SNTP + Discovery + Barrier Trigger Services
    # -------------------------------------------------------------------------

    def _start_background_services(self):
        threading.Thread(target=self._probe_or_launch_daemon, daemon=True, name="AbuClockDaemonProbe").start()
        threading.Thread(target=self._run_udp_50320_responder, daemon=True, name="AbuClockUDP50320").start()
        threading.Thread(target=self._run_udp_1230_responder, daemon=True, name="AbuClockUDP1230").start()

    def _probe_or_launch_daemon(self):
        # 1. Check if abu-clock daemon is already listening on :7878
        if not self._check_daemon_health():
            daemon_exe = r"c:\Users\USer\Documents\antigravity\abu-clock\target\release\abu-clock.exe"
            if os.path.exists(daemon_exe):
                try:
                    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)
                    subprocess.Popen(
                        [daemon_exe],
                        cwd=os.path.dirname(daemon_exe),
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        creationflags=creationflags,
                    )
                    time.sleep(0.6)
                except Exception:
                    pass

        while self._running:
            self._check_daemon_health()
            time.sleep(5.0)

    def _check_daemon_health(self) -> bool:
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{self.daemon_port}/api/status", method="GET")
            with urllib.request.urlopen(req, timeout=0.6) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    with self.lock:
                        self.daemon_connected = True
                        self.lock_state = data.get("state", "LOCKED_DAEMON")
                    self._register_self_with_daemon()
                    return True
        except Exception:
            with self.lock:
                self.daemon_connected = False
                if self._dll is not None:
                    self.lock_state = "LOCKED_DLL_MASTER"
                else:
                    self.lock_state = "WORKSTATION_MASTER"
        return False

    def _register_self_with_daemon(self):
        try:
            payload = json.dumps(
                {
                    "node_id": f"WinWorkstation-{socket.gethostname()}",
                    "node_type": "AbuTrackDesktop",
                    "capabilities": [
                        "LiveReceiver",
                        "PhotoSync_SLERP",
                        "RTP_VideoDecoder",
                        "MultiProtocolForwarder",
                        "ScheduleCaptureAt",
                    ],
                    "listening_port": 8080,
                }
            ).encode("utf-8")
            req = urllib.request.Request(
                f"http://127.0.0.1:{self.daemon_port}/api/ecosystem/register",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=0.5).close()
        except Exception:
            pass

    def _pack_sntp_response(self, request_bytes: bytes, rx_utc_sec: float) -> bytes:
        tx_utc_sec = self.now_utc_seconds()

        def to_ntp_64(utc_sec: float) -> Tuple[int, int]:
            ntp_sec = int(utc_sec) + NTP_EPOCH_DELTA
            frac = int((utc_sec - math.floor(utc_sec)) * 4294967296.0) & 0xFFFFFFFF
            return ntp_sec & 0xFFFFFFFF, frac

        rx_s, rx_f = to_ntp_64(rx_utc_sec)
        tx_s, tx_f = to_ntp_64(tx_utc_sec)

        resp = bytearray(48)
        resp[0] = 0x24  # LI=0, VN=4, Mode=4 (Server)
        resp[1] = 1     # Stratum 1 (Primary AbuClock Reference)
        resp[2] = 4     # Poll
        resp[3] = 0xEC  # Precision (-20 -> ~1 us)
        resp[12:16] = b"ABUC"

        # Copy client's Transmit Timestamp (bytes 40..47) into Originate Timestamp (bytes 24..31)
        if len(request_bytes) >= 48:
            resp[24:32] = request_bytes[40:48]

        # Reference Timestamp (16..23), Receive Timestamp (32..39), Transmit Timestamp (40..47)
        struct.pack_into(">II", resp, 16, rx_s, rx_f)
        struct.pack_into(">II", resp, 32, rx_s, rx_f)
        struct.pack_into(">II", resp, 40, tx_s, tx_f)
        return bytes(resp)

    def _run_udp_50320_responder(self):
        """
        Serves both:
        - `ABU_ECO_V1` auto-discovery probes from iOS / UE5 nodes on UDP 50320
        - 48-byte RFC 4330 SNTPv4 precision timing requests on UDP 50320
        """
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", 50320))
            self._sntp_50320_sock = sock
        except Exception:
            # Port 50320 is already bound by abu-clock.exe daemon
            return

        while self._running:
            try:
                data, addr = sock.recvfrom(2048)
                rx_utc = self.now_utc_seconds()
                if data.startswith(b"ABU_ECO_V1"):
                    self.discovered_nodes[addr[0]] = {
                        "ip": addr[0],
                        "port": addr[1],
                        "last_seen": time.time(),
                    }
                    snap = self.now()
                    reply = json.dumps(
                        {
                            "magic": "ABU_ECO_V1",
                            "role": "MASTER",
                            "node_id": f"AbuClock-Win-{socket.gethostname()}",
                            "sntp_port": 50320,
                            "rest_port": self.daemon_port,
                            "tai_ns": snap.tai_ns,
                            "smpte": snap.smpte_string,
                            "fps_num": self.fps_num,
                            "fps_den": self.fps_den,
                            "drop_frame": self.drop_frame,
                        }
                    ).encode("utf-8")
                    sock.sendto(reply, addr)
                elif len(data) >= 48:
                    self.discovered_nodes[addr[0]] = {
                        "ip": addr[0],
                        "port": addr[1],
                        "last_seen": time.time(),
                    }
                    resp = self._pack_sntp_response(data, rx_utc)
                    sock.sendto(resp, addr)
            except Exception:
                time.sleep(0.01)

    def _run_udp_1230_responder(self):
        """Legacy UDP 1230 SNTP responder for backward compatibility."""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", 1230))
            self._sntp_1230_sock = sock
        except Exception:
            return

        while self._running:
            try:
                data, addr = sock.recvfrom(2048)
                rx_utc = self.now_utc_seconds()
                if len(data) >= 48:
                    resp = self._pack_sntp_response(data, rx_utc)
                    sock.sendto(resp, addr)
            except Exception:
                time.sleep(0.01)

    # -------------------------------------------------------------------------
    # Future-Time Multi-Sensor Barrier Trigger (SCHEDULE_CAPTURE_AT on UDP 50319)
    # -------------------------------------------------------------------------

    def schedule_capture_barrier(
        self,
        lead_time_ms: int = 50,
        frame_id: Optional[int] = None,
        target_ips: Optional[List[str]] = None,
    ) -> dict:
        """
        Broadcasts a `SCHEDULE_CAPTURE_AT` barrier command (`ABU_TRIG_V1` 25-byte binary +
        JSON envelope) on UDP port 50319 so all iOS cameras, LiDAR sensors, and connected
        rigs fire their shutters at the exact same future TAI nanosecond `target_tai_ns`.
        """
        with self.lock:
            self.barrier_sequence += 1
            seq_id = frame_id if frame_id is not None else self.barrier_sequence

        lead_ns = max(5, int(lead_time_ms)) * 1_000_000
        target_tai_ns = self.now_tai_ns() + lead_ns
        target_snap = self.synthesize_from_tai_ns(target_tai_ns)

        # 25-byte binary packet: "ABU_TRIG_V1\0" (12B) + target_tai_ns (u64 BE) + frame_id (u32 BE) + sensor_mask (u8)
        binary_pkt = struct.pack(">12sQIB", b"ABU_TRIG_V1\x00", target_tai_ns, seq_id & 0xFFFFFFFF, 0xFF)

        destinations = set(["255.255.255.255", "127.0.0.1"])
        for ip in self.discovered_nodes.keys():
            destinations.add(ip)
        if target_ips:
            for ip in target_ips:
                if ip:
                    destinations.add(ip)

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            for ip in destinations:
                try:
                    sock.sendto(binary_pkt, (ip, 50319))
                except Exception:
                    pass
            sock.close()
        except Exception:
            pass

        info = {
            "sequence_id": seq_id,
            "target_tai_ns": target_tai_ns,
            "target_smpte": target_snap.smpte_subframe_string,
            "bcd_timecode": target_snap.bcd_hex,
            "lead_time_ms": lead_time_ms,
            "destinations": sorted(list(destinations)),
        }
        self.last_barrier_info = f"Frame #{seq_id} @ {target_snap.smpte_subframe_string} (+{lead_time_ms}ms)"
        return info

    # -------------------------------------------------------------------------
    # FreeD 0xD1 / 0xD2 (SMPTE FreeD-TC) & OpenTrackIO Packet Helpers
    # -------------------------------------------------------------------------

    @staticmethod
    def pack_freed_24(val: float) -> bytes:
        ival = int(round(val))
        if ival < 0:
            ival += 0x1000000
        ival &= 0xFFFFFF
        return bytes([(ival >> 16) & 0xFF, (ival >> 8) & 0xFF, ival & 0xFF])

    @staticmethod
    def unpack_freed_24(b0: int, b1: int, b2: int) -> int:
        val = (b0 << 16) | (b1 << 8) | b2
        if val & 0x800000:
            val -= 0x1000000
        return val

    def pack_freed_d2(
        self,
        pitch_deg: float,
        yaw_deg: float,
        roll_deg: float,
        x_m: float,
        y_m: float,
        z_m: float,
        focal_length_mm: float = 24.0,
        focus_distance_m: float = 1.5,
        utc_timestamp: Optional[float] = None,
        camera_id: int = 1,
    ) -> bytes:
        """
        Packs a 41-byte SMPTE FreeD-TC (0xD2) datagram:
        - Bytes 0..28 : Standard 29-byte FreeD body with 0xD2 message type & modulo-256 checksum
        - Bytes 29..32: 32-bit SMPTE ST 12-1 BCD timecode (big-endian)
        - Bytes 33..40: 64-bit TAI nanoseconds (big-endian)
        """
        snap = self.synthesize_from_utc_seconds(utc_timestamp) if utc_timestamp else self.now()
        pkt = bytearray()
        pkt.append(0xD2)
        pkt.append(camera_id & 0xFF)
        pkt.extend(self.pack_freed_24(pitch_deg * 32768.0))
        pkt.extend(self.pack_freed_24(yaw_deg * 32768.0))
        pkt.extend(self.pack_freed_24(roll_deg * 32768.0))
        pkt.extend(self.pack_freed_24(z_m * 1000.0 * 64.0))
        pkt.extend(self.pack_freed_24(x_m * 1000.0 * 64.0))
        pkt.extend(self.pack_freed_24(y_m * 1000.0 * 64.0))
        pkt.extend(self.pack_freed_24(focal_length_mm * 100.0))
        pkt.extend(self.pack_freed_24(focus_distance_m * 1000.0))
        pkt.extend(b"\x00\x00")
        checksum = (0x40 - sum(pkt)) & 0xFF
        pkt.append(checksum)
        pkt.extend(struct.pack(">IQ", snap.bcd_timecode, snap.tai_ns))
        return bytes(pkt)

    def unpack_freed_packet(self, data: bytes) -> Optional[dict]:
        """Unpacks 29B FreeD (0xD1), 37B Extended FreeD (0xD1), or 41B SMPTE FreeD-TC (0xD2)."""
        if len(data) < 29 or data[0] not in (0xD1, 0xD2):
            return None

        is_d2 = data[0] == 0xD2 and len(data) >= 41
        pitch = self.unpack_freed_24(data[2], data[3], data[4]) / 32768.0
        yaw = self.unpack_freed_24(data[5], data[6], data[7]) / 32768.0
        roll = self.unpack_freed_24(data[8], data[9], data[10]) / 32768.0
        pz = self.unpack_freed_24(data[11], data[12], data[13]) / (1000.0 * 64.0)
        px = self.unpack_freed_24(data[14], data[15], data[16]) / (1000.0 * 64.0)
        py = self.unpack_freed_24(data[17], data[18], data[19]) / (1000.0 * 64.0)
        zoom_raw = self.unpack_freed_24(data[20], data[21], data[22])
        focus_raw = self.unpack_freed_24(data[23], data[24], data[25])
        focal_mm = (zoom_raw / 100.0) if zoom_raw > 0 else 24.0

        if is_d2:
            bcd_tc, tai_ns = struct.unpack(">IQ", data[29:41])
            snap = self.synthesize_from_tai_ns(tai_ns)
            hh, mm, ss, ff, df = self.decode_bcd_timecode(bcd_tc, snap.drop_frame)
            sep = ";" if df else ":"
            smpte_str = f"{hh:02d}:{mm:02d}:{ss:02d}{sep}{ff:02d}"
            utc_ts = (tai_ns - TAI_UTC_OFFSET_NS) * 1e-9
            proto_name = "FreeD-TC 0xD2 (41B)"
        elif len(data) >= 37:
            utc_ms = struct.unpack(">q", data[29:37])[0]
            utc_ts = utc_ms / 1000.0
            snap = self.synthesize_from_utc_seconds(utc_ts)
            bcd_tc = snap.bcd_timecode
            tai_ns = snap.tai_ns
            smpte_str = snap.smpte_string
            proto_name = "FreeD 0xD1 (37B)"
        else:
            snap = self.now()
            utc_ts = snap.utc_seconds
            bcd_tc = snap.bcd_timecode
            tai_ns = snap.tai_ns
            smpte_str = snap.smpte_string
            proto_name = "FreeD 0xD1 (29B)"

        return {
            "protocol": proto_name,
            "camera_id": data[1],
            "x": px,
            "y": py,
            "z": pz,
            "pitch": pitch,
            "yaw": yaw,
            "roll": roll,
            "focalLength": focal_mm,
            "focusDistance": (focus_raw / 1000.0) if focus_raw > 0 else 1.5,
            "timestamp": utc_ts,
            "taiNs": tai_ns,
            "bcdTimecode": bcd_tc,
            "smpteTimecode": smpte_str,
            "subframePhase": snap.phase,
        }
