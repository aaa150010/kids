#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
android_root="$project_root/apps/android"
image="${GODOT_CI_IMAGE:-barichello/godot-ci:4.7.2}"
platform="${GODOT_CI_PLATFORM:-linux/amd64}"
keys_dir="${KIDS_PLAYGROUND_KEYS:-$HOME/Library/Application Support/KidsPlayground/keys}"
gradle_cache="${KIDS_PLAYGROUND_GRADLE_CACHE:-$HOME/Library/Caches/KidsPlayground/gradle}"
staging="$android_root/build/staging"
proxy_args=()
gradle_proxy_args=()
if [[ -n "${KIDS_DOCKER_PROXY:-}" ]]; then
  proxy_args=(-e "HTTP_PROXY=$KIDS_DOCKER_PROXY" -e "HTTPS_PROXY=$KIDS_DOCKER_PROXY")
  proxy_hostport="${KIDS_DOCKER_PROXY#http://}"
  proxy_host="${proxy_hostport%:*}"
  proxy_port="${proxy_hostport##*:}"
  gradle_proxy_args=(
    -e "GRADLE_OPTS=-Dhttp.proxyHost=$proxy_host -Dhttp.proxyPort=$proxy_port -Dhttps.proxyHost=$proxy_host -Dhttps.proxyPort=$proxy_port"
  )
fi

cd "$project_root"
node scripts/native/author-stories.mjs
node scripts/native/export-content.mjs
mkdir -p "$keys_dir"
mkdir -p "$gradle_cache"
SKIP_KEYTOOL=1 node scripts/native/signing.mjs

rm -rf "$staging"
mkdir -p "$staging"
rsync -a \
  --exclude='.godot/' \
  --exclude='build/' \
  --exclude='android/plugins/UpdateInstaller.aar' \
  "$android_root/" "$staging/"

set -a
source "$keys_dir/release.env"
set +a
NATIVE_PROJECT_DIR="$staging" \
  NATIVE_KEYSTORE_PATH="/keys/kids-playground-release.keystore" \
  SKIP_KEYTOOL=1 \
  node scripts/native/prepare-export.mjs

docker run --rm \
  --platform "$platform" \
  -v "$staging:/project" \
  -v "$keys_dir:/keys" \
  -v "$gradle_cache:/root/.gradle" \
  -e KEY_ALIAS="$KEY_ALIAS" \
  -e KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD" \
  ${proxy_args[@]+"${proxy_args[@]}"} \
  ${gradle_proxy_args[@]+"${gradle_proxy_args[@]}"} \
  -w /project \
  -i "$image" bash -s <<'CONTAINER'
set -e
if [ ! -f /keys/kids-playground-release.keystore ]; then
  keytool -genkeypair \
    -keystore /keys/kids-playground-release.keystore \
    -storepass "$KEYSTORE_PASSWORD" \
    -keypass "$KEYSTORE_PASSWORD" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 3072 \
    -validity 10000 \
    -dname "CN=Kids Playground, OU=Local, O=Lynote, L=Shanghai, ST=Shanghai, C=CN"
fi
rm -rf /tmp/godot-android-template /tmp/plugin-build /tmp/plugin-aar
mkdir -p /tmp/godot-android-template /tmp/plugin-build /tmp/plugin-aar
unzip -q /root/.local/share/godot/export_templates/4.7.2.stable/android_source.zip -d /tmp/godot-android-template
unzip -q /tmp/godot-android-template/libs/release/godot-lib.template_release.aar -d /tmp/plugin-build/godot-lib
ANDROID_JAR="$(find /usr/lib/android-sdk/platforms -maxdepth 2 -name android.jar | sort | tail -1)"
javac -source 8 -target 8 -encoding UTF-8 \
  -classpath "$ANDROID_JAR:/tmp/plugin-build/godot-lib/classes.jar" \
  -d /tmp/plugin-build/classes \
  android/plugins/updater/src/main/java/xyz/lynote/kidsplayground/updater/*.java
jar --create --file /tmp/plugin-aar/classes.jar -C /tmp/plugin-build/classes .
cp android/plugins/updater/src/main/AndroidManifest.xml /tmp/plugin-aar/AndroidManifest.xml
jar --create --file android/plugins/UpdateInstaller.aar -C /tmp/plugin-aar .
rm -rf android/build
mkdir -p android/build
unzip -q /root/.local/share/godot/export_templates/4.7.2.stable/android_source.zip -d android/build
sed -i \
  -e "s/compileSdk         : 36/compileSdk         : 34/" \
  -e "s/minSdk             : 24/minSdk             : 26/" \
  -e "s/targetSdk          : 36/targetSdk          : 33/" \
  -e "s/buildTools[[:space:]]*:[[:space:]]*'36\\.1\\.0'/buildTools         : '34.0.0'/" \
  android/build/config.gradle
printf "4.7.2.stable\n" > android/.build_version
touch android/build/.gdignore
if [ "${KIDS_GRADLE_OFFLINE:-0}" = "1" ]; then
  mv android/build/gradlew android/build/gradlew.real
  cat > android/build/gradlew <<'OFFLINE_GRADLE'
#!/bin/sh
exec "$(dirname "$0")/gradlew.real" --offline "$@"
OFFLINE_GRADLE
  chmod +x android/build/gradlew
fi
godot --headless --import --quiet --path /project
godot --headless --editor --quit --quiet --path /project
mkdir -p build
godot --headless --path /project --export-release "Android" /project/build/kids-playground.apk
godot --headless --path /project --script res://tools/pack_content.gd -- /project/build/content.pck
CONTAINER
chmod 600 "$keys_dir/kids-playground-release.keystore" 2>/dev/null || true

APK_PATH="$staging/build/kids-playground.apk" \
  PCK_PATH="$staging/build/content.pck" \
  SKIP_KEYTOOL=1 \
  node scripts/native/generate-release.mjs
echo "原生安装包已生成：$project_root/build/native-release"
