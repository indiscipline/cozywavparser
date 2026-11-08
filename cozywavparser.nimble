# Package

packageName   = "cozywavparser"
version       = "0.1.0"
author        = "Kirill I"
description   = "Basic WAV file header parser"
license       = "GPL-2.0-or-later"
srcDir        = "."

skipDirs      = @["assets", "htmldocs", "specs"]

# Dependencies

requires "nim >= 2.0.0"

import std/[algorithm, os]

task test, "Run all t-prefixed tests with and without cwpAllowUnknownFormats":
  var tests: seq[string]
  for kind, path in walkDir("tests"):
    if kind in {pcFile, pcLinkToFile}:
      let (_, name, ext) = path.splitFile()
      if ext == ".nim" and name.len > 0 and name[0] == 't':
        tests.add path

  if tests.len == 0:
    quit("No t-prefixed tests found in tests/", 1)

  tests.sort()
  for test in tests:
    echo "Testing ", test
    exec "nim r --path:. " & test
    echo "Testing ", test, " with -d:cwpAllowUnknownFormats"
    exec "nim r --path:. -d:cwpAllowUnknownFormats " & test
