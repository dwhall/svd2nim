#[ Generate C code that prints out addresses of all registers

This is used to generate data used for integration testing, by checking
that the addresses of all registers procuced by svd2nim match the addresses
of the C header produced by ARM's SVDConv tool.

Run this file from the "scripts" directory, where it is located, as wowrking
directory. Data will be created in file "addrs.txt".
]#

import std/os
import std/strformat
import std/options
import std/strutils
import std/osproc
import svd2nim
import basetypes

const
  Indent = "  "

  CFileName = "addrs.c"

  OutputFile = "addrs.txt"

  # Edit this to reflect path of CMSIS_5 repository clone
  # See: https://github.com/ARM-software/CMSIS_5
  CMSIS_5_Repo_Path = joinPath(getHomeDir(), "source/CMSIS_5")

iterator allRegistersFq(periph: SvdPeripheral): tuple[fqname: string, reg: SvdRegister] =
  ## Yield pairs of (fully-qualified name, Register)
  ## FQ name is, eg, Peripheral.Cluster.Register

  for reg in periph.registers:
    yield (periph.name & "." & reg.name, reg)

  var cStack: seq[(string, SvdCluster)]
  for cls in periph.clusters:
    cStack.add (periph.name, cls)

  while cStack.len > 0:
    let (scope, cls) = cStack.pop
    for reg in cls.registers:
      yield ([scope, cls.name, reg.name].join("."), reg)
    for child in cls.clusters:
      cStack.add ([scope, cls.name].join("."), child)

func getCRegExpr(p: SvdPeripheral, fqname: string): string =
  let parts = fqname.split(".")
  doAssert parts.len >= 2

  var regCName = p.prependToName.get("") & parts[^1] & p.appendToName.get("")
  if regCName == "MTB_BASE":
    regCName = "MTB_Base"

  result = parts[0] & "->"
  if parts.len > 2:
    for i in 1..<parts.high:
      result = result & parts[i] & "."
  result = result & regCName

proc writeCFile(svdFile: string) =
  let outf = open(CFileName, fmWrite)
  outf.writeLine "#include <stdint.h>"
  outf.writeLine "#include <stdio.h>"
  outf.writeLine "#include \"ATSAMD21G18A.h\""
  outf.writeLine ""
  outf.writeLine "int main(void) {"

  let dev = processSvd(svdFile)

  for periph in dev.peripherals:
    for (fqname, reg) in allRegistersFq(periph):
      let cExpr = getCRegExpr(periph, fqname)
      outf.writeLine(fmt"""{Indent}printf("{fqname}:%#x\n", (intptr_t)&({cExpr}));""")

  outf.writeLine "}"
  outf.writeLine ""
  outf.close()

proc execCmdOrQuit(cmd: string) =
  echo cmd
  let ec = execCmd(cmd)
  if ec != 0:
    echo fmt"Command returned exit code {ec}, quitting."
    quit(ec)

proc main() =
  let svdFile = paramStr(1)

  # Generate C source
  writeCFile(svdFile)

  # Run SVDConv to produce the C header.
  # Don't check the exit code, SVDConv returns code 1 on warnings
  let svdconv = joinPath(CMSIS_5_Repo_Path, "CMSIS/Utilities/Linux64/SVDConv")
  discard execCmd([svdconv, svdFile, "--generate=header", "-x INFO"].join(" "))

  let headerFile = splitFile(svdFile).name & ".h"
  doAssert headerFile.fileExists

  # SVDConv creates a struct field with a macro conflict, see comment below about MTB_BASE
  # Rename the field to MTB_Base in header
  execCmdOrQuit &"sed -i -Ee 's/(__IM  uint32_t  )MTB_BASE;/\\1MTB_Base;/' {headerFile}"

  # SVDConv tries to include file system_ATSAMD21G18.h, this file doesn't exist,
  # as the header supplied by Atmel is named system_samd21.h. Doesn't matter,
  # we don't need it anyways, so comment out the include.
  execCmdOrQuit &"sed -i -Ee 's:^(#include \"system_ATSAMD21G18A.h\")://\\1:' {headerFile}"

  # Compile generated C file with gcc. Need to include CMSIS path for the
  # core_cm0plus.h file.
  let
    cmsisIncludePath = joinPath(CMSIS_5_Repo_Path, "CMSIS/Core/Include")
    cFileExec = CFileName.splitFile.name
  execCmdOrQuit &"gcc -I{cmsisIncludePath} -o {cFileExec} {CFileName}"

  # Run compiled file to generate the address data
  let addrsData = execProcess "./" & cFileExec
  let outf = open(cFileExec & ".txt", fmWrite)
  outf.writeLine("# File generated by generate_c_addrs.nim.")
  outf.writeLine(
    &"# Register addresses according to SVDConv output for SVD file '{svdFile.extractFileName}'"
  )
  outf.writeLine("")
  outf.write addrsData
  outf.close()

when isMainModule:
  main()
