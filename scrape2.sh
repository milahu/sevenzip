#! /usr/bin/env bash

# process the downloaded files in downloads.sourceforge.net/
# which were downloaded by scrape.sh


author_name="Igor Pavlov"
author_email="ipavlov@sourceforge.net"
#author_tz=0000

# https://offog.org/notes/tarballs-to-git/
# http://offog.org/git/misccode/git-import-snapshots



if ! [ -d .git ]; then
  git init
fi



history_format=0
prev_archive_version=""



# trace
#set -x



while read archive_path; do

  echo "archive path: $archive_path"

  archive_version="$(basename "$(dirname "$archive_path")" | tr '[[:upper:]]' '[[:lower:]]')"
  echo archive_version=$archive_version
  archive_version2=$(echo "$archive_version" | cut -d' ' -f2)
  if [[ "$archive_version2" == "beta" ]]; then
    echo "found beta archive_version: $archive_version";
    # TODO...
  fi

  archive_date=$(TZ=UTC stat -c%y "$archive_path")

  echo "archive date: $archive_date"

  # remove all committed files
  git rm -rf . >/dev/null

  # remove known 7zip folders
  rm -rf 7zip Asm C Common CPP DOC Far Windows

  echo "unpacking $archive_path"
  if echo "$archive_path" | grep -q '\.7z$'; then
    7z x "$archive_path"
  else
    tar xf "$archive_path"
  fi

  # note: tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/3.13/7z313.tar.bz2 has version 3.11 not 3.13
  # by DOC/readme.txt and by DOC/history.txt
  # but 3.13 never appears in the history.txt, also not in later versions
  # so i have to get a range of history entries
  # after the last release, and before-or-equal the current release

  # starting with 7zip version "4.58 beta"
  # the DOC/history.txt has a different format
  if [[ "$archive_version" == "4.58 beta" ]]; then
    history_format=2
  fi
  # TODO more cases

  history_path="$(find DOC/ -name history.txt -or -name src-history.txt)"
  if [[ $(echo "$history_path" | wc -l) != 1 ]]; then
    echo "error: did not find one history file in DOC/"
    echo "history_path: '$history_path'"
    exit 1
  fi

  first_history_version=""
  first_history_date=""

  # parse commit_message
  # different history files have different formats
  #if [ -z "$prev_archive_version" ]; then

  if [[ "$history_format" == 0 ]]; then

    # first tarball. use full history from 7z313/DOC/history.txt
    # tail -n +4: remove the first 3 lines with the "Sources history of the 7-Zip" heading
    commit_message="version $archive_version"$'\n\n'"$(cat $history_path | sed 's/^  //' | tail -n +4)"
    history_format=1

  elif [[ "$history_format" == 1 ]]; then

    # not used
    #history_version_lines="$(grep -E '^  Version [0-9]+\.[0-9]+( beta)? +[0-9]{4}-[0-9]{2}-[0-9]{2}.?$' $history_path)"
    # example:
    # release: tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/4.30 beta/7z430.tar.bz2
    # prev rl: tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/4.29 beta/7z429.tar.bz2
    # first version header lines in 7z430/DOC/history.txt:
    #   Version 4.30 beta           2005-11-18
    #   Version 4.27                2005-09-21
    # so we only want the "Version 4.30 beta" block as commit message

    # example:
    # release: tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/4.20/7z420.tar.bz2
    # prev rl: tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/3.13/7z313.tar.bz2
    # $ grep -E '^  Version [0-9]+\.[0-9]+( beta)? +[0-9]{4}-[0-9]{2}-[0-9]{2}.?$' 7z420/DOC/history.txt
    #   Version 4.19 beta           2005-05-21
    #   Version 4.14 beta           2005-01-11
    #   Version 4.10 beta           2004-10-21
    #   Version 4.07 beta           2004-10-03
    # ...
    # so we want the blocks: 4.19 4.14 4.10
    # because: 3.13 < 4.10 4.14 4.19 <= 4.20
    # we assume that the "<=" part (the upper bound) is always true
    # because the history file should not contain future versions
    # so we only check the "<" part (the lower bound)

    first_history_version_line="$(
      cat "$history_path" |
      tr -d $'\r' |
      tail -n +4 |
      grep -E '^  Version [0-9]+\.[0-9]+( beta)? +[0-9]{4}-[0-9]{2}-[0-9]{2}$' |
      head -n1
    )"

    first_history_version="$(
      echo $first_history_version_line |
      sed -E 's/^Version (.*) [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1/' |
      tr '[[:upper:]]' '[[:lower:]]'
    )"

    # note: this can be empty, for example for version 4.57
    first_history_date="$(
      echo $first_history_version_line |
      sed -E 's/^.* ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/'
    )"

    # debug
    if [[ -z "$first_history_date" ]]; then
      echo "FIXME empty first_history_date. first_history_version_line: '$first_history_version_line'. archive_path: '$archive_path'"
      exit 1
    fi

    commit_message="version $archive_version"$'\n\n'"$(
      # read the history file line by line
      # we need "IFS= read -r" to preserve leading space in lines
      # https://stackoverflow.com/questions/29689172/bash-read-ignores-leading-spaces
      while IFS= read -r history_line; do
        echo "history line: $history_line" >&2
        history_version_line="$(echo "$history_line" | grep -E '^  Version [0-9]+\.[0-9]+( beta)? +[0-9]{4}-[0-9]{2}-[0-9]{2}$')"
        if [[ -n "$history_version_line" ]]; then
          echo "history version line: $history_version_line" >&2
          # check bounds of version
          history_version=$(echo $history_version_line | cut -d' ' -f2-3 | sed -E 's/ [0-9]{4}-[0-9]{2}-[0-9]{2}$//' | tr '[[:upper:]]' '[[:lower:]]')

          # note: this can be empty, for example for version 4.57
          history_date="$(
            echo $history_version_line |
            sed -E 's/^.* ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/'
          )"

          # debug
          if [[ -z "$history_date" ]]; then
            echo "FIXME empty history_date. history_version_line: '$history_version_line'. archive_path: '$archive_path'" >&2
            # FIXME this does not stop the script
            #exit 1
          fi

          # debug
          echo "history version: $history_version - parsed from history_version_line: $history_version_line" >&2
          # compare $history_version and $prev_archive_version
          if [[ "$history_version" == "$prev_archive_version" ]]; then
            break
          fi
          if [[ "$history_version" == "$prev_first_history_version" ]]; then
            break
          fi
          if [[ -n "$history_date" ]] && [[ -n "$prev_history_date" ]] && [[ "$history_date" == "$prev_history_date" ]]; then
            break
          fi
          if [[ "$(echo "$history_version"$'\n'"$prev_archive_version" | sort --version-sort | head -n1)" == "$history_version" ]]; then
            # $history_version < $prev_archive_version
            break
          fi
          echo "$history_line" | sed -E 's/^  //; s/^ +$//'
        else
          echo "$history_line" | sed -E 's/^  //; s/^ +$//'
        fi
      done < <(
        # debug
        echo "reading history file: $history_path" >&2
        # tail -n +4: remove the first 3 lines with the "Sources history of the 7-Zip" heading
        cat "$history_path" | tr -d $'\r' | tail -n +4
      )
    )"

  elif [[ "$history_format" == 2 ]]; then

    # headings in the new format:
    # $ cat DOC/history.txt | grep -E '^[0-9]+\.[0-9]+'
    # 4.59           2008-07-27
    # 4.59 alpha     2008-05-30
    # 4.58 alpha 8   2008-04-15
    # 4.57
    # 4.50 beta      2007-07-24
    # 4.27           2005-09-21
    # 3.08.02        2003-09-20
    # 2.30 Beta 32   2003-05-15
    # 2.30 Beta 9    2002-01-08

    first_history_version_line="$(
      cat "$history_path" |
      tr -d $'\r' |
      tail -n +4 |
      grep -E '^[0-9]+\.[0-9]+' |
      head -n1
    )"

    # note: the date can be missing
    first_history_version="$(
      echo $first_history_version_line |
      sed -E 's/^(.*) [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1/' |
      tr '[[:upper:]]' '[[:lower:]]'
    )"

    # note: the date can be empty, for example for version 4.57
    first_history_date="$(
      echo $first_history_version_line |
      grep -o -E '[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    )"

    # debug
    if [[ -z "$first_history_date" ]]; then
      echo "FIXME empty first_history_date. first_history_version_line: '$first_history_version_line'. archive_path: '$archive_path'"
      exit 1
    fi

    commit_message="version $archive_version"$'\n\n'"$(
      # read the history file line by line
      # we need "IFS= read -r" to preserve leading space in lines
      # https://stackoverflow.com/questions/29689172/bash-read-ignores-leading-spaces
      while IFS= read -r history_line; do
        echo "history line: $history_line" >&2
        history_version_line="$(echo "$history_line" | grep -E '^[0-9]+\.[0-9]+')"
        if [[ -n "$history_version_line" ]]; then
          echo "history version line: $history_version_line" >&2
          # check bounds of version
          history_version=$(echo $history_version_line | sed -E 's/ [0-9]{4}-[0-9]{2}-[0-9]{2}$//' | tr '[[:upper:]]' '[[:lower:]]')

          # note: the date can be empty. the only known case is version 4.57
          history_date="$(
            echo $history_version_line |
            grep -o -E '[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          )"

          # debug
          if [[ -z "$history_date" ]]; then
            if [[ "$history_version_line" == "4.57" ]]; then
              # use archive_date of version 4.57
              # stat -c%y tarballs/downloads.sourceforge.net/project/sevenzip/7-Zip/4.57/7z457.tar.bz2
              history_date="2007-12-06"
            else
              echo "FIXME empty history_date. history_version_line: '$history_version_line'. archive_path: '$archive_path'" >&2
              # FIXME this does not stop the script
              #exit 1
            fi
          fi

          # debug
          echo "history version: $history_version - parsed from history_version_line: $history_version_line" >&2
          # compare $history_version and $prev_archive_version
          if [[ "$history_version" == "$prev_archive_version" ]]; then
            break
          fi
          if [[ "$history_version" == "$prev_first_history_version" ]]; then
            break
          fi
          if [[ -n "$history_date" ]] && [[ -n "$prev_history_date" ]] && [[ "$history_date" == "$prev_history_date" ]]; then
            break
          fi
          if [[ "$(echo "$history_version"$'\n'"$prev_archive_version" | sort --version-sort | head -n1)" == "$history_version" ]]; then
            # $history_version < $prev_archive_version
            break
          fi
          echo "$history_line" | sed -E 's/^  //; s/^ +$//'
        else
          echo "$history_line" | sed -E 's/^  //; s/^ +$//'
        fi
      done < <(
        # debug
        echo "reading history file: $history_path" >&2
        # tail -n +4: remove the first 3 lines with the "Sources history of the 7-Zip" heading
        cat "$history_path" | tr -d $'\r' | tail -n +4
      )
    )"

  #elif [ -e "DOC/src-history.txt" ]; then
  #  echo "FIXME implement parsing of DOC/src-history.txt"
  #  exit 1
  #else
  #  echo "FIXME: missing DOC/src-history.txt in version $archive_version"
  #  exit 1
  #  commit_message="version $archive_version"

  fi

  {
    echo "scraper/"
    echo "tarballs/"
  } >.gitignore
  git add .
  git rm -f .gitignore >/dev/null

  echo "git commit ..."

  GIT_AUTHOR_NAME="$author_name" \
  GIT_AUTHOR_EMAIL="$author_email" \
  GIT_COMMITTER_NAME="$author_name" \
  GIT_COMMITTER_EMAIL="$author_email" \
  GIT_AUTHOR_DATE="$archive_date" \
  GIT_COMMITTER_DATE="$archive_date" \
  git commit -m "$commit_message" >/dev/null || {
    echo "failed to 'git commit'"
    exit 1
  }

  echo "git commit done"

  git_tag=$(echo $archive_version | sed 's/ /-/g')
  git tag "$git_tag"

  prev_archive_version="$archive_version"
  prev_first_history_version="$first_history_version"
  prev_first_history_date="$first_history_date"

  echo

done < <(
  find tarballs/downloads.sourceforge.net/ -type f |
  sort --version-sort
)
