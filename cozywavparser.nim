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
## .. warning:: This code is not thoroughly tested and might not work correctly
##    for all valid WAV files

import std/streams
from std/enumutils import items

type
  WavHeaderRaw = object
    waveFormat: uint16
    numChannels: uint16
    sampleRate: uint32
    byteRate: uint32
    bitsPerSample: uint16

  ChunkHeader = object
    id: array[4, char]
    size: uint32

  WaveFormatTag* = enum ## Represents a non-exhaustive list of WAVE data formats.
    WAVE_FORMAT_PCM = (0x1, "PCM"),
    WAVE_FORMAT_IEEE_FLOAT = (0x3, "IEEE float"),
    WAVE_FORMAT_ALAW = (0x6, "8-bit ITU-T G.711 A-law"),
    WAVE_FORMAT_MULAW = (0x7,  "8-bit ITU-T G.711 µ-law"),
    WAVE_FORMAT_EXTENSIBLE = (0xFFFE, "Extensible Wave Format"),

  WavHeader* = object ## A parsed and superficially validated WAVE header.
    waveFormat*: WaveFormatTag
    numChannels*: int
    sampleRate*: int
    byteRate*: int
    bitsPerSample*: int
    isFloat*: bool

  WavParseError* = object of CatchableError ##|
    ## Raised when a WAVE header is malformed or unsupported.

{.push warning[HoleEnumConv]:off.}
const
  CHUNKID = ['R', 'I', 'F', 'F']
  FORMAT =  ['W', 'A', 'V', 'E']
  SUBCHUNK1ID = ['f', 'm', 't', ' ']
  SupportedWaveFormatTags = block:
    var wfSet: set[uint16]
    for wf in items(WaveFormatTag): wfSet.incl wf.uint16
    wfSet
{.pop.}

proc skipBytes(file: Stream; count: int64) {.raises: [IOError, OSError, WavParseError].} =
  ## Consumes `count` bytes from the stream without allocating `count` bytes.
  var
    remaining = count
    buffer: array[4096, char]
  while remaining > 0:
    let toRead = int(min(remaining, int64(buffer.len)))
    let readNow = file.readData(addr buffer[0], toRead)
    if readNow <= 0:
      raise newException(WavParseError, "Unexpected end of file inside a RIFF chunk")
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
    raise newException(WavParseError, "Truncated RIFF chunk header")
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
    raise newException(WavParseError, "No RIFF header found")

  discard readUint32(file) # RIFF chunk size

  var format: array[4, char]
  file.read(format)
  if format != FORMAT:
    raise newException(WavParseError, "No WAVE format marker found")

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
        raise newException(WavParseError, "Invalid fmt subchunk size: " & $chunk.size)

      result.waveFormat = readUint16(file)
      if result.waveFormat notin SupportedWaveFormatTags:
        raise newException(WavParseError, "Unknown/unsupported wave format: " & $result.waveFormat)

      result.numChannels = readUint16(file)
      result.sampleRate = readUint32(file)
      result.byteRate = readUint32(file)
      discard readUint16(file) # block align
      result.bitsPerSample = readUint16(file)
      skipChunkPayload(file, chunk.size - 16) # Extra fmt fields and padding
      return result

    if seenCount < MaxReportedChunks:
      seenChunks[seenCount] = chunk.id
      inc seenCount
    inc totalSeen
    skipChunkPayload(file, chunk.size)

  var msg = "No fmt subchunk found"
  if totalSeen > 0:
    msg.add(" (found: ")
    for i in 0..<seenCount:
      if i > 0:
        msg.add(", ")
      msg.add('\'')
      for c in seenChunks[i]:
        msg.add(c)
      msg.add('\'')
    if totalSeen > seenCount:
      msg.add(", ...")
    msg.add(')')
  raise newException(WavParseError, msg)

{.push warning[HoleEnumConv]:off.}
proc toWaveFormatEnumUnsafe(n: uint16): WaveFormatTag {.inline.} = WaveFormatTag(n)
{.pop.}

func toWavHeader(rawHeader: WavHeaderRaw): WavHeader {.inline.} =
  WavHeader(
    waveFormat: toWaveFormatEnumUnsafe(rawHeader.waveFormat),
    numChannels: int(rawHeader.numChannels),
    sampleRate: int(rawHeader.sampleRate),
    byteRate: int(rawHeader.byteRate),
    bitsPerSample: int(rawHeader.bitsPerSample),
    isFloat: (rawHeader.waveFormat == WAVE_FORMAT_IEEE_FLOAT.uint16)
  )

proc readWavHeader*(stream: Stream): WavHeader {.raises: [IOError, OSError, WavParseError].} =
  ## Reads and parses a WAVE header from a stream.
  ##
  ## A `WavParseError` is raised when the header is malformed or the audio data
  ## is in an unknown/unsupported format.
  readWavHeaderRaw(stream).toWavHeader()

proc readWavFileHeader*(path: string): WavHeader {.raises: [IOError, OSError, ValueError].} =
  ## A helper wrapper around `readWavHeader`.
  ## Reads and parses a WAVE header from a WAV file.
  ##
  ## A `ValueError` is raised when the header is malformed or the audio data
  ## is in an unknown/unsupported format.
  let stream = openFileStream(path, fmRead)
  try:
    result = readWavHeader(stream)
  except WavParseError as e: raise newException(ValueError, e.msg)
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
