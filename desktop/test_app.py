"""Exercise the real GUI's separate scan/send actions with a loop-bound device."""

import asyncio
import importlib.util
from types import SimpleNamespace
import time
import unittest
from unittest.mock import patch

GUI_AVAILABLE = importlib.util.find_spec('tkinter') is not None
if GUI_AVAILABLE:
    try:
        import tkinter as tk
        from app import App
    except ImportError:
        GUI_AVAILABLE = False


@unittest.skipUnless(GUI_AVAILABLE, 'Requires Tk; run this GUI regression test on the Mac')
class AppLoopTests(unittest.TestCase):
    def setUp(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.app = App(self.root)

    def tearDown(self):
        if hasattr(self.app, 'close'):
            self.app.close()
            self.app.async_thread.join(timeout=1)
        else:
            self.root.destroy()

    def wait_until_idle(self):
        deadline = time.monotonic() + 3
        while self.app.working and time.monotonic() < deadline:
            self.root.update()
            time.sleep(0.005)
        self.assertFalse(self.app.working, 'GUI operation did not finish')

    def test_scan_then_send_keeps_device_future_on_same_loop(self):
        transferred = []
        devices = []

        async def discover():
            device = SimpleNamespace(address='test-iphone', name='EpaperBridge')
            device.ready = asyncio.get_running_loop().create_future()
            devices.append(device)
            return [device]

        class Client:
            def __init__(self, device, **kwargs):
                self.device = device

            async def __aenter__(self):
                # CoreBluetooth exposes futures owned by the scanner's loop.
                # A new loop for connect must fail with the real asyncio error.
                asyncio.get_running_loop().call_later(0.05, self.device.ready.set_result, None)
                await self.device.ready
                return self

            async def __aexit__(self, *args):
                pass

        async def transfer(client, frame, progress, transport, host):
            transferred.append(frame)

        with patch('app.discover', discover), patch('bleak.BleakClient', Client), patch('app.transfer_image', transfer):
            self.app.start_scan()
            self.wait_until_idle()
            self.assertEqual(len(devices), 1)
            self.app.frame = bytes(48000)
            self.app.start_send()
            self.wait_until_idle()
        self.assertEqual(len(transferred), 1, self.app.status.get())
        self.assertEqual(transferred[0], bytes(48000))
        self.assertNotIn('different loop', self.app.status.get())


if __name__ == '__main__':
    unittest.main()
