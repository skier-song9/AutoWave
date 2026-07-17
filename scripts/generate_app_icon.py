#!/usr/bin/env python3
"""Render AutoWave's flat wave-ripple app icon without third-party packages."""

from pathlib import Path
import struct
import zlib


SIZE = 1024
SCALE = 4
OUTPUT = Path(__file__).resolve().parents[1] / "AutoWave/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
BACKGROUND = (7, 22, 48)
CYAN = (70, 230, 245)
AMBER = (255, 184, 65)


def render() -> bytes:
    high_size = SIZE * SCALE
    pixels = bytearray(BACKGROUND * (high_size * high_size))
    rings = ((512, 680, 205), (512, 680, 330), (512, 680, 455))
    ring_width = 22
    dot_center = (512, 515)
    dot_radius = 34

    for y in range(high_size):
        icon_y = (y + 0.5) / SCALE
        for x in range(high_size):
            icon_x = (x + 0.5) / SCALE
            color = None
            for center_x, center_y, radius in rings:
                distance = ((icon_x - center_x) ** 2 + (icon_y - center_y) ** 2) ** 0.5
                if abs(distance - radius) <= ring_width / 2:
                    color = CYAN
                    break

            dot_distance = ((icon_x - dot_center[0]) ** 2 + (icon_y - dot_center[1]) ** 2) ** 0.5
            if dot_distance <= dot_radius:
                color = AMBER

            if color is not None:
                index = (y * high_size + x) * 3
                pixels[index:index + 3] = bytes(color)

    output = bytearray()
    for y in range(SIZE):
        output.append(0)
        for x in range(SIZE):
            channels = [0, 0, 0]
            for sample_y in range(SCALE):
                for sample_x in range(SCALE):
                    index = (((y * SCALE + sample_y) * high_size) + x * SCALE + sample_x) * 3
                    for channel in range(3):
                        channels[channel] += pixels[index + channel]
            output.extend(channel // (SCALE * SCALE) for channel in channels)
    return png_bytes(SIZE, SIZE, bytes(output))


def png_bytes(width: int, height: int, data: bytes) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(data, 9)) + chunk(b"IEND", b"")


if __name__ == "__main__":
    OUTPUT.write_bytes(render())
    print(OUTPUT)
