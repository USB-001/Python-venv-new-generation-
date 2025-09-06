#!/bin/bash

# Détermine le shell de l'utilisateur
if [[ "$SHELL" == *"/bash" ]]; then
    SHELL_RC_FILE="$HOME/.bashrc"
    echo "Shell détecté: Bash. Fichier de configuration: $SHELL_RC_FILE"
elif [[ "$SHELL" == *"/zsh" ]]; then
    SHELL_RC_FILE="$HOME/.zshrc"
    echo "Shell détecté: Zsh. Fichier de configuration: $SHELL_RC_FILE"
else
    echo "Shell non pris en charge. Le script ne peut pas continuer."
    exit 1
fi

# Demande à l'utilisateur si il a un chemin de synchronisation personnalisé
read -p "Souhaitez-vous définir un chemin de venv par défaut pour la synchronisation? (O/n): " custom_sync_choice
if [[ "$custom_sync_choice" == "o" || "$custom_sync_choice" == "O" ]]; then
    read -e -p "Entrez le chemin absolu du dossier venv par défaut: " VENV_SYNC_PATH
    if [ -d "$VENV_SYNC_PATH" ]; then
        echo "Chemin de synchronisation défini: $VENV_SYNC_PATH"
    else
        echo "Le chemin spécifié n'existe pas. Aucune variable de synchronisation ne sera ajoutée."
        VENV_SYNC_PATH=""
    fi
else
    VENV_SYNC_PATH=""
fi

# Le contenu du script principal `venv`
read -r -d '' VENV_SCRIPT_CONTENT <<'EOF'
#!/bin/bash

VENV_DIR="venv"
VENV_SYNC_PATH="" # Cette variable sera remplacée par le script d'installation

help_menu() {
    echo "Usage: venv [OPTIONS] [COMMAND]"
    echo ""
    echo "Gère l'environnement virtuel Python '${VENV_DIR}'."
    echo ""
    echo "Options :"
    echo "  -h, --help       Affiche ce menu d'aide."
    echo "  -s, --status     Affiche le statut de l'environnement."
    echo "  -i, --info       Affiche les modules installés."
    echo "  -sy, --sync      Synchronise avec un dossier venv existant. Utilise VENV_SYNC_PATH par défaut."
    echo "  on               Active l'environnement virtuel."
    echo "  off              Désactive l'environnement virtuel."
    echo ""
    echo "Utilisation de commandes :"
    echo "  venv <commande>  Exécute une commande dans l'environnement virtuel."
    echo "  Exemple: venv pip install requests"
}

create_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo "L'environnement virtuel '${VENV_DIR}' n'existe pas. Création..."
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo "Erreur lors de la création de l'environnement."
            exit 1
        fi
    fi
}

main() {
    local sync_target=""

    # Gère les arguments
    case "$1" in
        -h|--help)
            help_menu
            ;;
        -s|--status)
            echo "===================================="
            echo "  Statut Venv"
            echo "===================================="
            if [[ "$VIRTUAL_ENV" == *"$VENV_DIR"* ]]; then
                echo "Statut : ✅ ACTIF"
                echo "Emplacement : $VIRTUAL_ENV"
            else
                echo "Statut : 🔴 INACTIF"
                echo "Emplacement : $(pwd)/$VENV_DIR"
            fi
            ;;
        -i|--info)
            echo "===================================="
            echo "  Modules installés"
            echo "===================================="
            if [[ "$VIRTUAL_ENV" != *"$VENV_DIR"* ]]; then
                source "$VENV_DIR/bin/activate"
                pip list --format=columns
                deactivate
            else
                pip list --format=columns
            fi
            ;;
        -sy|--sync)
            shift
            if [ -n "$1" ]; then
                sync_target=$(realpath "$1")
            elif [ -n "$VENV_SYNC_PATH" ]; then
                sync_target="$VENV_SYNC_PATH"
            else
                echo "Erreur: un chemin vers le venv source est requis."
                echo "Exemple: venv -sy /chemin/vers/mon_venv"
                exit 1
            fi
            
            if [ ! -d "$sync_target" ]; then
                echo "Erreur: le chemin spécifié n'existe pas ou n'est pas un dossier."
                exit 1
            fi
            echo "Synchronisation de l'environnement de travail avec le venv : $sync_target"
            rm -rf "$VENV_DIR"
            ln -s "$sync_target" "$VENV_DIR"
            echo "Synchronisation réussie. L'environnement '${VENV_DIR}' pointe maintenant vers '$sync_target'."
            ;;
        on)
            create_venv
            if [[ "$VIRTUAL_ENV" == *"$VENV_DIR"* ]]; then
                echo "L'environnement est déjà actif."
            else
                source "$VENV_DIR/bin/activate"
                echo "Environnement activé."
            fi
            ;;
        off)
            if [[ "$VIRTUAL_ENV" == *"$VENV_DIR"* ]]; then
                deactivate
                echo "Environnement désactivé."
            else
                echo "Aucun environnement n'est actif."
            fi
            ;;
        *)
            if [ -z "$1" ]; then
                echo "Erreur: aucune commande spécifiée."
                help_menu
                exit 1
            fi
            
            create_venv
            echo "Exécution de la commande dans l'environnement virtuel..."
            local VENV_IS_ACTIVE=false
            if [[ "$VIRTUAL_ENV" == *"$VENV_DIR"* ]]; then
                VENV_IS_ACTIVE=true
            fi

            source "$VENV_DIR/bin/activate"
            
            "$@"

            if [ "$VENV_IS_ACTIVE" = false ]; then
                deactivate
                echo "Commande terminée. Environnement désactivé."
            else
                echo "Commande terminée."
            fi
            ;;
    esac
}

main "$@"
EOF

# Remplace le chemin de synchronisation dans le script si l'utilisateur en a fourni un
if [ -n "$VENV_SYNC_PATH" ]; then
    VENV_SCRIPT_CONTENT=${VENV_SCRIPT_CONTENT//VENV_SYNC_PATH=""/VENV_SYNC_PATH=\"$VENV_SYNC_PATH\"}
fi

# Crée le script `venv` et le rend exécutable
echo "Création du script 'venv' dans /usr/local/bin/..."
echo "$VENV_SCRIPT_CONTENT" | sudo tee /usr/local/bin/venv > /dev/null
sudo chmod +x /usr/local/bin/venv

# Ajoute le commentaire de synchronisation au fichier de configuration du shell
if [ -n "$VENV_SYNC_PATH" ]; then
    echo "Ajout de la variable de synchronisation au fichier $SHELL_RC_FILE..."
    echo -e "\n# Variable de synchronisation pour le script venv\nexport VENV_SYNC_PATH=\"$VENV_SYNC_PATH\"" | tee -a "$SHELL_RC_FILE" > /dev/null
    echo "Installation terminée. Veuillez recharger votre shell (source $SHELL_RC_FILE) ou ouvrir un nouveau terminal."
else
    echo "Installation terminée. Veuillez recharger votre shell (source $SHELL_RC_FILE) ou ouvrir un nouveau terminal."
fi
