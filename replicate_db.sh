#!/bin/bash

# Set database type (default: mongo)
DB_TYPE="mongo"

# Set variables for source and destination databases
SOURCE_DB_STRING=""
SOURCE_DATABASE=""
SOURCE_FOLDER="source"

DEST_DB_STRING="mongodb://USER:PASS@localhost:27017"
DEST_DATABASE=""
DEST_FOLDER="destination"

# MySQL specific variables
MYSQL_SOURCE_HOST="localhost"
MYSQL_SOURCE_PORT="3306"
MYSQL_SOURCE_USER=""
MYSQL_SOURCE_PASS=""

MYSQL_DEST_HOST="localhost"
MYSQL_DEST_PORT="3307"
MYSQL_DEST_USER=""
MYSQL_DEST_PASS=""

# Directory for dump files
DUMP_DIR="db_dump"

# Colors and icons
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9D\x8C"

# Check args
CLEAN_UP=false
VERBOSE=false
LIST_DATABASES=false
while (("$#")); do
    case "$1" in
    -c | --clean)
        CLEAN_UP=true
        shift
        ;;
    -h | --help)
        echo "Usage: $0 [-c|--clean] [-v|--verbose] [-t|--type TYPE] [-l|--list-databases] [OPTIONS]"
        echo "  -c, --clean          Clean up the dump directory after data transfer"
        echo "  -h, --help           Display this help message"
        echo "  -v, --verbose        Display verbose output from commands"
        echo "  -t, --type           Database type: 'mongo' (default) or 'mysql'"
        echo "  -l, --list-databases List available databases and exit (MySQL only)"
        echo ""
        echo "MongoDB Options:"
        echo "  -sf, --source-folder Source folder name for dump"
        echo "  -df, --dest-folder   Destination folder name for dump"
        echo "  -dd, --dest-db       Destination database name"
        echo "  -sd, --source-db     Source database name"
        echo "Example:"
        echo "  ./replicate_db.sh -t mongo -sf source_folder -sd source_db -df dest_folder -dd dest_db -v"
        echo ""
        echo "MySQL Options:"
        echo "  -sh, --source-host   Source MySQL host"
        echo "  -sp, --source-port   Source MySQL port (default: 3306)"
        echo "  -su, --source-user   Source MySQL username"
        echo "  -sw, --source-pass   Source MySQL password"
        echo "  -dh, --dest-host     Destination MySQL host (default: localhost)"
        echo "  -dp, --dest-port     Destination MySQL port (default: 3306)"
        echo "  -du, --dest-user     Destination MySQL username"
        echo "  -dw, --dest-pass     Destination MySQL password"
        echo "  -sd, --source-db     Source database name"
        echo "  -dd, --dest-db       Destination database name"
        echo "Examples:"
        echo "  ./replicate_db.sh -t mysql -sh source_uri -sp source_port -su db_user -sw \"db_pass\" -sd db_name -dh dest_uri -dp dest_port -du dest_user -dw \"dest_pass\" -dd dest_db_name -v"

        exit 0
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
        ;;
    -l | --list-databases)
        LIST_DATABASES=true
        shift
        ;;
    -t | --type)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            DB_TYPE="$2"
            if [[ "$DB_TYPE" != "mongo" && "$DB_TYPE" != "mysql" ]]; then
                echo "Error: Database type must be 'mongo' or 'mysql'" >&2
                exit 1
            fi
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -sf | --source-folder)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            SOURCE_FOLDER="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -df | --dest-folder)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            DEST_FOLDER="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -dd | --dest-db)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            DEST_DATABASE="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -sd | --source-db)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            SOURCE_DATABASE="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -sh | --source-host)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_SOURCE_HOST="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -sp | --source-port)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_SOURCE_PORT="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -su | --source-user)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_SOURCE_USER="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -sw | --source-pass)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_SOURCE_PASS="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -dh | --dest-host)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_DEST_HOST="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -dp | --dest-port)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_DEST_PORT="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -du | --dest-user)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_DEST_USER="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    -dw | --dest-pass)
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
            MYSQL_DEST_PASS="$2"
            shift 2
        else
            echo "Error: Argument for $1 is missing" >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
done

check_variables() {
    if [ -z "$1" ]; then
        echo -e "${RED}${CROSS_MARK} Please set the required variable into the script. Exiting.${NC}"
        exit 1
    fi
}

# Validate variables based on database type
if [ "$DB_TYPE" = "mongo" ]; then
    check_variables "$SOURCE_DB_STRING"
    check_variables "$SOURCE_DATABASE"
    check_variables "$DEST_DB_STRING"
    check_variables "$DEST_DATABASE"
