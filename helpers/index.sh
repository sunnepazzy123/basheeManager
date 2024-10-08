#!/bin/bash

exportTableAsSqlFromDB() {
    local table=$1

    echo "Checking if the table exists..."
    if docker exec -i "$DOCKER_CONTAINER_NAME" psql -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -tAc "SELECT to_regclass('$table')" | grep -q "$table"; then
        echo "Table exists, proceeding with export..."

        echo "Exporting table to a file..."
        if docker exec -i "$DOCKER_CONTAINER_NAME" pg_dump -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -t "$table" --format=plain >exports/"$table.sql"; then
            echo "Export successful: check the exports folder."
        else
            echo "Export failed."
            exit 1
        fi
    else
        echo "Table '$table' does not exist."
        exit 1
    fi
}

exportTableAsCsvFromDB() {
    local table=$1
    local host_path="exports/$table.csv"        # Replace with the desired path on the host
    local container_temp_path="/tmp/$table.csv" # Adjust the temporary path inside the container

    echo "Exporting table to a CSV file..."
    if docker exec -t "$DOCKER_CONTAINER_NAME" psql -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -c "\\COPY \"$table\" TO $container_temp_path WITH CSV HEADER"; then
        docker cp "$DOCKER_CONTAINER_NAME":$container_temp_path "$host_path"
        echo -e "\e[0;32mExport successful: CSV file copied to '$host_path'.\e[0m"

        # Remove the csv file from container temp folder
        if docker exec -i $DOCKER_CONTAINER_NAME rm $container_temp_path; then
            echo -e "\e[0;32mTemporary CSV file removed from the container successfully.\e[0m"
        else
            echo -e "\e[1;31mTemporary CSV file did not removed from the container.\e[0m"
        fi
    else
        echo -e "\e[1;31mExport failed.\e[0m"
        exit 1
    fi
}

exportSchemaAsSqlFromDB() {
    local schema=$1

    echo "Exporting schema to a file..."
    if docker exec -i "$DOCKER_CONTAINER_NAME" pg_dump -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -n $schema --format=plain >exports/"$schema.sql"; then
        echo "Export successful: look in the exports folder"
    else
        echo "Export failed."
        exit 1
    fi
}

executeSqlScript() {
    local QueryFilePath=$1
    local log_file=logs/execution_log.txt

    # Ensure to check the path correctly
    checkPathIsSQLFile "$QueryFilePath"

    # Read the SQL file
    QueryFile=$(cat "$QueryFilePath") || {
        echo -e "\e[0;31mError: Unable to read SQL file: $QueryFilePath\e[0m"
        exit 1
    }

    local start_time=$(date +%s%N)
    if docker exec -i "$DOCKER_CONTAINER_NAME" psql -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -c "$QueryFile"; then
        local end_time=$(date +%s%N)
        execution_time=$((($end_time - $start_time) / 1000000))

        echo "SQL script executed successfully in ${execution_time} milliseconds." >>"$log_file"
        echo -e "\e[1;34mSQL script executed successfully in ${execution_time} milliseconds.!! Check ./logs folder to read execution logs\e[0m" # 1;32 ANSI escape codes for bold green
    else
        echo -e "\e[1;31mQuery execution failed.\e[0m" # 1;32 ANSI escape codes for bold red
        exit 1
    fi
}

