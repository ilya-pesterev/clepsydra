#!/bin/bash
# Печатает адрес репозитория как owner/name — тот, куда уходит код.
#
# Берётся из origin, а не пишется строкой: адрес нужен и релизу, и ссылке
# в описании релиза, и разойтись им нельзя. У репозитория два remote — код
# в origin, задачи в другом, — и выводить адрес из origin значит не перепутать.
#
#   ./Tools/origin-repo.sh                                адрес — из origin
#   ./Tools/origin-repo.sh git@github.com:owner/name.git  адрес снаружи, для тестов
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
    URL="$1"
else
    URL="$(git remote get-url origin 2>/dev/null || true)"
    if [[ -z "$URL" ]]; then
        echo "ОШИБКА: нет remote origin — публиковать некуда." >&2
        exit 1
    fi
fi

case "$URL" in
    *github.com[:/]*) ;;
    *)
        echo "ОШИБКА: origin ($URL) не на github.com — релизы делаются там." >&2
        exit 1
        ;;
esac

REPOSITORY="$(sed -E 's#^.*github\.com[:/]##; s#/*$##; s#\.git$##' <<< "$URL")"

if [[ "$REPOSITORY" != */* ]]; then
    echo "ОШИБКА: из origin ($URL) не читается owner/name." >&2
    exit 1
fi

echo "$REPOSITORY"