elif [ "$DB_TYPE" = "mysql" ]; then
    # For listing databases, we only need source connection
    if [ "$LIST_DATABASES" = true ]; then
        check_variables "$MYSQL_SOURCE_HOST"
        check_variables "$MYSQL_SOURCE_USER"
    else
        check_variables "$MYSQL_SOURCE_HOST"
        check_variables "$MYSQL_SOURCE_USER"
        check_variables "$SOURCE_DATABASE"
        check_variables "$MYSQL_DEST_HOST"
        check_variables "$MYSQL_DEST_USER"
        check_variables "$DEST_DATABASE"
    fi
fi

# Function to check if a command exists
check_command() {
    if ! which $1 >/dev/null; then
        echo "$1 is not installed."
        
        if [ "$DB_TYPE" = "mongo" ]; then
            echo "Please install MongoDB tools."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                echo "For Mac, you can install it using Homebrew:"
                echo "brew tap mongodb/brew"
                echo "brew install mongodb-database-tools"
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                echo "For Linux, you can follow the instructions at:"
                echo "https://www.mongodb.com/docs/database-tools/installation/installation-linux/"
            fi
        elif [ "$DB_TYPE" = "mysql" ]; then
            echo "Please install MySQL client tools."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                echo "For Mac, you can install it using Homebrew:"
                echo "brew install mysql-client"
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                echo "For Linux, you can install it using:"
                echo "sudo apt-get install mysql-client"
                echo "or"
                echo "sudo yum install mysql"
            fi
        fi

        exit 1
    else
        echo -e "${GREEN}$1 is installed. ${CHECK_MARK}${NC}"
    fi
}

# Check for required tools based on database type
if [ "$DB_TYPE" = "mongo" ]; then
    echo "Checking for required MongoDB tools..."
    check_command mongodump
    check_command mongorestore
elif [ "$DB_TYPE" = "mysql" ]; then
    echo "Checking for required MySQL tools..."
    check_command mysqldump
    check_command mysql
fi

# Function to list MySQL databases
list_mysql_databases() {
    echo "Available databases on $MYSQL_SOURCE_HOST:$MYSQL_SOURCE_PORT:"
    echo "=============================================="
    
    SOURCE_MYSQL_OPTS="--protocol=TCP -h$MYSQL_SOURCE_HOST -P$MYSQL_SOURCE_PORT -u$MYSQL_SOURCE_USER"
    if [ -n "$MYSQL_SOURCE_PASS" ]; then
        SOURCE_MYSQL_OPTS="$SOURCE_MYSQL_OPTS -p$MYSQL_SOURCE_PASS"
    fi
    
    mysql $SOURCE_MYSQL_OPTS -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$"
    
    if [ $? -eq 0 ]; then
        echo "=============================================="
        echo -e "${GREEN}Use these database names with -sd or --source-db parameter${NC}"
    else
        echo -e "${RED}${CROSS_MARK} Failed to connect to MySQL server or list databases${NC}"
        exit 1
    fi
}

# If listing databases is requested, do it and exit
if [ "$LIST_DATABASES" = true ]; then
    if [ "$DB_TYPE" = "mysql" ]; then
        list_mysql_databases
        exit 0
    else
        echo -e "${RED}${CROSS_MARK} --list-databases option is only available for MySQL${NC}"
        exit 1
    fi
fi

create_dump_dir() {
    rm -rf $1
    mkdir -p $1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dump directory created: $1 ${CHECK_MARK}${NC}"
    else
        echo "Failed to create dump directory. Exiting."
        exit 1
    fi
}
echo "Creating dump directories..."
create_dump_dir $DUMP_DIR/$SOURCE_FOLDER
create_dump_dir $DUMP_DIR/$DEST_FOLDER

# Dump the source database
echo "Dumping data..."

dump_data_mongo() {
    # verbose output
    if $VERBOSE; then
        mongodump --uri $1 --out $2
    else
        mongodump --uri $1 --out $2 --quiet
    fi
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dump successful. Data dumped to $2 ${CHECK_MARK}${NC}"
    else
        echo "Dump failed. Exiting."
        exit 1
    fi
}

dump_data_mysql() {
    local host_port_user_pass=$1
    local database=$2
    local output_file=$3
    
    if $VERBOSE; then
        mysqldump $host_port_user_pass $database > $output_file
    else
        mysqldump $host_port_user_pass $database > $output_file 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dump successful. Data dumped to $output_file ${CHECK_MARK}${NC}"
    else
        echo "Dump failed. Exiting."
        exit 1
    fi
}

if [ "$DB_TYPE" = "mongo" ]; then
    dump_data_mongo $SOURCE_DB_STRING $DUMP_DIR/$SOURCE_FOLDER
    dump_data_mongo $DEST_DB_STRING $DUMP_DIR/$DEST_FOLDER
