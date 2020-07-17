#!/bin/sh

init_options() {
  OPTIONS="--no-progress"

  if [ "$INPUT_DEBUG_MODE" = true ]; then
    set -x

    OPTIONS="${OPTIONS} --verbose"
  fi

  if [ -n "$INPUT_CROWDIN_BRANCH_NAME" ]; then
    OPTIONS="${OPTIONS} --branch=${INPUT_CROWDIN_BRANCH_NAME}"
  fi

  if [ -n "$INPUT_IDENTITY" ]; then
    OPTIONS="${OPTIONS} --identity=${INPUT_IDENTITY}"
  fi

  if [ -n "$INPUT_CONFIG" ]; then
    OPTIONS="${OPTIONS} --config=${INPUT_CONFIG}"
  fi

  if [ "$INPUT_DRYRUN_ACTION" = true ]; then
    OPTIONS="${OPTIONS} --dryrun"
  fi

  echo "${OPTIONS}"
}

init_config_options() {
  CONFIG_OPTIONS=""

  if [ -n "$INPUT_PROJECT_ID" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --project-id=${INPUT_PROJECT_ID}"
  fi

  if [ -n "$INPUT_TOKEN" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --token=${INPUT_TOKEN}"
  fi

  if [ -n "$INPUT_BASE_URL" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --base-url=${INPUT_BASE_URL}"
  fi

  if [ -n "$INPUT_BASE_PATH" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --base-path=${INPUT_BASE_PATH}"
  fi

  if [ -n "$INPUT_SOURCE" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --source=${INPUT_SOURCE}"
  fi

  if [ -n "$INPUT_TRANSLATION" ]; then
    CONFIG_OPTIONS="${CONFIG_OPTIONS} --translation=${INPUT_TRANSLATION}"
  fi

  echo "${CONFIG_OPTIONS}"
}

upload_sources() {
  echo "UPLOAD SOURCES"
  crowdin upload sources "${CONFIG_OPTIONS}" "${OPTIONS}"
}

upload_translations() {
  if [ -n "$INPUT_UPLOAD_LANGUAGE" ]; then
    OPTIONS="${OPTIONS} --language=${INPUT_UPLOAD_LANGUAGE}"
  fi

  if [ "$INPUT_AUTO_APPROVE_IMPORTED" = true ]; then
    OPTIONS="${OPTIONS} --auto-approve-imported"
  fi

  if [ "$INPUT_IMPORT_EQ_SUGGESTIONS" = true ]; then
    OPTIONS="${OPTIONS} --import-eq-suggestions"
  fi

  echo "UPLOAD TRANSLATIONS"
  crowdin upload translations "${CONFIG_OPTIONS}" "${OPTIONS}"
}

download_translations() {
  if [ -n "$INPUT_DOWNLOAD_LANGUAGE" ]; then
    OPTIONS="${OPTIONS} --language=${INPUT_DOWNLOAD_LANGUAGE}"
  elif [ -n "$INPUT_LANGUAGE" ]; then #back compatibility for older versions
    OPTIONS="${OPTIONS} --language=${INPUT_LANGUAGE}"
  fi

  if [ "$INPUT_SKIP_UNTRANSLATED_STRINGS" = true ]; then
    OPTIONS="${OPTIONS} --skip-untranslated-strings"
  fi

  if [ "$INPUT_SKIP_UNTRANSLATED_FILES" = true ]; then
    OPTIONS="${OPTIONS} --skip-untranslated-files"
  fi

  if [ "$INPUT_EXPORT_ONLY_APPROVED" = true ]; then
    OPTIONS="${OPTIONS} --export-only-approved"
  fi

  echo "DOWNLOAD TRANSLATIONS"
  crowdin download "${CONFIG_OPTIONS}" "${OPTIONS}"
}

create_pull_request() {
  TITLE="${1}"

  LOCALIZATION_BRANCH="${2}"

  AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
  HEADER="Accept: application/vnd.github.v3+json; application/vnd.github.antiope-preview+json; application/vnd.github.shadow-cat-preview+json"

  REPO_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}"
  REPO_RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X GET "${REPO_URL}")
  BASE_BRANCH=$(echo "${REPO_RESPONSE}" | jq --raw-output '.default_branch')

  PULLS_URL="${REPO_URL}/pulls"

  echo "CHECK IF ISSET SAME PULL REQUEST"
  DATA="{\"base\":\"${BASE_BRANCH}\", \"head\":\"${LOCALIZATION_BRANCH}\"}"
  RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X GET --data "${DATA}" "${PULLS_URL}")

  PULL_REQUESTS=$(echo "${RESPONSE}" | jq --raw-output '.[] | .head.ref ')

  if echo "$PULL_REQUESTS " | grep -q "$LOCALIZATION_BRANCH "; then
    echo "PULL REQUEST ALREADY EXIST"
  else
    echo "CREATE PULL REQUEST"

    DATA="{\"title\":\"${TITLE}\", \"base\":\"${BASE_BRANCH}\", \"head\":\"${LOCALIZATION_BRANCH}\"}"
    PULL_RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X POST --data "${DATA}" "${PULLS_URL}")
    CREATED_PULL_URL=$(echo "${PULL_RESPONSE}" | jq '.html_url')

    if [ -n "$INPUT_PULL_REQUEST_LABELS" ]; then
      if [ "$(echo "$INPUT_PULL_REQUEST_LABELS" | jq -e . > /dev/null 2>&1; echo $?)" -eq 0 ]; then
        echo "ADD LABELS TO PULL REQUEST"

        PULL_REQUESTS_NUMBER=$(echo "${PULL_RESPONSE}" | jq '.number')
        ISSUE_URL="${REPO_URL}/issues/${PULL_REQUESTS_NUMBER}"

        DATA="{\"labels\":${INPUT_PULL_REQUEST_LABELS}}";
        curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X PATCH --data "${DATA}" "${ISSUE_URL}";
      else
        echo "JSON OF pull_request_labels IS INVALID"
      fi
    fi

    echo "PULL REQUEST CREATED: ${CREATED_PULL_URL}"
  fi
}

push_to_branch() {
  LOCALIZATION_BRANCH=${INPUT_LOCALIZATION_BRANCH_NAME}

  COMMIT_MESSAGE="New Crowdin translations by Github Action"

  REPO_URL="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

  echo "CONFIGURATION GIT USER"
  git config --global user.email "support+bot@crowdin.com"
  git config --global user.name "Crowdin Bot"

  git checkout -b "${LOCALIZATION_BRANCH}"

  if [ -n "$(git status -s)" ]; then
    echo "PUSH TO BRANCH ${LOCALIZATION_BRANCH}"

    git add .
    git commit -m "${COMMIT_MESSAGE}"
    git push --force "${REPO_URL}"

    if [ "$INPUT_CREATE_PULL_REQUEST" = true ]; then
      create_pull_request "${COMMIT_MESSAGE}" "${LOCALIZATION_BRANCH}"
    fi
  else
    echo "NOTHING TO COMMIT"
  fi
}

# STARTING WORK
echo "STARTING CROWDIN ACTION"

set -e

OPTIONS=$(init_options)
CONFIG_OPTIONS=$(init_config_options)

if [ "$INPUT_UPLOAD_SOURCES" = true ]; then
  upload_sources
fi

if [ "$INPUT_UPLOAD_TRANSLATIONS" = true ]; then
  upload_translations
fi

if [ "$INPUT_DOWNLOAD_TRANSLATIONS" = true ]; then
  [ -z "${GITHUB_TOKEN}" ] && {
    echo "CAN NOT FIND 'GITHUB_TOKEN' IN ENVIRONMENT VARIABLES"
    exit 1
  }

  download_translations

  if [ "$INPUT_PUSH_TRANSLATIONS" = true ]; then
    push_to_branch
  fi
fi
