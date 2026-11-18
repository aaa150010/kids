#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  bash scripts/native/build-android.sh
fi

release_dir="$project_root/build/native-release"
if [[ ! -f "$release_dir/latest.json" || ! -f "$release_dir/latest.sig" || ! -f "$release_dir/index.html" || ! -f "$release_dir/app-icon.png" ]]; then
  echo "缺少构建产物，请先运行 scripts/native/build-android.sh。" >&2
  exit 1
fi

# Upload immutable narration files before making a matching APK/content index available.
bash scripts/native/deploy-story-audio.sh

version="$(node -e "console.log(require('./apps/android/version.json').versionName)")"
code="$(node -e "console.log(require('./apps/android/version.json').versionCode)")"
apk_name="$(node -e "console.log(require('./build/native-release/latest.json').apk.url)")"
content_name="$(node -e "console.log(require('./build/native-release/latest.json').content.url)")"
apk_sha="$(node -e "console.log(require('./build/native-release/latest.json').apk.sha256)")"
content_sha="$(node -e "console.log(require('./build/native-release/latest.json').content.sha256)")"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
remote_root="/opt/kids-playground/dist/play-app"

remote_stage="/opt/kids-playground/.native-upload-${code}-${stamp}"

ssh aliyun "set -eu
mkdir -p '$remote_root' /opt/kids-playground/backups
# Immutable artifacts share storage; replacing public files below preserves this snapshot.
cp -al '$remote_root' '/opt/kids-playground/backups/play-app-${stamp}'
mkdir -p '$remote_stage' '$remote_root/releases/${code}'"

cleanup_upload() {
  ssh aliyun "rm -rf '$remote_stage'" || true
}
trap cleanup_upload EXIT

upload_files=(app-icon.png latest.json latest.sig index.html)
for artifact in "$apk_name" "$content_name"; do
  if [[ "$artifact" == "$apk_name" ]]; then
    digest="$apk_sha"
  else
    digest="$content_sha"
  fi
  # Versioned artifacts are immutable. Reuse a matching server copy without uploading it.
  if ssh aliyun "set -eu
if [ ! -f '$remote_root/$artifact' ]; then exit 3; fi
printf '%s  %s\\n' '$digest' '$remote_root/$artifact' | sha256sum -c -"; then
    ssh aliyun "ln '$remote_root/$artifact' '$remote_stage/$artifact'"
  else
    status=$?
    if [[ "$status" -ne 3 ]]; then
      echo "服务器已有文件校验失败，停止发布：$artifact" >&2
      exit "$status"
    fi
    upload_files+=("$artifact")
  fi
done

COPYFILE_DISABLE=1 tar --no-xattrs -czf - -C "$release_dir" "${upload_files[@]}" |
  ssh aliyun "tar -xzf - -C '$remote_stage'"

ssh aliyun "set -eu
printf '%s  %s\\n' '$apk_sha' '$remote_stage/$apk_name' '$content_sha' '$remote_stage/$content_name' | sha256sum -c -
for artifact in '$apk_name' '$content_name' app-icon.png latest.json latest.sig index.html; do
  ln -f '$remote_stage/'\"\$artifact\" '$remote_root/releases/${code}/'\"\$artifact\"
done
for artifact in '$apk_name' '$content_name' app-icon.png latest.sig latest.json; do
  if [ '$remote_stage/'\"\$artifact\" -ef '$remote_root/'\"\$artifact\" ]; then
    rm '$remote_stage/'\"\$artifact\"
  else
    mv -f '$remote_stage/'\"\$artifact\" '$remote_root/'\"\$artifact\"
  fi
done
ln -sfn '$apk_name' '$remote_root/.latest.apk.next'
mv -Tf '$remote_root/.latest.apk.next' '$remote_root/latest.apk'"

ssh aliyun "set -eu
cp -a /opt/note-caddy/Caddyfile /opt/note-caddy/Caddyfile.download-${stamp}.bak
python3 - /opt/note-caddy/Caddyfile" < "$project_root/scripts/native/patch-caddy.py"

ssh aliyun "set -eu
docker exec note-ledger-caddy caddy validate --config /etc/caddy/Caddyfile
docker exec note-ledger-caddy caddy reload --config /etc/caddy/Caddyfile
if [ -d /opt/kids-playground/dist/play ]; then
  mv /opt/kids-playground/dist/play '/opt/kids-playground/backups/play-web-${stamp}'
fi
test -f '$remote_root/index.html'
test -L '$remote_root/latest.apk'"

# Publish the page only after its APK, content and update manifest are complete.
ssh aliyun "set -eu
mv -Tf '$remote_stage/index.html' '$remote_root/index.html'
rmdir '$remote_stage'
find '$remote_root/releases' -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\\n' 2>/dev/null | sort -nr | tail -n +4 | cut -d' ' -f2- | xargs -r rm -rf"
trap - EXIT

printf '\nAPK 下载页：https://lynote.xyz/play-app/\n'
printf '旧网页入口：https://lynote.xyz/play/（自动跳转到下载页）\n'
printf '固定 APK 链接：https://lynote.xyz/play-app/latest.apk\n'
printf '版本：%s (%s)\n' "$version" "$code"
