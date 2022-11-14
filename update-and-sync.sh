#!/usr/bin/env bash

set -e

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -h | --help) help=1 ;;
  *)
    echo "Unknown parameter passed: $1" >&2
    exit 1
    ;;
  esac
  shift
done

if [ $help ]; then
  me=$(basename "$0")
  cat <<EOF
$me: Update external/slang and synchronize submodules

- Pull the latest changes into external/slang
- Make the other submodules in "external" point to the same commits as their
  counterpart submodules in "external/slang/external"
- Commit the changes to git if there were changes

EOF
  exit
fi

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
external=$dir/external
slang=$external/slang
paths=()

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
msg=$tmp/msg

git submodule update --init

describe(){
  git -C "$1" describe --always --exclude master-tot --tags
}

git -C "$slang" fetch --tags --force 
old_ref=$(describe "$slang")
git submodule update --remote --checkout "$slang"
git -C "$slang" submodule update --init --recursive
old_ref=$(describe "$slang")
if [ "$old_ref" != "$new_ref" ]; then
  paths+=("$slang")
  echo "${slang#"$dir/"}: $old_ref -> $new_ref" >> "$msg"
  echo >> "$msg"
fi

sync(){
  echo "Sync $1"
  git -C "$external/$1" fetch --tags --force 
  old_ref=$(describe "$external/$1")
  ref=$(git -C "$slang" submodule status -- "$slang/external/$1" | cut -d' ' -f2)
  git -C "$external/$1" checkout "$ref"
  new_ref=$(describe "$external/$1")
  if [ "$old_ref" != "$new_ref" ]; then
    paths+=("$external/$1")
    echo "- external/$1: $old_ref -> $new_ref" >> "$msg"
  fi
}

sync glslang
sync spirv-tools
sync spirv-headers
sync slang-binaries

if [ -f "$msg" ]; then
  git commit --file "$msg" "${paths[@]}"
fi


