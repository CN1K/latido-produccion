#!/usr/bin/env bash
#
# ¿SIGUE VIVA CADA PRODUCCIÓN? — no «¿sigue viva la máquina?».
#
# QUÉ CAMBIÓ Y POR QUÉ. Este latido nació de un apagón de ONCE HORAS que nadie
# advirtió, y durante meses su condición de fallo fue `vivos -eq 0`: solo gritaba si
# NO respondía ninguno de los cuatro dominios que llevaba escritos. Es decir, una
# producción caída con las otras tres en pie salía VERDE, y el correo no llegaba. Una
# guarda que se ejecuta, sale verde y no cubre lo que parece cubrir es peor que no
# tenerla: ocupa su sitio.
#
# Ahora falla si cae CUALQUIERA, y distingue los dos casos al informar porque exigen
# reacciones distintas: un apagón es la máquina, una sola caída es un servicio.
#
# LA SEÑAL SIGUE SIENDO «¿CONTESTA ALGO?», NO «¿CONTESTA 200?». Traefik responde 404 a
# un dominio sin ruta, y ese 404 ya demuestra que la máquina está viva y sirviendo TLS.
# Exigir 2xx convertiría cada redespliegue en una falsa alarma, y una alarma que cría
# lobos deja de leerse.
#
# Uso:  latido.sh [fichero-de-dominios]     (por defecto, produccion-publica.txt)
# Variables de ensayo: LATIDO_INTENTOS, LATIDO_ESPERA, LATIDO_CURL
set -uo pipefail

LISTA="${1:-$(dirname "$0")/../produccion-publica.txt}"
INTENTOS="${LATIDO_INTENTOS:-3}"
ESPERA="${LATIDO_ESPERA:-20}"
# Se sustituye entero para poder ensayarlo sin red. No es una variable con la URL:
# es el mandato, porque lo que hay que poder falsear es la RESPUESTA, no el destino.
CURL="${LATIDO_CURL:-curl}"

[ -r "$LISTA" ] || { echo "::error::no se puede leer la lista de producciones: $LISTA"; exit 2; }

# Sin `mapfile`: no existe en el bash 3.2 que trae macOS, donde se ensaya esto.
HOSTS=()
while IFS= read -r linea; do
  linea=$(echo "$linea" | tr -d ' \t')
  case "$linea" in ''|\#*) continue ;; esac
  HOSTS+=("$linea")
done < "$LISTA"

# ANTI-VACUIDAD. Sin esto, una lista vacía —o un filtro que deje de casar— haría que el
# bucle no se ejecutara ni una vez y el latido saliera VERDE sin haber preguntado a
# nadie: el mismo silencio del que viene este workflow.
if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "::error::la lista de producciones está VACÍA: el latido no ha comprobado nada"
  exit 2
fi

vivos=0
muertos=()

for h in "${HOSTS[@]}"; do
  ok=0
  for intento in $(seq 1 "$INTENTOS"); do
    # `-w '%{http_code}'` imprime `000` cuando curl falla, así que hay que exigir
    # ADEMÁS que curl termine bien: sin eso, un fallo de red se leía como respuesta.
    codigo=$("$CURL" -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$h/" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$codigo" ] && [ "$codigo" != "000" ]; then
      echo "  $h -> HTTP $codigo (vivo)"
      ok=1
      break
    fi
    echo "  $h -> sin respuesta (intento $intento/$INTENTOS)"
    [ "$intento" -lt "$INTENTOS" ] && sleep "$ESPERA"
  done
  if [ "$ok" = 1 ]; then vivos=$(( vivos + 1 )); else muertos+=("$h"); fi
done

echo
echo "vivos: $vivos/${#HOSTS[@]}"

if [ "$vivos" -eq 0 ]; then
  echo "::error::APAGÓN: ninguna de las ${#HOSTS[@]} producciones responde tras $INTENTOS intentos."
  exit 1
fi

if [ "${#muertos[@]}" -gt 0 ]; then
  echo "::error::CAÍDA: ${#muertos[@]} de ${#HOSTS[@]} producciones no responden: ${muertos[*]-}"
  echo "  (las demás sí contestan, así que la máquina está viva: es el servicio)"
  exit 1
fi

echo "las ${#HOSTS[@]} producciones responden."
