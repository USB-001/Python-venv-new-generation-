!/bin/bash

# ==============================================================================
#                 INSTALLATEUR COMPLET & GESTIONNAIRE VENV
# ==============================================================================

# Variables de configuration
CORRECTION_FILE="/tmp/corrections.json"
CURRENT_USER=$(whoami)

# Fonctions pour les messages stylisés
print_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}
print_success() {
    echo -e "\e[32m[SUCCÈS]\e[0m $1"
}
print_error() {
    echo -e "\e[31m[ERREUR]\e[0m $1"
}

# Fonction pour incrémenter le compteur de corrections (dans un fichier temporaire)
increment_corrections_count() {
    if [ ! -f "$CORRECTION_FILE" ]; then
        echo "{\"count\": 0}" > "$CORRECTION_FILE"
    fi
    local current_count
    current_count=$(jq '.count' "$CORRECTION_FILE" 2>/dev/null)
    if [ -z "$current_count" ]; then
        current_count=0
    fi
    local new_count=$((current_count + 1))
    jq ".count = $new_count" "$CORRECTION_FILE" > "$CORRECTION_FILE.tmp" && mv "$CORRECTION_FILE.tmp" "$CORRECTION_FILE"
    print_info "Correction #$new_count appliquée."
}

# Fonction pour vérifier et installer les dépendances du système
install_system_dependencies() {
    print_info "Vérification et installation des dépendances système..."
    local pkgs_to_check=("jq" "python3" "realpath" "python3-venv")
    local pkgs_to_install=()

    for pkg in "${pkgs_to_check[@]}"; do
        if [ "$pkg" == "python3-venv" ] && ! dpkg -l | grep -q python3-venv; then
             pkgs_to_install+=("$pkg")
        elif ! command -v "$pkg" &>/dev/null && [ "$pkg" != "python3-venv" ]; then
            pkgs_to_install+=("$pkg")
        fi
    done

    if [ ${#pkgs_to_install[@]} -ne 0 ]; then
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get update > /dev/null 2>&1
                sudo apt-get install -y "${pkgs_to_install[@]}" > /dev/null 2>&1
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y "${pkgs_to_install[@]}" > /dev/null 2>&1
            elif command -v yum &>/dev/null; then
                sudo yum install -y "${pkgs_to_install[@]}" > /dev/null 2>&1
            fi
        fi
    fi
    print_success "Dépendances du système installées avec succès."
}

# Fonction pour effectuer une installation propre
clean_installation() {
    read -p "Voulez-vous effectuer une installation propre et supprimer les anciennes configurations pour tous les utilisateurs ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Démarrage du nettoyage des anciennes configurations..."
        local users=$(cut -d: -f1,6 /etc/passwd | awk -F: '$2 ~ /^\/home\// {print $1}')
        for user in $users; do
            local home_dir=$(getent passwd "$user" | cut -d: -f6)
            local venv_dir="$home_dir/.venv_system"
            if [ -d "$venv_dir" ]; then
                print_info "Suppression de $venv_dir pour l'utilisateur $user..."
                sudo rm -rf "$venv_dir"
            fi
        done
        print_success "Nettoyage terminé."
    fi
}

# Fonction pour installer les dépendances Python du système Venv
install_python_dependencies() {
    print_info "Création de l'environnement virtuel pour le système Venv..."
    local VENV_SYSTEM_ENV_DIR="$VENV_SYSTEM_DIR/venv_system_env"
    if [ ! -d "$VENV_SYSTEM_ENV_DIR" ]; then
        sudo -u "$CURRENT_USER" python3 -m venv "$VENV_SYSTEM_ENV_DIR"
        print_success "Environnement virtuel du système Venv créé."
    else
        print_info "Environnement virtuel du système Venv déjà existant."
    fi

    print_info "Installation des dépendances Python (rich, colorama)..."
    local VENV_PIP="$VENV_SYSTEM_ENV_DIR/bin/pip"
    local DEPENDENCIES=("rich" "colorama")

    for dep in "${DEPENDENCIES[@]}"; do
        if sudo -u "$CURRENT_USER" "$VENV_PIP" install "$dep" > /dev/null 2>&1; then
            print_success "Module '$dep' installé."
        else
            print_error "Échec de l'installation de '$dep'. Veuillez la vérifier manuellement."
            exit 1
        fi
    done
}

# Fonction pour installer tous les fichiers et scripts pour un utilisateur spécifique
install_for_user() {
    local USER="$1"
    local HOME_DIR="$2"
    local VENV_SYSTEM_DIR="$HOME_DIR/.venv_system"
    local VENV_CONFIG_DIR="$VENV_SYSTEM_DIR/config"
    local VENV_PROJECTS_DIR="$VENV_SYSTEM_DIR/projects"
    local VENV_COMMANDS_DIR="$VENV_SYSTEM_DIR/commands"

    print_info "Configuration de Venv pour l'utilisateur: $USER"

    # Création de la structure de dossiers et des fichiers de config
    sudo -u "$USER" mkdir -p "$VENV_COMMANDS_DIR" "$VENV_CONFIG_DIR" "$VENV_PROJECTS_DIR"

    if [ ! -f "$VENV_CONFIG_DIR/global.json" ]; then
        echo "{\"active_project\": \"\", \"python_default\": \"python3\"}" | sudo -u "$USER" tee "$VENV_CONFIG_DIR/global.json" > /dev/null
    fi
    sudo chown -R "$USER:$USER" "$VENV_SYSTEM_DIR"
    print_success "Structure de dossiers créée pour $USER."

    # Installation du script 'menu'
    local MENU_SCRIPT_CONTENT=$(cat << 'EOF'
#!/usr/bin/env python3
import os
import json
import subprocess
from rich.console import Console
from rich.table import Table
from rich.prompt import Prompt
from rich.text import Text
from rich.style import Style
from rich import print as rprint

console = Console()
VENV_SYSTEM_DIR = os.path.expanduser("~/.venv_system")
VENV_PROJECTS_DIR = os.path.join(VENV_SYSTEM_DIR, "projects")
GLOBAL_CONFIG_FILE = os.path.join(VENV_SYSTEM_DIR, "config", "global.json")

def load_global_config():
    with open(GLOBAL_CONFIG_FILE, "r") as f:
        return json.load(f)

def save_global_config(config):
    with open(GLOBAL_CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)

def load_project_config(project_name):
    project_path = os.path.join(VENV_PROJECTS_DIR, project_name, "project.json")
    if not os.path.exists(project_path):
        return {"python_version": "", "description": ""}
    with open(project_path, "r") as f:
        return json.load(f)

def save_project_config(project_name, config):
    project_dir = os.path.join(VENV_PROJECTS_DIR, project_name)
    os.makedirs(project_dir, exist_ok=True)
    project_path = os.path.join(project_dir, "project.json")
    with open(project_path, "w") as f:
        json.dump(config, f, indent=4)

def get_projects():
    projects = {}
    if os.path.exists(VENV_PROJECTS_DIR):
        for item in os.listdir(VENV_PROJECTS_DIR):
            item_path = os.path.join(VENV_PROJECTS_DIR, item)
            if os.path.isdir(item_path):
                projects[item] = load_project_config(item)
    return projects

def display_main_menu(active_project):
    table = Table(title=Text("Menu des Projets Venv", style="bold cyan"), show_header=True, header_style=Style(color="blue", bold=True))
    table.add_column("ID", style="dim", width=4)
    table.add_column("Nom du Projet", style="bold")
    table.add_column("Description", style="italic")

    projects = get_projects()
    project_names = sorted(projects.keys())

    for i, name in enumerate(project_names):
        config = projects[name]
        status_symbol = "[green]●" if name == active_project else "[red]○"
        description = config.get("description", "Aucune description")
        table.add_row(f"[bold]{i+1}", f"{status_symbol} {name}", description)

    console.print(table)

    rprint("\n[bold green]Options:[/bold green]")
    rprint("  [magenta]s[/magenta] : Sélectionner un projet")
    rprint("  [magenta]n[/magenta] : Nouveau projet")
    rprint("  [magenta]q[/magenta] : Quitter")
    choice = Prompt.ask("Entrez votre choix")

    if choice == "q":
        return None
    elif choice == "s":
        try:
            project_id = int(Prompt.ask("Entrez l'ID du projet à sélectionner"))
            if 0 < project_id <= len(project_names):
                project_name = project_names[project_id - 1]
                config = load_global_config()
                config["active_project"] = project_name
                save_global_config(config)
                rprint(f"[bold green]Projet '{project_name}' sélectionné.[/bold green]")
                return project_name
            else:
                rprint("[bold red]Erreur:[/bold red] ID de projet invalide.")
                return display_main_menu(active_project)
        except (ValueError, IndexError):
            rprint("[bold red]Erreur:[/bold red] ID de projet invalide.")
            return display_main_menu(active_project)
    elif choice == "n":
        new_project_name = Prompt.ask("Entrez le nom du nouveau projet")
        if not new_project_name:
            rprint("[bold red]Erreur:[/bold red] Le nom du projet ne peut pas être vide.")
            return display_main_menu(active_project)
        config = load_global_config()
        config["active_project"] = new_project_name
        save_global_config(config)
        rprint(f"[bold green]Projet '{new_project_name}' créé et activé.[/bold green]")
        return new_project_name
    else:
        rprint("[bold red]Erreur:[/bold red] Choix invalide.")
        return display_main_menu(active_project)

def display_project_menu(project_name):
    config = load_project_config(project_name)
    rprint(f"\n[bold green]Gestion du Projet '{project_name}'[/bold green]")
    rprint(f"  Version Python: [cyan]{config.get('python_version', 'Non spécifiée')}[/cyan]")
    rprint(f"  Chemin du venv: [cyan]~/.venv_system/projects/{project_name}/venv[/cyan]")

    rprint("\n[bold green]Options:[/bold green]")
    rprint("  [magenta]1[/magenta] : Modifier la version de Python")
    rprint("  [magenta]2[/magenta] : Gérer la description")
    rprint("  [magenta]3[/magenta] : Renommer le projet")
    rprint("  [magenta]4[/magenta] : Supprimer le projet")
    rprint("  [magenta]5[/magenta] : Revenir au menu principal")
    choice = Prompt.ask("Entrez votre choix")

    if choice == "1":
        new_version = Prompt.ask("Entrez la nouvelle version de Python (ex: python3.9)")
        config["python_version"] = new_version
        save_project_config(project_name, config)
        rprint("[bold green]Version de Python mise à jour.[/bold green]")
        display_project_menu(project_name)
    elif choice == "2":
        new_desc = Prompt.ask("Entrez la nouvelle description")
        config["description"] = new_desc
        save_project_config(project_name, config)
        rprint("[bold green]Description mise à jour.[/bold green]")
        display_project_menu(project_name)
    elif choice == "3":
        new_name = Prompt.ask("Entrez le nouveau nom du projet")
        os.rename(os.path.join(VENV_PROJECTS_DIR, project_name), os.path.join(VENV_PROJECTS_DIR, new_name))
        global_config = load_global_config()
        if global_config.get("active_project") == project_name:
            global_config["active_project"] = new_name
            save_global_config(global_config)
        rprint("[bold green]Projet renommé avec succès.[/bold green]")
        run()
    elif choice == "4":
        confirm = Prompt.ask(f"[bold red]Êtes-vous sûr de vouloir supprimer le projet '{project_name}' et son environnement? (o/n)[/bold red]", default="n")
        if confirm.lower() == "o":
            os.system(f"rm -rf {os.path.join(VENV_PROJECTS_DIR, project_name)}")
            global_config = load_global_config()
            if global_config.get("active_project") == project_name:
                global_config["active_project"] = ""
                save_global_config(global_config)
            rprint("[bold green]Projet supprimé.[/bold green]")
            run()
        else:
            display_project_menu(project_name)
    elif choice == "5":
        run()
    else:
        rprint("[bold red]Choix invalide.[/bold red]")
        display_project_menu(project_name)

def run():
    try:
        global_config = load_global_config()
    except FileNotFoundError:
        rprint("[bold red]Erreur:[/bold red] Fichier de configuration global manquant. Veuillez exécuter 'installateur_venv.sh' d'abord.")
        return

    active_project = global_config.get("active_project")

    while True:
        choice = display_main_menu(active_project)
        if choice is None:
            break

        active_project = choice
        display_project_menu(active_project)

if __name__ == "__main__":
    run()
EOF
)
    echo "$MENU_SCRIPT_CONTENT" | sudo -u "$USER" tee "$VENV_COMMANDS_DIR/menu" > /dev/null
    sudo -u "$USER" chmod +x "$VENV_COMMANDS_DIR/menu"
    print_success "Script 'menu' installé pour $USER."

    # Installation du script 'help'
    local HELP_SCRIPT_CONTENT=$(cat << 'EOF'
#!/usr/bin/env python3
import os
import json
from rich.console import Console
from rich.text import Text
from rich.panel import Panel
from rich.table import Table
from rich.style import Style
from rich import print as rprint

console = Console()
VENV_SYSTEM_DIR = os.path.expanduser("~/.venv_system")
VENV_COMMANDS_DIR = os.path.join(VENV_SYSTEM_DIR, "commands")

def get_command_help():
    help_text = Text("\nUsage: venv <command> [OPTIONS]\n\n", style="bold")

    command_data = {
        "venv": {
            "description": "Commande principale pour gérer les environnements virtuels.",
            "options": [
                ("-h, --help", "Affiche ce menu d'aide."),
                ("-m, --menu", "Lance le menu interactif de gestion de projets."),
                ("-s, --select", "Sélectionne le répertoire de travail actuel et le lie au système Venv.")
            ]
        },
        "activate": {
            "description": "Active l'environnement virtuel du projet actif.",
            "options": []
        },
        "deactivate": {
            "description": "Désactive l'environnement virtuel en cours.",
            "options": []
        },
        "project": {
            "description": "Gère le projet actif ou un projet spécifique.",
            "options": [
                ("[project_name]", "Définit le projet spécifié comme actif. Crée le projet s'il n'existe pas."),
                ("-c, --create", "Crée un nouveau projet (nécessite un nom)."),
                ("-d, --delete", "Supprime un projet existant (nécessite un nom).")
            ]
        },
        "status": {
            "description": "Affiche l'état du projet actif.",
            "options": []
        }
    }

    rprint(help_text)

    for cmd_name, data in command_data.items():
        table = Table(title=Text(f"Commande: {cmd_name}", style="bold cyan"), show_header=True, header_style=Style(color="blue", bold=True))
        table.add_column("Option/Paramètre", style="dim", no_wrap=True)
        table.add_column("Description", style="italic")

        for opt, desc in data["options"]:
            table.add_row(opt, desc)

        rprint(Panel(table, title=data["description"], border_style="green"))

if __name__ == "__main__":
    get_command_help()
EOF
)
    echo "$HELP_SCRIPT_CONTENT" | sudo -u "$USER" tee "$VENV_COMMANDS_DIR/help" > /dev/null
    sudo -u "$USER" chmod +x "$VENV_COMMANDS_DIR/help"
    print_success "Script 'help' installé pour $USER."

    # Installation des commandes alias
    local commands=("activate" "deactivate" "project" "status")
    for cmd in "${commands[@]}"; do
        local alias_script="#!/bin/bash\nexec /usr/local/bin/venv -- $cmd \"\$@\""
        echo -e "$alias_script" | sudo -u "$USER" tee "$VENV_COMMANDS_DIR/$cmd" > /dev/null
        sudo -u "$USER" chmod +x "$VENV_COMMANDS_DIR/$cmd"
    done

    print_success "Commandes d'environnement installées pour $USER."
    print_success "Installation terminée pour l'utilisateur $USER."
}

# Fonction principale
main() {
    print_info "Lancement de l'installation complète du système Venv..."
    increment_corrections_count

    clean_installation

    install_system_dependencies

    # Création de l'environnement virtuel du système Venv une seule fois
    local VENV_SYSTEM_DIR="$HOME/.venv_system"
    install_python_dependencies

    # Installation de la commande principale 'venv' dans un emplacement global
    install_venv_command

    # Installation pour tous les utilisateurs du système
    print_info "Début de l'installation pour tous les utilisateurs du système."
    local users=$(cut -d: -f1,6 /etc/passwd | awk -F: '$2 ~ /^\/home\// {print $1 " " $2}')
    if [ -z "$users" ]; then
        print_error "Aucun utilisateur avec un répertoire /home/ trouvé."
        exit 1
    fi

    while read -r user home_dir; do
        if [ "$user" == "root" ]; then
            print_info "Ignorant l'utilisateur root."
            continue
        fi
        install_for_user "$user" "$home_dir"
    done <<< "$users"

    print_success "Installation complète terminée pour tous les utilisateurs! Redémarrez votre terminal."
}

# Exécute la fonction principale
main
        if [ ! -f "$venv_config_dir/global.json" ]; then
            print_log "INFO" "Restauration de la configuration pour l'utilisateur '$user'."
            echo '{"active_project": "", "python_default": "python3"}' | sudo -u "$user" tee "$venv_config_dir/global.json" >/dev/null
        fi
        
        sudo chown -R "$user:$user" "$venv_user_dir"
        print_log "SUCCESS" "Configuration initiale terminée pour '$user'."
    done
}

# Fonction principale de l'installateur
main_installer() {
    if [ "$EUID" -ne "$ROOT_UID" ]; then
        print_log "ERROR" "Le script doit être exécuté avec des privilèges root (sudo)."
        exit 1
    fi
    
    print_log "INFO" "Lancement de l'installateur venv..."
    
    if ! install_system_dependencies; then
        print_log "ERROR" "Impossible de continuer sans les dépendances nécessaires."
        exit 1
    fi
    
    print_log "INFO" "Installation du binaire principal $VENV_BIN_PATH..."
    # Utilisation d'une "heredoc" pour inclure le code du binaire dans le script d'installation.
    local venv_script_content
    read -r -d '' venv_script_content <<'EOF'
#!/usr/bin/env bash
# ==============================================================================
#                  /usr/local/bin/venv - GESTIONNAIRE D'ENVIRONNEMENTS VIRTUELS PYTHON
# ==============================================================================
# Auteur : Gemini
# Version : 1.0.0
# Licence : MIT
# Description : Un gestionnaire complet et centralisé pour les environnements
#               virtuels Python.
#
# ==============================================================================

set -Eeuo pipefail

# Empêche l'expansion de nom de fichier
IFS=$'\n\t'

# ==============================================================================
# GLOBAL CONFIGURATION & VARIABLES
# ==============================================================================

# Chemins
readonly VENV_HOME="${VENV_HOME:-$HOME/.venv_system}"
readonly VENV_PROJECTS_DIR="${VENV_PROJECTS_DIR:-$VENV_HOME/projects}"
readonly VENV_CONFIG_DIR="$VENV_HOME/config"
readonly VENV_BACKUPS_DIR="$VENV_HOME/backups"
readonly VENV_CACHE_DIR="$VENV_HOME/cache"
readonly VENV_GLOBAL_CONFIG_FILE="${VENV_CONFIG_FILE:-$VENV_CONFIG_DIR/global.json}"
readonly VENV_HOOKS_DIR="$VENV_HOME/hooks"
readonly VENV_LOG_FILE="$VENV_CACHE_DIR/venv.log"
readonly VENV_BIN_PATH="/usr/local/bin/venv"

# Options et états
DRY_RUN=false
YES=false
IS_ROOT=false
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
fi

# Couleurs et styles
NO_COLOR="${NO_COLOR-}"
if [[ -z "${NO_COLOR}" && -t 1 ]]; then
    readonly C_RED='\e[31m'
    readonly C_GREEN='\e[32m'
    readonly C_YELLOW='\e[33m'
    readonly C_BLUE='\e[34m'
    readonly C_CYAN='\e[36m'
    readonly C_BOLD='\e[1m'
    readonly C_RESET='\e[0m'
else
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_BLUE=''
    readonly C_CYAN=''
    readonly C_BOLD=''
    readonly C_RESET=''
fi

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local color=""
    local log_file_path="$VENV_LOG_FILE"

    case "$level" in
        "INFO") color="${C_BLUE}";;
        "WARN") color="${C_YELLOW}";;
        "ERROR") color="${C_RED}";;
        "SUCCESS") color="${C_GREEN}";;
        "DEBUG") color="${C_CYAN}";;
        *) color="${C_RESET}";;
    esac

    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file_path")"

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$log_file_path"

    # Log to stdout
    echo -e "${color}[$level]${C_RESET} $message"
}

