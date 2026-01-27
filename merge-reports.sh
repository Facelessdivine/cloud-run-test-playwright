#!/usr/bin/env bash
set -euo pipefail

# 1. Verificación de Inicio
echo "===================================================="
echo "🚀 INICIANDO MERGE - VERSION: 2026-v2-FIXED"
echo "===================================================="

RUN_ID=${RUN_ID:?ERROR: RUN_ID no está configurado}
BUCKET=${BUCKET:?ERROR: BUCKET no está configurado}

WORK="/merge"
mkdir -p "$WORK/all-blob"
cd "$WORK"

echo "📂 Directorio de trabajo: $PWD"
echo "🆔 RUN_ID: $RUN_ID"
echo "🪣 BUCKET: $BUCKET"

# 2. Sincronización de Blobs
echo "----------------------------------------------------"
echo "🔄 Sincronizando blobs desde GCS..."
gcloud storage rsync --recursive "${BUCKET}/runs/${RUN_ID}/blob" "$WORK/blob"

echo "🔍 Contenido descargado en $WORK/blob:"
ls -R "$WORK/blob"

# 3. Recolección de Archivos ZIP (Lógica Mejorada)
echo "----------------------------------------------------"
echo "📦 Recolectando archivos .zip para el merge..."
# Buscamos todos los archivos .zip y los movemos a la raíz de all-blob
# Playwright merge-reports prefiere que los .zip estén en una carpeta plana o subcarpetas directas
find "$WORK/blob" -type f -name "*.zip" -exec cp {} "$WORK/all-blob/" \;

echo "📊 Archivos encontrados para merge en $WORK/all-blob:"
ls -lh "$WORK/all-blob"

# Verificación de seguridad: si no hay archivos, el merge fallará
if [ -z "$(ls -A "$WORK/all-blob" 2>/dev/null)" ]; then
  echo "❌ ERROR CRÍTICO: No se encontraron archivos .zip en all-blob."
  exit 1
fi

# 4. Generación de Reportes
echo "----------------------------------------------------"
echo "🧪 Ejecutando Playwright merge-reports..."

# Generar HTML (Crea la carpeta playwright-report)
echo "🖥️ Generando reporte HTML..."
npx playwright merge-reports --reporter html "$WORK/all-blob"

# Generar JUnit (Redirigiendo salida al archivo results.xml)
echo "📄 Generando reporte JUnit XML..."
npx playwright merge-reports --reporter junit "$WORK/all-blob" > "$WORK/results.xml" || {
  echo "⚠️ El comando merge de JUnit falló o no devolvió nada. Creando archivo vacío de seguridad."
  echo '<?xml version="1.0" encoding="UTF-8"?><testsuites></testsuites>' > "$WORK/results.xml"
}

# 5. Verificación de archivos antes de subir
echo "----------------------------------------------------"
echo "📋 Verificando archivos generados localmente:"
ls -lh "$WORK"
[ -d "$WORK/playwright-report" ] && echo "✅ Carpeta HTML existe." || echo "❌ Carpeta HTML NO existe."
[ -f "$WORK/results.xml" ] && echo "✅ Archivo results.xml existe." || echo "❌ Archivo results.xml NO existe."

# 6. Subida a Cloud Storage
echo "----------------------------------------------------"
echo "📤 Subiendo resultados finales a GCS..."

echo "📤 Subiendo HTML..."
gcloud storage rsync --recursive "$WORK/playwright-report" "${BUCKET}/runs/${RUN_ID}/final/html"

echo "📤 Subiendo JUnit XML..."
# Usamos -n para no fallar si por algún motivo extraño el archivo no estuviera
gcloud storage cp "$WORK/results.xml" "${BUCKET}/runs/${RUN_ID}/final/junit.xml"

echo "===================================================="
echo "✅ PROCESO COMPLETADO EXITOSAMENTE"
echo "🔗 HTML: ${BUCKET}/runs/${RUN_ID}/final/html/index.html"
echo "🔗 JUnit: ${BUCKET}/runs/${RUN_ID}/final/junit.xml"
echo "===================================================="
