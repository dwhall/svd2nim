import std/strutils
import std/strscans


proc getNimbleVersion(): string {.compileTime.} =
  let dump = staticExec "nimble dump .."
  for ln in dump.splitLines:
    if scanf(ln, "version: \"$*\"", result): return


proc getVersion*(): string {.compileTime.} =
  let
    baseVersion = getNimbleVersion()
    gitTags: seq[string] = staticExec("git tag -l --points-at HEAD").split()
    prerelease = gitTags.find(baseVersion) < 0

  result =
    if prerelease:
      let shortHash = staticExec "git rev-parse --short HEAD"
      baseVersion & "-dev-" & shortHash
    else:
      baseVersion


