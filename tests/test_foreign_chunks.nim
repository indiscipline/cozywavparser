import std/[streams, strutils, unittest]
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
            bitsPerSample: uint16 = 16; extra = ""): string =
  let blockAlign = channels * (bitsPerSample div 8)
  le16(0x0001) & le16(channels) & le32(sampleRate) &
    le32(sampleRate * uint32(blockAlign)) & le16(blockAlign) &
    le16(bitsPerSample) & extra

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
      check e.msg.contains("found: 'JUNK', 'bext'")

  test "rejects fmt chunk smaller than 16 bytes":
    let stream = newStringStream(wavFile([("fmt ", newString(12))]))
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.msg.contains("Invalid fmt subchunk size: 12")

  test "rejects a truncated chunk header":
    let stream = newStringStream("RIFF" & le32(7) & "WAVE" & "JUN")
    try:
      discard readWavHeader(stream)
      check false
    except WavParseError as e:
      check e.msg.contains("Truncated RIFF chunk header")