# Demande une confirmation
ask_confirm() {
    local prompt="$1"
    if [ "$YES" == true ]; then
        return 0
    fi
    read -p "$prompt [y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

# Fonctions de gestion de la configuration
get_config_value() {
    local key="$1"
    local config_file="$VENV_GLOBAL_CONFIG_FILE"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    jq -r ".$key" "$config_file" 2>/dev/null || {
        log_message "ERROR" "Erreur de lecture de la clé '$key' dans la configuration."
        return 1
    }
}

set_config_value() {
    local key="$1"
    local value="$2"
    local config_file="$VENV_GLOBAL_CONFIG_FILE"
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Modification de la configuration : '$key' = '$value'"
        return 0
    fi
    local current_config
    if [ ! -f "$config_file" ]; then
        current_config='{}'
    else
        current_config=$(cat "$config_file")
    fi
    local new_config
    new_config=$(echo "$current_config" | jq --arg k "$key" --arg v "$value" '.[$k] = $v' 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_message "ERROR" "La modification de la configuration a échoué pour la clé '$key'."
        return 1
    fi
    echo "$new_config" > "$config_file"
    log_message "SUCCESS" "Configuration mise à jour : '$key' = '$value'"
    return 0
}

# Exécute un hook
run_hook() {
    local hook_name="$1"
    local hook_path="$VENV_HOOKS_DIR/$hook_name"
    if [ -f "$hook_path" ] && [ -x "$hook_path" ]; then
        log_message "INFO" "Exécution du hook : $hook_path"
        "$hook_path" "${@:2}"
    fi
}
# ==============================================================================
# COMMANDES DU BINAIRE PRINCIPAL
# ==============================================================================

# Sous-commande : help
cmd_help() {
    cat << EOF
Utilisation: venv [options] <commande> [arguments]

Options globales:
  --yes, -y       Passe les confirmations de sécurité.
  --dry-run       Affiche les actions sans les exécuter.
  --quiet, -q     Réduit la verbosité des messages.

Commandes:
  help                             Affiche cette aide.
  status                           Affiche l'état du projet actif.
  list                             Liste tous les projets venv.
  project create <name> [--python <bin>]  Crée un nouveau projet.
  project select <name>            Sélectionne un projet comme actif.
  project delete <name> [--yes]    Supprime un projet.
  activate                         Affiche la commande d'activation.
  deactivate                       Affiche la commande de désactivation.
  install [-r <file>] [pkg ...]    Installe des paquets dans le venv actif.
  freeze [--output file]           Exporte les dépendances du venv actif.
  purge <name> [--yes]             Supprime le venv d'un projet.
  python set <bin>                 Définit la version de Python par défaut.
  config show                      Affiche la configuration effective.
  config set <key> <value>         Modifie la configuration globale.
  open <name>                      Ouvre le dossier d'un projet.
  doctor                           Exécute une série de diagnostics.
  uninstall                        Désinstalle le gestionnaire venv.
EOF
}

# Sous-commande : status
cmd_status() {
    local active_project
    active_project=$(get_config_value 'active_project')
    local python_default=$(get_config_value 'python_default')

    echo "=========================================="
    echo "Statut du système Venv"
    echo "=========================================="
    log_message "INFO" "Projet actif : ${active_project:-${C_YELLOW}Aucun${C_RESET}}"
    log_message "INFO" "Python par défaut : ${python_default:-${C_YELLOW}Non défini${C_RESET}}"

    if [ -n "$active_project" ]; then
        local project_dir="$VENV_PROJECTS_DIR/$active_project"
        local venv_dir="$project_dir/venv"
        log_message "INFO" "Chemin du projet : ${project_dir}"
        if [ -d "$venv_dir" ]; then
            log_message "SUCCESS" "Statut du venv : Prêt à l'emploi"
            if [[ -n "${VIRTUAL_ENV}" && "${VIRTUAL_ENV}" == *"$active_project"* ]]; then
                 log_message "INFO" "État d'activation : ${C_GREEN}Actif${C_RESET}"
            else
                 log_message "INFO" "État d'activation : ${C_YELLOW}Inactif${C_RESET}"
            fi
        else
            log_message "WARN" "Statut du venv : ${C_RED}Absent ou corrompu${C_RESET}"
            log_message "INFO" "Suggestion : 'venv project create $active_project' pour le recréer."
        fi
    fi
}

# Sous-commande : list
cmd_list() {
    local active_project
    active_project=$(get_config_value 'active_project')
    
    if [ ! -d "$VENV_PROJECTS_DIR" ]; then
        log_message "INFO" "Aucun projet venv trouvé dans $VENV_PROJECTS_DIR."
        return 0
    fi
    
    echo "=========================================="
    echo "Liste des projets Venv"
    echo "=========================================="
    
    local projects=()
    while IFS= read -r -d '' line; do
        projects+=("$line")
    done < <(find "$VENV_PROJECTS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
    
    if [ ${#projects[@]} -eq 0 ]; then
        log_message "INFO" "Aucun projet trouvé."
        return 0
    fi
    
    for project_path in "${projects[@]}"; do
        local project_name=$(basename "$project_path")
        local venv_path="$project_path/venv"
        local status_icon=" "
        
        if [ "$project_name" == "$active_project" ]; then
            status_icon="${C_BOLD}>${C_RESET}"
        fi
        
        local venv_status="${C_RED}✖ Cassé${C_RESET}"
        if [ -d "$venv_path" ]; then
            venv_status="${C_GREEN}✔ Prêt${C_RESET}"
        fi
        
        echo "  $status_icon $project_name  -  [${venv_status}]"
    done
}

# Sous-commande : project
cmd_project() {
    local action="$1"
    local project_name="$2"
    local python_version=""
    local venv_dir

    case "$action" in
        create)
            if [ -z "$project_name" ]; then
                log_message "ERROR" "Le nom du projet est manquant."
                log_message "INFO" "Usage: venv project create <nom> [--python <bin>]"
                return 1
            fi
            shift 2
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    --python)
                        python_version="$2"
                        shift 2
                        ;;
                    *)
                        log_message "ERROR" "Argument invalide : '$1'"
                        return 1
                        ;;
                esac
            done
            create_project "$project_name" "$python_version"
            ;;
        delete)
            if [ -z "$project_name" ]; then
                log_message "ERROR" "Le nom du projet est manquant."
                log_message "INFO" "Usage: venv project delete <nom>"
                return 1
            fi
            delete_project "$project_name"
            ;;
        select)
            if [ -z "$project_name" ]; then
                log_message "ERROR" "Le nom du projet est manquant."
                log_message "INFO" "Usage: venv project select <nom>"
                return 1
            fi
            if [ ! -d "$VENV_PROJECTS_DIR/$project_name" ]; then
                log_message "ERROR" "Le projet '$project_name' n'existe pas."
                return 1
            fi
            if [ "$DRY_RUN" == true ]; then
                log_message "INFO" "DRY-RUN: Le projet '$project_name' sera sélectionné."
                return 0
            fi
            set_config_value "active_project" "$project_name"
            ;;
        *)
            log_message "ERROR" "Commande de projet invalide. Utilisez 'create', 'select' ou 'delete'."
            return 1
            ;;
    esac
}

