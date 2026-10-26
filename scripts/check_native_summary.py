"""Compile descriptive four-test summary regressions with workspace-only output on macOS.

Uses production declarations, not mock analysis. Does not install tools, run the
app, or write UserDefaults. Full `swift test` and an iOS build are still required.
"""
import json
import os
from pathlib import Path
import platform
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.tools' / 'native-review'
OUT.mkdir(parents=True, exist_ok=True)
DEVELOPER = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
compiler = DEVELOPER / 'usr/bin/swiftc'
if not compiler.exists():
    compiler = DEVELOPER / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk = DEVELOPER / 'SDKs/MacOSX.sdk'
if not sdk.exists():
    sdk = DEVELOPER / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
modules = OUT / 'modules'
modules.mkdir(exist_ok=True)
temporary = OUT / 'tmp'
temporary.mkdir(exist_ok=True)
env = dict(os.environ, TMPDIR=str(temporary), CLANG_MODULE_CACHE_PATH=str(modules))
policy = '(version 1)(allow default)(deny file-write*)(allow file-write* (subpath ' + json.dumps(str(ROOT)) + ') (literal "/dev/null") (literal "/dev/tty"))'
prefix = ['/usr/bin/sandbox-exec', '-p', policy]
flags = ['-module-cache-path', str(modules), '-sdk', str(sdk)]
# Some CLT installations contain two definitions of SwiftBridging. Hide only the
# legacy duplicate for this invocation through VFS; never edit the installed SDK.
legacy = DEVELOPER / 'usr/include/swift/module.modulemap'
modern = legacy.with_name('bridging.modulemap')
if legacy.exists() and modern.exists() and all('module SwiftBridging' in p.read_text() for p in (legacy, modern)):
    empty = OUT / 'empty.modulemap'
    empty.write_text('// Legacy duplicate hidden for this compiler invocation only.\n')
    overlay = OUT / 'sdk-overlay.json'
    overlay.write_text(json.dumps({'version': 0, 'case-sensitive': 'false', 'roots': [
        {'type': 'file', 'name': str(legacy), 'external-contents': str(empty)}]}))
    flags += ['-vfsoverlay', str(overlay)]
source = ROOT / 'NeuroPulse-iOS/Sources/NeuroPulse'
executable = OUT / 'summary-regression'
subprocess.run(prefix + [str(compiler), *flags, '-target', f'{platform.machine()}-apple-macosx14.0',
    str(source / 'Models/BiometricTypes.swift'), str(source / 'Models/Constants.swift'),
    str(source / 'Biometrics/GazeMath.swift'),
    str(ROOT / 'NeuroPulse-iOS/Tests/NativeSummaryRegression/main.swift'), '-o', str(executable)],
    cwd=ROOT, env=env, check=True)
subprocess.run(prefix + [str(executable)], cwd=ROOT, env=env, check=True)
