## Cozy Wav Parser
## ===============
##
## This module provides a basic parser for WAV file metadata.
## As the actual PCM format specification is unreasonably complex, this module
## only supports the most common formats, which easily covers 99% of use-cases.
##
## This module is useful to quickly extract common information about the audio
## stream in a WAV file, such as sample rate, bit depth and the number of channels.
##
## `WAVE_FORMAT_EXTENSIBLE` files are resolved through their `SubFormat` GUID;
## `WavHeader.waveFormat` reports the effective format while `waveFormatTag`
## and `subFormatTag` expose the raw tag values.
##
## Unknown format tags and unknown extensible subformats are rejected by
## default. Compile with `-d:cwpAllowUnknownFormats` to return
## `WAVE_FORMAT_UNKNOWN` and preserve the raw tags instead.
##
## .. warning:: This code is not thoroughly tested and might not work correctly
##    for all valid WAV files

import std/streams
from std/enumutils import items

const
  cwpAllowUnknownFormats* {.booldefine.} = false ##|
    ## When enabled at build time (`-d:cwpAllowUnknownFormats`), unknown
    ## `wFormatTag` values and unknown `WAVE_FORMAT_EXTENSIBLE` subformats are
    ## returned as `WAVE_FORMAT_UNKNOWN` instead of raising `WavParseError`.

type
  WaveFormatTag* = enum ## Represents a non-exhaustive list of WAVE data formats.
    WAVE_FORMAT_UNKNOWN = (0x0, "Unknown"),
    WAVE_FORMAT_PCM = (0x1, "PCM"),
    WAVE_FORMAT_IEEE_FLOAT = (0x3, "IEEE float"),
    WAVE_FORMAT_ALAW = (0x6, "8-bit ITU-T G.711 A-law"),
    WAVE_FORMAT_MULAW = (0x7,  "8-bit ITU-T G.711 µ-law"),
    WAVE_FORMAT_EXTENSIBLE = (0xFFFE, "Extensible Wave Format"),

  WavHeaderRaw = object
    waveFormatTag: uint16
    effectiveFormat: WaveFormatTag
    subFormatTag: uint16
    numChannels: uint16
    sampleRate: uint32
    byteRate: uint32
    bitsPerSample: uint16
    isFloat: bool

  ChunkHeader = object
    id: array[4, char]
    size: uint32

  WavHeader* = object ## A parsed and superficially validated WAVE header.
    waveFormat*: WaveFormatTag
      ## Effective audio format. For `WAVE_FORMAT_EXTENSIBLE`, this is resolved
      ## from `SubFormat`.
    waveFormatTag*: uint16
      ## Raw `wFormatTag` field. For extensible files this is `0xFFFE`.
    subFormatTag*: uint16
      ## Raw `SubFormat` GUID tag for extensible files, otherwise 0.
    numChannels*: int
    sampleRate*: int
    byteRate*: int
    bitsPerSample*: int
    isFloat*: bool

  WavErrorKind* = enum ## Machine-readable reason a WAVE header was rejected.
    weNoRiff
    weNoWave
    weNoFmt
    weInvalidFmtSize
    weInvalidFmt
    weUnsupportedFormat
    weTruncatedHeader
    weTruncatedChunk

  WavParseError* = object of ValueError ##|
    ## Raised when a WAVE header is malformed or unsupported.
    ##
    ## `kind` identifies the failure without inspecting `msg`. Because this is
    ## a `ValueError`, callers of `readWavFileHeader` that already catch
    ## `ValueError` keep working.
    kind*: WavErrorKind

const
  CHUNKID = ['R', 'I', 'F', 'F']
  FORMAT =  ['W', 'A', 'V', 'E']
  SUBCHUNK1ID = ['f', 'm', 't', ' ']

func toWaveFormatTag(raw: uint16): WaveFormatTag =
  for fmt in items(WaveFormatTag):
    if fmt.uint16 == raw:
      return fmt
  WAVE_FORMAT_UNKNOWN

func isKnownFormat(fmt: WaveFormatTag): bool =
  case fmt
  of WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT, WAVE_FORMAT_ALAW,
     WAVE_FORMAT_MULAW, WAVE_FORMAT_EXTENSIBLE: true
  of WAVE_FORMAT_UNKNOWN: false

func isPcmLike(fmt: WaveFormatTag): bool =
  case fmt
  of WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT, WAVE_FORMAT_ALAW,
     WAVE_FORMAT_MULAW: true
  else: false

