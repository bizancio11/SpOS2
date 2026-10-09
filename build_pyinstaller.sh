#!/bin/bash
# Compila SpOS2 UNA sola vez con PyInstaller y deriva los 3 programas en dist/
#   dist/SpOS2-N/SpOS2-N   dist/SpOS2-Programmer/SpOS2-Programmer   dist/SpOS2-Premium/SpOS2-Premium
# Despues crea las 3 ISOs (./build_pyinstaller.sh --sin-iso para omitirlas).
set -e
cd "$(dirname "$0")"
HERE="$PWD"
if [ ! -d .venv ]; then
  python3 -m venv .venv || { echo "Falta: sudo apt install python3-venv"; exit 1; }
fi
.venv/bin/pip install -q -r requirements.txt

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Modulos comunes para tus scripts .py; se excluye lo que SpOS2 no usa
HIDDEN=""
for m in math random json datetime time re collections itertools functools statistics string textwrap \
         base64 csv pathlib typing urllib.request socket threading decimal fractions heapq bisect copy uuid; do
  HIDDEN="$HIDDEN --hidden-import $m"
done
EXCL=""
for m in tkinter unittest pydoc pydoc_data distutils lib2to3 idlelib turtle curses xmlrpc ensurepip sqlite3 \
         pygame.tests pygame.examples pygame.docs pygame.midi pygame.pypm; do
  EXCL="$EXCL --exclude-module $m"
done

rm -rf dist
.venv/bin/pyinstaller --noconfirm --onedir --strip --name SpOS2 \
    --distpath "$HERE/dist" --workpath "$T/work" --specpath "$T" \
    --paths "$HERE" --add-data "$HERE/logo.png:." $HIDDEN $EXCL "$HERE/main.py"

# Las 3 versiones son copias; solo cambia el nombre y edition.txt
for par in normal:SpOS2-N programmer:SpOS2-Programmer premium:SpOS2-Premium; do
  ed="${par%%:*}"; name="${par##*:}"
  cp -a dist/SpOS2 "dist/$name"
  mv "dist/$name/SpOS2" "dist/$name/$name"
  echo "$ed" > "dist/$name/edition.txt"
done
rm -rf dist/SpOS2
echo
echo "Binarios listos. Ejemplo:  ./ejecutar.sh premium --bin"
if [ "${1:-}" != "--sin-iso" ]; then
  echo ">> Creando las 3 ISOs..."
  "$HERE/build_iso.sh"
fi
