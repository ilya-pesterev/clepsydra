#!/bin/bash
# Печатает номер сборки — момент по UTC как YYYYMMDDHHMMSS.
# Почему так — docs/development.md.
#
#   ./Tools/build-number.sh              момент — сейчас
#   ./Tools/build-number.sh 1700000000   момент приходит снаружи, для тестов
set -euo pipefail

date -u -r "${1:-$(date +%s)}" +%Y%m%d%H%M%S
