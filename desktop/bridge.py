"""Prepare images and send them to the project's iPhone BLE receiver."""

import argparse
import asyncio
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
from pathlib import Path
import secrets
import socket
import struct
import threading
import zlib

from PIL import Image, ImageOps

SERVICE = "e3911000-7c21-4e12-9234-18a3347a6000"
CONTROL = "e3911001-7c21-4e12-9234-18a3347a6000"
DATA = "e3911002-7c21-4e12-9234-18a3347a6000"
STATUS = "e3911003-7c21-4e12-9234-18a3347a6000"
SIZE = (800, 480)
FRAME_BYTES = 48000


def prepare(path, fit="contain", dither=True):
    """Return an exact-size 1-bit image; white is 1, first pixel is MSB."""
    with Image.open(path) as source:
        oriented = ImageOps.exif_transpose(source).convert("RGBA")
        white = Image.new("RGBA", oriented.size, "white")
        white.alpha_composite(oriented)
        gray = white.convert("L")
    if fit == "cover":
        gray = ImageOps.fit(gray, SIZE, method=Image.Resampling.LANCZOS)
    else:
        scaled = ImageOps.contain(gray, SIZE, method=Image.Resampling.LANCZOS)
        gray = Image.new("L", SIZE, 255)
        gray.paste(scaled, ((800 - scaled.width) // 2, (480 - scaled.height) // 2))
    return gray, gray.convert(
        "1", dither=Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
    )


def begin_packet(payload):
    if len(payload) != FRAME_BYTES:
        raise ValueError("800 × 480 圖片必須是 48000 bytes")
    return struct.pack("<BHHII", 1, *SIZE, len(payload), zlib.crc32(payload))


def data_packets(payload, chunk_size=15):
    if not 1 <= chunk_size <= 15:
        raise ValueError("資料區塊大小必須介於 1–15")
    for offset in range(0, len(payload), chunk_size):
        yield struct.pack("<BI", 2, offset) + payload[offset:offset + chunk_size]


def parse_status(raw):
    if len(raw) != 9:
        raise RuntimeError("iPhone 回傳無法辨識的狀態")
    return struct.unpack("<BII", raw)


async def transfer(client, payload, progress=print):
    """ATT acknowledgements pace every write; commit validates the whole image."""
    checksum = zlib.crc32(payload)
    await client.write_gatt_char(CONTROL, begin_packet(payload), response=True)
    state, count, _ = parse_status(await client.read_gatt_char(STATUS))
    if (state, count) != (1, 0):
        raise RuntimeError("iPhone 尚未準備接收")
    for index, packet in enumerate(data_packets(payload)):
        await client.write_gatt_char(DATA, packet, response=True)
        if index % 320 == 0:
            progress(f"BLE 傳送 {min((index + 1) * 15, len(payload)) * 100 // len(payload)}%")
    await client.write_gatt_char(CONTROL, b"\x03", response=True)
    state, count, actual_crc = parse_status(await client.read_gatt_char(STATUS))
    if (state, count, actual_crc) != (2, len(payload), checksum):
        raise RuntimeError("iPhone 未確認完整接收；請重新傳送整張圖片")
    progress("iPhone 已完整接收並通過 CRC 檢查；請在手機按「更新電子紙」。")


def lan_address(host=None):
    if host is None:
        # Selecting a route does not transmit a packet to this documentation IP.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 9))
            host = probe.getsockname()[0]
    address = ipaddress.IPv4Address(host)
    networks = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16")
    if not any(address in ipaddress.IPv4Network(net) for net in networks):
        raise ValueError("請以 --host 指定 iPhone 可連到的電腦區域網路 IPv4 位址")
    return str(address)


@contextmanager
def image_server(payload, host, port=0):
    """Serve only this in-memory image at an unpredictable, temporary URL."""
    if len(payload) != FRAME_BYTES:
        raise ValueError("圖片長度錯誤")
    route = "/" + secrets.token_urlsafe(24) + "/frame.bin"

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def do_GET(self):
            if self.path != route:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer((host, port), Handler)
    worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
    worker.start()
    try:
        yield f"http://{host}:{server.server_port}{route}"
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)


async def transfer_wifi(client, payload, progress=print, host=None, timeout=60):
    host = lan_address(host)
    checksum = zlib.crc32(payload)
    with image_server(payload, host) as url:
        descriptor = json.dumps({
            "url": url, "width": 800, "height": 480,
            "length": len(payload), "crc32": checksum,
        }, separators=(",", ":")).encode()
        await client.write_gatt_char(
            CONTROL, struct.pack("<BII", 4, len(descriptor), zlib.crc32(descriptor)), response=True
        )
        state, count, _ = parse_status(await client.read_gatt_char(STATUS))
        if (state, count) != (1, 0):
            raise RuntimeError("iPhone 不支援 Wi-Fi 交接或尚未準備接收")
        for packet in data_packets(descriptor):
            await client.write_gatt_char(DATA, packet, response=True)
        progress(f"BLE 已交接，正在透過區域網路 {host} 傳圖…")
        await client.write_gatt_char(CONTROL, b"\x03", response=True)
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            state, count, actual_crc = parse_status(await client.read_gatt_char(STATUS))
            if state == 4:
                if (count, actual_crc) != (len(payload), checksum):
                    raise RuntimeError("Wi-Fi 圖片完整性確認不符")
                progress("iPhone 已透過區域網路完整接收；請在手機按「更新電子紙」。")
                return
            if state == 5:
                raise RuntimeError("iPhone 下載失敗；請查看手機訊息、區域網路權限與電腦防火牆，或改用 --transport ble")
            if state != 3:
                raise RuntimeError("Wi-Fi 接收已取消；請在手機重新開啟接收")
            await asyncio.sleep(0.25)
        raise RuntimeError("Wi-Fi 傳圖逾時；請確認同一區域網路與防火牆，或改用 --transport ble")


async def transfer_image(client, payload, progress=print, transport="wifi", host=None):
    if transport == "ble":
        await transfer(client, payload, progress)
    else:
        await transfer_wifi(client, payload, progress, host)


async def discover(address=None):
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=10, service_uuids=[SERVICE])
    if address:
        found = [d for d in found if d.address.lower() == address.lower()]
    return found


