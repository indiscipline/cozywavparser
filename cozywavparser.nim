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
    chunkID: array[4, char]
    chunkSize: uint32
    format: array[4, char]
    subchunk1ID: array[4, char]
    subchunk1Size: uint32
    waveFormat: uint16
    numChannels: uint16
    sampleRate: uint32
    byteRate: uint32
    blockAlign: uint16
    bitsPerSample: uint16

  WaveFormatTag* = enum ## Represents a non-exhaustive list of WAVE data formats.
    WAVE_FORMAT_PCM = (0x1, "PCM"),
    WAVE_FORMAT_IEEE_FLOAT = (0x3, "IEEE float"),
    WAVE_FORMAT_ALAW = (0x6, "8-bit ITU-T G.711 A-law"),
    WAVE_FORMAT_MULAW = (0x7,  "8-bit ITU-T G.711 µ-law"),
    WAVE_FORMAT_EXTENSIBLE = (0xFFFE, "Extensible Wave Format"),

  WavHeader* = object ## A parsed and superficially validated WAVE header.
    #chunkID: string
    #chunkSize: int
    #format: string
    #subchunk1ID: string
    #subchunk1Size: int
    waveFormat*: WaveFormatTag
    numChannels*: int
    sampleRate*: int
    byteRate*: int
    #blockAlign: int
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

proc readWavHeaderRaw(file: Stream): WavHeaderRaw {.raises: [IOError, OSError, WavParseError].} =
  ## Reads a raw WAVE header from a stream.
  ##
  ## A `WavParseError` is raised when the header is malformed or the audio data
  ## is in an unknown/unsupported format.
  var header: WavHeaderRaw

  # Read RIFF header
  file.read(header.chunkID)
  if header.chunkID != CHUNKID:
    raise newException(WavParseError, "No RIFF header found")

  header.chunkSize = readUint32(file)

  file.read(header.format)
  if header.format != FORMAT:
    raise newException(WavParseError, "No WAVE format marker found")

  # Read "fmt " subchunk
  file.read(header.subchunk1ID)

  if header.subchunk1ID != SUBCHUNK1ID:
    raise newException(WavParseError, "No fmt subchunk found")

  header.subchunk1Size = readUint32(file)
  header.waveFormat = readUint16(file)

  if header.waveFormat notin SupportedWaveFormatTags:
    raise newException(WavParseError, "Unknown/unsupported wave format: " & $header.waveFormat)

  header.numChannels = readUint16(file)
  header.sampleRate = readUint32(file)
  header.byteRate = readUint32(file)
  header.blockAlign = readUint16(file)
  header.bitsPerSample = readUint16(file)

  header

{.push warning[HoleEnumConv]:off.}
proc toWaveFormatEnumUnsafe(n: uint16): WaveFormatTag {.inline.} = WaveFormatTag(n)
{.pop.}

func toWavHeader(rawHeader: WavHeaderRaw): WavHeader {.inline.} =
  WavHeader(
    #chunkID: $rawHeader.chunkID,
    #chunkSize: int(rawHeader.chunkSize),
    #format: $rawHeader.format,
    #subchunk1ID: $rawHeader.subchunk1ID,
    #subchunk1Size: int(rawHeader.subchunk1Size),
    waveFormat: toWaveFormatEnumUnsafe(rawHeader.waveFormat),
    numChannels: int(rawHeader.numChannels),
    sampleRate: int(rawHeader.sampleRate),
    byteRate: int(rawHeader.byteRate),
    #blockAlign: int(rawHeader.blockAlign),
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
