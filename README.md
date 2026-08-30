# Latido de producción

Cada hora, desde un ejecutor de GitHub —es decir, **fuera de la máquina que vigila**—,
pregunta a cada producción pública del holding si contesta, y se pone en rojo (y manda
el correo de GitHub) si cae **cualquiera** de ellas. Distingue una caída suelta (es el
servicio) de un apagón (es la máquina), porque exigen reacciones distintas.

## Por qué es un repositorio aparte, y público

Nació en `runner-ci-cd` (privado). Desde el 2026-08-25 GitHub no arranca jobs en
ejecutor de pago de la cuenta, y la dirección decidió no pagar: todo lo demás corre en
el pool propio del holding. El latido no puede: un vigilante que corre en la máquina
vigilada se apaga con ella. En un repositorio **público** GitHub no cobra los minutos de
sus ejecutores, y lo que hay aquí es público de todas formas: quince nombres de host que
ya están en el DNS y un bucle de `curl`. **Nada más puede entrar en este repositorio.**

## De dónde sale cada fichero

- `scripts/latido.sh` y `produccion-publica.txt` son **copias literales** de los de
  `runner-ci-cd`, que sigue siendo la fuente de verdad (allí viven sus pruebas y allí
  `verificar-despliegues.sh` contrasta la lista con lo que Traefik sirve de verdad).
  Se cambian ALLÍ y se copian aquí; la CI de `runner-ci-cd` compara ambas copias y se
  pone roja si se desvían.
- `.github/workflows/latido-produccion.yml` es el gemelo del de `runner-ci-cd`, que
  queda ciego mientras la facturación siga bloqueada. Si algún día vuelve a arrancar,
  hay que retirar uno de los dos: dos latidos son dos correos por caída.

## Ejecutarlo a mano

```bash
./scripts/latido.sh                 # desde cualquier máquina con curl
gh workflow run latido-produccion.yml -R CN1K/latido-produccion   # o en GitHub
```
