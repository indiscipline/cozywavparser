import std/[os, streams, strutils, unittest]
import cozywavparser

func le16(value: uint16): string =
  result = newString(2)
  result[0] = char(value and 0xFF)
  result[1] = char((value shr 8) and 0xFF)

func le32(value: uint32): string =
  result = newString(4)
  result[0] = char(value and 0xFF)
  result[1] = char((value shr 8) and 0xFF)
  result[2] = char((value shr 16) and 0xFF)
  result[3] = char((value shr 24) and 0xFF)

func pcmFmt(channels: uint16 = 2; sampleRate: uint32 = 48000;
            bitsPerSample: uint16 = 16; extra = "";
            blockAlignOverride: uint16 = 0;
            byteRateOverride: uint32 = 0): string =
  let blockAlign =
    if blockAlignOverride != 0: blockAlignOverride
    else: channels * ((bitsPerSample + 7) div 8)
  let byteRate =
    if byteRateOverride != 0: byteRateOverride
    else: sampleRate * uint32(blockAlign)
  le16(0x0001) & le16(channels) & le32(sampleRate) & le32(byteRate) &
    le16(blockAlign) & le16(bitsPerSample) & extra

func extensibleFmt(subFormatTag: uint16; channels: uint16 = 2;
                   sampleRate: uint32 = 48000; bitsPerSample: uint16 = 32;
                   validBitsPerSample: uint16 = 0; channelMask: uint32 = 3;
                   cbSize: uint16 = 22; extra = ""): string =
  let blockAlign = channels * ((bitsPerSample + 7) div 8)
  let byteRate = sampleRate * uint32(blockAlign)
  le16(0xFFFE) & le16(channels) & le32(sampleRate) & le32(byteRate) &
    le16(blockAlign) & le16(bitsPerSample) & le16(cbSize) &
    le16(if validBitsPerSample == 0: bitsPerSample else: validBitsPerSample) &
    le32(channelMask) & le16(subFormatTag) & newString(14) & extra

func wavFile(chunks: openArray[(string, string)]): string =
  ## Builds a minimal RIFF/WAVE file from (chunk ID, payload) pairs.
  var body = "WAVE"
  for (id, payload) in chunks:
    doAssert id.len == 4
    body.add(id)
    body.add(le32(uint32(payload.len)))
    body.add(payload)
    if payload.len mod 2 == 1:
      body.add('\0')
  "RIFF" & le32(uint32(body.len)) & body

