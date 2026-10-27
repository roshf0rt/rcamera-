#!/usr/bin/env bash
# Запускает REA-анализ CamX через Ghidra. Без установленной Ghidra ничего не делает.
# Использование: GHIDRA_INSTALL_DIR=/abs/path/ghidra_12.1.4_PUBLIC ./run_rea_ghidra.sh <CamX binary> <out dir>
set -euo pipefail
BIN="${1:?путь к Mach-O бинарнику CamX}"
OUT="${2:?новый каталог для decompile-all}"
: "${GHIDRA_INSTALL_DIR:?задайте GHIDRA_INSTALL_DIR (Ghidra 12.1.x)}"
[ -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ] || { echo "нет $GHIDRA_INSTALL_DIR/support/analyzeHeadless"; exit 1; }
java -version 2>&1 | grep -q '"21' || { echo "нужен JDK 21"; exit 1; }
[ ! -e "$OUT" ] || { echo "каталог $OUT уже существует"; exit 1; }
export REA_GHIDRA_STARTUP_TIMEOUT_MS="${REA_GHIDRA_STARTUP_TIMEOUT_MS:-3000000}"
REA="${REA:-rea}"
"$REA" inspect-artifact "$BIN" --format json > "$OUT.inspect.json"
"$REA" analyze "$BIN" --provider ghidra --format json > "$OUT.analyze.json"
mkdir -p "$OUT"
"$REA" decompile-all "$BIN" --provider ghidra --output "$OUT" --format json > "$OUT.manifest.json"
echo "готово: $OUT"
