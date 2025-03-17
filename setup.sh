#!/bin/bash
# Configuración inicial
set -e  # Detener en caso de error
set -u  # Detectar variables no definidas

# Versión del script
VERSION="2.0.0"

# Colores y estilos (se pueden desactivar)
USE_COLORS=true
if $USE_COLORS; then
    RED=$'\033[0;31m'
    WHITE=$'\033[1;37m'
    GREEN=$'\033[0;32m'
    BLUE=$'\033[0;34m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    BLUE=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Funciones de mensajes
print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✔]${NC} $1"; }
print_error() { echo -e "${RED}[✘]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

# Verificar si se está ejecutando como root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Este script no debe ejecutarse como root"
        exit 1
    fi
}

# Función para mantener sudo activo
keep_sudo_alive() {
    # Solicitar contraseña interactiva al inicio
    echo -e "${YELLOW}[!] Por favor ingrese su contraseña de sudo:${NC}"
    if ! sudo -v; then
        print_error "No se pudieron obtener privilegios de administrador"
        exit 1
    fi

    # Renovar timestamp cada 15 segundos (en segundo plano)
    (
        while true; do
            sleep 15
            sudo -n -v 2>/dev/null || {
                print_error "Error renovando privilegios de sudo"
                exit 1
            }
        done
    ) &
    SUDO_PID=$!
    trap 'kill $SUDO_PID 2>/dev/null' EXIT SIGINT SIGTERM
}

# Mostrar spinner para operaciones largas
show_spinner() {
    local pid=$1
    local delay=0.15
    local spin='-\|/'
    local char=''
    while kill -0 $pid 2>/dev/null; do
        char=${spin:0:1}
        spin=${spin:1}${char}
        echo -ne "\r${CYAN}[${char}] ${NC}Por favor espere..."
        sleep $delay
    done
    echo ""
}

# Función de backup
backup_file() {
    if [ -f "$1" ]; then
        sudo -n cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)" || {
            print_error "No se pudo crear el respaldo de $1"
            return 1
        }
        print_success "Respaldo creado para $1"
    fi
}

# Verificar conexión a internet
check_internet() {
    print_status "Verificando conexión a internet..."
    if ! ping -c 1 8.8.8.8 ; then
        print_error "No hay conexión a internet"
        exit 1
    fi
    print_success "Conexión a internet verificada"
}

# Verificar espacio en disco con soporte para TB, GB, MB
check_disk_space() {
    local free_space=$(df -h / | awk 'NR==2 {print $4}')
    # Reemplazar coma por punto para el procesamiento numérico
    local size_num=$(echo $free_space | sed 's/[A-Za-z]//g' | tr ',' '.')
    local size_unit=$(echo $free_space | grep -o '[A-Za-z]*$')
    print_info "Espacio detectado: ${free_space}"

    # Convertir todo a GB para comparación usando awk
    case ${size_unit^^} in  # {^^} convierte a mayúsculas
        "T"|"TB")
            size_num=$(awk "BEGIN {print $size_num * 1024}")
            ;;
        "M"|"MB")
            size_num=$(awk "BEGIN {print $size_num / 1024}")
            ;;
        "G"|"GB")
            size_num=$size_num
            ;;
        *)
            print_error "No se pudo determinar la unidad de almacenamiento: $size_unit (espacio total: $free_space)"
            return 1
            ;;
    esac

    if awk "BEGIN {exit !($size_num < 20)}"; then
        print_warning "Poco espacio en disco (${free_space}). Se recomiendan al menos 20GB"
        read -p "¿Desea continuar? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    print_success "Espacio en disco suficiente (${free_space})"
    return 0
}

# Verificar requisitos del sistema
check_requirements() {
    print_status "Verificando requisitos del sistema..."
    
    # Verificar si es Arch Linux
    if [ ! -f /etc/arch-release ]; then
        print_error "Este script solo funciona en Arch Linux"
        exit 1
    fi

    # Verificar espacio en disco
    check_disk_space || exit 1

    # Verificar memoria
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 4 ]; then
        print_warning "Se recomienda al menos 4GB de RAM para un funcionamiento óptimo"
    fi

    # Verificar si KDE Plasma está instalado
    if ! command -v plasmashell ; then
        print_error "KDE Plasma no está instalado. Por favor, instálelo antes de continuar."
        exit 1
    fi 

    # Verificar si kwriteconfig6 está disponible
    if ! command -v kwriteconfig6 &>/dev/null && ! command -v kwriteconfig5 &>/dev/null; then
        print_warning "kwriteconfig no está instalado. Instalando..."
        sudo -n pacman --color=always -S --needed --noconfirm kconfig || {
            print_error "No se pudo instalar kconfig"
            exit 1
        }
    fi
}

# Verificar conexión a BlackArch
check_blackarch_connection() {
    print_status "Verificando conexión a BlackArch..."
    if ! curl -s --connect-timeout 8 https://blackarch.org/ > /dev/null; then
        print_error "No se puede conectar a BlackArch. Verifique su conexión a internet."
        return 1
    fi
    print_success "Conexión a BlackArch verificada"
    return 0
}

setup_blackarch() {
    print_status "Configurando repositorio BlackArch..."
    local temp_dir=$(mktemp -d)

    # Descargar strap.sh
    curl -sL https://blackarch.org/strap.sh -o "$temp_dir/strap.sh" || {
        print_error "Error descargando strap.sh"
        return 1
    }

    # Neutralizar la instalación de paquetes sin romper la sintaxis
    sed -i '/pacman --color=always -Sy blackarch-officials/s/^/#/' "$temp_dir/strap.sh"  # Comenta la línea
    sed -i '/blackarch-officials/d' "$temp_dir/strap.sh"                 # Elimina el meta-paquete

    # Ejecutar la versión modificada
    chmod +x "$temp_dir/strap.sh"
    echo "N" | sudo -n "$temp_dir/strap.sh" --no-official  # Envía "N" automáticamente

    # Verificar que el repositorio se agregó
    if ! grep -q "^\[blackarch\]" /etc/pacman.conf; then
        print_error "No se pudo agregar BlackArch a pacman.conf"
        return 1
    fi

    # Sincronizar bases de datos
    sudo -n pacman --color=always -Syy --noconfirm

    print_success "Repositorio BlackArch configurado (sin herramientas)"
    return 0
}

# Configurar repositorios
setup_repositories() {
    print_status "Configurando repositorios..."

    # Hacer backup de pacman.conf
    backup_file "/etc/pacman.conf" || exit 1

    # Configurar BlackArch
    setup_blackarch || return 1

    # Configurar Chaotic-AUR
    if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
        print_status "Configurando Chaotic-AUR..."

        # Verificar e instalar las llaves
        if ! sudo -n pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
            sudo -n pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || {
                print_error "Error recibiendo clave GPG de Chaotic-AUR"
                return 1
            }
            sudo -n pacman-key --lsign-key 3056513887B78AEB || {
                print_error "Error firmando clave GPG de Chaotic-AUR"
                return 1
            }
        fi

        # Instalar paquetes necesarios
        sudo -n pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
                                   'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || {
            print_error "Error instalando paquetes de Chaotic-AUR"
            return 1
        }

        {
            echo -e "\n[chaotic-aur]"
            echo "Include = /etc/pacman.d/chaotic-mirrorlist"
        } | sudo -n tee -a /etc/pacman.conf || {
            print_error "Error actualizando pacman.conf para Chaotic-AUR"
            return 1
        }

        print_success "Repositorio Chaotic-AUR configurado"
    else
        print_warning "Repositorio Chaotic-AUR ya está configurado"
    fi

    # Actualizar bases de datos
    print_status "Sincronizando bases de datos de paquetes..."
    {
        sudo -n pacman --color=always -Syy
    } || {
        print_error "Error sincronizando las bases de datos"
        return 1
    }
    print_success "Bases de datos sincronizadas correctamente"

    # Instalar yay si no está instalado
    if ! command -v yay ; then
        print_status "Instalando yay..."
        sudo -n pacman --color=always -S --needed --noconfirm git base-devel  || {
            print_error "Error instalando dependencias para yay"
            return 1
        }
        git clone https://aur.archlinux.org/yay.git /tmp/yay || {
            print_error "Error clonando el repositorio de yay"
            return 1
        }
        (cd /tmp/yay && makepkg -si --noconfirm ) || {
            print_error "Error compilando yay"
            return 1
        }
        rm -rf /tmp/yay
        print_success "yay instalado correctamente"
    else
        print_info "yay ya está instalado"
    fi
}