suite "RIFF chunk handling":
  test "fmt chunk directly after WAVE marker":
    let stream = newStringStream(wavFile([("fmt ", pcmFmt()), ("data", "")]))
    let header = readWavHeader(stream)
    check header.waveFormat == WAVE_FORMAT_PCM
    check header.waveFormatTag == 0x0001'u16
    check header.subFormatTag == 0
    check header.numChannels == 2
    check header.sampleRate == 48000
    check header.bitsPerSample == 16

  test "skips bext chunk before fmt chunk":
    let stream = newStringStream(wavFile([
      ("bext", newString(1114)),
      ("fmt ", pcmFmt()), ("PAD ", newString(100)), ("data", "")]))
    let header = readWavHeader(stream)
    check header.waveFormat == WAVE_FORMAT_PCM
    check header.numChannels == 2
    check header.sampleRate == 48000
    check header.byteRate == 192000
    check header.bitsPerSample == 16
    check not header.isFloat

  test "skips odd-sized chunk including its pad byte":
    let stream = newStringStream(wavFile([
      ("JUNK", "abcde"),
      ("fmt ", pcmFmt())]))
    let header = readWavHeader(stream)
    check header.numChannels == 2
    check header.sampleRate == 48000

  test "skips chunk larger than the internal read buffer":
    let stream = newStringStream(wavFile([
      ("bext", newString(10000)),
      ("fmt ", pcmFmt(channels = 1, sampleRate = 44100, bitsPerSample = 24))]))
    let header = readWavHeader(stream)
    check header.numChannels == 1
    check header.sampleRate == 44100
    check header.byteRate == 132300
    check header.bitsPerSample == 24

  test "handles fmt chunk with extra fields":
    let stream = newStringStream(wavFile([
      ("fmt ", pcmFmt(extra = le16(0)))]))
    let header = readWavHeader(stream)
    check header.sampleRate == 48000

  test "reports chunks seen when fmt chunk is missing":
    let stream = newStringStream(wavFile([
      ("JUNK", newString(4)), ("bext", newString(4))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weNoFmt
      check e.msg.contains("found: 'JUNK', 'bext'")

  test "rejects fmt chunk smaller than 16 bytes":
    let stream = newStringStream(wavFile([("fmt ", newString(12))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weInvalidFmtSize
      check e.msg.contains("Invalid fmt subchunk size: 12")

  test "rejects a truncated chunk header":
    let stream = newStringStream("RIFF" & le32(7) & "WAVE" & "JUN")
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weTruncatedHeader
      check e.msg.contains("Truncated RIFF chunk header")

  test "resolves extensible PCM subformat":
    let stream = newStringStream(wavFile([("fmt ", extensibleFmt(0x0001))]))
    let header = readWavHeader(stream)
    check header.waveFormat == WAVE_FORMAT_PCM
    check header.waveFormatTag == 0xFFFE'u16
    check header.subFormatTag == 0x0001'u16
    check header.bitsPerSample == 32
    check not header.isFloat

  test "resolves extensible IEEE float subformat":
    let stream = newStringStream(wavFile([("fmt ", extensibleFmt(0x0003))]))
    let header = readWavHeader(stream)
    check header.waveFormat == WAVE_FORMAT_IEEE_FLOAT
    check header.waveFormatTag == 0xFFFE'u16
    check header.subFormatTag == 0x0003'u16
    check header.isFloat

  test "rejects invalid extensible cbSize":
    let stream = newStringStream(wavFile([
      ("fmt ", extensibleFmt(0x0001, cbSize = 21))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weInvalidFmt
      check e.msg.contains("cbSize=21")

  test "rejects extensible wBitsPerSample that is not byte-aligned":
    let stream = newStringStream(wavFile([
      ("fmt ", extensibleFmt(0x0001, bitsPerSample = 20,
                             validBitsPerSample = 20))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weInvalidFmt
      check e.msg.contains("not a multiple of 8")

  test "rejects inconsistent nBlockAlign":
    let stream = newStringStream(wavFile([
      ("fmt ", pcmFmt(blockAlignOverride = 3))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weInvalidFmt
      check e.msg.contains("nBlockAlign=3, expected 4")

  test "rejects inconsistent nAvgBytesPerSec":
    let stream = newStringStream(wavFile([
      ("fmt ", pcmFmt(byteRateOverride = 1))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.kind == weInvalidFmt
      check e.msg.contains("nAvgBytesPerSec=1, expected 192000")

  when cwpAllowUnknownFormats:
    test "accepts unknown wave format tags when enabled":
      let payload = le16(0xFFF0) & le16(2) & le32(48000) & le32(1) &
                    le16(1) & le16(8)
      let header = readWavHeader(newStringStream(wavFile([("fmt ", payload)])))
      check header.waveFormat == WAVE_FORMAT_UNKNOWN
      check header.waveFormatTag == 0xFFF0'u16
      check header.subFormatTag == 0

    test "accepts unknown extensible subformats when enabled":
      let header = readWavHeader(newStringStream(wavFile([
        ("fmt ", extensibleFmt(0xFFF0))])))
      check header.waveFormat == WAVE_FORMAT_UNKNOWN
      check header.waveFormatTag == 0xFFFE'u16
      check header.subFormatTag == 0xFFF0'u16
      check not header.isFloat
  else:
    test "rejects unknown wave format tags by default":
      let stream = newStringStream(wavFile([
        ("fmt ", le16(0xFFF0) & newString(14))]))
      try:
        discard readWavHeader(stream)
        check false
      except WavParseError as e:
        check e.kind == weUnsupportedFormat
        check e.msg.contains("65520")

    test "rejects unknown extensible subformats by default":
      let stream = newStringStream(wavFile([
        ("fmt ", extensibleFmt(0xFFF0))]))
      try:
        discard readWavHeader(stream)
        check false
      except WavParseError as e:
        check e.kind == weUnsupportedFormat
        check e.msg.contains("extensible subformat 65520")

  test "WavParseError remains catchable as ValueError":
    try:
      discard readWavHeader(newStringStream(wavFile([("JUNK", newString(4))])))
      check false
    except ValueError as e:
      check e of WavParseError

  test "file wrapper preserves the parse error kind":
    let path = getTempDir() / "cozywavparser-" & $getCurrentProcessId() & ".wav"
    writeFile(path, wavFile([("JUNK", newString(4))]))
    defer: removeFile(path)
    try:
      discard readWavFileHeader(path)
      check false
    except WavParseError as e:
      check e.kind == weNoFmt
