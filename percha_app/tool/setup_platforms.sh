#!/usr/bin/env bash
# Genera los proyectos nativos (Android/iOS) y agrega los permisos que la app necesita.
# Ejecutar UNA vez en la raíz del proyecto, con Flutter instalado:  bash tool/setup_platforms.sh
set -euo pipefail

flutter create --platforms=android,ios --org pe.percha --project-name percha_app .

# iOS: textos que el sistema muestra al pedir permiso (sin ellos la app se cierra al abrir la cámara).
PLIST=ios/Runner/Info.plist
set_plist() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"
}
if [[ "$(uname)" == "Darwin" ]]; then
  set_plist NSCameraUsageDescription "Para escanear códigos de barras de las prendas y el QR de los vales, y para tomar fotos de productos."
  set_plist NSPhotoLibraryUsageDescription "Para elegir fotos de tus productos."
  echo "iOS: permisos de cámara y fotos agregados a $PLIST"
else
  echo "Aviso: en macOS se agregan solos los permisos de iOS. En otro sistema, agrega a $PLIST:"
  echo "  NSCameraUsageDescription y NSPhotoLibraryUsageDescription (ver docs/23-lector-de-codigos.md)"
fi

# Android: mobile_scanner declara el permiso de cámara en su propio manifiesto (se combina solo).
echo "Listo. Ahora: flutter pub get && flutter run"
