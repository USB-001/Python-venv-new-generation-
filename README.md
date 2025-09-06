
# 🐍 Gestionnaire de Venv
Ce projet propose un script shell (venv) qui simplifie la gestion des environnements virtuels Python. Il automatise la création, l'activation, la désactivation et l'exécution de commandes, offrant une interface simple et puissante.
___

##🚀 Installation

###📋 Prérequis
Pour utiliser ce script, vous devez avoir Python 3, pip, venv et pipx installés sur votre système.
 * Python 3 & Pip
   La plupart des systèmes Linux modernes incluent Python 3.
   sudo apt update
sudo apt install python3 python3-pip

 * Environnement Virtuel (venv)
   venv est généralement inclus avec Python 3.3+.
   python3 -m venv --help

 * Pipx
   pipx est un outil pour installer et exécuter des applications Python dans des environnements virtuels isolés.
   python3 -m pip install --user pipx
python3 -m pipx ensurepath

   Relancez votre terminal pour que les changements prennent effet.

___

###📥 Installation du script venv
Pour que le script soit utilisable partout, exécutez le script d'installation qui le placera dans votre $PATH.
 * Créez un fichier nommé install_venv.sh et copiez-collez le code suivant :
   #!/bin/bash

if [[ "$SHELL" == *"/bash" ]]; then
    SHELL_RC_FILE="$HOME/.bashrc"
elif [[ "$SHELL" == *"/zsh" ]]; then
    SHELL_RC_FILE="$HOME/.zshrc"
else
    echo "Shell non pris en charge. Le script ne peut pas continuer."
    exit 1
fi

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

read -r -d '' VENV_SCRIPT_CONTENT <<'EOF'
#!/bin/bash
VENV_DIR="venv"
VENV_SYNC_PATH="" 
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
if [ -n "$VENV_SYNC_PATH" ]; then
    VENV_SCRIPT_CONTENT=${VENV_SCRIPT_CONTENT//VENV_SYNC_PATH=""/VENV_SYNC_PATH=\"$VENV_SYNC_PATH\"}
fi

echo "Création du script 'venv' dans /usr/local/bin/..."
echo "$VENV_SCRIPT_CONTENT" | sudo tee /usr/local/bin/venv > /dev/null
sudo chmod +x /usr/local/bin/venv

if [ -n "$VENV_SYNC_PATH" ]; then
    echo "Ajout de la variable de synchronisation au fichier $SHELL_RC_FILE..."
    echo -e "\n# Variable de synchronisation pour le script venv\nexport VENV_SYNC_PATH=\"$VENV_SYNC_PATH\"" | sudo tee -a "$SHELL_RC_FILE" > /dev/null
    echo "Installation terminée. Veuillez recharger votre shell (source $SHELL_RC_FILE) ou ouvrir un nouveau terminal."
else
    echo "Installation terminée. Veuillez recharger votre shell (source $SHELL_RC_FILE) ou ouvrir un nouveau terminal."
fi
```

 * Rendez le script exécutable et exécutez-le :
   chmod +x install_venv.sh
sudo ./install_venv.sh
___

###💡 Utilisation
Une fois installé, le script venv peut être utilisé de n'importe où.
| Commande | Description |
|---|---|
| venv | Active ou désactive l'environnement virtuel. |
| venv on / venv off | Force l'activation ou la désactivation. |
| venv <commande> | Exécute une commande dans le venv et le désactive après. Ex: venv pip install requests |
| venv -s | Affiche le statut actuel du venv (actif ou inactif). |
| venv -i | Liste les modules installés dans le venv. |
| venv -sy <chemin> | Synchronise votre répertoire de travail avec un autre dossier venv existant. |
| venv -h | Affiche le menu d'aide. |