create_project() {
    local project_name="$1"
    local python_version="$2"
    local project_dir="$VENV_PROJECTS_DIR/$project_name"
    local venv_dir="$project_dir/venv"

    if [ -d "$project_dir" ]; then
        log_message "WARN" "Le projet '$project_name' existe déjà."
        return 0
    fi
    
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Le projet '$project_name' sera créé dans $project_dir."
        return 0
    fi

    mkdir -p "$project_dir" || {
        log_message "ERROR" "Impossible de créer le répertoire du projet."
        return 1
    }

    local python_bin="${python_version:-$(get_config_value 'python_default')}"
    if ! command -v "$python_bin" &>/dev/null; then
        log_message "ERROR" "Le binaire Python '$python_bin' est introuvable."
        log_message "INFO" "Veuillez l'installer ou le changer avec 'venv python set <bin>'."
        rm -rf "$project_dir"
        return 1
    fi
    
    "$python_bin" -m venv "$venv_dir" || {
        log_message "ERROR" "Échec de la création du venv pour '$project_name'."
        rm -rf "$project_dir"
        return 1
    }
    
    echo '{"python_version": "'"$python_bin"'"}' > "$project_dir/config.json"
    set_config_value "active_project" "$project_name"
    log_message "SUCCESS" "Projet '$project_name' créé et sélectionné."
}