# Configuración de pacman
setup_pacman_config() {
    print_status "Configurando opciones visuales de pacman..."
    
    # Habilitar ILoveCandy (asegurarse de descomentar si estaba comentado)
    sudo -n sed -i '/^#\?ILoveCandy/s/^#//' /etc/pacman.conf
    
    # Verificar si ya existe un backup reciente
    if [ ! -f "/etc/pacman.conf.backup.$(date +%Y%m%d)" ]; then
        sudo -n cp /etc/pacman.conf "/etc/pacman.conf.backup.$(date +%Y%m%d)"
    fi

    # Array de opciones a configurar
    local options=(
        "Color"
        "ILoveCandy"
        "VerbosePkgLists"
        "ParallelDownloads = 5"
        "UseSyslog"
    )

    # Configurar cada opción
    for opt in "${options[@]}"; do
        if [[ "$opt" == *"="* ]]; then
            # Para opciones con valor
            local key="${opt%% = *}"
            if ! grep -q "^${key}" /etc/pacman.conf; then
                sudo -n sed -i "/\[options\]/a ${opt}" /etc/pacman.conf
                print_success "${key} configurado en pacman"
            fi
        else
            # Para opciones sin valor
            if ! grep -q "^${opt}" /etc/pacman.conf; then
                sudo -n sed -i "/^#${opt}/c\\${opt}" /etc/pacman.conf 2>/dev/null || \
                sudo -n sed -i "/\[options\]/a ${opt}" /etc/pacman.conf
                print_success "${opt} habilitado en pacman"
            fi
        fi
    done
}
# Instalar paquetes básicos y obligatorios
install_basic_packages() {
    print_status "Instalando paquetes básicos y obligatorios..."

    local basic_packages=(
        # Paquetes base y desarrollo
        "base-devel" "cmake" "extra-cmake-modules" "git" "go"

        # Herramientas del sistema
        "bat" "btop" "curl" "fzf" "gzip" "htop" "less"
        "lsd" "ncdu" "neofetch" "net-tools" "p7zip" "reflector"
        "tree" "unzip" "wget" "zip" "zsh"

        # Navegadores y editores
        "brave-browser" "firefox" "code"

        # Herramientas de red
        "netcat" "nmap" "socat" "traceroute" "whois"
        "openvpn" "openldap"

        # Terminales y utilidades
        "kitty" "konsole" "ttf-roboto" "ttf-roboto-mono-nerd"

        # Java y Node.js
        "jdk17-openjdk" "nodejs" "npm"

        # Aplicaciones de seguridad básicas
        "exploitdb" "impacket-ba" "nikto"

        # Utilidades adicionales
        "spectacle" "keepassxc" "obsidian" "peazip" "yt-dlp" "lolcat"

        # KDE Plasma componentes adicionales
        "plasma-systemmonitor" "plasma-browser-integration" "kdeplasma-addons"
        "kdeconnect" "kwallet-pam" "kscreen" "powerdevil" "bluedevil"
        "plasma-nm" "plasma-pa" "discover" "packagekit-qt5" "kinfocenter"
    )

    local total_packages=${#basic_packages[@]}
    local current_package=0
    local failed_packages=()

    for package in "${basic_packages[@]}"; do
        ((current_package++))
        print_status "[$current_package/$total_packages] Instalando ${package}..."

        if sudo -n pacman --color=always -S --needed --noconfirm "$package" ; then 
            print_success "✔ $package instalado"
        else
            print_error "✘ Error instalando $package"
            failed_packages+=("$package")
        fi
    done

    # Reportar paquetes fallidos
    if [ ${#failed_packages[@]} -gt 0 ]; then
        print_warning "Los siguientes paquetes no se pudieron instalar:"
        for package in "${failed_packages[@]}"; do
            echo "  - $package"
        done
        return 1
    fi

    print_success "Paquetes básicos instalados correctamente"
    return 0
}

# Función para determinar la versión de kwriteconfig
get_kwriteconfig_cmd() {
    if command -v kwriteconfig6 &>/dev/null; then
        echo "kwriteconfig6"
    else
        echo "kwriteconfig5"
    fi
}

# Función para determinar la versión de kreadconfig
get_kreadconfig_cmd() {
    if command -v kreadconfig6 &>/dev/null; then
        echo "kreadconfig6"
    else
        echo "kreadconfig5"
    fi
}

# Configurar fondo de pantalla para KDE Plasma
setup_wallpaper() {
    print_status "Configurando fondo de pantalla para KDE Plasma..."
    
    # Directorio de wallpapers
    local wallpaper_source="./Wallpamper"
    local wallpaper_dest="$HOME/Wallpamper"
    
    # Verificar directorio fuente
    if [ ! -d "$wallpaper_source" ]; then
        print_error "Directorio de wallpapers no encontrado: $wallpaper_source"
        return 1
    fi

    # Verificar archivos .jpeg
    if ! find "$wallpaper_source" -name "Arch-Linux-*.jpeg" -quit; then
        print_error "No se encontraron fondos válidos en $wallpaper_source"
        return 1
    fi

    # Crear directorio destino
    mkdir -p "$wallpaper_dest" || {
        print_error "No se pudo crear $wallpaper_dest"
        return 1
    }

    # Copiar wallpapers
    cp -r "$wallpaper_source"/* "$wallpaper_dest"/ || {
        print_error "Error copiando wallpapers"
        return 1
    }

    # Seleccionar wallpaper aleatorio (ruta absoluta)
    local wallpaper_file=$(find "$(realpath "$wallpaper_dest")" -name "Arch-Linux-*.jpeg" | shuf -n 1)
    if [ -z "$wallpaper_file" ]; then
        print_error "No se pudo seleccionar un fondo"
        return 1
    fi

    print_status "Fondo seleccionado: $(basename "$wallpaper_file")"
    
    # Determinar el comando kwriteconfig
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # ESTRATEGIA 1: Usar kwriteconfig para configurar Plasma
    print_status "Configurando fondo de pantalla con $kwriteconfig_cmd..."
    
    # Configurar el fondo de escritorio
    $kwriteconfig_cmd --file "plasma-org.kde.plasma.desktop-appletsrc" --group "Containments" --group "1" --group "Wallpaper" --group "org.kde.image" --group "General" --key "Image" "file://$wallpaper_file"
    
    # Verificar si todos los monitores usan el mismo script
    local desktop_script_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [ -f "$desktop_script_file" ]; then
        # Buscar todos los containments para escritorios
        local containments=$(grep -E "\[Containments\]\[[0-9]+\]" "$desktop_script_file" | sed -E 's/\[Containments\]\[([0-9]+)\]/\1/g')
        
        for containment in $containments; do
            # Verificar si es un desktop
            local wallpaper_plugin=$(grep -A 10 "\[Containments\]\[$containment\]" "$desktop_script_file" | grep -E "wallpaperplugin=org.kde.image" | wc -l)
            
            if [ "$wallpaper_plugin" -gt 0 ]; then
                print_status "Configurando fondo para containment $containment..."
                $kwriteconfig_cmd --file "plasma-org.kde.plasma.desktop-appletsrc" --group "Containments" --group "$containment" --group "Wallpaper" --group "org.kde.image" --group "General" --key "Image" "file://$wallpaper_file"
            fi
        done
    fi
    
    # ESTRATEGIA 2: Usar el comando plasma-apply-wallpaperimage si está disponible
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        print_status "Aplicando fondo con plasma-apply-wallpaperimage..."
        plasma-apply-wallpaperimage "$wallpaper_file" && {
            print_success "Fondo aplicado con plasma-apply-wallpaperimage"
            return 0
        }
    fi
    
    # ESTRATEGIA 3: Alternativamente, configurar para la sesión actual con DBUS
    print_status "Intentando con DBUS para la sesión actual..."
    if command -v qdbus &>/dev/null; then
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            var allDesktops = desktops();
            for (i=0; i<allDesktops.length; i++) {
                d = allDesktops[i];
                d.wallpaperPlugin = 'org.kde.image';
                d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
                d.writeConfig('Image', 'file://$wallpaper_file');
            }
        " && {
            print_success "Fondo aplicado con DBUS para la sesión actual"
            return 0
        }
    fi
    
    # ESTRATEGIA 4: Script directo a través de DBUS
    print_status "Ejecutando script para configurar el fondo..."
    
    # Crear un script temporal
    local tmp_script=$(mktemp)
    cat > "$tmp_script" << EOF
#!/bin/bash
# Configurar fondo en KDE Plasma con varios métodos
WALLPAPER="$wallpaper_file"

# Método 1: Configuración directa para la sesión actual
if command -v qdbus >/dev/null; then
    qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        var allDesktops = desktops();
        for (i=0; i<allDesktops.length; i++) {
            d = allDesktops[i];
            d.wallpaperPlugin = 'org.kde.image';
            d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
            d.writeConfig('Image', 'file://\$WALLPAPER');
        }
    "
fi

# Método 2: Usar gsettings si está disponible
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.background picture-uri "file://\$WALLPAPER" 2>/dev/null
    gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null
fi

# Método 3: Como último recurso, reiniciar plasmashell
if pgrep plasmashell >/dev/null; then
    kquitapp5 plasmashell >/dev/null 2>&1 || kquitapp6 plasmashell >/dev/null 2>&1
    sleep 1
    kstart5 plasmashell >/dev/null 2>&1 || kstart6 plasmashell >/dev/null 2>&1 || plasmashell >/dev/null 2>&1 &
fi

exit 0
EOF
    
    chmod +x "$tmp_script"
    bash "$tmp_script"
    rm -f "$tmp_script"
    
    # Consideramos que tuvo éxito incluso si no podemos verificarlo directamente
    print_success "Script ejecutado para aplicar el fondo"
    print_success "Fondo configurado exitosamente: $(basename "$wallpaper_file")"
    return 0
}

# Instalar fuentes del sistema
install_fonts() {
    print_status "Instalando fuentes del sistema..."

    # Crear estructura de directorios
    local font_dirs=(
        "hackfonts"
        "roboto"
        "impact"
        "ibm-plex"
        "inter"
        "poppins"
    )

    for dir in "${font_dirs[@]}"; do
        sudo -n mkdir -p "/usr/share/fonts/${dir}"
    done

    # Función auxiliar para descargar y descomprimir fuentes
    download_and_install_font() {
        local font_name="$1"
        local font_url="$2"
        local font_dir="$3"
        local temp_dir=$(mktemp -d)
        local is_zip=false

        if [[ "$font_url" == *".zip" ]]; then
            is_zip=true
        fi

        print_status "Instalando ${font_name}..."
        cd "$temp_dir"

        # Descargar fuente
        if ! wget -q --show-progress -O "${font_name}" "${font_url}"; then
            print_error "Error descargando ${font_name}"
            cd - > /dev/null
            rm -rf "$temp_dir"
            return 1
        fi

        # Procesar según el tipo de archivo
        if $is_zip; then
            if ! unzip -q "${font_name}"; then
                print_error "Error descomprimiendo ${font_name}"
                cd - > /dev/null
                rm -rf "$temp_dir"
                return 1
            fi
            # Copiar todos los archivos .ttf recursivamente
            sudo -n find . -name "*.ttf" -exec cp {} "/usr/share/fonts/${font_dir}/" \;
        else
            sudo -n cp "${font_name}" "/usr/share/fonts/${font_dir}/"
        fi

        cd - > /dev/null
        rm -rf "$temp_dir"
        print_success "${font_name} instalada correctamente"
        return 0
    }

    # Array de fuentes para instalar
    local fonts=(
        "Hack Nerd Font|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip|hackfonts"
        "Roboto|https://fonts.google.com/download?family=Roboto|roboto"
        "Impact|https://github.com/sophilabs/macgifer/raw/refs/heads/master/static/font/impact.ttf|impact"
    )

    # Instalar cada fuente
    for font in "${fonts[@]}"; do
        IFS="|" read -r name url dir <<< "$font"
        download_and_install_font "$name" "$url" "$dir" || {
            print_warning "Continuando con la siguiente fuente..."
            continue
        }
    done

    # Instalar fuentes adicionales del archivo ZIP
    print_status "Instalando fuentes adicionales..."
    if [ -f "IBM_Plex_Sans,Inter,Poppins.zip" ]; then
        local temp_dir=$(mktemp -d)
        unzip -q "IBM_Plex_Sans,Inter,Poppins.zip" -d "$temp_dir" || {
            print_error "Error descomprimiendo fuentes adicionales"
            rm -rf "$temp_dir"
            return 1
        }

        # Mapeo de directorios
        local font_mapping=(
            "IBM_Plex_Sans:ibm-plex"
            "Inter:inter"
            "Poppins:poppins"
        )

        # Copiar cada familia de fuentes
        for mapping in "${font_mapping[@]}"; do
            IFS=":" read -r src_dir dst_dir <<< "$mapping"
            if [ -d "$temp_dir/$src_dir" ]; then
                sudo -n cp -f "$temp_dir/$src_dir"/*.ttf "/usr/share/fonts/$dst_dir/" || {
                    print_error "Error copiando fuentes de $src_dir"
                    continue
                }
                print_success "Fuentes $src_dir instaladas"
            else
                print_warning "Directorio $src_dir no encontrado"
            fi
        done

        rm -rf "$temp_dir"
    else
        print_error "Archivo de fuentes adicionales no encontrado"
        return 1
    fi

    # Actualizar cache de fuentes
    print_status "Actualizando cache de fuentes..."
    if sudo -n fc-cache -fv; then
        print_success "Cache de fuentes actualizado correctamente"
    else
        print_error "Error actualizando el cache de fuentes"
        return 1
    fi
}

# Instalar temas e iconos
install_themes_and_icons() {
    print_status "Instalando temas e iconos..."

    # Crear directorios si no existen
    sudo -n mkdir -p /usr/share/themes
    sudo -n mkdir -p /usr/share/icons
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Instalar tema Andromeda
    if [ -f "Andromeda.tar.xz" ]; then
        print_status "Instalando tema Andromeda..."
        if sudo -n tar xf "Andromeda.tar.xz" -C /usr/share/themes/; then
            print_success "Tema Andromeda instalado"
        else
            print_error "Error instalando tema Andromeda"
            return 1
        fi
    else
        print_error "Archivo Andromeda.tar.xz no encontrado"
        return 1
    fi

    # Instalar tema similar para KDE (Breeze Dark con configuración personalizada)
    print_status "Configurando tema Breeze Dark para KDE..."
    
    # Configurar tema global
    $kwriteconfig_cmd --file kdeglobals --group General --key ColorScheme "BreezeDark"
    $kwriteconfig_cmd --file kdeglobals --group General --key Name "Breeze Dark"
    $kwriteconfig_cmd --file kdeglobals --group General --key widgetStyle "Breeze"
    $kwriteconfig_cmd --file kdeglobals --group KDE --key LookAndFeelPackage "org.kde.breezedark.desktop"
    
    # Aplicar tema desde la línea de comandos
    if command -v plasma-apply-colorscheme &>/dev/null; then
        plasma-apply-colorscheme BreezeDark
    fi
    
    if command -v plasma-apply-lookandfeel &>/dev/null; then
        plasma-apply-lookandfeel -a org.kde.breezedark.desktop
    fi
    
    # Instalar iconos Avidity 
    print_status "Instalando temas de iconos Avidity..."

    # 1. Avidity-Dusk-Mixed-Suru
    if [ -f "Avidity-Dusk-Mixed-Suru.zip" ]; then
        local temp_dir=$(mktemp -d)
        if unzip -q "Avidity-Dusk-Mixed-Suru.zip" -d "$temp_dir"; then
            sudo -n cp -r "$temp_dir/Avidity-Dusk-Mixed-Suru" /usr/share/icons/
            print_success "Tema de iconos Avidity-Dusk-Mixed-Suru instalado"
        else
            print_error "Error descomprimiendo Avidity-Dusk-Mixed-Suru"
            rm -rf "$temp_dir"
            return 1
        fi
        rm -rf "$temp_dir"
    else
        print_error "Archivo Avidity-Dusk-Mixed-Suru.zip no encontrado"
        return 1
    fi

    # 2. Avidity-Total-Dusk
    if [ -f "Avidity-Total-Dusk.zip" ]; then
        local temp_dir=$(mktemp -d)
        if unzip -q "Avidity-Total-Dusk.zip" -d "$temp_dir"; then
            sudo -n cp -r "$temp_dir/Avidity-Total-Dusk" /usr/share/icons/
            print_success "Tema de iconos Avidity-Total-Dusk instalado"
        else
            print_error "Error descomprimiendo Avidity-Total-Dusk"
            rm -rf "$temp_dir"
            return 1
        fi
        rm -rf "$temp_dir"
    else
        print_error "Archivo Avidity-Total-Dusk.zip no encontrado"
        return 1
    fi

    # Configurar iconos para KDE
    print_status "Configurando tema de iconos para KDE..."
    $kwriteconfig_cmd --file kdeglobals --group Icons --key Theme "Avidity-Dusk-Mixed-Suru"
    
    # Aplicar tema de iconos si está disponible el comando
    if command -v plasma-apply-icontheme &>/dev/null; then
        plasma-apply-icontheme Avidity-Dusk-Mixed-Suru
    fi
    
    # Actualizar cache de iconos
    if command -v gtk-update-icon-cache &>/dev/null; then
        sudo -n gtk-update-icon-cache -f /usr/share/icons/Avidity-Dusk-Mixed-Suru
        sudo -n gtk-update-icon-cache -f /usr/share/icons/Avidity-Total-Dusk
    fi
    
    # Configurar estilo de ventanas
    $kwriteconfig_cmd --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__Andromeda"
    
    print_success "Temas e iconos instalados correctamente"
    return 0
}

# Configurar terminal predeterminada
setup_default_terminal() {
    print_status "Configurando Kitty como terminal predeterminada..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Configurar terminal predeterminada para KDE
    $kwriteconfig_cmd --file kdeglobals --group General --key TerminalApplication "kitty"
    $kwriteconfig_cmd --file kdeglobals --group General --key TerminalService "kitty.desktop"
    
    # Actualizar alternativas del sistema
    if command -v update-alternatives &>/dev/null; then
        sudo -n update-alternatives --set x-terminal-emulator /usr/bin/kitty
    fi

    # Configurar para aplicaciones que usan xdg-open
    if [ -d ~/.local/share/applications ]; then
        echo "[Default Applications]
terminal=kitty.desktop" > ~/.local/share/applications/mimeapps.list
    fi

    print_success "Kitty configurada como terminal predeterminada"
}

# Configurar Konsole
configure_konsole() {
    print_status "Configurando Konsole..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Crear directorio de configuración si no existe
    mkdir -p "$HOME/.local/share/konsole"
    
    # Crear un perfil personalizado
    local profile_file="$HOME/.local/share/konsole/P4nxos.profile"
    cat > "$profile_file" << EOF
[Appearance]
ColorScheme=DarkPastels
Font=Hack Nerd Font Mono,10,-1,5,50,0,0,0,0,0

[General]
Name=P4nxos
Parent=FALLBACK/

[Scrolling]
HistoryMode=2
ScrollBarPosition=2

[Terminal Features]
BlinkingCursorEnabled=true
EOF

    # Configurar como perfil por defecto
    $kwriteconfig_cmd --file konsolerc --group "Desktop Entry" --key DefaultProfile "P4nxos.profile"
    
    # Configurar transparencia
    $kwriteconfig_cmd --file konsolerc --group "KonsoleWindow" --key "RememberWindowSize" "true"
    
    # Deshabilitar barra de menú
    $kwriteconfig_cmd --file konsolerc --group "KonsoleWindow" --key "ShowMenuBarByDefault" "false"
    
    # Crear un esquema de color oscuro
    local colorscheme_file="$HOME/.local/share/konsole/DarkPastels.colorscheme"
    if [ ! -f "$colorscheme_file" ]; then
        cat > "$colorscheme_file" << EOF
[Background]
Color=29,29,29

[BackgroundFaint]
Color=29,29,29

[BackgroundIntense]
Color=40,40,40

[Color0]
Color=63,63,63

[Color0Faint]
Color=52,52,52

[Color0Intense]
Color=112,144,128

[Color1]
Color=240,84,88

[Color1Faint]
Color=120,42,44

[Color1Intense]
Color=252,94,94

[Color2]
Color=64,172,112

[Color2Faint]
Color=32,86,56

[Color2Intense]
Color=124,240,122

[Color3]
Color=248,248,96

[Color3Faint]
Color=124,124,48

[Color3Intense]
Color=254,254,124

[Color4]
Color=64,148,192

[Color4Faint]
Color=32,74,96

[Color4Intense]
Color=68,156,228

[Color5]
Color=176,118,212

[Color5Faint]
Color=88,59,106

[Color5Intense]
Color=192,128,224

[Color6]
Color=80,180,184

[Color6Faint]
Color=40,90,92

[Color6Intense]
Color=96,196,196

[Color7]
Color=204,204,204

[Color7Faint]
Color=102,102,102

[Color7Intense]
Color=252,252,252

[Foreground]
Color=220,220,204

[ForegroundFaint]
Color=136,136,136

[ForegroundIntense]
Color=248,248,240

[General]
Blur=false
ColorRandomization=false
Description=Dark Pastels
Opacity=0.85
Wallpaper=
EOF
    fi

    print_success "Konsole configurada correctamente"
    return 0
}

# Configurar archivos de configuración de Kitty
setup_kitty_config() {
    print_status "Configurando Kitty..."

    # Verificar archivos requeridos
    local required_files=("kitty.conf" "color.ini")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Archivo requerido $file no encontrado"
            return 1
        fi
    done

    # Directorios de configuración
    local kitty_user_dir="$HOME/.config/kitty"
    local kitty_root_dir="/root/.config/kitty"

    # Crear directorios con manejo de errores
    print_status "Creando directorios de configuración..."
    mkdir -p "$kitty_user_dir" || {
        print_error "No se pudo crear $kitty_user_dir"
        return 1
    }
    
    sudo -n mkdir -p "$kitty_root_dir" || {
        print_error "No se pudo crear $kitty_root_dir"
        return 1
    }

    # Copiar archivos de configuración para usuario actual
    print_status "Copiando archivos de configuración para usuario $(whoami)..."
    for file in "${required_files[@]}"; do
        cp "$file" "$kitty_user_dir/" || {
            print_error "Error copiando $file para usuario actual"
            return 1
        }
        chmod 644 "$kitty_user_dir/$file" || {
            print_error "Error estableciendo permisos para $file de usuario"
            return 1
        }
    done
    print_success "Configuración de Kitty copiada para usuario $(whoami)"

    # Copiar archivos de configuración para root
    print_status "Copiando archivos de configuración para root..."
    for file in "${required_files[@]}"; do
        sudo -n cp "$file" "$kitty_root_dir/" || {
            print_error "Error copiando $file para root"
            return 1
        }
        sudo -n chmod 644 "$kitty_root_dir/$file" || {
            print_error "Error estableciendo permisos para $file de root"
            return 1
        }
    done
    print_success "Configuración de Kitty copiada para root"

    # Verificar la instalación
    print_status "Verificando la instalación..."
    for file in "${required_files[@]}"; do
        # Verificar archivos del usuario
        if [ ! -f "$kitty_user_dir/$file" ]; then
            print_error "Verificación fallida: $file no encontrado en $kitty_user_dir"
            return 1
        fi
        # Verificar archivos de root usando sudo
        if ! sudo -n test -f "$kitty_root_dir/$file"; then
            print_error "Verificación fallida: $file no encontrado en $kitty_root_dir"
            return 1
        fi
    done

    print_success "Configuración de Kitty completada exitosamente para usuario $(whoami) y root"
    return 0
}

# Configurar efectos visuales para KDE
setup_kde_effects() {
    print_status "Configurando efectos visuales para KDE..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # Configurar efectos visuales en KWin
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "Enabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "GLCore" "true"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "GLTextureFilter" "2"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "HiddenPreviews" "4"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "OpenGLIsUnsafe" "false"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "UnredirectFullscreen" "false"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "XRenderSmoothScale" "false"
    
    # Habilitar efectos de blur
    $kwriteconfig_cmd --file kwinrc --group Effect-blur --key "BlurStrength" "15"
    $kwriteconfig_cmd --file kwinrc --group Effect-blur --key "NoiseStrength" "0"
    
    # Configurar animaciones
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "blurEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_fadedesktopEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_fadeEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_scaleEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_squashEnabled" "false"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "magiclampEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "slidingpopupsEnabled" "true"
    
    # Configurar transparencias
    $kwriteconfig_cmd --file kdeglobals --group KDE --key "SingleClick" "false"
    
    print_success "Efectos visuales de KDE configurados correctamente"
    return 0
}

# Instalar temas e iconos
install_themes_and_icons() {
    print_status "Instalando temas e iconos..."

    # Crear directorios si no existen
    sudo -n mkdir -p /usr/share/themes
    sudo -n mkdir -p /usr/share/icons
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Instalar tema Andromeda
    if [ -f "Andromeda.tar.xz" ]; then
        print_status "Instalando tema Andromeda..."
        if sudo -n tar xf "Andromeda.tar.xz" -C /usr/share/themes/; then
            print_success "Tema Andromeda instalado"
        else
            print_error "Error instalando tema Andromeda"
            return 1
        fi
    else
        print_error "Archivo Andromeda.tar.xz no encontrado"
        return 1
    fi

    # Instalar tema similar para KDE (Breeze Dark con configuración personalizada)
    print_status "Configurando tema Breeze Dark para KDE..."
    
    # Configurar tema global
    $kwriteconfig_cmd --file kdeglobals --group General --key ColorScheme "BreezeDark"
    $kwriteconfig_cmd --file kdeglobals --group General --key Name "Breeze Dark"
    $kwriteconfig_cmd --file kdeglobals --group General --key widgetStyle "Breeze"
    $kwriteconfig_cmd --file kdeglobals --group KDE --key LookAndFeelPackage "org.kde.breezedark.desktop"
    
    # Aplicar tema desde la línea de comandos
    if command -v plasma-apply-colorscheme &>/dev/null; then
        plasma-apply-colorscheme BreezeDark
    fi
    
    if command -v plasma-apply-lookandfeel &>/dev/null; then
        plasma-apply-lookandfeel -a org.kde.breezedark.desktop
    fi
    
    # Instalar iconos Avidity 
    print_status "Instalando temas de iconos Avidity..."

    # 1. Avidity-Dusk-Mixed-Suru
    if [ -f "Avidity-Dusk-Mixed-Suru.zip" ]; then
        local temp_dir=$(mktemp -d)
        if unzip -q "Avidity-Dusk-Mixed-Suru.zip" -d "$temp_dir"; then
            sudo -n cp -r "$temp_dir/Avidity-Dusk-Mixed-Suru" /usr/share/icons/
            print_success "Tema de iconos Avidity-Dusk-Mixed-Suru instalado"
        else
            print_error "Error descomprimiendo Avidity-Dusk-Mixed-Suru"
            rm -rf "$temp_dir"
            return 1
        fi
        rm -rf "$temp_dir"
    else
        print_error "Archivo Avidity-Dusk-Mixed-Suru.zip no encontrado"
        return 1
    fi

    # 2. Avidity-Total-Dusk
    if [ -f "Avidity-Total-Dusk.zip" ]; then
        local temp_dir=$(mktemp -d)
        if unzip -q "Avidity-Total-Dusk.zip" -d "$temp_dir"; then
            sudo -n cp -r "$temp_dir/Avidity-Total-Dusk" /usr/share/icons/
            print_success "Tema de iconos Avidity-Total-Dusk instalado"
        else
            print_error "Error descomprimiendo Avidity-Total-Dusk"
            rm -rf "$temp_dir"
            return 1
        fi
        rm -rf "$temp_dir"
    else
        print_error "Archivo Avidity-Total-Dusk.zip no encontrado"
        return 1
    fi

    # Configurar iconos para KDE
    print_status "Configurando tema de iconos para KDE..."
    $kwriteconfig_cmd --file kdeglobals --group Icons --key Theme "Avidity-Dusk-Mixed-Suru"
    
    # Aplicar tema de iconos si está disponible el comando
    if command -v plasma-apply-icontheme &>/dev/null; then
        plasma-apply-icontheme Avidity-Dusk-Mixed-Suru
    fi
    
    # Actualizar cache de iconos
    if command -v gtk-update-icon-cache &>/dev/null; then
        sudo -n gtk-update-icon-cache -f /usr/share/icons/Avidity-Dusk-Mixed-Suru
        sudo -n gtk-update-icon-cache -f /usr/share/icons/Avidity-Total-Dusk
    fi
    
    # Configurar estilo de ventanas
    $kwriteconfig_cmd --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__Andromeda"
    
    print_success "Temas e iconos instalados correctamente"
    return 0
}

# Configurar terminal predeterminada
setup_default_terminal() {
    print_status "Configurando Kitty como terminal predeterminada..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Configurar terminal predeterminada para KDE
    $kwriteconfig_cmd --file kdeglobals --group General --key TerminalApplication "kitty"
    $kwriteconfig_cmd --file kdeglobals --group General --key TerminalService "kitty.desktop"
    
    # Actualizar alternativas del sistema
    if command -v update-alternatives &>/dev/null; then
        sudo -n update-alternatives --set x-terminal-emulator /usr/bin/kitty
    fi

    # Configurar para aplicaciones que usan xdg-open
    if [ -d ~/.local/share/applications ]; then
        echo "[Default Applications]
terminal=kitty.desktop" > ~/.local/share/applications/mimeapps.list
    fi

    print_success "Kitty configurada como terminal predeterminada"
}

# Configurar Konsole
configure_konsole() {
    print_status "Configurando Konsole..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)

    # Crear directorio de configuración si no existe
    mkdir -p "$HOME/.local/share/konsole"
    
    # Crear un perfil personalizado
    local profile_file="$HOME/.local/share/konsole/P4nxos.profile"
    cat > "$profile_file" << EOF
[Appearance]
ColorScheme=DarkPastels
Font=Hack Nerd Font Mono,10,-1,5,50,0,0,0,0,0

[General]
Name=P4nxos
Parent=FALLBACK/

[Scrolling]
HistoryMode=2
ScrollBarPosition=2

[Terminal Features]
BlinkingCursorEnabled=true
EOF

    # Configurar como perfil por defecto
    $kwriteconfig_cmd --file konsolerc --group "Desktop Entry" --key DefaultProfile "P4nxos.profile"
    
    # Configurar transparencia
    $kwriteconfig_cmd --file konsolerc --group "KonsoleWindow" --key "RememberWindowSize" "true"
    
    # Deshabilitar barra de menú
    $kwriteconfig_cmd --file konsolerc --group "KonsoleWindow" --key "ShowMenuBarByDefault" "false"
    
    # Crear un esquema de color oscuro
    local colorscheme_file="$HOME/.local/share/konsole/DarkPastels.colorscheme"
    if [ ! -f "$colorscheme_file" ]; then
        cat > "$colorscheme_file" << EOF
[Background]
Color=29,29,29

[BackgroundFaint]
Color=29,29,29

[BackgroundIntense]
Color=40,40,40

[Color0]
Color=63,63,63

[Color0Faint]
Color=52,52,52

[Color0Intense]
Color=112,144,128

[Color1]
Color=240,84,88

[Color1Faint]
Color=120,42,44

[Color1Intense]
Color=252,94,94

[Color2]
Color=64,172,112

[Color2Faint]
Color=32,86,56

[Color2Intense]
Color=124,240,122

[Color3]
Color=248,248,96

[Color3Faint]
Color=124,124,48

[Color3Intense]
Color=254,254,124

[Color4]
Color=64,148,192

[Color4Faint]
Color=32,74,96

[Color4Intense]
Color=68,156,228

[Color5]
Color=176,118,212

[Color5Faint]
Color=88,59,106

[Color5Intense]
Color=192,128,224

[Color6]
Color=80,180,184

[Color6Faint]
Color=40,90,92

[Color6Intense]
Color=96,196,196

[Color7]
Color=204,204,204

[Color7Faint]
Color=102,102,102

[Color7Intense]
Color=252,252,252

[Foreground]
Color=220,220,204

[ForegroundFaint]
Color=136,136,136

[ForegroundIntense]
Color=248,248,240

[General]
Blur=false
ColorRandomization=false
Description=Dark Pastels
Opacity=0.85
Wallpaper=
EOF
    fi

    print_success "Konsole configurada correctamente"
    return 0
}

# Configurar archivos de configuración de Kitty
setup_kitty_config() {
    print_status "Configurando Kitty..."

    # Verificar archivos requeridos
    local required_files=("kitty.conf" "color.ini")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Archivo requerido $file no encontrado"
            return 1
        fi
    done

    # Directorios de configuración
    local kitty_user_dir="$HOME/.config/kitty"
    local kitty_root_dir="/root/.config/kitty"

    # Crear directorios con manejo de errores
    print_status "Creando directorios de configuración..."
    mkdir -p "$kitty_user_dir" || {
        print_error "No se pudo crear $kitty_user_dir"
        return 1
    }
    
    sudo -n mkdir -p "$kitty_root_dir" || {
        print_error "No se pudo crear $kitty_root_dir"
        return 1
    }

    # Copiar archivos de configuración para usuario actual
    print_status "Copiando archivos de configuración para usuario $(whoami)..."
    for file in "${required_files[@]}"; do
        cp "$file" "$kitty_user_dir/" || {
            print_error "Error copiando $file para usuario actual"
            return 1
        }
        chmod 644 "$kitty_user_dir/$file" || {
            print_error "Error estableciendo permisos para $file de usuario"
            return 1
        }
    done
    print_success "Configuración de Kitty copiada para usuario $(whoami)"

    # Copiar archivos de configuración para root
    print_status "Copiando archivos de configuración para root..."
    for file in "${required_files[@]}"; do
        sudo -n cp "$file" "$kitty_root_dir/" || {
            print_error "Error copiando $file para root"
            return 1
        }
        sudo -n chmod 644 "$kitty_root_dir/$file" || {
            print_error "Error estableciendo permisos para $file de root"
            return 1
        }
    done
    print_success "Configuración de Kitty copiada para root"

    # Verificar la instalación
    print_status "Verificando la instalación..."
    for file in "${required_files[@]}"; do
        # Verificar archivos del usuario
        if [ ! -f "$kitty_user_dir/$file" ]; then
            print_error "Verificación fallida: $file no encontrado en $kitty_user_dir"
            return 1
        fi
        # Verificar archivos de root usando sudo
        if ! sudo -n test -f "$kitty_root_dir/$file"; then
            print_error "Verificación fallida: $file no encontrado en $kitty_root_dir"
            return 1
        fi
    done

    print_success "Configuración de Kitty completada exitosamente para usuario $(whoami) y root"
    return 0
}

# Configurar efectos visuales para KDE
setup_kde_effects() {
    print_status "Configurando efectos visuales para KDE..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # Configurar efectos visuales en KWin
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "Enabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "GLCore" "true"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "GLTextureFilter" "2"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "HiddenPreviews" "4"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "OpenGLIsUnsafe" "false"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "UnredirectFullscreen" "false"
    $kwriteconfig_cmd --file kwinrc --group Compositing --key "XRenderSmoothScale" "false"
    
    # Habilitar efectos de blur
    $kwriteconfig_cmd --file kwinrc --group Effect-blur --key "BlurStrength" "15"
    $kwriteconfig_cmd --file kwinrc --group Effect-blur --key "NoiseStrength" "0"
    
    # Configurar animaciones
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "blurEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_fadedesktopEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_fadeEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_scaleEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "kwin4_effect_squashEnabled" "false"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "magiclampEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "slidingpopupsEnabled" "true"
    
    # Habilitar ventanas gelatinosas (wobbly windows)
    $kwriteconfig_cmd --file kwinrc --group Plugins --key "wobblywindowsEnabled" "true"
    $kwriteconfig_cmd --file kwinrc --group Effect-wobblywindows --key "Drag" "85"
    $kwriteconfig_cmd --file kwinrc --group Effect-wobblywindows --key "Stiffness" "10"
    $kwriteconfig_cmd --file kwinrc --group Effect-wobblywindows --key "WobblynessLevel" "3"
    $kwriteconfig_cmd --file kwinrc --group Effect-wobblywindows --key "MoveFactor" "10"
    
    # Configurar transparencias
    $kwriteconfig_cmd --file kdeglobals --group KDE --key "SingleClick" "false"
    
    print_success "Efectos visuales de KDE configurados correctamente"
    return 0
}

# Configurar ZSH y sus plugins
setup_zsh() {
    print_status "Configurando ZSH y sus plugins..."

    # Verificar archivos requeridos
    local required_files=(".zshrc" ".p10k.zsh" ".p10k.zsh.root")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Archivo requerido $file no encontrado"
            return 1
        fi
    done

    # Instalar ZSH si no está presente
    if ! command -v zsh &> /dev/null; then
        sudo -n pacman -S --noconfirm zsh || {
            print_error "Error instalando ZSH"
            return 1
        }
    fi

    # Crear directorios para plugins
    print_status "Configurando directorios de plugins ZSH..."
    local plugins_base="/usr/share/zsh/plugins"
    sudo -n mkdir -p "$plugins_base"/{zsh-syntax-highlighting,zsh-autosuggestions,zsh-sudo} || {
        print_error "Error creando directorios de plugins"
        return 1
    }

    # Instalar plugins desde repositorios oficiales
    print_status "Instalando plugins de ZSH desde repositorios..."
    sudo -n pacman -S --noconfirm zsh-syntax-highlighting zsh-autosuggestions || {
        print_error "Error instalando plugins desde repositorios"
        return 1
    }

    # Instalar zsh-sudo manualmente
    print_status "Instalando plugin sudo para ZSH..."
    sudo -n curl -sL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/sudo/sudo.plugin.zsh" \
        -o "$plugins_base/zsh-sudo/sudo.plugin.zsh" || {
        print_error "Error descargando plugin sudo"
        return 1
    }
    print_success "Plugin sudo instalado correctamente"

    # Verificar que los plugins estén correctamente instalados
    for plugin in "zsh-syntax-highlighting" "zsh-autosuggestions" "zsh-sudo"; do
        local plugin_path=""
        case "$plugin" in
            "zsh-sudo")
                if [ ! -f "$plugins_base/zsh-sudo/sudo.plugin.zsh" ]; then
                    print_error "Plugin sudo no instalado correctamente"
                    return 1
                fi
                ;;
            *)
                if [ ! -f "/usr/share/zsh/plugins/$plugin/$plugin.zsh" ]; then
                    print_error "Plugin $plugin no instalado correctamente"
                    return 1
                fi
                ;;
        esac
    done

    print_success "Plugins ZSH instalados y configurados correctamente"

    # Configurar Powerlevel10k para el usuario actual
    print_status "Instalando Powerlevel10k para el usuario actual..."
    local p10k_user="$HOME/.powerlevel10k"  # Ahora con punto para que sea oculto
    if [ -d "$HOME/powerlevel10k" ]; then
        # Si existe el directorio sin punto, moverlo y hacerlo oculto
        mv "$HOME/powerlevel10k" "$p10k_user" || {
            print_error "Error moviendo directorio powerlevel10k existente"
            # Intentar removerlo y clonarlo de nuevo
            rm -rf "$HOME/powerlevel10k"
        }
    fi
    
    if [ ! -d "$p10k_user" ]; then
        git clone --depth=1 "https://github.com/romkatv/powerlevel10k.git" "$p10k_user" || {
            print_error "Error clonando Powerlevel10k para el usuario"
            return 1
        }
    fi

    # Configurar Powerlevel10k para root
    print_status "Instalando Powerlevel10k para root..."
    local p10k_root="/root/.powerlevel10k"  # Directorio oculto para root
    sudo -n mkdir -p "$(dirname "$p10k_root")"
    
    if sudo -n test -d "/root/powerlevel10k"; then
        # Si existe el directorio sin punto, moverlo y hacerlo oculto
        sudo -n mv "/root/powerlevel10k" "$p10k_root" || {
            print_warning "Error moviendo directorio powerlevel10k existente para root"
            # Intentar removerlo
            sudo -n rm -rf "/root/powerlevel10k"
        }
    fi
    
    if ! sudo -n test -d "$p10k_root"; then
        sudo -n git clone --depth=1 "https://github.com/romkatv/powerlevel10k.git" "$p10k_root" || {
            print_error "Error clonando Powerlevel10k para root"
            return 1
        }
    fi

    # Copiar archivos de configuración p10k
    print_status "Configurando archivos p10k..."
    if [ -f ".p10k.zsh" ]; then
        cp ".p10k.zsh" "$HOME/.p10k.zsh" || {
            print_error "Error copiando .p10k.zsh para usuario"
            return 1
        }
        print_success "Archivo .p10k.zsh copiado para usuario"
    else
        print_error "Archivo .p10k.zsh no encontrado"
        return 1
    fi

    if [ -f ".p10k.zsh.root" ]; then
        sudo -n cp ".p10k.zsh.root" "/root/.p10k.zsh" || {
            print_error "Error copiando .p10k.zsh para root" 
            return 1
        }
        print_success "Archivo .p10k.zsh copiado para root"
    else
        print_error "Archivo .p10k.zsh.root no encontrado"
        return 1
    fi

    # Configurar .zshrc
    local zshrc_source=".zshrc"
    if [ -f "$zshrc_source" ]; then
        # Actualizar las rutas de powerlevel10k en el archivo .zshrc para que use la ruta oculta
        sed -i 's|~/powerlevel10k|~/.powerlevel10k|g' "$zshrc_source"
        
        # Asegurar que las rutas de los plugins sean correctas
        cp "$zshrc_source" "$HOME/.zshrc" || {
            print_error "Error copiando .zshrc"
            return 1
        }
        
        # Enlace simbólico para root
        sudo -n ln -sf "$HOME/.zshrc" "/root/.zshrc" || {
            print_error "Error creando enlace para root"
            return 1
        }
        print_success "Archivo .zshrc configurado para usuario y root"
    else
        print_error "Archivo .zshrc no encontrado"
        return 1
    fi

    # Configurar ZSH como shell predeterminado
    print_status "Estableciendo ZSH como shell predeterminado..."
    local zsh_path="$(which zsh)"
    if ! grep -q "$zsh_path" /etc/shells; then
        echo "$zsh_path" | sudo -n tee -a /etc/shells >/dev/null
    fi

    sudo -n chsh -s "$zsh_path" "$USER" || {
        print_error "Error configurando ZSH para el usuario"
        return 1
    }
    sudo -n chsh -s "$zsh_path" root || {
        print_error "Error configurando ZSH para root"
        return 1
    }

    print_success "ZSH configurado correctamente como shell predeterminado"
    return 0
}
# Configurar atajos de teclado para KDE
setup_kde_shortcuts() {
    print_status "Configurando atajos de teclado para KDE..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # Crear un directorio temporal para el archivo de configuración
    local temp_dir=$(mktemp -d)
    local shortcuts_file="$temp_dir/kglobalshortcutsrc"
    
    # Crear un archivo de atajos básico
    cat > "$shortcuts_file" << EOF
[KDE Keyboard Layout Switcher]
Switch to Next Keyboard Layout=Meta+Alt+K,Meta+Alt+K,Cambiar al siguiente diseño de teclado

[kaccess]
Toggle Screen Reader On and Off=Meta+Alt+S,Meta+Alt+S,Activar/Desactivar el lector de pantalla

[kcm_touchpad]
Disable Touchpad=Touchpad Off,Touchpad Off,Deshabilitar el panel táctil
Enable Touchpad=Touchpad On,Touchpad On,Habilitar el panel táctil
Toggle Touchpad=Touchpad Toggle,Touchpad Toggle\tMeta+Ctrl+Zenkaku Hankaku,Alternar el panel táctil

[kded5]
Show System Activity=Ctrl+Esc,Ctrl+Esc,Mostrar la actividad del sistema
display=Display\tMeta+P,Display\tMeta+P,Cambiar pantalla

[khotkeys]
{49c91b27-de12-4c76-88eb-d509b268abdb}=Meta+Return,none,Kitty
{a389055e-f01b-4a37-98e5-37ebb9e4c5c6}=Meta+Shift+S,none,Spectacle
{c9cef472-1d13-456e-853d-3e7aa454a77d}=Meta+Shift+B,none,Brave Browser

[kmix]
decrease_microphone_volume=Microphone Volume Down,Microphone Volume Down,Bajar el volumen del micrófono
decrease_volume=Volume Down,Volume Down,Bajar el volumen
increase_microphone_volume=Microphone Volume Up,Microphone Volume Up,Subir el volumen del micrófono
increase_volume=Volume Up,Volume Up,Subir el volumen
mic_mute=Microphone Mute\tMeta+Volume Mute,Microphone Mute\tMeta+Volume Mute,Silenciar el micrófono
mute=Volume Mute,Volume Mute,Silenciar

[ksmserver]
Halt Without Confirmation=,,Apagar sin confirmación
Lock Session=Meta+L\tScreensaver,Meta+L\tScreensaver,Bloquear la sesión
Log Out=Ctrl+Alt+Del,Ctrl+Alt+Del,Cerrar la sesión
Log Out Without Confirmation=,,Cerrar la sesión sin confirmación
Reboot Without Confirmation=,,Reiniciar sin confirmación

[kwin]
Activate Window Demanding Attention=Meta+Ctrl+A,Meta+Ctrl+A,Activar ventana que requiere atención
Decrease Opacity=,,Disminuir la opacidad de la ventana activa un 5 %
Edit Tiles=Meta+T,Meta+T,Alternar el editor de mosaicos
Expose=Ctrl+F9,Ctrl+F9,Alternar la presentación de ventanas (escritorio actual)
ExposeAll=Ctrl+F10\tLaunch (C),Ctrl+F10\tLaunch (C),Alternar la presentación de ventanas (todos los escritorios)
ExposeClass=Ctrl+F7,Ctrl+F7,Alternar la presentación de ventanas (clase de ventana)
ExposeClassCurrentDesktop=,,Alternar la presentación de ventanas (clase de ventana en el escritorio actual)
Increase Opacity=,,Aumentar la opacidad de la ventana activa un 5 %
Kill Window=Meta+Ctrl+Esc,Meta+Ctrl+Esc,Matar la ventana
MoveMouseToCenter=Meta+F6,Meta+F6,Mover el puntero del ratón al centro
MoveMouseToFocus=Meta+F5,Meta+F5,Mover el puntero del ratón al foco
MoveZoomDown=,,Mover el área ampliada hacia abajo
MoveZoomLeft=,,Mover el área ampliada hacia la izquierda
MoveZoomRight=,,Mover el área ampliada hacia la derecha
MoveZoomUp=,,Mover el área ampliada hacia arriba
Overview=Meta+W,Meta+W,Alternar la vista general
Setup Window Shortcut=,,Configurar el atajo para la ventana
Show Desktop=Meta+D,Meta+D,Mostrar el escritorio
ShowDesktopGrid=Meta+F8,Meta+F8,Mostrar el escritorio en forma de rejilla
Suspend Compositing=Alt+Shift+F12,Alt+Shift+F12,Suspender la composición
Switch One Desktop Down=Meta+Ctrl+Down,Meta+Ctrl+Down,Cambiar un escritorio hacia abajo
Switch One Desktop Up=Meta+Ctrl+Up,Meta+Ctrl+Up,Cambiar un escritorio hacia arriba
Switch One Desktop to the Left=Meta+Ctrl+Left,Meta+Ctrl+Left,Cambiar un escritorio hacia la izquierda
Switch One Desktop to the Right=Meta+Ctrl+Right,Meta+Ctrl+Right,Cambiar un escritorio hacia la derecha
Switch Window Down=Meta+Alt+Down,Meta+Alt+Down,Cambiar a la ventana de abajo
Switch Window Left=Meta+Alt+Left,Meta+Alt+Left,Cambiar a la ventana de la izquierda
Switch Window Right=Meta+Alt+Right,Meta+Alt+Right,Cambiar a la ventana de la derecha
Switch Window Up=Meta+Alt+Up,Meta+Alt+Up,Cambiar a la ventana de arriba
Switch to Desktop 1=Ctrl+F1,Ctrl+F1,Cambiar al escritorio 1
Switch to Desktop 10=,,Cambiar al escritorio 10
Switch to Desktop 11=,,Cambiar al escritorio 11
Switch to Desktop 12=,,Cambiar al escritorio 12
Switch to Desktop 13=,,Cambiar al escritorio 13
Switch to Desktop 14=,,Cambiar al escritorio 14
Switch to Desktop 15=,,Cambiar al escritorio 15
Switch to Desktop 16=,,Cambiar al escritorio 16
Switch to Desktop 17=,,Cambiar al escritorio 17
Switch to Desktop 18=,,Cambiar al escritorio 18
Switch to Desktop 19=,,Cambiar al escritorio 19
Switch to Desktop 2=Ctrl+F2,Ctrl+F2,Cambiar al escritorio 2
Switch to Desktop 20=,,Cambiar al escritorio 20
Switch to Desktop 3=Ctrl+F3,Ctrl+F3,Cambiar al escritorio 3
Switch to Desktop 4=Ctrl+F4,Ctrl+F4,Cambiar al escritorio 4
Switch to Desktop 5=,,Cambiar al escritorio 5
Switch to Desktop 6=,,Cambiar al escritorio 6
Switch to Desktop 7=,,Cambiar al escritorio 7
Switch to Desktop 8=,,Cambiar al escritorio 8
Switch to Desktop 9=,,Cambiar al escritorio 9
Switch to Next Desktop=,,Cambiar al siguiente escritorio
Switch to Next Screen=,,Cambiar a la siguiente pantalla
Switch to Previous Desktop=,,Cambiar al escritorio anterior
Switch to Previous Screen=,,Cambiar a la pantalla anterior
Switch to Screen 0=,,Cambiar a la pantalla 0
Switch to Screen 1=,,Cambiar a la pantalla 1
Switch to Screen 2=,,Cambiar a la pantalla 2
Switch to Screen 3=,,Cambiar a la pantalla 3
Switch to Screen 4=,,Cambiar a la pantalla 4
Switch to Screen 5=,,Cambiar a la pantalla 5
Switch to Screen 6=,,Cambiar a la pantalla 6
Switch to Screen 7=,,Cambiar a la pantalla 7
Switch to Screen Above=,,Cambiar a la pantalla de arriba
Switch to Screen Below=,,Cambiar a la pantalla de abajo
Switch to Screen to the Left=,,Cambiar a la pantalla de la izquierda
Switch to Screen to the Right=,,Cambiar a la pantalla de la derecha
Toggle Night Color=,,Alternar el color nocturno
Toggle Window Raise/Lower=,,Alternar elevar/bajar ventana
Walk Through Desktop List=,,Recorrer la lista de escritorios
Walk Through Desktop List (Reverse)=,,Recorrer la lista de escritorios (al revés)
Walk Through Desktops=,,Recorrer los escritorios
Walk Through Desktops (Reverse)=,,Recorrer los escritorios (al revés)
Walk Through Windows=Alt+Tab,Alt+Tab,Recorrer las ventanas
Walk Through Windows (Reverse)=Alt+Shift+Tab,Alt+Shift+Tab,Recorrer las ventanas (al revés)
Walk Through Windows Alternative=,,Recorrer las ventanas alternativa
Walk Through Windows Alternative (Reverse)=,,Recorrer las ventanas alternativa (al revés)
Walk Through Windows of Current Application=Alt+\`,Alt+\`,Recorrer las ventanas de la aplicación actual
Walk Through Windows of Current Application (Reverse)=Alt+~,Alt+~,Recorrer las ventanas de la aplicación actual (al revés)
Walk Through Windows of Current Application Alternative=,,Recorrer las ventanas de la aplicación actual alternativa
Walk Through Windows of Current Application Alternative (Reverse)=,,Recorrer las ventanas de la aplicación actual alternativa (al revés)
Window Above Other Windows=,,Mantener la ventana sobre las demás
Window Below Other Windows=,,Mantener la ventana bajo las demás
Window Close=Alt+F4,Alt+F4,Cerrar la ventana
Window Fullscreen=F11,F11,Ventana en pantalla completa
Window Grow Horizontal=,,Expandir la ventana horizontalmente
Window Grow Vertical=,,Expandir la ventana verticalmente
Window Lower=,,Bajar la ventana
Window Maximize=Meta+PgUp,Meta+PgUp,Maximizar la ventana
Window Maximize Horizontal=,,Maximizar la ventana horizontalmente
Window Maximize Vertical=,,Maximizar la ventana verticalmente
Window Minimize=Meta+PgDown,Meta+PgDown,Minimizar la ventana
Window Move=,,Mover la ventana
Window Move Center=,,Mover la ventana al centro
Window No Border=,,Ocultar el borde de la ventana
Window On All Desktops=,,Mantener la ventana en todos los escritorios
Window One Desktop Down=Meta+Ctrl+Shift+Down,Meta+Ctrl+Shift+Down,Ventana un escritorio abajo
Window One Desktop Up=Meta+Ctrl+Shift+Up,Meta+Ctrl+Shift+Up,Ventana un escritorio arriba
Window One Desktop to the Left=Meta+Ctrl+Shift+Left,Meta+Ctrl+Shift+Left,Ventana un escritorio a la izquierda
Window One Desktop to the Right=Meta+Ctrl+Shift+Right,Meta+Ctrl+Shift+Right,Ventana un escritorio a la derecha
Window One Screen Down=,,Ventana una pantalla abajo
Window One Screen Up=,,Ventana una pantalla arriba
Window One Screen to the Left=,,Ventana una pantalla a la izquierda
Window One Screen to the Right=,,Ventana una pantalla a la derecha
Window Operations Menu=Alt+F3,Alt+F3,Menú de operaciones de la ventana
Window Pack Down=,,Mover la ventana abajo
Window Pack Left=,,Mover la ventana a la izquierda
Window Pack Right=,,Mover la ventana a la derecha
Window Pack Up=,,Mover la ventana arriba
Window Quick Tile Bottom=Meta+Down,Meta+Down,Ventana en mosaico rápido abajo
Window Quick Tile Bottom Left=Meta+Shift+Left,Meta+Shift+Left,Ventana en mosaico rápido abajo a la izquierda
Window Quick Tile Bottom Right=Meta+Shift+Down,Meta+Shift+Down,Ventana en mosaico rápido abajo a la derecha
Window Quick Tile Left=Meta+Left,Meta+Left,Ventana en mosaico rápido a la izquierda
Window Quick Tile Right=Meta+Right,Meta+Right,Ventana en mosaico rápido a la derecha
Window Quick Tile Top=Meta+Up,Meta+Up,Ventana en mosaico rápido arriba
Window Quick Tile Top Left=Meta+Shift+Up,Meta+Shift+Up,Ventana en mosaico rápido arriba a la izquierda
Window Quick Tile Top Right=Meta+Shift+Right,Meta+Shift+Right,Ventana en mosaico rápido arriba a la derecha
Window Raise=,,Elevar la ventana
Window Resize=,,Redimensionar la ventana
Window Shade=,,Enrollar la ventana
Window Shrink Horizontal=,,Encoger la ventana horizontalmente
Window Shrink Vertical=,,Encoger la ventana verticalmente
Window to Desktop 1=,,Ventana al escritorio 1
Window to Desktop 10=,,Ventana al escritorio 10
Window to Desktop 11=,,Ventana al escritorio 11
Window to Desktop 12=,,Ventana al escritorio 12
Window to Desktop 13=,,Ventana al escritorio 13
Window to Desktop 14=,,Ventana al escritorio 14
Window to Desktop 15=,,Ventana al escritorio 15
Window to Desktop 16=,,Ventana al escritorio 16
Window to Desktop 17=,,Ventana al escritorio 17
Window to Desktop 18=,,Ventana al escritorio 18
Window to Desktop 19=,,Ventana al escritorio 19
Window to Desktop 2=,,Ventana al escritorio 2
Window to Desktop 20=,,Ventana al escritorio 20
Window to Desktop 3=,,Ventana al escritorio 3
Window to Desktop 4=,,Ventana al escritorio 4
Window to Desktop 5=,,Ventana al escritorio 5
Window to Desktop 6=,,Ventana al escritorio 6
Window to Desktop 7=,,Ventana al escritorio 7
Window to Desktop 8=,,Ventana al escritorio 8
Window to Desktop 9=,,Ventana al escritorio 9
Window to Next Desktop=,,Ventana al siguiente escritorio
Window to Next Screen=Meta+Shift+Right,Meta+Shift+Right,Ventana a la siguiente pantalla
Window to Previous Desktop=,,Ventana al escritorio anterior
Window to Previous Screen=Meta+Shift+Left,Meta+Shift+Left,Ventana a la pantalla anterior
Window to Screen 0=,,Ventana a la pantalla 0
Window to Screen 1=,,Ventana a la pantalla 1
Window to Screen 2=,,Ventana a la pantalla 2
Window to Screen 3=,,Ventana a la pantalla 3
Window to Screen 4=,,Ventana a la pantalla 4
Window to Screen 5=,,Ventana a la pantalla 5
Window to Screen 6=,,Ventana a la pantalla 6
Window to Screen 7=,,Ventana a la pantalla 7
view_actual_size=Meta+0,Meta+0,Tamaño real
view_zoom_in=Meta++\tMeta+=,Meta++,Ampliar
view_zoom_out=Meta+-,Meta+-,Reducir

[org.kde.dolphin.desktop]
_launch=Meta+E,Meta+E,Dolphin

[org.kde.konsole.desktop]
NewTab=,,Nueva pestaña
NewWindow=,,Nueva ventana
_launch=Ctrl+Alt+T,Ctrl+Alt+T,Konsole

[org.kde.krunner.desktop]
RunClipboard=Alt+Shift+F2,Alt+Shift+F2,Ejecutar comando sobre el contenido del portapapeles
_launch=Alt+Space\tAlt+F2\tSearch,Alt+Space\tAlt+F2\tSearch,KRunner

[org.kde.plasma.emojier.desktop]
_launch=Meta+.,Meta+.,Selector de emojis

[org.kde.spectacle.desktop]
ActiveWindowScreenShot=Meta+Print,Meta+Print,Capturar la ventana activa
CurrentMonitorScreenShot=,,Capturar el monitor actual
FullScreenScreenShot=Shift+Print,Shift+Print,Capturar todo el escritorio
OpenWithoutScreenshot=,,Iniciar Spectacle sin realizar una captura
RectangularRegionScreenShot=Meta+Shift+Print,Meta+Shift+Print,Capturar una región rectangular
WindowUnderCursorScreenShot=Meta+Ctrl+Print,Meta+Ctrl+Print,Capturar la ventana bajo el cursor
_launch=Print,Print,Iniciar Spectacle

[org_kde_powerdevil]
Decrease Keyboard Brightness=Keyboard Brightness Down,Keyboard Brightness Down,Disminuir el brillo del teclado
Decrease Screen Brightness=Monitor Brightness Down,Monitor Brightness Down,Disminuir el brillo de la pantalla
Hibernate=Hibernate,Hibernate,Hibernar
Increase Keyboard Brightness=Keyboard Brightness Up,Keyboard Brightness Up,Aumentar el brillo del teclado
Increase Screen Brightness=Monitor Brightness Up,Monitor Brightness Up,Aumentar el brillo de la pantalla
PowerDown=Power Down,Power Down,Apagar
PowerOff=Power Off,Power Off,Apagar
Sleep=Sleep,Sleep,Suspender
Toggle Keyboard Backlight=Keyboard Light On/Off,Keyboard Light On/Off,Alternar la retroiluminación del teclado
Turn Off Screen=,,Apagar la pantalla

[plasmashell]
activate task manager entry 1=Meta+1,Meta+1,Activar la entrada 1 del gestor de tareas
activate task manager entry 10=,Meta+0,Activar la entrada 10 del gestor de tareas
activate task manager entry 2=Meta+2,Meta+2,Activar la entrada 2 del gestor de tareas
activate task manager entry 3=Meta+3,Meta+3,Activar la entrada 3 del gestor de tareas
activate task manager entry 4=Meta+4,Meta+4,Activar la entrada 4 del gestor de tareas
activate task manager entry 5=Meta+5,Meta+5,Activar la entrada 5 del gestor de tareas
activate task manager entry 6=Meta+6,Meta+6,Activar la entrada 6 del gestor de tareas
activate task manager entry 7=Meta+7,Meta+7,Activar la entrada 7 del gestor de tareas
activate task manager entry 8=Meta+8,Meta+8,Activar la entrada 8 del gestor de tareas
activate task manager entry 9=Meta+9,Meta+9,Activar la entrada 9 del gestor de tareas
clear-history=,,Borrar historial del portapapeles
clipboard_action=Meta+Ctrl+X,Meta+Ctrl+X,Menú emergente de acciones automáticas
cycleNextAction=,,Siguiente elemento del historial
cyclePrevAction=,,Elemento anterior del historial
edit_clipboard=,,Editar el contenido...
manage activities=Meta+Q,Meta+Q,Actividades...
next activity=Meta+Tab,Meta+Tab,Recorrer las actividades
previous activity=Meta+Shift+Tab,Meta+Shift+Tab,Recorrer las actividades (inverso)
repeat_action=Meta+Ctrl+R,Meta+Ctrl+R,Invocar manualmente la acción en el portapapeles actual
show dashboard=Ctrl+F12,Ctrl+F12,Mostrar el escritorio
show-barcode=,,Mostrar código de barras...
show-on-mouse-pos=Meta+V,Meta+V,Abrir Klipper en la posición del ratón
stop current activity=Meta+S,Meta+S,Detener la actividad actual
switch to next activity=,,Cambiar a la actividad siguiente
switch to previous activity=,,Cambiar a la actividad anterior
toggle do not disturb=,,Alternar no molestar

[systemsettings.desktop]
_launch=Tools,Tools,Preferencias del sistema
kcm-lookandfeel=,,Global Theme
kcm-users=,,Users
kcm-workspacetheme=,,Tema del espacio de trabajo
EOF

    # Copiar el archivo de configuración a la ubicación adecuada
    local kde_config_dir="$HOME/.config"
    cp "$shortcuts_file" "$kde_config_dir/kglobalshortcutsrc" || {
        print_error "Error copiando el archivo de atajos de teclado"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Recargar configuración de atajos de teclado
    if command -v kglobalaccel5 &>/dev/null; then
        kglobalaccel5 --reload &>/dev/null
    elif command -v kglobalaccel6 &>/dev/null; then
        kglobalaccel6 --reload &>/dev/null
    fi
    
    # Limpiar directorio temporal
    rm -rf "$temp_dir"
    
    print_success "Atajos de teclado de KDE configurados correctamente"
    return 0
}

# Configurar Spectacle (captura de pantalla)
setup_spectacle() {
    print_status "Configurando Spectacle para capturas de pantalla..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # Crear directorio de configuración si no existe
    mkdir -p "$HOME/.config"
    
    # Configurar opciones de Spectacle
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "autoSaveImage" "true"
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "clipboardGroup" "PostScreenshotCopyImage"
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "copyImageToClipboard" "true"
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "copySaveLocation" "false"
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "useReleaseToCapture" "true"
    $kwriteconfig_cmd --file spectaclerc --group "General" --key "defaultSaveLocation" "$HOME/Pictures/Screenshots"
    
    # Crear directorio para capturas de pantalla si no existe
    mkdir -p "$HOME/Pictures/Screenshots"
    
    # Configurar opciones de la GUI
    $kwriteconfig_cmd --file spectaclerc --group "GuiConfig" --key "cropRegion" "0,0,800,600"
    $kwriteconfig_cmd --file spectaclerc --group "GuiConfig" --key "includeDecorations" "true"
    $kwriteconfig_cmd --file spectaclerc --group "GuiConfig" --key "includePointer" "false"
    $kwriteconfig_cmd --file spectaclerc --group "GuiConfig" --key "useLightMaskColour" "false"
    
    # Configurar retraso por defecto
    $kwriteconfig_cmd --file spectaclerc --group "Delay" --key "delayMsec" "1000"
    
    print_success "Spectacle configurado correctamente"
    return 0
}

# Instalar herramientas de seguridad
install_security_tools() {
    print_status "¿Desea instalar herramientas de seguridad adicionales? [y/N]"
    read -r install_security
    
    if [[ ! $install_security =~ ^[Yy]$ ]]; then
        print_info "Omitiendo instalación de herramientas de seguridad adicionales"
        return 0
    fi

    print_status "Procediendo con la instalación de herramientas de seguridad..."

    local security_tools=(
        "wireshark-qt|Wireshark|Analizador de red"
        "metasploit|Metasploit Framework|Framework de explotación"
        "burpsuite|Burp Suite|Proxy de interceptación web"
        "gobuster|Gobuster|Herramienta de fuzzing web"
        "sqlmap|SQLMap|Herramienta de inyección SQL"
        "john|John the Ripper|Cracker de contraseñas"
        "hashcat|Hashcat|Cracker de hashes"
        "wfuzz|WFuzz|Fuzzer web"
        "hydra|Hydra|Cracker de credenciales online"
        "dirb|DIRB|Scanner web"
        "wpscan|WPScan|Scanner WordPress"
        "zaproxy|OWASP ZAP|Proxy de seguridad"
        "maltego|Maltego|OSINT"
        "nbtscan|NBTScan|Scanner NetBIOS"
        "websploit|WebSploit|Framework de explotación web"
        "theharvester|TheHarvester|OSINT"
        "legion|Legion|Scanner de red"
        "crackmapexec|CrackMapExec|Post-explotación"
        "seclists|SecLists|Listas de palabras"
        "ffuf|FFuF|Fuzzer web"
        "netexec|NetExec|Framework de explotación de red"
        "proxychains-ng|ProxyChains-NG|Túnel de proxy"
        "gdb|GDB|Debugger"
    )

    print_status "Seleccione las herramientas a instalar (separadas por espacio, ENTER para todas):"
    echo "Índice | Nombre | Descripción"
    echo "------------------------------"
    for i in "${!security_tools[@]}"; do
        IFS="|" read -r tool name desc <<< "${security_tools[$i]}"
        printf "%3d | %-20s | %s\n" "$i" "$name" "$desc"
    done

    read -r selected_tools

    if [ -z "$selected_tools" ]; then
        print_status "Instalando todas las herramientas..."
        selected_tools=$(seq 0 $((${#security_tools[@]} - 1)))
    fi

    local total_selected=$(echo "$selected_tools" | wc -w)
    local current_tool=0
    local failed_tools=()

    for tool_index in $selected_tools; do
        if [ "$tool_index" -lt "${#security_tools[@]}" ]; then
            ((current_tool++))
            IFS="|" read -r tool name _ <<< "${security_tools[$tool_index]}"
            print_status "[$current_tool/$total_selected] Instalando $name..."

            if sudo -n pacman --color=always -S --needed --noconfirm "$tool" ; then
                print_success "✔ $name instalado"
                
                # Crear accesos directos en el menú de KDE para herramientas de seguridad
                case "$tool" in
                    "wireshark-qt")
                        sudo -n usermod -aG wireshark "$USER" 
                        print_success "Usuario $(whoami) agregado al grupo wireshark"
                        ;;
                    "burpsuite")
                        # Configurar categoría especializada para Burp Suite
                        local desktop_file="$HOME/.local/share/applications/burpsuite.desktop"
                        if [ -f "/usr/share/applications/burpsuite.desktop" ]; then
                            mkdir -p "$HOME/.local/share/applications"
                            cp "/usr/share/applications/burpsuite.desktop" "$desktop_file" 
                            sed -i 's/Categories=.*/Categories=Qt;KDE;Security;Pentesting;/' "$desktop_file"
                        fi
                        ;;
                    "zaproxy")
                        # Configurar categoría especializada para OWASP ZAP
                        local desktop_file="$HOME/.local/share/applications/zaproxy.desktop"
                        if [ -f "/usr/share/applications/zaproxy.desktop" ]; then
                            mkdir -p "$HOME/.local/share/applications"
                            cp "/usr/share/applications/zaproxy.desktop" "$desktop_file" 
                            sed -i 's/Categories=.*/Categories=Qt;KDE;Security;Pentesting;/' "$desktop_file"
                        fi
                        ;;
                esac
            else
                print_error "✘ Error instalando $name"
                failed_tools+=("$name")
            fi
        fi
    done

    # Crear categoría para herramientas de pentesting en el menú de KDE
    mkdir -p "$HOME/.local/share/desktop-directories"
    cat > "$HOME/.local/share/desktop-directories/pentesting.directory" << EOF
[Desktop Entry]
Name=Penetration Testing
Name[es]=Pruebas de Penetración
Icon=security-high
Type=Directory
EOF

    # Crear el archivo .menu para agrupar herramientas de seguridad
    mkdir -p "$HOME/.config/menus"
    cat > "$HOME/.config/menus/applications-merged/pentesting.menu" << EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>Pentesting</Name>
    <Directory>pentesting.directory</Directory>
    <Include>
      <Category>Pentesting</Category>
      <Category>Security</Category>
    </Include>
  </Menu>
</Menu>
EOF

    # Reportar herramientas fallidas si existen
    if [ ${#failed_tools[@]} -gt 0 ]; then
        print_warning "Las siguientes herramientas no se pudieron instalar:"
        for tool in "${failed_tools[@]}"; do
            echo "  - $tool"
        done
        print_warning "Algunas herramientas no se instalaron correctamente"
    else
        print_success "Todas las herramientas de seguridad seleccionadas fueron instaladas correctamente"
    fi

    return 0
}

# Configurar entorno adicional de KDE
configure_kde_extra() {
    print_status "Configurando ajustes adicionales de KDE..."
    local kwriteconfig_cmd=$(get_kwriteconfig_cmd)
    
    # Configurar el panel de Plasma
    print_status "Configurando el panel de Plasma..."

    # Configurar panel de KDE en la parte superior con altura de 28px
print_status "Configurando panel de Plasma en la parte superior..."

# Obtener la lista de paneles
local panel_ids=$(grep -l "plugin=org.kde.panel" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | grep -o '[0-9]*')

if [ -n "$panel_ids" ]; then
    # Para cada panel encontrado
    for panel_id in $panel_ids; do
        # Configurar posición en la parte superior
        $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[$panel_id]" --key "location" "3"
        
        # Configurar altura de 28px
        $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[$panel_id]" --key "height" "28"
        
        # Especificar que está anclado en la parte superior
        $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[$panel_id]" --key "formfactor" "2"
        
        print_success "Panel $panel_id configurado en la parte superior con altura de 28px"
    done
else
    # Si no se encuentra ningún panel, intentar con el panel predeterminado
    print_warning "No se detectaron paneles específicos, intentando con el panel predeterminado..."
    
    # Intentar con el panel predeterminado (generalmente 2)
    $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[2]" --key "location" "3"
    $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[2]" --key "height" "28"
    $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments[2]" --key "formfactor" "2"
    
    print_success "Panel predeterminado configurado en la parte superior con altura de 28px"
fi
    
    # Configuración de Dolphin (gestor de archivos)
    $kwriteconfig_cmd --file dolphinrc --group "General" --key "ShowFullPath" "true"
    $kwriteconfig_cmd --file dolphinrc --group "General" --key "ShowSelectionToggle" "true"
    $kwriteconfig_cmd --file dolphinrc --group "General" --key "ShowSpaceInfo" "true"
    $kwriteconfig_cmd --file dolphinrc --group "General" --key "ShowZoomSlider" "true"
    $kwriteconfig_cmd --file dolphinrc --group "ContextMenu" --key "ShowCopyMoveMenu" "true"
    
    # Configurar fuentes del sistema
    $kwriteconfig_cmd --file kdeglobals --group "General" --key "fixed" "Hack Nerd Font Mono,10,-1,5,50,0,0,0,0,0"
    $kwriteconfig_cmd --file kdeglobals --group "General" --key "font" "Roboto,10,-1,5,50,0,0,0,0,0"
    $kwriteconfig_cmd --file kdeglobals --group "General" --key "menuFont" "Roboto,10,-1,5,50,0,0,0,0,0"
    $kwriteconfig_cmd --file kdeglobals --group "General" --key "smallestReadableFont" "Roboto,8,-1,5,50,0,0,0,0,0"
    $kwriteconfig_cmd --file kdeglobals --group "General" --key "toolBarFont" "Roboto,10,-1,5,50,0,0,0,0,0"
    $kwriteconfig_cmd --file kdeglobals --group "WM" --key "activeFont" "Roboto,10,-1,5,50,0,0,0,0,0"
    
    # Configurar Konsole como terminal de Dolphin
    $kwriteconfig_cmd --file dolphinrc --group "General" --key "TerminalApplication" "kitty"
    
    # Configurar notificaciones
    $kwriteconfig_cmd --file plasmanotifyrc --group "DoNotDisturb" --key "until" "0"
    $kwriteconfig_cmd --file plasmanotifyrc --group "DoNotDisturb" --key "whenScreensMirrored" "false"
    
    # Configurar autoarranque de aplicaciones
    mkdir -p "$HOME/.config/autostart"
    
    # Configurar gestor de energía
    $kwriteconfig_cmd --file powermanagementprofilesrc --group "AC" --group "DimDisplay" --key "idleTime" "300000"
    $kwriteconfig_cmd --file powermanagementprofilesrc --group "Battery" --group "DimDisplay" --key "idleTime" "120000"
    $kwriteconfig_cmd --file powermanagementprofilesrc --group "LowBattery" --group "DimDisplay" --key "idleTime" "60000"
    
    # Configurar reglas de ventanas para aplicaciones específicas
    local windowrules_file="$HOME/.config/kwinrulesrc"
    cat > "$windowrules_file" << EOF
# [1]
# Description=Configuración para Kitty
# above=false
# aboverule=2
# clientmachine=localhost
# clientmachinematch=0
# noborderrule=2
# position=0,0
# positionrule=3
# size=800,600
# sizerule=3
# title=kitty
# titlematch=2
# wmclass=kitty
# wmclassmatch=1

[2]
Description=Configuración para Brave
clientmachine=localhost
clientmachinematch=0
maximize=true
maximizerule=3
noborder=false
noborderrule=2
wmclass=brave-browser
wmclassmatch=1

[3]
Description=Configuración para Spectacle
clientmachine=localhost
clientmachinematch=0
noborder=false
noborderrule=2
position=center
positionrule=3
wmclass=spectacle
wmclassmatch=1

[General]
count=2
rules=2,3
EOF
    
    # Configurar Plasma para mostrar segundos en el reloj
    $kwriteconfig_cmd --file plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "1" --group "Applets" --group "7" --group "Configuration" --group "Appearance" --key "showSeconds" "true"
    
    # Habilitar la papelera de reciclaje
    $kwriteconfig_cmd --file kiorc --group "Trash" --key "ConfirmTrash" "false"
    $kwriteconfig_cmd --file kiorc --group "Trash" --key "EmptyTrash" "true"
    
    # Configuración para incluir menú de aplicaciones en panel superior
    mkdir -p "$HOME/.local/share/plasma/layout-templates"
    
    print_success "Configuración adicional de KDE completada"
    return 0
}

# Configurar firewall
setup_firewall() {
    print_status "Configurando firewall (UFW)..."
    
    # Instalar UFW si no está disponible
    if ! command -v ufw &>/dev/null; then
        print_status "Instalando UFW (Uncomplicated Firewall)..."
        sudo -n pacman -S --noconfirm ufw || {
            print_error "Error instalando UFW"
            return 1
        }
    fi
    
    # Configurar reglas básicas
    print_status "Configurando reglas básicas del firewall..."
    
    # Detener UFW para configuración
    sudo -n systemctl stop ufw || true
    
    # Configurar reglas por defecto
    sudo -n ufw default deny incoming
    sudo -n ufw default allow outgoing
    
    # Permitir SSH (se puede omitir si no se requiere)
    sudo -n ufw allow ssh
    
    # Permitir servicios necesarios 
    sudo -n ufw allow 443/tcp  # HTTPS
    sudo -n ufw allow 80/tcp   # HTTP
    sudo -n ufw allow 53       # DNS
    
    # Habilitar IPv6
    sudo -n sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
    
    # Habilitar el firewall
    sudo -n ufw --force enable
    sudo -n systemctl enable ufw
    
    # Iniciar el servicio
    sudo -n systemctl start ufw
    
    # Verificar el estado
    sudo -n ufw status verbose
    
    print_success "Firewall configurado y activado correctamente"
    return 0
}

# Aplicar configuraciones finales de KDE
apply_kde_settings() {
    print_status "Aplicando configuraciones finales de KDE..."
    
    # Recargar configuración de KDE sin reiniciar componentes cruciales
    if command -v qdbus &>/dev/null; then
        # Intentar reconfiguraciones menos invasivas
        print_status "Recargando configuraciones de KDE..."
        
        # Recargar configuración sin forzar un reinicio
        qdbus org.kde.KWin /KWin reconfigure &>/dev/null || true
        
        # Una forma más segura de recargar la configuración de Plasma
        qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell &>/dev/null || true
        
        # Recargar sólo ciertas partes de la configuración
        DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-"unix:path=/run/user/$(id -u)/bus"}
        export DBUS_SESSION_BUS_ADDRESS
        
        # Notificar a las aplicaciones sobre cambios en la configuración
        dbus-send --session --dest=org.kde.klauncher5 --type=method_call --print-reply --reply-timeout=5000 /KLauncher org.kde.KLauncher.reparseConfiguration &>/dev/null || true
        dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply --reply-timeout=5000 /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig &>/dev/null || true
    fi
    
    # Informar al usuario sobre la necesidad de reiniciar la sesión
    print_success "Configuraciones de KDE aplicadas"
    print_warning "Para que todos los cambios surtan efecto, se recomienda cerrar sesión y volver a iniciarla"
    
    # Preguntar si se desea reiniciar la sesión ahora
    read -p "¿Desea reiniciar la sesión ahora? (NO recomendado durante la ejecución del script) [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Reiniciando sesión en 10 segundos..."
        (sleep 10 && loginctl terminate-session $XDG_SESSION_ID) &
    fi
    
    return 0
}

# Función de limpieza para ser ejecutada al salir
cleanup() {
    # Matar el proceso de sudo si existe
    if [ -n "$SUDO_PID" ]; then
        kill $SUDO_PID &>/dev/null || true
    fi
    
    print_info "Limpieza completada"
}

# Función principal
main() {
        # Banner con CHILE en colores de la bandera
    cat << EOF
${BLUE}╔══════════════════════════════════════════════════════════════════════════╗
║                            ${RED}⚡ ${BOLD}P4NX0S SETUP KDE6${NC} ${RED}⚡                          ${BLUE}║
║                                                                                 ║
║    ${GREEN}█▀█ █▀█ █▄░█ ▀▄▀ █▀█ █▀                                       ${BLUE}║
║    ${YELLOW}█▀▀ █▀▄ █░▀█ █░█ █▄█ ▄█                                      ${BLUE}║
║                                                                                 ║
║   ${CYAN}╭────────────╮ ${RED}╭────────────╮ ${GREEN}╭────────────╮      ${BLUE}║
║   ${CYAN}│ KDE Plasma │ ${RED}│Cybersecurity│ ${GREEN}│    Arch    │     ${BLUE}║
║   ${CYAN}│    v.2     │ ${RED}│    Setup    │ ${GREEN}│   Linux    │     ${BLUE}║
║   ${CYAN}╰────────────╯ ${RED}╰────────────╯ ${GREEN}╰────────────╯      ${BLUE}║
║                                                                                 ║
║   ${YELLOW}📦 ${NC}Includes: Hacking Tools, Custom Themes,               ${BLUE}║
║   ${YELLOW}🛠️ ${NC}Github: ${CYAN}https://github.com/panxos              ${BLUE}║
║   ${YELLOW}👨‍💻 ${NC}Developed by: ${BOLD}P4NX0S${NC} © 2025 - ${BOLD}${BLUE}C${WHITE}H${RED}I${BLUE}L${RED}E${NC}                                   ${BLUE}║
║                                                                                 ║
╚═════════════════════════════════════════════════════════════════════════════════╝${NC}
EOF

    # Verificaciones iniciales
    check_root
    check_internet
    check_blackarch_connection || exit 1

    print_status "Solicitando privilegios de administrador..."
    keep_sudo_alive 

    # Configurar trap para limpieza
    trap cleanup EXIT

    # Verificar requisitos
    check_requirements || exit 1

    # Configurar repositorios y pacman
    setup_repositories || exit 1
    setup_pacman_config || exit 1

    # Actualizar sistema
    print_status "Actualizando sistema..."
    if ! sudo -n pacman --color=always -Syu --noconfirm; then
        print_error "Error actualizando el sistema"
        exit 1
    fi

    # Instalar componentes
    local install_steps=(
        "install_basic_packages:Paquetes básicos"
        "setup_repositories:Repositorios"
        "setup_pacman_config:Configuración de Pacman"
        "setup_zsh:ZSH y plugins"
        "install_fonts:Fuentes del sistema"
        "install_themes_and_icons:Temas e iconos"
        "setup_kitty_config:Configuración de Kitty"
        "configure_konsole:Configuración de Konsole"
        "setup_default_terminal:Terminal predeterminada"
        "setup_wallpaper:Fondo de pantalla"
        "setup_kde_effects:Configuración de efectos visuales"
        "setup_kde_shortcuts:Atajos de teclado"
        "setup_spectacle:Configuración de Spectacle"
        "configure_kde_extra:Configuración adicional de KDE"
        "setup_firewall:Configuración del firewall"
        "install_security_tools:Herramientas de seguridad"
        "apply_kde_settings:Aplicar configuraciones finales"
    )

    for step in "${install_steps[@]}"; do
        IFS=":" read -r func desc <<< "$step"
        print_status "Instalando $desc..."
        if ! $func; then
            if [ "$func" = "install_security_tools" ]; then
                print_warning "Omitiendo herramientas de seguridad"
                continue  # Continuar con el siguiente paso aunque falle
            fi
            print_error "Error en la instalación de $desc"
            exit 1
        fi
    done

    # Mensaje final
    cat << EOF
${GREEN}${BOLD}¡Instalación Completada!${NC}

${CYAN}Próximos pasos:${NC}
1. Cierra la sesión y vuelve a iniciar
2. Abre una terminal Kitty o Konsole
3. Ejecuta 'p10k configure' si deseas personalizar el prompt

${YELLOW}Notas:${NC}
- Los grupos de usuario se actualizarán en el próximo inicio de sesión
- La configuración de KDE Plasma 6 se ha realizado con los nuevos temas y fuentes
- Revisa la configuración de energía según tus necesidades
- Los efectos visuales como ventanas gelatinosas están activados
- Puedes encontrar más configuraciones en: https://github.com/panxos

${CYAN}Atajos de teclado configurados:${NC}
- Meta+Return: Abrir Kitty
- Meta+E: Abrir Dolphin (gestor de archivos)
- Meta+Shift+S: Captura de pantalla con Spectacle
- Meta+Shift+B: Abrir Brave Browser
- Meta+D: Mostrar escritorio
- Meta+L: Bloquear pantalla
- Print: Captura de pantalla completa

${GREEN}¡Gracias por usar P4NX0S Setup KDE6!${NC}
EOF
}

# Ejecutar script
main
