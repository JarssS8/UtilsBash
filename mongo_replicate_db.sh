#!/bin/bash

# Set variables for source and destination databases
SOURCE_DB_STRING=""
SOURCE_DATABASE=""
SOURCE_FOLDER="source"

DEST_DB_STRING="mongodb://USER:PASS@localhost:27017"
DEST_DATABASE=""
DEST_FOLDER="destination"

# Directory for dump files
DUMP_DIR="mongo_dump"

# Colors and icons
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9D\x8C"

# Check args
CLEAN_UP=false
VERBOSE=false
while (("$#")); do
    case "$1" in
    -c | --clean)
        CLEAN_UP=true
        shift
        ;;
    -h | --help)
        echo "Usage: $0 [-c|--clean] [-v|--verbose] [-sf|--source-folder FOLDER] [-df|--dest-folder FOLDER] [-dd|--dest-db DB]"
        echo "  -c, --clean          Clean up the dump directory after data transfer"
        echo "  -h, --help           Display this help message"
        echo "  -v, --verbose        Display verbose output from mongo commands"
        echo "  -sf, --source-folder Source folder name for dump"
        echo "  -df, --dest-folder   Destination folder name for dump"
        echo "  -dd, --dest-db       Destination database name"
        echo "  -sd, --source-db     Source database name"
        exit 0
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
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

# Example usage
check_variables $SOURCE_DB_STRING
check_variables $SOURCE_DATABASE
check_variables $DEST_DB_STRING
check_variables $DEST_DATABASE

# Function to check if a command exists
check_command() {
    if ! which $1 >/dev/null; then
        echo "$1 is not installed."
        echo "Please install MongoDB tools."

        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "For Mac, you can install it using Homebrew:"
            echo "brew tap mongodb/brew"
            echo "brew install mongodb-database-tools"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "For Linux, you can follow the instructions at:"
            echo "https://www.mongodb.com/docs/database-tools/installation/installation-linux/"
        fi

        exit 1
    else
        echo -e "${GREEN}$1 is installed. ${CHECK_MARK}${NC}"
    fi
}

# Check for mongodump and mongorestore
echo "Checking for required MongoDB tools..."
check_command mongodump
check_command mongorestore

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

dump_data() {
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

dump_data $SOURCE_DB_STRING $DUMP_DIR/$SOURCE_FOLDER
dump_data $DEST_DB_STRING $DUMP_DIR/$DEST_FOLDER

# Restore the dump to the destination database
echo "Restoring data..."

# check if source database exists in mongo_dump/source
if [ ! -d "$DUMP_DIR/$SOURCE_FOLDER/$SOURCE_DATABASE" ]; then
    echo -e "${RED}${CROSS_MARK} Source database dump not found. Exiting.${NC}"
    exit 1
fi

if $VERBOSE; then
    mongorestore --uri $DEST_DB_STRING --db=$DEST_DATABASE --authenticationDatabase=admin --drop mongo_dump/$SOURCE_FOLDER/$SOURCE_DATABASE
else
    mongorestore --uri $DEST_DB_STRING --db=$DEST_DATABASE --authenticationDatabase=admin --drop mongo_dump/$SOURCE_FOLDER/$SOURCE_DATABASE --quiet
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