delete_project() {
    local project_name="$1"
    local project_dir="$VENV_PROJECTS_DIR/$project_name"

    if [ ! -d "$project_dir" ]; then
        log_message "ERROR" "Le projet '$project_name' n'existe pas."
        return 1
    fi
    
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Le projet '$project_name' sera supprimé."
        return 0
    fi
    
    if ! ask_confirm "Êtes-vous sûr de vouloir supprimer le projet '$project_name' ?"; then
        log_message "INFO" "Opération annulée par l'utilisateur."
        return 0
    fi

    rm -rf "$project_dir" || {
        log_message "ERROR" "Échec de la suppression du projet."
        return 1
    }
    
    local active_project=$(get_config_value 'active_project')
    if [ "$active_project" == "$project_name" ]; then
        set_config_value "active_project" ""
    fi
    log_message "SUCCESS" "Projet '$project_name' supprimé."
}

# Sous-commande : activate
cmd_activate() {
    local active_project
    active_project=$(get_config_value 'active_project')
    
    if [ -z "$active_project" ]; then
        log_message "ERROR" "Aucun projet actif. Utilisez 'venv project select <nom>'."
        return 1
    fi
    
    local venv_path="$VENV_PROJECTS_DIR/$active_project/venv"
    if [ ! -d "$venv_path" ]; then
        log_message "ERROR" "Le venv pour le projet '$active_project' n'existe pas ou est corrompu."
        return 1
    fi

    log_message "INFO" "Copiez-collez la commande suivante pour activer l'environnement :"
    echo "source \"$venv_path/bin/activate\""
}