func wavErrorMessage(kind: WavErrorKind; detail = ""): string =
  case kind
    of weNoRiff: "No RIFF header found"
    of weNoWave: "No WAVE format marker found"
    of weNoFmt:
      if detail.len > 0: "No fmt subchunk found (found: " & detail & ")"
      else: "No fmt subchunk found"
    of weInvalidFmtSize: "Invalid fmt subchunk size: " & detail
    of weInvalidFmt: "Invalid fmt subchunk fields: " & detail
    of weUnsupportedFormat: "Unknown/unsupported wave format: " & detail
    of weTruncatedHeader: "Truncated RIFF chunk header"
    of weTruncatedChunk: "Unexpected end of file inside a RIFF chunk"

proc newWavError(kind: WavErrorKind; detail = ""): ref WavParseError =
  result = newException(WavParseError, wavErrorMessage(kind, detail))
  result.kind = kind

proc validateFmtFields(raw: WavHeaderRaw; blockAlign: uint16;
                       extensible: bool) {.raises: [WavParseError].} =
  ## Validates cross-field consistency for the PCM-like formats this module
  ## supports. Unknown formats are left unvalidated because their field
  ## semantics are format-specific.
  if not isPcmLike(raw.effectiveFormat):
    return
  if raw.numChannels == 0:
    raise newWavError(weInvalidFmt, "nChannels is 0")
  if raw.sampleRate == 0:
    raise newWavError(weInvalidFmt, "nSamplesPerSec is 0")
  if raw.bitsPerSample == 0:
    raise newWavError(weInvalidFmt, "wBitsPerSample is 0")
  if extensible and raw.bitsPerSample mod 8 != 0:
    raise newWavError(weInvalidFmt, "wBitsPerSample is not a multiple of 8")

  let
    containerBytes = (uint32(raw.bitsPerSample) + 7) div 8
    expectedBlockAlign = uint32(raw.numChannels) * containerBytes
  if uint32(blockAlign) != expectedBlockAlign:
    raise newWavError(weInvalidFmt,
      "nBlockAlign=" & $blockAlign & ", expected " & $expectedBlockAlign)

  let expectedByteRate = uint64(raw.sampleRate) * uint64(blockAlign)
  if uint64(raw.byteRate) != expectedByteRate:
    raise newWavError(weInvalidFmt,
      "nAvgBytesPerSec=" & $raw.byteRate & ", expected " & $expectedByteRate)

proc skipBytes(file: Stream; count: int64) {.raises: [IOError, OSError, WavParseError].} =
  ## Consumes `count` bytes from the stream without allocating `count` bytes.
  var
    remaining = count
    buffer: array[4096, char]
  while remaining > 0:
    let toRead = int(min(remaining, int64(buffer.len)))
    let readNow = file.readData(addr buffer[0], toRead)
    if readNow <= 0:
      raise newWavError(weTruncatedChunk)
    remaining -= readNow

proc skipChunkPayload(file: Stream; size: uint32) {.raises: [IOError, OSError, WavParseError].} =
  ## Skips a chunk's data, including the pad byte required for odd sizes.
  skipBytes(file, int64(size) + int64(size and 1))

proc readChunkHeader(file: Stream; chunk: var ChunkHeader): bool {.raises: [IOError, OSError, WavParseError].} =
  ## Reads the next RIFF chunk header into `chunk`.
  ## Returns false at a clean end of stream, raises on a truncated header.
  var bytesRead = 0
  while bytesRead < chunk.id.len:
    let readNow = file.readData(addr chunk.id[bytesRead], chunk.id.len - bytesRead)
    if readNow <= 0:
      break
    bytesRead += readNow
  if bytesRead == 0:
    return false
  if bytesRead < chunk.id.len:
    raise newWavError(weTruncatedHeader)
  chunk.size = readUint32(file)
  true

