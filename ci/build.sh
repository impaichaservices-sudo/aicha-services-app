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

# Types de processeur inclus (variable AICHA_ABIS) : on retire les
# fichiers des émulateurs (x86), inutiles sur les téléphones.
if [ -f android/app/build.gradle ]; then
  cat >> android/app/build.gradle <<'GRADLE'

android {
    defaultConfig {
        def abis = System.getenv('AICHA_ABIS')
        if (abis) { ndk { abiFilters.addAll(abis.split(',') as List) } }
    }
}
GRADLE
else
  cat >> android/app/build.gradle.kts <<'GRADLE'

android {
    defaultConfig {
        System.getenv("AICHA_ABIS")?.let { a -> ndk { abiFilters.addAll(a.split(",")) } }
    }
}
GRADLE
fi

echo "== 3. Numéro interne de version"
# Toujours plus grand que tout ce qui a déjà été installé (sinon Android
# refuse la mise à jour). Base 2200 : les versions du 20/11 matin avaient
# un numéro interne de 2125/2126.
LAST=$(gh release view --json tagName -q .tagName 2>/dev/null | tr -dc '0-9' || true)
LAST=${LAST:-0}
BUILD=$(( RUN_NUMBER + 2200 ))
if [ "$BUILD" -le "$LAST" ]; then BUILD=$(( LAST + 1 )); fi
echo "Numéro interne : $BUILD (dernière publiée : $LAST)"

echo "== 4. Dépendances et icône"
flutter pub get
dart run flutter_launcher_icons

echo "== 5. Vérification du code (informatif)"
# Les vraies erreurs apparaissent dans le résumé (« Annotations »).
flutter analyze --no-fatal-infos --no-fatal-warnings lib 2>&1 | tee analyze.log || true
grep -E "^\s*error " analyze.log | head -20 | while IFS= read -r l; do
  echo "::error::ANALYSE $l"
done || true

echo "== 6. Compilation"
# Pas de --split-per-abi : il ajoute 1000/2000 au numéro interne et rendait
# les versions incompatibles entre elles. Ici, toutes ont le MÊME numéro.
DEFINES=(--dart-define=BUILD_NUMBER=$BUILD)
for v in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_SENDER_ID FIREBASE_PROJECT_ID FIREBASE_STORAGE_BUCKET; do
  if [ -n "${!v:-}" ]; then DEFINES+=("--dart-define=$v=${!v}"); fi
done
OUT=build/app/outputs/flutter-apk
make_apk() { # $1 = plateformes, $2 = nom du fichier, $3 = types de processeur
  local ok=0
  export AICHA_ABIS="$3"
  for i in 1 2; do
    if flutter build apk --release --target-platform "$1" \
         --build-number=$BUILD "${DEFINES[@]}" 2>&1 | tee build.log; then ok=1; break; fi
    # Afficher les erreurs dans le résumé (« Annotations »)
    grep -E "(Error|error):|^e: |What went wrong" -A2 build.log | grep -v "^Note:" | grep -v "^--$" \
      | head -25 | while IFS= read -r l; do echo "::error::$l"; done || true
    echo "Nouvel essai dans 30 s…"; sleep 30
  done
  [ $ok = 1 ] || exit 1
  cp "$OUT/app-release.apk" "$2"
}
# Version légère (téléphones récents, 64 bits) : mise à jour intégrée
make_apk android-arm64 aicha-services-arm64.apk arm64-v8a
# Version universelle (tous les téléphones) : lien à partager
make_apk android-arm,android-arm64 aicha-services.apk armeabi-v7a,arm64-v8a

echo "== 7. Publication pour les clients"
ls -la aicha-services*.apk
if [ -f NOUVEAUTES.txt ]; then cp NOUVEAUTES.txt notes.txt; else echo "Mise à jour de l'application Aïcha Services" > notes.txt; fi
gh release create "v$BUILD" aicha-services.apk aicha-services-arm64.apk \
  --title "Mise à jour $BUILD" --notes-file notes.txt --latest
echo "Publié : v$BUILD"
