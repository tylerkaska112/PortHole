# 0006 (audio jitter cushion) is retired

`0006-madeira-audio-cushion.patch` kept the audio ring from running dry (a 80 ms silence prime plus slow playback while refilling). It no longer applies: in the Madeira update of 2026-10-04
upstream rewrote the same code with its own pacing (`ml1230`: the timer thread keeps `MADEIRA_AUDIO_LEAD_MS` of audio in the ring, default 60 ms, and wakes the client by ring fill
instead of every 10 ms), plus silent `GetBuffer` and a 7.1.4 fold-down. It targets the same problem (choppy audio), so Porthole now uses upstream's audio as it is.

The old patch file is kept for reference. If the audio is choppy again on a device, try `MADEIRA_AUDIO_LEAD_MS=120` first, then consider porting the cushion on top of the new code.
