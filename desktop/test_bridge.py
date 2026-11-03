import asyncio
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import zlib

from PIL import Image

from bridge import CONTROL, DATA, FRAME_BYTES, begin_packet, data_packets, image_server, lan_address, prepare, transfer, transfer_wifi


class ImageTests(unittest.TestCase):
    def test_transparency_is_white_and_content_is_not_stretched(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.png"
            source = Image.new("RGBA", (100, 200), (0, 0, 0, 255))
            source.putpixel((50, 100), (0, 0, 0, 0))
            source.save(path)
            _, mono = prepare(path, dither=False)
            self.assertEqual(mono.size, (800, 480))
            self.assertEqual(len(mono.tobytes()), FRAME_BYTES)
            self.assertEqual(mono.getpixel((0, 240)), 255)
            self.assertEqual(mono.getpixel((280, 240)), 0)
            self.assertEqual(mono.getpixel((400, 240)), 255)

    def test_cover_fills_canvas(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.png"
            Image.new("RGB", (100, 200), "black").save(path)
            _, mono = prepare(path, fit="cover")
            self.assertEqual(mono.tobytes(), bytes(FRAME_BYTES))

    def test_white_is_one_and_first_pixel_is_high_bit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.png"
            source = Image.new("L", (800, 480), 255)
            source.putpixel((0, 0), 0)
            source.save(path)
            _, mono = prepare(path, dither=False)
            self.assertEqual(mono.tobytes()[:2], b"\x7f\xff")


class FakeReceiver:
    """Model the wire contract, not the platform BLE implementation."""
    def __init__(self, corrupt=False):
        self.buffer = bytearray()
        self.state = 0
        self.crc = 0
        self.corrupt = corrupt

    async def write_gatt_char(self, characteristic, packet, *, response):
        assert response is True
        assert len(packet) <= 20
        if characteristic == CONTROL and packet[0] == 1:
            _, width, height, count, self.expected = struct.unpack("<BHHII", packet)
            assert (width, height, count) == (800, 480, 48000)
            self.state = 1
        elif characteristic == DATA:
            offset = struct.unpack("<I", packet[1:5])[0]
            assert offset == len(self.buffer)
            self.buffer.extend(packet[5:])
        elif characteristic == CONTROL and packet == b"\x03":
            if self.corrupt:
                self.buffer[0] ^= 1
            self.crc = zlib.crc32(self.buffer)
            self.state = 2 if self.crc == self.expected else 3

    async def read_gatt_char(self, _):
        return struct.pack("<BII", self.state, len(self.buffer), self.crc)


class TransferTests(unittest.TestCase):
    def test_whole_image_reaches_receiver(self):
        payload = bytes(range(256)) * 187 + bytes(range(128))
        receiver = FakeReceiver()
        asyncio.run(transfer(receiver, payload, progress=lambda _: None))
        self.assertEqual(receiver.buffer, payload)
        self.assertEqual(receiver.state, 2)

    def test_corruption_does_not_report_success(self):
        with self.assertRaisesRegex(RuntimeError, "未確認完整接收"):
            asyncio.run(transfer(FakeReceiver(corrupt=True), bytes(48000), progress=lambda _: None))

    def test_invalid_frame_and_oversized_chunks_are_rejected(self):
        with self.assertRaises(ValueError):
            begin_packet(bytes(1))
        with self.assertRaises(ValueError):
            list(data_packets(bytes(48000), 16))


class WifiReceiver(FakeReceiver):
    def __init__(self, corrupt=False, stall=False):
        super().__init__(corrupt)
        self.stall = stall
        self.url = None
        self.image = None

    async def write_gatt_char(self, characteristic, packet, *, response):
        assert response is True
        assert len(packet) <= 20
        if characteristic == CONTROL and packet[0] == 4:
            _, self.length, self.expected = struct.unpack("<BII", packet)
            self.state = 1
        elif characteristic == DATA:
            assert struct.unpack("<I", packet[1:5])[0] == len(self.buffer)
            self.buffer.extend(packet[5:])
        elif characteristic == CONTROL and packet == b"\x03":
            assert len(self.buffer) == self.length
            assert zlib.crc32(self.buffer) == self.expected
            descriptor = json.loads(self.buffer)
            self.url = descriptor['url']
            self.state = 3
            if self.stall:
                return
            with urllib.request.urlopen(self.url, timeout=2) as response:
                image = bytearray(response.read())
            if self.corrupt:
                image[0] ^= 1
            self.image = image
            self.buffer = image
            self.crc = zlib.crc32(image)
            self.state = 4 if self.crc == descriptor['crc32'] else 5


class WifiTests(unittest.TestCase):
    def test_ble_handoff_downloads_image_over_http(self):
        payload = bytes(range(256)) * 187 + bytes(range(128))
        receiver = WifiReceiver()
        with patch('bridge.lan_address', return_value='127.0.0.1'):
            asyncio.run(transfer_wifi(receiver, payload, progress=lambda _: None))
        self.assertEqual(receiver.image, payload)
        # Only metadata travelled through BLE, not the image.
        self.assertLess(receiver.length, 1024)
        with self.assertRaises(urllib.error.URLError):
            urllib.request.urlopen(receiver.url, timeout=1)

    def test_wrong_route_is_not_a_file_server(self):
        with image_server(bytes(48000), '127.0.0.1') as url:
            base = url.split('/', 3)[:3]
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen('/'.join(base) + '/README.md', timeout=1)
            self.assertEqual(caught.exception.code, 404)
            caught.exception.close()

    def test_corrupt_wifi_image_is_failure(self):
        with patch('bridge.lan_address', return_value='127.0.0.1'):
            with self.assertRaisesRegex(RuntimeError, '下載失敗'):
                asyncio.run(transfer_wifi(WifiReceiver(corrupt=True), bytes(48000), progress=lambda _: None))

    def test_timeout_closes_server(self):
        receiver = WifiReceiver(stall=True)
        with patch('bridge.lan_address', return_value='127.0.0.1'):
            with self.assertRaisesRegex(RuntimeError, '逾時'):
                asyncio.run(transfer_wifi(receiver, bytes(48000), progress=lambda _: None, timeout=0))
        with self.assertRaises(urllib.error.URLError):
            urllib.request.urlopen(receiver.url, timeout=1)

    def test_non_lan_hosts_are_rejected(self):
        for host in ['127.0.0.1', '0.0.0.0', '8.8.8.8', 'example.com']:
            with self.assertRaises(ValueError):
                lan_address(host)
        self.assertEqual(lan_address('192.168.1.8'), '192.168.1.8')


if __name__ == "__main__":
    unittest.main()
