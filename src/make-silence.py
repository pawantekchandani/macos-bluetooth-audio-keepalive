#!/usr/bin/env python3
"""Generate the near-silent WAV the keepalive loops.

48 kHz because that is what browsers typically output, and dithered noise at
roughly -72 dBFS rather than digital silence: some devices ignore a stream of
pure zeros, and a real (inaudible) signal costs nothing.
"""

import random
import struct
import sys
import wave

OUT = sys.argv[1] if len(sys.argv) > 1 else "silence48.wav"
RATE = 48000
SECONDS = 10
PEAK = 4  # LSB amplitude -> about -72 dBFS

with wave.open(OUT, "w") as f:
    f.setnchannels(2)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(
        b"".join(
            struct.pack("<hh", random.randint(-PEAK, PEAK), random.randint(-PEAK, PEAK))
            for _ in range(RATE * SECONDS)
        )
    )

print(f"wrote {OUT} ({SECONDS}s, {RATE} Hz, stereo, ~-72 dBFS)")
