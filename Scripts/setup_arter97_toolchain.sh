#!/usr/bin/env bash
set -euo pipefail

kernel_dir="${1:-kernel}"
makefile="$kernel_dir/Makefile"
tool_dir=/usr/local/lib/np2-llvm/bin

if [[ ! -f "$makefile" ]]; then
  echo "arter97 kernel Makefile not found: $makefile" >&2
  exit 1
fi

# Resolve the actual binaries installed by Ubuntu. Prefer versioned LLVM tools
# so this works even when the runner does not provide unversioned aliases.
mkdir -p "$tool_dir"
for tool in clang clang++ llvm-ar llvm-nm llvm-objdump llvm-objcopy llvm-readelf llvm-strip ld.lld; do
  # Ubuntu packages expose versioned names such as llvm-ar-18 and clang-18.
  # compgen returns the full path, which is important for the generated links.
  src="$(compgen -G "/usr/bin/${tool}-[0-9]*" | sort -V | tail -n1 || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    src="/usr/bin/$tool"
  fi
  if [[ ! -x "$src" ]]; then
    echo "Required LLVM tool is missing: $tool (checked versioned and unversioned paths in /usr/bin)" >&2
    exit 1
  fi
  ln -sf "$src" "$tool_dir/$tool"
done

# arter97 hardcodes its own workstation's cross compilers and LLVM directory
# with GNU make's override directive. Replace only those assignments, keeping
# all other upstream kernel settings intact.
python3 - "$makefile" "$tool_dir/" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
llvm_path = sys.argv[2]
s = p.read_text()
replacements = {
    r'^override CROSS_COMPILE\s*:=.*$': 'override CROSS_COMPILE := aarch64-linux-gnu-',
    r'^override CROSS_COMPILE_ARM32\s*:=.*$': 'override CROSS_COMPILE_ARM32 := arm-linux-gnueabi-',
    r'^override LLVM_PATH\s*:=.*$': f'override LLVM_PATH := {llvm_path}',
}
for pattern, replacement in replacements.items():
    s, count = re.subn(pattern, replacement, s, count=1, flags=re.M)
    if count != 1:
        raise SystemExit(f'Expected exactly one Makefile assignment matching {pattern!r}; found {count}')
p.write_text(s)
PY

printf 'Prepared arter97 toolchain aliases in %s\n' "$tool_dir"
grep -E '^override (CROSS_COMPILE|CROSS_COMPILE_ARM32|LLVM_PATH)' "$makefile"