# Sous-commande : deactivate
cmd_deactivate() {
    if [[ "$VIRTUAL_ENV" == *"$VENV_HOME"* ]]; then
        echo "deactivate"
        log_message "INFO" "Copiez-collez la commande ci-dessus pour désactiver le venv."
    else
        log_message "INFO" "Aucun environnement venv-system n'est actif."
    fi
}

# Sous-commande : install
cmd_install() {
    local active_project
    active_project=$(get_config_value 'active_project')
    
    if [ -z "$active_project" ]; then
        log_message "ERROR" "Aucun projet actif. Utilisez 'venv project select <nom>'."
        return 1
    fi
    
    local venv_path="$VENV_PROJECTS_DIR/$active_project/venv"
    if [ ! -d "$venv_path" ]; then
        log_message "ERROR" "L'environnement virtuel n'existe pas."
        return 1
    fi

    local pip_bin="$venv_path/bin/pip"
    if [ ! -f "$pip_bin" ]; then
        log_message "ERROR" "Le binaire pip est introuvable dans le venv."
        return 1
    fi
    
    local req_file=""
    local pkgs=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -r)
                req_file="$2"
                shift 2
                ;;
            *)
                pkgs+=("$1")
                shift
                ;;
        esac
    done

    if [ -n "$req_file" ]; then
        if [ ! -f "$req_file" ]; then
            log_message "ERROR" "Fichier de requirements '$req_file' introuvable."
            return 1
        fi
        log_message "INFO" "Installation depuis $req_file..."
        if [ "$DRY_RUN" == true ]; then
            log_message "INFO" "DRY-RUN: $pip_bin install -r $req_file"
        else
            "$pip_bin" install -r "$req_file" || {
                log_message "ERROR" "L'installation a échoué."
                return 1
            }
        fi
    fi
    
    if [ ${#pkgs[@]} -gt 0 ]; then
        log_message "INFO" "Installation des paquets : ${pkgs[*]}..."
        if [ "$DRY_RUN" == true ]; then
            log_message "INFO" "DRY-RUN: $pip_bin install ${pkgs[*]}"
        else
            "$pip_bin" install "${pkgs[@]}" || {
                log_message "ERROR" "L'installation a échoué."
                return 1
            }
        fi
    fi
    
    log_message "SUCCESS" "Installation terminée."
}

# Sous-commande : freeze
cmd_freeze() {
    local active_project
    active_project=$(get_config_value 'active_project')
    
    if [ -z "$active_project" ]; then
        log_message "ERROR" "Aucun projet actif. Utilisez 'venv project select <nom>'."
        return 1
    fi
    
    local venv_path="$VENV_PROJECTS_DIR/$active_project/venv"
    if [ ! -d "$venv_path" ]; then
        log_message "ERROR" "L'environnement virtuel n'existe pas."
        return 1
    fi
    
    local pip_bin="$venv_path/bin/pip"
    local output_file=""
    
    if [ -n "$1" ]; then
        if [ "$1" == "--output" ] && [ -n "$2" ]; then
            output_file="$2"
        else
            log_message "ERROR" "Argument invalide pour freeze : '$1'"
            return 1
        fi
    fi
    
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Exécution de '$pip_bin freeze' et sortie vers '$output_file'."
        return 0
    fi
    
    if [ -n "$output_file" ]; then
        "$pip_bin" freeze > "$output_file" || {
            log_message "ERROR" "Échec de l'exportation des dépendances vers '$output_file'."
            return 1
        }
        log_message "SUCCESS" "Dépendances exportées vers '$output_file'."
    else
        "$pip_bin" freeze
    fi
}

# Sous-commande : purge
cmd_purge() {
    local project_name="$1"
    
    if [ -z "$project_name" ]; then
        log_message "ERROR" "Le nom du projet est manquant."
        return 1
    fi
    
    local project_dir="$VENV_PROJECTS_DIR/$project_name"
    local venv_dir="$project_dir/venv"

    if [ ! -d "$project_dir" ]; then
        log_message "ERROR" "Le projet '$project_name' n'existe pas."
        return 1
    fi
    
    if [ ! -d "$venv_dir" ]; then
        log_message "WARN" "L'environnement virtuel est déjà purgé."
        return 0
    fi
    
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Le venv de '$project_name' sera supprimé."
        return 0
    fi
    
    if ! ask_confirm "Êtes-vous sûr de vouloir purger le venv de '$project_name' ?"; then
        log_message "INFO" "Opération annulée."
        return 0
    fi
    
    rm -rf "$venv_dir"
    log_message "SUCCESS" "Environnement virtuel du projet '$project_name' purgé."
}

# Sous-commande : python set
cmd_python_set() {
    local bin_name="$1"
    
    if [ -z "$bin_name" ]; then
        log_message "ERROR" "Le nom du binaire Python est manquant."
        return 1
    fi
    
    if ! command -v "$bin_name" &>/dev/null; then
        log_message "ERROR" "Le binaire Python '$bin_name' est introuvable sur le système."
        return 1
    fi
    
    set_config_value "python_default" "$bin_name"
}

# Sous-commande : config
cmd_config() {
    local action="$1"
    shift
    
    case "$action" in
        "show")
            log_message "INFO" "Configuration effective :"
            if [ -f "$VENV_GLOBAL_CONFIG_FILE" ]; then
                jq '.' "$VENV_GLOBAL_CONFIG_FILE"
            else
                echo '{"active_project": "", "python_default": "python3"}' | jq '.'
            fi
            ;;
        "set")
            local key="$1"
            local value="$2"
            if [ -z "$key" ] || [ -z "$value" ]; then
                log_message "ERROR" "Arguments manquants. Usage: venv config set <clé> <valeur>"
                return 1
            fi
            set_config_value "$key" "$value"
            ;;
        *)
            log_message "ERROR" "Commande de configuration invalide."
            return 1
            ;;
    esac
}

