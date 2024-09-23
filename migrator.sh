#!/bin/bash
# Load enviromental variables
source .env
# Import helper functions
source $(pwd)/helpers/index.sh

main() {
    startApp
    # Unset environmental variable
    source cleanUps/index.sh
}

main
