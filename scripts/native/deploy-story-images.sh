#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="$project_root/content-src/assets/stories"
manifest="$project_root/content-src/data/story-illustrations.json"
remote_root="/opt/kids-playground/dist/play-app/story-images"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
release_root="/opt/kids-playground/story-image-releases"
remote_release="${release_root}/${stamp}"
remote_checksums="${remote_release}/.checksums.sha256"
remote_link="/opt/kids-playground/dist/play-app/.story-images-link-${stamp}"
backup_root="/opt/kids-playground/backups"
backup="${backup_root}/story-images-${stamp}"
checksums="$(mktemp "${TMPDIR:-/tmp}/kids-story-images.XXXXXX")"

if [[ ! -f "$manifest" ]]; then
  echo "缺少故事插画清单：$manifest" >&2
  exit 1
fi
expected_count="$(node --input-type=module -e '
  import { readFile } from "node:fs/promises"
  const manifest = JSON.parse(await readFile(process.argv[1], "utf8"))
  process.stdout.write(String(Object.keys(manifest.assets ?? {}).length))
' "$manifest")"
count="$(find "$source_root" -type f -name '*.webp' | wc -l | tr -d ' ')"
if [[ "$expected_count" -le 0 || "$count" -ne "$expected_count" ]]; then
  echo "故事插画数量不正确：$count，清单期望 $expected_count" >&2
  exit 1
fi

node --input-type=module -e '
  import { createHash } from "node:crypto"
  import { readdir, readFile, writeFile } from "node:fs/promises"
  import { join, relative } from "node:path"
  const [sourceRoot, outputPath] = process.argv.slice(1)
  async function collect(directory) {
    const files = []
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name)
      if (entry.isDirectory()) files.push(...await collect(path))
      else if (entry.isFile() && entry.name.endsWith(".webp")) files.push(path)
    }
    return files
  }
  const files = (await collect(sourceRoot)).sort()
  const lines = []
  for (const path of files) {
    const hash = createHash("sha256").update(await readFile(path)).digest("hex")
    lines.push(`${hash}  ${relative(sourceRoot, path)}`)
  }
  await writeFile(outputPath, `${lines.join("\n")}\n`)
' "$source_root" "$checksums"

cleanup() {
  rm -f "$checksums"
  ssh aliyun "set -eu
if [ -L '$remote_root' ] && [ \"\$(readlink -f '$remote_root')\" = '$remote_release' ]; then
  rm -f '$remote_link'
else
  rm -rf '$remote_release'
  rm -f '$remote_link'
fi" || true
}
trap cleanup EXIT

ssh aliyun "set -eu
mkdir -p '$remote_release' '$release_root' '$backup_root' '$(dirname "$remote_root")'"

COPYFILE_DISABLE=1 tar --no-xattrs -czf - -C "$source_root" . |
  ssh aliyun "tar -xzf - -C '$remote_release'"

ssh aliyun "cat > '$remote_checksums'" < "$checksums"

ssh aliyun "set -eu
test \"\$(find '$remote_release' -type f -name '*.webp' | wc -l)\" -eq '$expected_count'
cd '$remote_release'
sha256sum -c .checksums.sha256 >/dev/null
rm .checksums.sha256
ln -s '$remote_release' '$remote_link'
if [ -L '$remote_root' ]; then
  previous_target=\"\$(readlink -f '$remote_root')\"
  mv -Tf '$remote_link' '$remote_root'
else
  previous_target=''
  if [ -e '$remote_root' ]; then mv '$remote_root' '$backup'; fi
  if ! mv -Tf '$remote_link' '$remote_root'; then
    if [ -e '$backup' ] && [ ! -e '$remote_root' ]; then mv '$backup' '$remote_root'; fi
    exit 1
  fi
fi
if [ ! -d '$remote_root' ]; then
  if [ -n \"\$previous_target\" ]; then ln -s \"\$previous_target\" '$remote_root'; fi
  exit 1
fi"

trap - EXIT
rm -f "$checksums"
printf '故事插画已上传并逐文件校验：https://lynote.xyz/play-app/story-images/（%s 张）\n' "$count"
