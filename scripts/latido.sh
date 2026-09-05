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
# LA SEÑAL NO ES «¿CONTESTA 200?», PERO TAMPOCO «¿CONTESTA ALGO?». Durante meses fue lo
# segundo: cualquier código distinto de 000 era «vivo», con el argumento de que el 404
# de Traefik a un dominio sin ruta ya demuestra que la máquina sirve TLS. Y eso fue
# exactamente lo que pasó el 2026-09-04: el gateway arrancó sin salida a internet, no
# pudo cargar un plugin del que dependen TODOS sus routers, y los quince dominios
# contestaron 404 durante seis horas. Este latido dio 15/15 vivos las dos veces que
# corrió (runs 33905607657 y 33921192430). La máquina estaba viva; ninguna producción.
#
# HAY DOS 404, Y SE DISTINGUEN POR UNA CABECERA. El gateway añade desde el punto de
# entrada `Strict-Transport-Security` a TODA respuesta que ha pasado por un router —
# también al 404 de una API a su raíz (api.cromos, api.comunidad y api-loyalhub lo dan
# a diario, y están vivas)—. El 404 del PROPIO Traefik —«ningún router para este
# Host»— sale de su manejador por defecto, al que los middlewares del punto de entrada
# no envuelven: llega SIN esa cabecera. Ese 404 es caída, y un 5xx también: el gateway
# contesta, el servicio no. Exigir 2xx seguiría siendo un error: 30x, 401, 403 y el
# 404 de una aplicación son producciones sirviendo, y cada redespliegue sería una
# falsa alarma; una alarma que cría lobos deja de leerse.
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
sin_ruta=0   # de los muertos, cuántos reciben el 404 del PROPIO Traefik (sin router)

for h in "${HOSTS[@]}"; do
  ok=0
  motivo=""
  for intento in $(seq 1 "$INTENTOS"); do
    # `-w '%{http_code}'` imprime `000` cuando curl falla, así que hay que exigir
    # ADEMÁS que curl termine bien: sin eso, un fallo de red se leía como respuesta.
    # Se pide a la vez la cabecera Strict-Transport-Security (`%header{}`, curl ≥ 7.84):
    # es lo que separa el 404 de una aplicación del 404 del propio gateway.
    respuesta=$("$CURL" -s -o /dev/null -w '%{http_code} %header{strict-transport-security}' --max-time 15 "https://$h/" 2>/dev/null)
    rc=$?
    # Un espacio de más, para que el corte sea el mismo con cabecera, sin ella, o con
    # un curl de ensayo que imprime solo el código.
    respuesta="$respuesta "
    codigo=${respuesta%% *}
    sts=${respuesta#* }; sts=${sts%% *}
    case "$sts" in %header*)
      echo "::error::el curl de este ejecutor no entiende %header{}: no puedo distinguir el 404 del gateway del de una aplicación"
      exit 2 ;;
    esac
    motivo=""
    if [ "$rc" -eq 0 ] && [ -n "$codigo" ] && [ "$codigo" != "000" ]; then
      case "$codigo" in
        5??) motivo="HTTP $codigo: el gateway contesta, el servicio no" ;;
        404) [ -n "$sts" ] || motivo="404 del propio Traefik: SIN RUTA para este dominio" ;;
      esac
      if [ -z "$motivo" ]; then
        echo "  $h -> HTTP $codigo (vivo)"
        ok=1
        break
      fi
      echo "  $h -> $motivo (intento $intento/$INTENTOS)"
    else
      echo "  $h -> sin respuesta (intento $intento/$INTENTOS)"
    fi
    [ "$intento" -lt "$INTENTOS" ] && sleep "$ESPERA"
  done
  if [ "$ok" = 1 ]; then vivos=$(( vivos + 1 )); else muertos+=("$h"); fi
  case "$motivo" in *"SIN RUTA"*) sin_ruta=$(( sin_ruta + 1 )) ;; esac
done

echo
echo "vivos: $vivos/${#HOSTS[@]}"

# EL HOMBRE MUERTO DEL HOLDING ENTERO, y lo pinga este guion porque es lo único
# que corre FUERA de la máquina. Un check en healthchecks.io que espera un ping
# cada hora cubre lo que ningún vigilante de dentro puede ver: la máquina apagada
# (2026-08-08: 11 h 42 min sin aviso) y este mismo latido dejando de correr —
# GitHub desactiva los `schedule` de un repositorio público sin actividad en 60
# días, y una cuenta bloqueada tampoco arranca nada—. El correo de GitHub por
# flujo fallido sigue; esto añade un canal que no depende de GitHub para avisar.
# Con fallo —apagón, caída o gateway sin rutas— se pinga `/fail` (alerta
# inmediata, sin esperar al plazo). Sin URL no hace nada: en el ensayo local no la
# hay. Y un ping que no llega NO cambia el veredicto: lo que se juzga son las
# producciones, no el servicio de avisos.
# La URL llega por LATIDO_HC_URL (secreto del repositorio que ejecuta esto, ver
# el yml) y NUNCA se escribe aquí: este fichero es público.
hombre_muerto() {  # hombre_muerto [/fail]
  [ -n "${LATIDO_HC_URL:-}" ] || return 0
  "$CURL" -fsS --max-time 15 -o /dev/null "${LATIDO_HC_URL%/}${1:-}" >/dev/null 2>&1 \
    || echo "  (aviso: el ping al hombre muerto no llegó)"
}

# EL GATEWAY SIN RUTAS NO ES UN APAGÓN, y pide otro remedio: la máquina contesta y
# sirve TLS; lo que faltan son los routers (un plugin que no cargó, un proveedor
# caído). Se reinicia el gateway, no la máquina. Se dice ANTES que el apagón porque
# con todos en ese 404 `vivos` también vale cero.
if [ "$sin_ruta" -gt 0 ] && [ "$vivos" -eq 0 ]; then
  echo "::error::GATEWAY SIN RUTAS: $sin_ruta de ${#HOSTS[@]} producciones reciben el 404 del propio Traefik y ninguna responde. La máquina está viva; el gateway no enruta."
  hombre_muerto /fail
  exit 1
fi

if [ "$vivos" -eq 0 ]; then
  echo "::error::APAGÓN: ninguna de las ${#HOSTS[@]} producciones responde tras $INTENTOS intentos."
  hombre_muerto /fail
  exit 1
fi

if [ "${#muertos[@]}" -gt 0 ]; then
  echo "::error::CAÍDA: ${#muertos[@]} de ${#HOSTS[@]} producciones no responden: ${muertos[*]-}"
  [ "$sin_ruta" -gt 0 ] && echo "  ($sin_ruta de ellas con el 404 del propio Traefik: sin router para ese dominio)"
  echo "  (las demás sí contestan, así que la máquina está viva: es el servicio)"
  hombre_muerto /fail
  exit 1
fi

hombre_muerto
echo "las ${#HOSTS[@]} producciones responden."
