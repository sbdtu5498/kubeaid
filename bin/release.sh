#!/bin/bash
set -e

# Generate comprehensive release notes from git history
# This captures ALL commits since last release, not just chart updates

CHANGELOG_FILE="CHANGELOG.md"
RELEASE_NOTES_FILE=".release-notes.md"
# Run this when the helm chart update PR is merged into master
NEW_TAG=${1:-$(cat VERSION)}

# Get the previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

# Check if current branch is master
CURRENT_BRANCH=$(git branch --show-current)

if [[ "${CURRENT_BRANCH}" != "master" ]]; then
  echo "Error: Not on master branch. Current branch: ${CURRENT_BRANCH}"
  exit 1
fi

# Pull latest changes to ensure we're up to date
if ! git pull origin master; then
  echo "Error: Failed to pull latest changes from origin master. Please resolve any issues and try again."
  exit 1
fi

if [ -z "$PREVIOUS_TAG" ]; then
  echo "No previous tag found, using all commits"
  COMMIT_RANGE="HEAD"
else
  echo "Generating release notes since $PREVIOUS_TAG..$NEW_TAG"
  COMMIT_RANGE="$PREVIOUS_TAG..HEAD"
fi

# Check if the new tag already exists
if git rev-parse -q --verify "refs/tags/$NEW_TAG" >/dev/null; then
  echo "ERROR: Tag '$NEW_TAG' already exists. Update the VERSION file before releasing."
  exit 1
fi

# Initialize arrays for categorization
declare -a FEATURES
declare -a BUG_FIXES
declare -a CONFIG_CHANGES
declare -a OTHER_CHANGES
declare -a NEW_CHARTS
declare -a MAJOR_CHART_UPDATES
declare -a MINOR_CHART_UPDATES
declare -a PATCH_CHART_UPDATES

MAJOR_CHART_UPDATES=()
MINOR_CHART_UPDATES=()
PATCH_CHART_UPDATES=()
NEW_CHARTS=()

sort_update_commits() {
  local update_type="$1"      # Major, Minor, or Patch
  local commit_hash="$short_hash"

  # Capitalize the update type for the section header
  local capitalized="${update_type^}"

  # Create temporary array for new items
  local temp_array=()

  # Extract lines from the specific section and add to temp array
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      temp_array+=("- ${commit_hash} $line")
    fi
  done < <(git log --format=%B -n 1 "$commit_hash" | \
    sed -n "/### ${capitalized} Version Upgrades/,/^$/p" | \
    grep -E '^\s*Updated' | \
    sed 's/^[[:space:]]*//')

  # Append temp array to the target array using nameref
  local -n target_array="${update_type^^}_CHART_UPDATES"
  target_array+=("${temp_array[@]}")
}

# Process commits
while IFS= read -r commit; do
  # Get commit message (first line only)
  message=$(git log --format=%s -n 1 "$commit")
  short_hash=$(git log --format=%h -n 1 "$commit")
  formatted_message="- $short_hash $message"

  # Skip merge commits
  if [[ $message =~ ^Merge ]]; then
    continue
  fi

  # Skip chart update commits (they're handled separately)
  # Categorize commits
  if [[ $message =~ chore\(chart\):.*kubeaid.*charts ]]; then
    sort_update_commits 'Major'
    sort_update_commits 'Minor'
    sort_update_commits 'Patch'
  elif [[ $message =~ chore\(major\ update\): ]]; then
    MAJOR_CHART_UPDATES+=("$formatted_message")
  elif [[ $message =~ chore\(minor\ update\): ]]; then
    MINOR_CHART_UPDATES+=("$formatted_message")
  elif [[ $message =~ chore\(patch\ update\): ]]; then
    PATCH_CHART_UPDATES+=("$formatted_message")
  elif [[ $message =~ chore\(new\): ]]; then
    NEW_CHARTS+=("$formatted_message")
  elif [[ $message =~ ^feat ]]; then
    FEATURES+=("$formatted_message")
  elif [[ $message =~ ^fix ]]; then
    BUG_FIXES+=("$formatted_message")
  elif [[ $message =~ ^chore ]]; then
    CONFIG_CHANGES+=("$formatted_message")
  else
    OTHER_CHANGES+=("$formatted_message")
  fi