executeSqlScripts() {
    local sqlQueriesFolder=$1
    local log_file=logs/execution_log.txt

    checkPathExist $sqlQueriesFolder
    local start_time=$(date +%s%N)
    for file in "$sqlQueriesFolder"/*.sql; do
        if [ -f $file ]; then
            executeSqlScript $file
        else
            echo -e "\e[1;31mNo sql file found: $file \e[0m" # 1;32 ANSI escape codes for bold red
            exit 1
        fi
    done

    local end_time=$(date +%s%N)
    execution_time=$((($end_time - $start_time) / 1000000))

    echo "SQL scripts executed successfully in ${execution_time} milliseconds." >>"$log_file"
    echo -e "\e[1;34mSQL scripts executed successfully in ${execution_time} milliseconds.!! Check ./logs folder to read execution logs\e[0m" # 1;32 ANSI escape codes for bold green
}

checkPathIsSQLFile() {
    local PATH=$1
    # Check if the file path ends with .sql extension
    if [[ ! "$PATH" =~ \.sql$ ]]; then
        echo -e "\e[0;31mError: The specified file $PATH is not a .sql file.\e[0m"
        exit 1
    fi

    echo -e "\e[0;32mChecked: PATH is $PATH \e[0m"
}

checkPathIsCsvFile() {
    local PATH=$1
    # Check if the file path ends with .sql extension
    if [[ ! "$PATH" =~ \.csv$ ]]; then
        echo -e "\e[0;31mError: The specified file $PATH is not a .csv file.\e[0m"
        exit 1
    fi

    echo -e "\e[1;32mChecked: PATH is $PATH \e[0m"

}

checkPathExist() {
    local PATH=$1
    # Check if the file/folder path exists
    if [ ! -e "$PATH" ]; then
        echo -e "\e[1;31mError: File/Folder $PATH not found\e[0m." # 1;32 ANSI escape codes for bold red
        exit 1
    fi
}

import_csv_to_table() {
    local csv_file=$1
    local table_name=$2
    local log_file=logs/execution_log.txt
    local filename=$(basename $csv_file)
    local container_temp_path="/tmp/$filename" # Adjust the temporary path inside the container

    checkPathIsCsvFile $csv_file

    echo "Connecting to PostgreSQL container and copying CSV file..."
    local start_time=$(date +%s%N)
    if docker cp $csv_file "$DOCKER_CONTAINER_NAME:$container_temp_path"; then
        echo -e "\e[1;33mCSV file copied successfully to a temporary location inside the container.\e[0m"

        local command="\COPY $table_name FROM $container_temp_path WITH CSV HEADER;"

        echo "Running SQL query inside the PostgreSQL container..."
        if docker exec -i $DOCKER_CONTAINER_NAME psql -U $DOCKER_DB_USER -d $DOCKER_DB_NAME -c "$command"; then
            local end_time=$(date +%s%N)
            local execution_time=$((($end_time - $start_time) / 1000000))

            echo "CSV-SQL script executed successfully in ${execution_time} milliseconds." >>$log_file
            echo -e "\e[1;32mCSV-SQL script executed successfully in ${execution_time} milliseconds. Check ./logs folder to read execution logs\e[0m"
        else
            # Remove the temporary CSV file from the container
            docker exec -i $DOCKER_CONTAINER_NAME rm $container_temp_path
            echo -e "\e[1;33mTemporary CSV file removed from the container.\e[0m"
            echo -e "\e[1;31mQuery execution failed. import_csv_to_table func\e[0m"
            exit 1
        fi
        # Remove the temporary CSV file from the container
        docker exec -i $DOCKER_CONTAINER_NAME rm $container_temp_path
        echo -e "\e[1;33mTemporary CSV file removed from the container.\e[0m"
    else
        echo -e "\e[1;31mFailed to copy CSV file to a temporary location inside the container.\e[0m"
        exit 1
    fi
}

permissionCurrentFolder() {
    # Grant permissions to the current directory
    chmod +rwx "$(pwd)"

    # Grant permissions to all subdirectories
    find "$(pwd)" -type d -exec chmod +rwx {} \;

    echo "Permissions granted successfully."
}

installNodeJs() {
    # Set up directories for installation
    mkdir -p ~/bin ~/lib ~/include ~/node-latest-install

    # Download and extract the Node.js binaries
    wget -O ~/node-latest-install/node.tar.xz https://nodejs.org/dist/v20.11.0/node-v20.11.0.tar.gz
    cd ~/node-latest-install
    # tar tf node.tar.xz
    tar xf node.tar.xz --strip-components=1

    # Move the binaries to the appropriate directories in your home directory
    mv ~/node-latest-install/* ~/bin/
    mv ~/node-latest-install/include/* ~/include/
    mv ~/node-latest-install/lib/* ~/lib/

    # Add the local bin directory to your PATH
    echo 'export PATH=$HOME/bin:$PATH' >>~/.bashrc
    source ~/.bashrc

}

execute_docker_compose() {
    local compose_file="$2"
    local command="$1"

    checkPathExist $compose_file

    # Check if the file path ends with .yml/yaml extension
    if [[ ! "$compose_file" =~ \.(yaml|yml)$ ]]; then
        echo -e "\e[0;31mError: The specified file $compose_file is not a .yml/yaml file.\e[0m"
        exit 1
    fi

    if [ "$command" = "up" ]; then
        docker-compose -f "$compose_file" $command -d
        echo "docker compose up <file_name>"
    elif [ $command = "down" ]; then
        docker-compose -f "$compose_file" $command
        echo "docker compose down <file_name>"
    else
        echo -e "\e[1;31mError: command should be <up> or <down>\e[0m: $compose_file"
        exit 1
    fi
}

docker_login() {
    # Check if all required arguments are provided
    if [ -z "$DOCKER_USER" ] || [ -z "$DOCKER_PASSWORD" ]; then
        echo -e "\e[1;31mUsage: docker_login  required <username> <password> [<registry>]\e[0m"
        exit 1
    fi

    if [ -n "$registry" ]; then
        echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USER" --password-stdin "$registry"
    else
        echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USER" --password-stdin
    fi
}

checkFileExtension() {
    local compose_file=$1
    local ext_file="$2"

    if [[ ! "$compose_file" =~ \.($ext_file)$ ]]; then
        echo -e "\e[0;31mError: The specified file $compose_file is not a .$ext_file file.\e[0m"
        exit 1
    fi

    echo -e "\e[0;32mChecked: File Extension is $compose_file => .$ext_file \e[0m"
}

export_to_csv() {
    local sqlFile=$1
    local host_path="exports/$table.csv"        # Replace with the desired path on the host
    local container_temp_path="/tmp/$table.csv" # Adjust the temporary path inside the container

    docker exec -it $container_name psql -U $db_user -d $db_name -f /export_to_csv.sql
    echo "Exporting table to a CSV file..."
    if docker exec -t "$DOCKER_CONTAINER_NAME" psql -U "$DOCKER_DB_USER" -d "$DOCKER_DB_NAME" -c "\\COPY $table TO $container_temp_path WITH CSV HEADER"; then
        docker cp "$DOCKER_CONTAINER_NAME":$container_temp_path "$host_path"
        echo -e "\e[0;32mExport successful: CSV file copied to '$host_path'.\e[0m"

        # Remove the csv file from container temp folder
        if docker exec -i $DOCKER_CONTAINER_NAME rm $container_temp_path; then
            echo -e "\e[0;32mTemporary CSV file removed from the container successfully.\e[0m"
        else
            echo -e "\e[1;31mTemporary CSV file did not removed from the container.\e[0m"
        fi
    else
        echo -e "\e[1;31mExport failed.\e[0m"
        exit 1
    fi
}

printScreen() {
    clear # Clear the screen for a cleaner display
    check_docker_status
    # Print the current working directory for debugging
    echo "Current Working Directory: $(pwd)"
    echo "===================================="
    echo "        Bashee Manager"
    echo "===================================="
    echo "===================================="
    echo "        SQL Query Runner"
    echo "===================================="
    echo ""
    echo -e "\e[1;33mChoose your option:\e[0m"
    echo "1. Run Multiple Queries (all) from sqlQueries folder"
    echo "2. Run Single Query (one) from sqlQueries folder"
    echo "3. Export Table as Csv From DB to exports folder"
    echo "4. Export Table as SQL From DB to exports folder"
    echo ""
}

# Function to check Docker on Linux
check_docker_linux() {
    if systemctl is-active --quiet docker; then
        echo "Docker is running on Linux"
    else
        echo "Docker is not running on Linux"
        exit 1
    fi
}

# Function to check Docker on Windows
check_docker_windows() {
    dockerStatus=$(powershell.exe -Command "(Get-Service -Name 'com.docker.service').Status")
    if [[ $dockerStatus == *"Running"* ]]; then
        echo "Docker is running on Windows"
    else
        echo "Docker is not running on Windows"
        exit 1
    fi
}

# Function to check if Docker is running
check_docker_status() {
    if docker info >/dev/null 2>&1; then
        echo -e "\e[0;32mDocker is running\e[0m"
    else
        echo "Docker is not running"
        exit 1
    fi
    echo -e "\e[0;32mChecking if .env file exist\e[0m"
    checkPathExist $(pwd)/.env
}

detectOs() {
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux OS
        check_docker_linux
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        # Windows OS (using Git Bash or WSL)
        check_docker_windows
    else
        echo "Unsupported OS"
        exit 1
    fi
}

handleInputCommand() {
    # Prompt for SQL query option
    read -p "Enter your choice: " command
    echo ""
    echo "your command is $command"

    SQL_QUERY_FOLDER="$(pwd)/sqlQueries"
    EXPORTS_FOLDER="$(pwd)/exports"

    if [[ "$command" == "1" ]]; then
        executeSqlScripts $SQL_QUERY_FOLDER
    elif [[ "$command" == "2" ]]; then
        # Prompt for SQL query file path
        read -p "Enter the SQL query file path (default: $SQL_QUERY_FOLDER/$SQL_QUERY_FILE): " SQL_QUERY_FILE
        SQL_QUERY_FILE=$SQL_QUERY_FOLDER/$SQL_QUERY_FILE # Construct the full file path
        executeSqlScript $SQL_QUERY_FILE
    elif [[ "$command" == "3" ]]; then
        read -p "Enter table name: " tableName
        echo ""
        exportTableAsCsvFromDB $tableName
    elif [[ "$command" == "4" ]]; then
        read -p "Enter table name: " tableName
        echo ""
        exportTableAsSqlFromDB $tableName
    else
        echo "Wrong Command"
    fi
}

startApp() {
    printScreen
    handleInputCommand
}
