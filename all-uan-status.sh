#!/bin/bash

for system in $(cray config list | jq -r '.configurations[] | .name'); do

  if [[ "$system" == "default" ]]; then
    continue
  fi

  echo "$system UAN status"

  uan-install-composer.sh -a $system -u
done
