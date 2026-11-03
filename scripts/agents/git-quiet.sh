# shellcheck shell=bash
# Config de git para los tests que clonan repos locales (#224, como #186 y #190): ningún git de la prueba
# corre gc ni mantenimiento automático. Un gc que empaqueta objetos sueltos mientras otro git clona o lee
# ese repo puede romperlo ("failed to copy file ... No such file or directory"), a veces y solo en el CI.
# Uso: . "$RAIZ/scripts/agents/git-quiet.sh"; git_quiet_env
# Suma sus entradas a las que ya traiga GIT_CONFIG_COUNT (del entorno de quien corre el test) y no las pisa.
git_quiet_env() {
  local n=${GIT_CONFIG_COUNT:-0}
  case $n in ''|*[!0-9]*) n=0 ;; esac
  export "GIT_CONFIG_KEY_$n=gc.auto" "GIT_CONFIG_VALUE_$n=0"
  n=$((n + 1))
  export "GIT_CONFIG_KEY_$n=maintenance.auto" "GIT_CONFIG_VALUE_$n=false"
  export GIT_CONFIG_COUNT=$((n + 1))
}
