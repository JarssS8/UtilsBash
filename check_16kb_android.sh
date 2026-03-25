#!/usr/bin/env bash

set -e

INPUT_FILE="$1"
DEFAULT_APK="/Users/jars/Programming/Bidetrack/bidetrack/android/app/build/outputs/apk/develop/debug/app-develop-debug.apk"

if [[ -z "$INPUT_FILE" ]]; then
  echo "Uso: $0 <app.apk | app.aab>"
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Archivo no encontrado: $INPUT_FILE"
  echo "Usando APK por defecto: $DEFAULT_APK"
  INPUT_FILE="$DEFAULT_APK"
fi

WORK_DIR=$(mktemp -d)
echo "📂 Usando directorio temporal: $WORK_DIR"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "📦 Extrayendo APK..."

if [[ "$INPUT_FILE" == *.apk ]]; then
  unzip -qq "$INPUT_FILE" -d "$WORK_DIR/apk"
  APK_PATH="$WORK_DIR/apk"
elif [[ "$INPUT_FILE" == *.aab ]]; then
  unzip -qq "$INPUT_FILE" -d "$WORK_DIR/aab"
  # Extraer módulos base del AAB
  find "$WORK_DIR/aab" -name "base.apk" | head -1 | xargs -I {} unzip -qq {} -d "$WORK_DIR/apk"
  APK_PATH="$WORK_DIR/apk"
else
  echo "❌ Formato no soportado. Usa APK o AAB."
  exit 1
fi

echo ""
echo "🔍 Verificando alineación de segmentos ELF de librerías..."

FAIL_ELF=0
TOTAL_LIBS=0
LIB_DIR="$APK_PATH/lib"

# Verificar librerías nativas
if [[ ! -d "$LIB_DIR" ]]; then
  echo "ℹ️  No hay librerías nativas en el APK"
else
  while IFS= read -r -d '' sofile; do
    ((TOTAL_LIBS++))
    ARCH_DIR=$(dirname "$sofile")
    ARCH_NAME=$(basename "$ARCH_DIR")
    LIB_NAME=$(basename "$sofile")
    
    echo "➡️  [$ARCH_NAME] $LIB_NAME"
    
    # Verificar alineación de segmentos LOAD
    # Todos deben tener align 2**14 (2^14 = 16384 = 0x4000)
    HAS_ALIGN_14=true
    HAS_BAD_ALIGN=false
    
    while IFS= read -r line; do
      if [[ $line =~ align\ 2\*\*([0-9]+) ]]; then
        ALIGN_POWER="${BASH_REMATCH[1]}"
        if (( ALIGN_POWER < 14 )); then
          HAS_BAD_ALIGN=true
        fi
      fi
    done < <(readelf -l "$sofile" 2>/dev/null | grep "LOAD")
    
    if [[ "$HAS_BAD_ALIGN" == "true" ]]; then
      echo "   ❌ NO compatible - Algunos segmentos LOAD no tienen align 2**14"
      FAIL_ELF=1
    else
      echo "   ✅ Alineación ELF compatible (2**14)"
    fi
  done < <(find "$LIB_DIR" -name "*.so" -print0)
fi

echo ""
echo "🔍 Verificando alineación ZIP del APK (zipalign -c -P 16 -v 4)..."

# Buscar zipalign en PATH o en Android SDK
ZIPALIGN_CMD=""

# 1. Intentar en PATH
if command -v zipalign &> /dev/null; then
  ZIPALIGN_CMD="zipalign"
fi

# 2. Buscar en ANDROID_HOME/build-tools
if [[ -z "$ZIPALIGN_CMD" && -n "$ANDROID_HOME" ]]; then
  # Buscar en la versión más reciente
  ZIPALIGN_PATH=$(find "$ANDROID_HOME/build-tools" -name "zipalign" -type f 2>/dev/null | sort -V | tail -1)
  if [[ -n "$ZIPALIGN_PATH" && -x "$ZIPALIGN_PATH" ]]; then
    ZIPALIGN_CMD="$ZIPALIGN_PATH"
  fi
fi

# 3. Rutas comunes en macOS
if [[ -z "$ZIPALIGN_CMD" ]]; then
  for sdk_path in ~/Library/Android/sdk ~/android-sdk $HOME/Android/sdk; do
    ZIPALIGN_PATH=$(find "$sdk_path/build-tools" -name "zipalign" -type f 2>/dev/null | sort -V | tail -1)
    if [[ -n "$ZIPALIGN_PATH" && -x "$ZIPALIGN_PATH" ]]; then
      ZIPALIGN_CMD="$ZIPALIGN_PATH"
      break
    fi
  done
fi

if [[ -n "$ZIPALIGN_CMD" ]]; then
  if "$ZIPALIGN_CMD" -c -P 16 -v 4 "$INPUT_FILE" > /dev/null 2>&1; then
    echo "✅ APK está correctamente alineado en ZIP a 16KB"
    FAIL_ZIP=0
  else
    echo "❌ APK NO está correctamente alineado en ZIP a 16KB"
    FAIL_ZIP=1
  fi
else
  echo "⚠️  zipalign no encontrado. Búscalo manualmente en:"
  echo "   • En PATH: zipalign"
  echo "   • Android SDK: \$ANDROID_HOME/build-tools/XX.X.X/zipalign"
  echo "   • macOS típica: ~/Library/Android/sdk/build-tools/XX.X.X/zipalign"
  echo ""
  echo "   O instala el SDK de Android si no lo tienes."
  FAIL_ZIP=2
fi

echo ""
echo "📊 RESULTADO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total librerías (.so) analizadas: $TOTAL_LIBS"

if [[ $TOTAL_LIBS -eq 0 ]]; then
  echo "✅ No hay código nativo - App es compatible con 16KB"
  EXIT_CODE=0
elif [[ $FAIL_ELF -eq 0 ]]; then
  echo "✅ Alineación ELF: COMPATIBLE (16KB)"
  EXIT_CODE=0
else
  echo "❌ Alineación ELF: NO COMPATIBLE"
  EXIT_CODE=2
fi

if [[ $FAIL_ZIP -eq 0 ]]; then
  echo "✅ Alineación ZIP: COMPATIBLE (16KB)"
elif [[ $FAIL_ZIP -eq 1 ]]; then
  echo "❌ Alineación ZIP: NO COMPATIBLE"
  EXIT_CODE=2
else
  echo "⚠️  Alineación ZIP: NO VERIFICADA (falta zipalign)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL_ELF -eq 0 && ($FAIL_ZIP -eq 0 || $FAIL_ZIP -eq 2) ]]; then
  echo "🎉 APK es compatible con alineación de 16KB para Android"
  exit 0
else
  echo "🚨 APK tiene problemas de alineación de 16KB"
  exit 2
fi