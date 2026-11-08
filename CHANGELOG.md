# Changelog

## 0.1.0 - 2026-11-08

Initial versioned release.

- Walk RIFF chunks by declared size instead of assuming `fmt ` is the first chunk;
  unknown chunks such as `bext`, `JUNK`, `PAD `, and `FLLR` are skipped safely.
- Resolve `WAVE_FORMAT_EXTENSIBLE` through its `SubFormat` GUID.
- Expose raw `waveFormatTag` and `subFormatTag` values alongside the effective
  `waveFormat`.
- Validate PCM-like `wBitsPerSample`, `nBlockAlign`, and `nAvgBytesPerSec`
  consistency.
- Add typed `WavParseError.kind` values; `WavParseError` remains a `ValueError`.
- Add `-d:cwpAllowUnknownFormats` to accept unknown format tags/subformats as
  `WAVE_FORMAT_UNKNOWN` with raw tags preserved.
