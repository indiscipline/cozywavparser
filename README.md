# Cozy Wav Parser

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

Cozy Wav Parser is a basic module for parsing WAV file header metadata for the Nim programming language.
It provides a simple way to extract common information about the audio stream, such as sample rate, bit depth, and the number of channels.
While the actual PCM format specification is complex, this module focuses on supporting the most common formats, which easily covers 99% of use-cases.

## Features

- Supports parsing headers for the most common WAVE files
- Extracts essential audio stream information: sample rate, bit depth, number of channels, byte rate, and float/integer sample format

> [!WARNING]
> This code is not thoroughly tested and might not work correctly for all valid WAV files. PRs welcome.

## Installation

Cozy Wav Parser is not yet in the nimble directory. You can `git clone` or download the module directly.

Upon acceptance in the nimble directory, you can install it using `atlas` or `nimble`:

```
atlas use cozywavparser
```

```
nimble install cozywavparser
```

## Usage

```nim
import pkg/cozywavparser

# Parse WAV header from a file
let wavHeader = readWavFileHeader("audio.wav")

# Print audio stream information
echo "Wave Format: ", wavHeader.waveFormat
echo "Channels: ", wavHeader.numChannels
echo "Sample Rate: ", wavHeader.sampleRate, "Hz"
echo "Bits per Sample: ", wavHeader.bitsPerSample
echo "Float Samples: ", wavHeader.isFloat

# Parse WAV header from a stream
import std/streams
let stream = newFileStream("audio.wav", fmRead)
if not isNil(stream):
  let wavHeaderFromStream = readWavHeader(stream)
  echo wavHeaderFromStream
stream.close()
```

## Documentation

Documentation is included. You can generate it locally with `nim doc cozywavparser.nim`.

## License

Cozy Log Writer is licensed under GNU General Public License version 2.0 or later. See the LICENSE file for details.