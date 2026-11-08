# Sanitized WAVs

These files reproduce chunk order/types and `fmt ` fields observed in real
BWF/PCM recordings. They contain no original audio, metadata, or identifying
bytes:

- `bext` and filler payloads are zero-filled.
- Audio is generated silence.
- Filler chunk sizes are reduced from the originals to keep the WAVs tiny.

Layouts:

| File | Chunk layout |
|---|---|
| `bext-before-fmt-padded.wav` | `bext` (32 B) → `fmt ` (PCM, 48 kHz, mono, 24-bit) → `PAD ` (32 B) → `data` (16 silent frames) |
| `fllr-after-fmt.wav` | `fmt ` (PCM, 44.1 kHz, mono, 16-bit) → `FLLR` (32 B) → `data` (16 silent frames) |
| `canonical-pcm16.wav` | `fmt ` (PCM, 48 kHz, mono, 16-bit) → `data` (16 silent frames) |
