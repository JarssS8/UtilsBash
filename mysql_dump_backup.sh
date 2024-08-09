#!/bin/bash

# Variables
USER=""
PASSWORD=""
DATABASE=""
HOST=""
BACKUP_PATH="./backups"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9D\x8C"

# Check if mysql-client is installed
if ! command -v mysqldump &> /dev/null
then
    echo -e "${RED}${CROSS_MARK} mysqldump could not be found${NC}"
    echo -e "${RED}${CROSS_MARK} Please install mysql-client${NC}"
    echo -e "${RED}${CROSS_MARK} MAC: brew install mysql-client${NC}"
    echo -e "${RED}${CROSS_MARK} Linux: sudo apt install mysql-client${NC}"
    exit
fi

# Check variables 
if [ -z "$USER" ] || [ -z "$PASSWORD" ] || [ -z "$DATABASE" ] || [ -z "$HOST" ]; then
    echo -e "${RED}${CROSS_MARK} Please fill in the required variables in this file${NC}"
    exit
fi

echo -e "${GREEN}Starting backup...${NC}"
if [ ! -d $BACKUP_PATH ]; then
    echo -e "${RED}Creating backup directory...${NC}"
    mkdir $BACKUP_PATH
fi
echo -e "${GREEN}Backup directory created${NC}"

# Create backup
echo -e "${GREEN}Creating backup...${NC}"
mysqldump -u $USER -p$PASSWORD -h $HOST $DATABASE > $BACKUP_PATH/$DATABASE-$(date +%Y-%m-%d-%H-%M-%S).sql

if [ $? -eq 0 ]; then
    echo -e "${GREEN}${CHECK_MARK} Backup created successfully${NC}"
else
    echo -e "${RED}${CROSS_MARK} Backup failed${NC}"
fi
