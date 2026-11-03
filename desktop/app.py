"""Desktop window for selecting an image and sending it to an iPhone."""

import asyncio
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from PIL import ImageTk

from bridge import discover, prepare, transfer_image


class App:
    def __init__(self, root):
        self.root = root
        self.events = queue.Queue()
        self.frame = None
        self.devices = []
        self.working = False
        # CoreBluetooth devices/futures belong to the event loop that scanned
        # them. Keep one loop and thread alive for every GUI action.
        self.async_loop = asyncio.new_event_loop()
        self.async_thread = threading.Thread(target=self.serve_async, daemon=True)
        self.async_thread.start()
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.title("電子紙橋接 · 電腦 → iPhone → NFC")
        root.geometry("850x650")
        panel = ttk.Frame(root, padding=20)
        panel.pack(fill="both", expand=True)
        ttk.Label(panel, text="選擇圖片，傳送到 iPhone", font=("", 18)).pack(anchor="w")
        self.preview = ttk.Label(panel, text="800 × 480 · 等比例縮放與補白 · 灰階抖色")
        self.preview.pack(pady=15)
        controls = ttk.Frame(panel)
        controls.pack(fill="x")
        self.choose = ttk.Button(controls, text="選擇圖片", command=self.select)
        self.choose.pack(side="left")
        self.scan = ttk.Button(controls, text="搜尋 iPhone", command=self.start_scan)
        self.scan.pack(side="left", padx=8)
        self.combo = ttk.Combobox(controls, state="readonly", width=38)
        self.combo.pack(side="left", padx=8)
        self.send = ttk.Button(controls, text="傳送圖片", command=self.start_send)
        self.send.pack(side="left")
        network = ttk.Frame(panel)
        network.pack(fill="x", pady=12)
        self.fast = tk.BooleanVar(value=True)
        self.fast_switch = ttk.Checkbutton(network, text="BLE 連線後使用區域網路快速傳圖", variable=self.fast)
        self.fast_switch.pack(side="left")
        ttk.Label(network, text="電腦 IP（留空自動）：").pack(side="left", padx=8)
        self.host = ttk.Entry(network, width=18)
        self.host.pack(side="left")
        self.status = tk.StringVar(value="先在專用 iPhone App 按「接收電腦圖片」，並保持前景。")
        ttk.Label(panel, textvariable=self.status, wraplength=780).pack(anchor="w", pady=15)
        self.root.after(100, self.poll)

    def select(self):
        name = filedialog.askopenfilename(filetypes=[("圖片", "*.png *.jpg *.jpeg *.webp *.bmp"), ("所有檔案", "*")])
        if not name:
            return
        try:
            gray, mono = prepare(name)
            self.frame = mono.tobytes()
            preview = mono.resize((720, 432))
            self.photo = ImageTk.PhotoImage(preview)
            self.preview.configure(image=self.photo, text="")
            output = Path("output")
            output.mkdir(exist_ok=True)
            mono.save(output / "preview.png")
            gray.save(output / "preview-gray.png")
            self.status.set(f"已準備 {Path(name).name} · 800 × 480")
        except (OSError, ValueError) as error:
            messagebox.showerror("無法開啟圖片", str(error))

    def run(self, operation):
        if self.working:
            return
        self.working = True
        for widget in (self.choose, self.scan, self.send, self.fast_switch, self.host):
            widget.configure(state="disabled")
        self.combo.configure(state="disabled")

        async def worker():
            try:
                await operation()
            except Exception as error:
                self.events.put(("message", f"未完成：{error}"))
            finally:
                self.events.put(("done", None))

        asyncio.run_coroutine_threadsafe(worker(), self.async_loop)

    def serve_async(self):
        asyncio.set_event_loop(self.async_loop)
        try:
            self.async_loop.run_forever()
        finally:
            pending = asyncio.all_tasks(self.async_loop)
            for task in pending:
                task.cancel()
            if pending:
                try:
                    self.async_loop.run_until_complete(asyncio.wait_for(
                        asyncio.gather(*pending, return_exceptions=True), timeout=3
                    ))
                except asyncio.TimeoutError:
                    pass
            self.async_loop.close()

    def close(self):
        self.async_loop.call_soon_threadsafe(self.async_loop.stop)
        self.root.destroy()

    def start_scan(self):
        async def scan():
            self.events.put(("message", "正在搜尋，請保持 iPhone App 在前景…"))
            devices = await discover()
            self.events.put(("devices", devices))
        self.run(scan)

    def start_send(self):
        index = self.combo.current()
        if self.frame is None or index < 0:
            messagebox.showinfo("尚未準備完成", "請選擇圖片，並搜尋及選取 iPhone。")
            return
        frame, device = self.frame, self.devices[index]
        transport = "wifi" if self.fast.get() else "ble"
        host = self.host.get().strip() or None

        async def send():
            from bleak import BleakClient

            self.events.put(("message", "正在連線到 iPhone…"))
            async with BleakClient(device, timeout=30) as client:
                await transfer_image(client, frame, lambda text: self.events.put(("message", text)), transport, host)
        self.run(send)

    def poll(self):
        try:
            while True:
                kind, value = self.events.get_nowait()
                if kind == "message":
                    self.status.set(value)
                elif kind == "devices":
                    self.devices = value
                    self.combo["values"] = [f"{d.name or 'EpaperBridge'} · {d.address}" for d in value]
                    self.combo.set("")
                    if value:
                        self.combo.current(0)
                    self.status.set(f"找到 {len(value)} 台接收端" if value else "找不到接收端，請在 iPhone 開啟接收後重試。")
                elif kind == "done":
                    self.working = False
                    for widget in (self.choose, self.scan, self.send, self.fast_switch, self.host):
                        widget.configure(state="normal")
                    self.combo.configure(state="readonly")
        except queue.Empty:
            pass
        self.root.after(100, self.poll)


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()