# Sous-commande : open
cmd_open() {
    local project_name="$1"
    if [ -z "$project_name" ]; then
        local active_project
        active_project=$(get_config_value 'active_project')
        if [ -z "$active_project" ]; then
            log_message "ERROR" "Aucun projet spécifié et aucun projet actif."
            return 1
        fi
        project_name="$active_project"
    fi
    
    local project_dir="$VENV_PROJECTS_DIR/$project_name"
    if [ ! -d "$project_dir" ]; then
        log_message "ERROR" "Le projet '$project_name' n'existe pas."
        return 1
    fi
    
    log_message "INFO" "Commande pour se déplacer vers le projet : cd '$project_dir'"
    if command -v code &>/dev/null; then
        log_message "INFO" "Pour ouvrir dans VS Code : code '$project_dir'"
    fi
}

# Sous-commande : doctor
cmd_doctor() {
    log_message "INFO" "Lancement du diagnostic..."
    local errors=0
    
    log_message "INFO" "Vérification des dépendances système..."
    if ! command -v jq &>/dev/null; then
        log_message "ERROR" "Dépendance manquante : 'jq'."
        ((errors++))
    else
        log_message "SUCCESS" "Dépendance 'jq' trouvée."
    fi
    if ! command -v python3 &>/dev/null; then
        log_message "ERROR" "Dépendance manquante : 'python3'."
        ((errors++))
    else
        log_message "SUCCESS" "Dépendance 'python3' trouvée."
    fi
    
    log_message "INFO" "Vérification de la structure de fichiers utilisateur : $VENV_HOME..."
    if [ ! -d "$VENV_HOME" ] || [ ! -d "$VENV_CONFIG_DIR" ] || [ ! -f "$VENV_GLOBAL_CONFIG_FILE" ]; then
        log_message "ERROR" "Structure de fichiers utilisateur incomplète. Lancez à nouveau le script d'installation."
        ((errors++))
    else
        log_message "SUCCESS" "Structure de fichiers utilisateur correcte."
    fi
    
    if [ "$errors" -eq 0 ]; then
        log_message "SUCCESS" "Diagnostic complet. Aucune erreur critique détectée."
    else
        log_message "ERROR" "Diagnostic terminé avec $errors erreur(s)."
    fi
}