done < <(git rev-list "$COMMIT_RANGE")

function get_total_chart_updates() {
  git log --format='%B' -n 1 "$short_hash" | grep -c Update
}

TOTAL_CHART_UPDATES=get_total_chart_updates

cat $CHANGELOG_FILE | tail -n +5 > $CHANGELOG_FILE.tmp

# Generate release notes file
{
  printf '%s\n' "## KubeAid Release Version ${NEW_TAG}"
  echo ""

  if [ ${#NEW_CHARTS[@]} -gt 0 ]; then
    echo "### New Charts Added"
    echo ""
    printf '%s\n' "${NEW_CHARTS[@]}"
    echo ""
  fi

  if [ ${#MAJOR_CHART_UPDATES[@]} -gt 0 ]; then
    echo "### Major Version Upgrades"
    echo ""
    printf '%s\n' "${MAJOR_CHART_UPDATES[@]}"
    echo ""
  fi

  if [ ${#MINOR_CHART_UPDATES[@]} -gt 0 ]; then
    echo "### Minor Version Upgrades"
    echo ""
    printf '%s\n' "${MINOR_CHART_UPDATES[@]}"
    echo ""
  fi

  if [ ${#PATCH_CHART_UPDATES[@]} -gt 0 ]; then
    echo "### Patch Version Upgrades"
    echo ""
    printf '%s\n' "${PATCH_CHART_UPDATES[@]}"
    echo ""
  fi

  if [ ${#FEATURES[@]} -gt 0 ]; then
    echo "### Features"
    echo ""
    printf '%s\n' "${FEATURES[@]}"
    echo ""
  fi

  if [ ${#BUG_FIXES[@]} -gt 0 ]; then
    echo "### Bug Fixes"
    echo ""
    printf '%s\n' "${BUG_FIXES[@]}"
    echo ""
  fi

  if [ ${#CONFIG_CHANGES[@]} -gt 0 ]; then
    echo "### Configuration Changes"
    echo ""
    printf '%s\n' "${CONFIG_CHANGES[@]}"
    echo ""
  fi

  if [ ${#OTHER_CHANGES[@]} -gt 0 ]; then
    echo "### Other Changes"
    echo ""
    printf '%s\n' "${OTHER_CHANGES[@]}"
    echo ""
  fi

   # If no commits categorized, add a note
   total=$((TOTAL_CHART_UPDATES + ${#FEATURES[@]} + ${#BUG_FIXES[@]} + ${#CONFIG_CHANGES[@]} + ${#OTHER_CHANGES[@]}))
   if [ $total -eq 0 ]; then
    echo "No changes in this release."
   fi
} > "$RELEASE_NOTES_FILE"

{
  printf '%s\n' "# Changelog"
  echo ""
  printf '%s\n' "All releases and the changes included in them (pulled from git commits added since last release) will be detailed in this file."
  echo ""
} > "$CHANGELOG_FILE"


# Prepend the new release note in the changelog.md file
cat "$RELEASE_NOTES_FILE" "$CHANGELOG_FILE.tmp" >> "$CHANGELOG_FILE"

echo "Release notes generated: $CHANGELOG_FILE"
rm -fr $CHANGELOG_FILE.tmp

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A "$CHANGELOG_FILE" "$RELEASE_NOTES_FILE" VERSION
  git commit -m "chore(release): update CHANGELOG and Release Notes for Kubeaid ${NEW_TAG}"
fi

git tag -a "$NEW_TAG" -m "Kubeaid Release $NEW_TAG"

echo "Pushing changelog changes to Gitea"
git push origin master

echo "Pushing tag to Gitea"
git push origin "$NEW_TAG"

echo "Pushing changelog changes to Github"
git push github master

echo "Pushing tag to Github"
git push github "$NEW_TAG"
