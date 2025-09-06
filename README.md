
# 🐍 Gestionnaire de Venv
Ce projet propose un script shell (venv) qui simplifie la gestion des environnements virtuels Python. Il automatise la création, l'activation, la désactivation et l'exécution de commandes, offrant une interface simple et puissante.
___
## 🚀 Installation
### 📋 Prérequis
Pour utiliser ce script, vous devez avoir Python 3, pip, venv et pipx installés sur votre système.
 * Python 3 & Pip
   La plupart des systèmes Linux modernes incluent déjà ces outils.

```bash

python3 -m pip install --user pipx

```

```bash

sudo apt update
sudo apt install python3 python3-pip


```
 * Environnement Virtuel (venv)
   venv est généralement inclus avec Python 3.3+.
 * Pipx
   pipx est un outil pour installer et exécuter des applications Python dans des environnements virtuels isolés.

```bash



python3 -m pipx ensurepath


```
___
### 📥 Installation du script venv
Pour que le script soit utilisable partout, exécutez le script d'installation qui le placera dans votre $PATH.
 * Créez un fichier nommé install_venv.sh et copiez-y le code d'installation fourni.
 * Rendez le script exécutable et exécutez-le en tant qu'administrateur.

___
### 💡 Utilisation
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



execute pour voir les commandes
```bash
venv -h
```