# Sous-commande : uninstall
cmd_uninstall() {
    if [ "$IS_ROOT" != true ]; then
        log_message "ERROR" "La désinstallation doit être exécutée avec des privilèges root (sudo)."
        return 1
    fi

    if ! ask_confirm "Êtes-vous sûr de vouloir désinstaller le système venv ?"; then
        log_message "INFO" "Opération annulée."
        return 0
    fi
    
    local keep_projects=false
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --keep-projects)
                keep_projects=true
                shift
                ;;
            *)
                log_message "ERROR" "Argument invalide pour uninstall : '$1'"
                return 1
                ;;
        esac
    done
    
    if [ "$DRY_RUN" == true ]; then
        log_message "INFO" "DRY-RUN: Suppression du binaire $VENV_BIN_PATH"
    else
        sudo rm -f "$VENV_BIN_PATH"
    fi
    
    if [ "$keep_projects" == true ]; then
        log_message "INFO" "Les dossiers utilisateur ~/.venv_system/ seront conservés."
    else
        if ! ask_confirm "Voulez-vous aussi supprimer tous les fichiers utilisateur (~/.venv_system/) y compris les projets et backups ?"; then
            log_message "INFO" "Les fichiers utilisateur seront conservés."
        else
            if [ "$DRY_RUN" == true ]; then
                log_message "INFO" "DRY-RUN: Suppression de tous les dossiers utilisateur ~/.venv_system/"
            else
                local users
                mapfile -t users < <(getent passwd | cut -d: -f1,6 | awk -F: '$2 ~ /^\/home\// {print $1}')
                for user in "${users[@]}"; do
                    if [ "$user" == "root" ]; then continue; fi
                    local home_dir
                    home_dir=$(getent passwd "$user" | cut -d: -f6)
                    sudo rm -rf "$home_dir/.venv_system"
                    log_message "SUCCESS" "Dossiers utilisateur supprimés pour '$user'."
                done
            fi
        fi
    fi
    
    log_message "SUCCESS" "Désinstallation terminée. Veuillez recharger votre shell."
}

