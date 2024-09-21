#!/bin/bash

source $HOME/wdteam-app/invoice-generator/scripts/helpers/index.sh

SQL_QUERY_FOLDER="$HOME/wdteam-app/invoice-generator/scripts/sqlQueries"

printHello
SQL_QUERY_FILE="$HOME/wdteam-app/invoice-generator/scripts/sqlQueries/sql_query.sql"


executeSqlScript $SQL_QUERY_FILE