elif [ "$DB_TYPE" = "mysql" ]; then
    # Build MySQL connection strings with TCP protocol
    SOURCE_MYSQL_OPTS="--protocol=TCP -h$MYSQL_SOURCE_HOST -P$MYSQL_SOURCE_PORT -u$MYSQL_SOURCE_USER"
    if [ -n "$MYSQL_SOURCE_PASS" ]; then
        SOURCE_MYSQL_OPTS="$SOURCE_MYSQL_OPTS -p$MYSQL_SOURCE_PASS"
    fi
    
    DEST_MYSQL_OPTS="--protocol=TCP -h$MYSQL_DEST_HOST -P$MYSQL_DEST_PORT -u$MYSQL_DEST_USER"
    if [ -n "$MYSQL_DEST_PASS" ]; then
        DEST_MYSQL_OPTS="$DEST_MYSQL_OPTS -p$MYSQL_DEST_PASS"
    fi
    
    # Verify source database exists
    echo "Checking if source database '$SOURCE_DATABASE' exists..."
    mysql $SOURCE_MYSQL_OPTS -e "USE $SOURCE_DATABASE" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}${CROSS_MARK} Source database '$SOURCE_DATABASE' does not exist or cannot be accessed. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Source database '$SOURCE_DATABASE' found. ${CHECK_MARK}${NC}"
    
    # Create dump files
    SOURCE_DUMP_FILE="$DUMP_DIR/${SOURCE_FOLDER}_${SOURCE_DATABASE}.sql"
    DEST_DUMP_FILE="$DUMP_DIR/${DEST_FOLDER}_${DEST_DATABASE}.sql"
    
    dump_data_mysql "$SOURCE_MYSQL_OPTS" "$SOURCE_DATABASE" "$SOURCE_DUMP_FILE"
    
    # Check if destination database exists and backup if needed
    echo "Checking destination database '$DEST_DATABASE'..."
    mysql $DEST_MYSQL_OPTS -e "USE $DEST_DATABASE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Destination database '$DEST_DATABASE' exists. Creating backup before overwriting...${NC}"
        dump_data_mysql "$DEST_MYSQL_OPTS" "$DEST_DATABASE" "$DEST_DUMP_FILE"
    else
        echo "Destination database '$DEST_DATABASE' doesn't exist. It will be created."
    fi
fi

# Restore the dump to the destination database
echo "Restoring data..."

if [ "$DB_TYPE" = "mongo" ]; then
    # check if source database exists in dump_dir/source
    if [ ! -d "$DUMP_DIR/$SOURCE_FOLDER/$SOURCE_DATABASE" ]; then
        echo -e "${RED}${CROSS_MARK} Source database dump not found. Exiting.${NC}"
        exit 1
    fi

    if $VERBOSE; then
        mongorestore --uri $DEST_DB_STRING --db=$DEST_DATABASE --authenticationDatabase=admin --drop $DUMP_DIR/$SOURCE_FOLDER/$SOURCE_DATABASE
    else
        mongorestore --uri $DEST_DB_STRING --db=$DEST_DATABASE --authenticationDatabase=admin --drop $DUMP_DIR/$SOURCE_FOLDER/$SOURCE_DATABASE --quiet
    fi

elif [ "$DB_TYPE" = "mysql" ]; then
    # Check if source dump file exists
    if [ ! -f "$SOURCE_DUMP_FILE" ]; then
        echo -e "${RED}${CROSS_MARK} Source database dump file not found. Exiting.${NC}"
        exit 1
    fi
    
    # Drop and recreate destination database to ensure clean restore
    echo "Dropping and recreating destination database '$DEST_DATABASE'..."
    mysql $DEST_MYSQL_OPTS -e "DROP DATABASE IF EXISTS $DEST_DATABASE;" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Destination database '$DEST_DATABASE' dropped successfully. ${CHECK_MARK}${NC}"
    fi
    
    mysql $DEST_MYSQL_OPTS -e "CREATE DATABASE $DEST_DATABASE;" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Destination database '$DEST_DATABASE' created successfully. ${CHECK_MARK}${NC}"
    else
        echo -e "${RED}${CROSS_MARK} Failed to create destination database '$DEST_DATABASE'. Exiting.${NC}"
        exit 1
    fi
    
    echo "Restoring data from '$SOURCE_DATABASE' to '$DEST_DATABASE'..."
    if $VERBOSE; then
        mysql $DEST_MYSQL_OPTS $DEST_DATABASE < $SOURCE_DUMP_FILE
    else
        mysql $DEST_MYSQL_OPTS $DEST_DATABASE < $SOURCE_DUMP_FILE 2>/dev/null
    fi
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Restore successful. ${CHECK_MARK}${NC}"
else
    echo "Restore failed. Exiting."
    exit 1
fi

if $CLEAN_UP; then
    # Clean up the dump directory
    echo "Cleaning up dump directory..."
    rm -rf $DUMP_DIR
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dump directory cleaned up. ${CHECK_MARK}${NC}"
    else
        echo "Failed to clean up dump directory."
        exit 1
    fi
fi
echo -e "${GREEN}Data transfer from $SOURCE_DATABASE to $DEST_DATABASE completed successfully. ${CHECK_MARK}${NC}"