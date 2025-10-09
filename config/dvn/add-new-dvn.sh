#!/bin/bash

# Check if an argument is passed
if [ -z "$1" ]; then
  echo "Please provide a key name to add."
  exit 1
fi

# Argument passed (key name to add)
key_name=$1

# Loop through all JSON files in config/dvn directory
for file in config/dvn/*.json; do
  # Extract the base filename (e.g., 1.json, 728126428.json)
  filename=$(basename "$file" .json)
  
  # Skip the file if its base filename matches the provided key_name
  if [ "$filename" == "$key_name" ]; then
    echo "Skipping $file as it matches the provided key_name."
    continue
  fi

  # Skip the file if it doesn't follow the number.json pattern
  if [[ ! "$filename" =~ ^[0-9]+$ ]]; then
    continue
  fi
  
  # Get the last key in the JSON file (the last key in the order of the file)
  last_key=$(jq -r 'keys | last' "$file")
  
  # Get the value of the last key
  last_value=$(jq -r ".\"$last_key\"" "$file")
  
  # If last_key or last_value is empty or null, skip the file
  if [ -z "$last_key" ] || [ -z "$last_value" ]; then
    echo "No valid last key or value found in $file. Skipping."
    continue
  fi
  
  # Check if the last value is a JSON object (i.e., contains `{}`), then add it to the new key
  if [[ "$last_value" == "{"*"}" ]]; then
    # Add the new key-value pair (key_name: last_value) to the JSON file using jq
    jq --indent 4 --arg key "$key_name" --argjson value "$last_value" \
       '.[$key] = $value' "$file" > tmpfile && mv tmpfile "$file"
  else
    # Add the new key-value pair (key_name: last_value) to the JSON file using jq
    jq --indent 4 --arg key "$key_name" --arg value "$last_value" \
       '.[$key] = $value' "$file" > tmpfile && mv tmpfile "$file"
  fi
  
  echo "Added $key_name: $last_value to $file"
done
