#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target_dir="$repo_root/infra/minio/build"
mkdir -p "$target_dir"
checksum=d8898351831761e083e7ba6b74ea7ec478b9a6680794fe92e5e838145341c9c5
if [ ! -f "$target_dir/minio.deb" ]; then
  curl --fail --silent --show-error --location \
    https://github.com/minio/minio/releases/download/RELEASE.2025-04-22T22-12-26Z/minio_20250422221226.0.0_amd64.deb \
    -o "$target_dir/minio.deb"
fi
printf '%s  %s\n' "$checksum" "$target_dir/minio.deb" | sha256sum -c -