async def send(payload, address, transport="wifi", host=None):
    from bleak import BleakClient

    devices = await discover(address)
    if not devices:
        raise RuntimeError("找不到接收端；請開啟 iPhone App 並按「接收電腦圖片」，保持前景。")
    if len(devices) != 1:
        raise RuntimeError("找到多個接收端；請先 scan，再以 --address 指定裝置。")
    async with BleakClient(devices[0], timeout=30) as client:
        await transfer_image(client, payload, transport=transport, host=host)


def main():
    parser = argparse.ArgumentParser(description="電腦 → BLE → iPhone → NFC → 電子紙")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("scan", help="尋找專用 iPhone 接收端")
    for name in ("prepare", "send"):
        command = commands.add_parser(name)
        command.add_argument("image", type=Path)
        command.add_argument("--fit", choices=("contain", "cover"), default="contain")
        command.add_argument("--threshold", action="store_true", help="直接二值化，停用抖色")
        command.add_argument("--output", type=Path, default=Path("output"))
        if name == "send":
            command.add_argument("--address", help="由 scan 取得的電腦端裝置識別碼")
            command.add_argument("--transport", choices=("wifi", "ble"), default="wifi")
            command.add_argument("--host", help="電腦的區域網路 IPv4；多個網路介面時手動指定")
    args = parser.parse_args()
    try:
        if args.command == "scan":
            for device in asyncio.run(discover()):
                print(device.address, device.name or "EpaperBridge")
            return
        gray, mono = prepare(args.image, args.fit, not args.threshold)
        args.output.mkdir(parents=True, exist_ok=True)
        gray.save(args.output / "preview-gray.png")
        mono.save(args.output / "preview.png")
        payload = mono.tobytes()
        (args.output / "frame.bin").write_bytes(payload)
        print(f"已輸出 800 × 480 預覽至 {args.output}")
        if args.command == "send":
            asyncio.run(send(payload, args.address, args.transport, args.host))
    except Exception as error:
        parser.exit(1, f"錯誤：{error}\n")
    except KeyboardInterrupt:
        parser.exit(130, "已取消傳送；請重新傳送整張圖片。\n")


if __name__ == "__main__":
    main()
