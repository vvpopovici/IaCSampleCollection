#!/bin/bash

# This will copy the content of the folder ./volume-data/ to the folder /volume/ using rsync command.
# Both source and destination must come as arguments, if not - as environemnt variables:
# - the source is $1 or $SOURCE_PATH. Default value './volume-data/'.
# - the target is $2 or $VOLUME_PATH. Default value '/volume/'.
# Usage:
#   bash ./volume-data-rsync.sh
#   bash ./volume-data-rsync.sh ./volume-data/ /volume

source=${SOURCE_PATH:-$1}; source=${source:-'./volume-data/'}
target=${VOLUME_PATH:-$2}; target=${target:-'/volume/'}
echo -e "\n### Rsync-ing files from '${source}' to '${target}'...\n"

rsync -vrh --delete-after --stats "$source" "$target"

echo -e "\n### Rsync to ${target} finished.\n"
