# UtilsBash
## Mongo Database Replication
This script performs a dump of a database from one URI and restores it to another URI. It is useful for replicating data between development, testing, and production environments.

### Initial Setup
Before running the script, you need to configure the following variables at the beginning of the file:
- `DEST_DB_STRING`: Connection string for the destination database.
- `SOURCE_DB_STRING`: Connection string for the source database.
- `DEST_DATABASE`: String with the name of the database where you want to dump the data.
- `SOURCE_DATABASE`: String with the name of the database from which you want to obtain the data.

Ensure these variables are correctly set to avoid overwriting important data.

### Usage
The script supports various arguments and options to customize the replication operation:
```
./mongo_replicate_db.sh [options]
```

Available options:
- `-c`, `--clean`: Cleans the dump directory after data transfer.
- `-h`, `--help`: Displays this help message.
- `-v`, `--verbose`: Shows detailed output of MongoDB commands.
- `-sf`, `--source-folder FOLDER`: Name of the source directory for the dump.
- `-df`, `--dest-folder FOLDER`: Name of the destination directory for the dump.
- `-dd`, `--dest-db DB`: Name of the destination database.
- `-sd`, `--source-db DB`: Name of the source database.

### Example Usage
To perform a clean and detailed replication of a database, you can use the following command:
```
./mongo_replicate_db.sh -c -v -sd source_db_name -dd dest_db_name
```
However, simply using the command without options will suffice:
```
./mongo_replicate_db.sh
```

This command dumps the database specified with `-sd`, cleans the dump directory after the transfer, and shows detailed output during the process.

### Additional Notes
- Ensure you have the appropriate permissions to access the source and destination databases.
- Check that there is sufficient disk space to perform the database dump.
- Make sure file has permisions for execute the file
```
chmod +x ./mongo_replicate_db.sh
```
- Consider not use `--clean` option to prevent data loss.
- Consider create an alias to make you easy use this command

```
alias mongo_replicate="/opt/mongo_replicate_db.sh"
```
![image](https://imgur.com/7EdmaY8.png)