proc readWavHeaderRaw(file: Stream): WavHeaderRaw {.raises: [IOError, OSError, WavParseError].} =
  ## Reads a raw WAVE header from a stream.
  ##
  ## A `WavParseError` is raised when the header is malformed or the audio data
  ## is in an unknown/unsupported format.
  var chunkID: array[4, char]

  # Read RIFF header
  file.read(chunkID)
  if chunkID != CHUNKID:
    raise newWavError(weNoRiff)

  discard readUint32(file) # RIFF chunk size

  var format: array[4, char]
  file.read(format)
  if format != FORMAT:
    raise newWavError(weNoWave)

  # RIFF files may contain arbitrary chunks before the "fmt " chunk,
  # e.g. "bext", "JUNK" or "FLLR". Walk them until the format is found.
  const MaxReportedChunks = 8
  var
    seenChunks: array[MaxReportedChunks, array[4, char]]
    seenCount = 0
    totalSeen = 0
    chunk: ChunkHeader

  while readChunkHeader(file, chunk):
    if chunk.id == SUBCHUNK1ID:
      if chunk.size < 16:
        raise newWavError(weInvalidFmtSize, $chunk.size)

      result.waveFormatTag = readUint16(file)
      result.effectiveFormat = toWaveFormatTag(result.waveFormatTag)
      result.subFormatTag = 0

      result.numChannels = readUint16(file)
      result.sampleRate = readUint32(file)
      result.byteRate = readUint32(file)
      let blockAlign = readUint16(file)
      result.bitsPerSample = readUint16(file)

      if result.waveFormatTag == WAVE_FORMAT_EXTENSIBLE.uint16:
        if chunk.size < 18:
          raise newWavError(weInvalidFmtSize, $chunk.size)
        let cbSize = readUint16(file)
        if cbSize < 22 or int64(cbSize) > int64(chunk.size) - 18:
          raise newWavError(weInvalidFmt,
            "cbSize=" & $cbSize & ", fmt size=" & $chunk.size)

        discard readUint16(file) # wValidBitsPerSample
        discard readUint32(file) # dwChannelMask
        var subFormatGuid: array[16, char]
        file.read(subFormatGuid)
        result.subFormatTag =
          uint16(ord(subFormatGuid[0])) or
          (uint16(ord(subFormatGuid[1])) shl 8)

        let subFormat = toWaveFormatTag(result.subFormatTag)
        if isPcmLike(subFormat):
          result.effectiveFormat = subFormat
        elif cwpAllowUnknownFormats:
          result.effectiveFormat = WAVE_FORMAT_UNKNOWN
        else:
          raise newWavError(weUnsupportedFormat,
            "extensible subformat " & $result.subFormatTag)
        result.isFloat = result.effectiveFormat == WAVE_FORMAT_IEEE_FLOAT
        validateFmtFields(result, blockAlign, extensible = true)
        skipChunkPayload(file, chunk.size - 40)
      else:
        if not isKnownFormat(result.effectiveFormat):
          if cwpAllowUnknownFormats:
            result.effectiveFormat = WAVE_FORMAT_UNKNOWN
          else:
            raise newWavError(weUnsupportedFormat, $result.waveFormatTag)
        result.isFloat = result.effectiveFormat == WAVE_FORMAT_IEEE_FLOAT
        validateFmtFields(result, blockAlign, extensible = false)
        skipChunkPayload(file, chunk.size - 16)
      return result

    if seenCount < MaxReportedChunks:
      seenChunks[seenCount] = chunk.id
      inc seenCount
    inc totalSeen
    skipChunkPayload(file, chunk.size)

  var detail = ""
  if totalSeen > 0:
    for i in 0..<seenCount:
      if i > 0:
        detail.add(", ")
      detail.add('\'')
      for c in seenChunks[i]:
        detail.add(c)
      detail.add('\'')
    if totalSeen > seenCount:
      detail.add(", ...")
  raise newWavError(weNoFmt, detail)

func toWavHeader(rawHeader: WavHeaderRaw): WavHeader {.inline.} =
  WavHeader(
    waveFormat: rawHeader.effectiveFormat,
    waveFormatTag: rawHeader.waveFormatTag,
    subFormatTag: rawHeader.subFormatTag,
    numChannels: int(rawHeader.numChannels),
    sampleRate: int(rawHeader.sampleRate),
    byteRate: int(rawHeader.byteRate),
    bitsPerSample: int(rawHeader.bitsPerSample),
    isFloat: rawHeader.isFloat
  )

proc readWavHeader*(stream: Stream): WavHeader {.raises: [IOError, OSError, WavParseError].} =
  ## Reads and parses a WAVE header from a stream.
  ##
  ## A `WavParseError` is raised when the header is malformed or the audio data
  ## is in an unknown/unsupported format.
  readWavHeaderRaw(stream).toWavHeader()

proc readWavFileHeader*(path: string): WavHeader {.raises: [IOError, OSError, WavParseError].} =
  ## A helper wrapper around `readWavHeader`.
  ## Reads and parses a WAVE header from a WAV file.
  ##
  ## A `WavParseError` (a `ValueError`) is raised when the header is malformed
  ## or the audio data is in an unknown/unsupported format.
  let stream = openFileStream(path, fmRead)
  try:
    result = readWavHeader(stream)
  finally: stream.close()

when isMainModule:
  import std/[os, sequtils]
  let tests = walkfiles("tests/*.wav").toSeq()
  var ok = true
  for filePath in tests:
    echo filePath, ":"
    let res = try:
        let header = readWavFileHeader(filePath)
        echo header
        true
      except IOError as e:
        echo("Error opening file: " & e.msg); false
      except OSError as e:
        echo("Error: " & e.msg); false
      except ValueError as e:
        echo("Error parsing file: " & e.msg); false
    ok = ok and res
  quit(ord(not ok))
