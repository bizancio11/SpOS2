# SpOS2: generar las tres ISOs con GitHub Actions

Este repositorio incluye un flujo que compila `main.py` y `core.py` con PyInstaller y luego genera las tres imágenes Live:

- `SpOS2-N.iso`
- `SpOS2-Programmer.iso`
- `SpOS2-Premium.iso`

## Cómo usarlo

1. Crea un repositorio en https://github.com/new.
2. Sube **todo el contenido de esta carpeta** a la raíz del repositorio: `main.py`, `core.py`, `logo.png`, `requirements.txt`, `build_pyinstaller.sh`, `build_iso.sh`, `ejecutar.sh`, `kernel/`, `.github/` y este README.
3. En GitHub, abre la pestaña **Actions**.
4. Selecciona **Build SpOS2 ISOs** en la lista de la izquierda.
5. Pulsa **Run workflow** y después el botón verde **Run workflow**.
6. Cuando el trabajo termine con una marca verde, abre esa ejecución y descarga el artefacto **SpOS2-3-ISOs**. Dentro estarán las tres ISOs y `SHA256SUMS`.

No hace falta que instales las dependencias de compilación en Linux Mint: el workflow las instala en una máquina Ubuntu temporal de GitHub. La primera compilación puede tardar y descargar varios gigabytes. El artefacto queda disponible durante 14 días.

Si falla, abre la ejecución en Actions y lee el primer paso rojo; suele indicar qué paquete o etapa falló. Las ISOs se producen solamente si el trabajo termina correctamente.