# Main routing logic
main() {
    # Parse global options first
    local cmd_found=false
    local positional_args=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --yes|-y) YES=true; shift;;
            --dry-run) DRY_RUN=true; shift;;
            --quiet|-q) exec 1>/dev/null; shift;; # Redirect stdout to null
            -*) log_message "ERROR" "Option globale inconnue : '$1'"; exit 1;;
            *) positional_args+=("$1"); cmd_found=true; shift;;
        esac
    done
    
    if [ "$cmd_found" == false ]; then
        cmd_help
        exit 0
    fi
    
    local cmd="${positional_args[0]}"
    local args=("${positional_args[@]:1}")
    
    case "$cmd" in
        help|status|list|project|activate|deactivate|install|freeze|purge|python|config|open|doctor|uninstall)
            "cmd_$cmd" "${args[@]}"
            ;;
        *)
            log_message "ERROR" "Commande inconnue : '$cmd'"
            cmd_help
            exit 1
            ;;
    esac
}
main "$@"
EOF
    sudo install -m 0755 /dev/stdin "$VENV_BIN_PATH" <<< "$venv_script_content"
    print_log "SUCCESS" "Binaire $VENV_BIN_PATH installé avec succès."
    
    configure_initial_user_files
    
    print_log "SUCCESS" "Installation complète terminée ! Redémarrez votre terminal pour que les changements prennent effet."
}

# Lancement de l'installateur
main_installer
