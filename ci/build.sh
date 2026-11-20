#!/usr/bin/env bash
# Compilation de l'application AÏCHA SERVICES (appelé par GitHub Actions).
# Ce script fait partie du code : pour changer la compilation, il suffit
# d'envoyer un nouveau zip (plus besoin de toucher au dossier .github).
#
# Variables reçues : RUN_NUMBER, ANDROID_KEYSTORE, GH_TOKEN,
# FIREBASE_* (facultatives : l'application a des valeurs par défaut).
set -euo pipefail

echo "== 1. Fichiers Android"
if [ ! -d android ]; then
  flutter create --platforms=android --org ml.aichaservices --project-name aicha_services .
  rm -f test/widget_test.dart
fi
# Anciens fichiers inutiles (ne sont pas compilés, mais on nettoie)
rm -f lib/services/storage_service.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi
sed -i 's/android:label="aicha_services"/android:label="Aicha Services"/' "$MANIFEST"
for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ]; then
    sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$f"
  fi
done

echo "== 2. Signature fixe (mises à jour sans désinstaller)"
if [ -z "${ANDROID_KEYSTORE:-}" ]; then
  echo "::error::Le secret ANDROID_KEYSTORE est manquant."
  exit 1
fi
printf '%s' "$ANDROID_KEYSTORE" | tr -d ' \r\n' | base64 -d > android/app/aicha.keystore
keytool -list -keystore android/app/aicha.keystore -storepass android | grep -i "SHA" \
  || { echo "::error::Le secret ANDROID_KEYSTORE est abîmé."; exit 1; }
if [ -f android/app/build.gradle ]; then
  cat >> android/app/build.gradle <<'GRADLE'

android {
    signingConfigs {
        aicha {
            storeFile file('aicha.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }
    buildTypes {
        release { signingConfig signingConfigs.aicha }
    }
}
GRADLE
else
  cat >> android/app/build.gradle.kts <<'GRADLE'

android {
    signingConfigs {
        create("aicha") {
            storeFile = file("aicha.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    buildTypes {
        getByName("release") { signingConfig = signingConfigs.getByName("aicha") }
    }
}
GRADLE
fi

echo "== 3. Numéro interne de version"
# Toujours plus grand que la dernière version publiée (sinon Android refuse
# la mise à jour), même si le fichier de compilation change de nom.
LAST=$(gh release view --json tagName -q .tagName 2>/dev/null | tr -dc '0-9' || true)
LAST=${LAST:-0}
BUILD=$(( RUN_NUMBER + 100 ))
if [ "$BUILD" -le "$LAST" ]; then BUILD=$(( LAST + 1 )); fi
echo "Numéro interne : $BUILD (dernière publiée : $LAST)"

echo "== 4. Dépendances et icône"
flutter pub get
dart run flutter_launcher_icons

echo "== 5. Vérification du code (informatif)"
flutter analyze --no-fatal-infos --no-fatal-warnings lib \
  || echo "::warning::L'analyse du code signale des problèmes (voir ci-dessus)."

echo "== 6. Compilation (un APK léger par type de téléphone)"
DEFINES=(--dart-define=BUILD_NUMBER=$BUILD)
for v in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_SENDER_ID FIREBASE_PROJECT_ID FIREBASE_STORAGE_BUCKET; do
  if [ -n "${!v:-}" ]; then DEFINES+=("--dart-define=$v=${!v}"); fi
done
build() {
  flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
    --build-number=$BUILD "${DEFINES[@]}"
}
build || { echo "Nouvel essai dans 30 s…"; sleep 30; build; }
OUT=build/app/outputs/flutter-apk
cp "$OUT/app-arm64-v8a-release.apk" aicha-services-arm64.apk
cp "$OUT/app-armeabi-v7a-release.apk" aicha-services-arm32.apk

echo "== 6b. APK universel (s'installe sur TOUS les téléphones, pour le partage)"
universal() {
  flutter build apk --release --target-platform android-arm,android-arm64 \
    --build-number=$BUILD "${DEFINES[@]}"
}
universal || { echo "Nouvel essai dans 30 s…"; sleep 30; universal; }
cp "$OUT/app-release.apk" aicha-services.apk

echo "== 7. Publication pour les clients"
# aicha-services.apk = universel (lien à partager) ;
# -arm64 / -arm32 = versions légères utilisées par la mise à jour intégrée.
ls -la aicha-services*.apk
if [ -f NOUVEAUTES.txt ]; then cp NOUVEAUTES.txt notes.txt; else echo "Mise à jour de l'application Aïcha Services" > notes.txt; fi
gh release create "v$BUILD" aicha-services.apk aicha-services-arm64.apk aicha-services-arm32.apk \
  --title "Mise à jour $BUILD" --notes-file notes.txt --latest
echo "Publié : v$BUILD"
