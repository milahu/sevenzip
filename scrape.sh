#! /usr/bin/env bash

debug=false
#debug=true

function sourceforge_get_file_urls() {

  # return one folder per line, multiple file urls per line

  local folder_url="$1"

  local html="$(curl -s "$folder_url")"

  local links="$(echo "$html" | grep '^<th scope="row" headers="files_name_h"><a href' | cut -d'"' -f6 | sed 's|^/|https://sourceforge.net/|')"

  $debug && echo "sourceforge_get_file_urls: links:" >&2
  $debug && echo "$links" | sed 's/^/  /' >&2

  # loop files
  # convert file urls to "proper basename" urls = locally resolve the first http redirect
  # example:
  # a: https://          sourceforge.net/projects/sevenzip/files/7-Zip/21.07/7z2107-src.tar.xz/download
  # b: https://downloads.sourceforge.net/project /sevenzip      /7-Zip/21.07/7z2107-src.tar.xz
  $debug && echo "sourceforge_get_file_urls: looping files" >&2
  file_links=$(echo "$links" | grep '/download$')
  if [ -n "$file_links" ]; then
    echo "$file_links" |
    sed -E 's|^https://sourceforge.net/projects/([^/]+)/files/([^/]+)/(.*?)/download$|https://downloads.sourceforge.net/project/\1/\2/\3|' |
    xargs echo -n
    echo
  fi

  # loop folders
  $debug && echo "sourceforge_get_file_urls: looping folders" >&2
  while read next_folder_url; do
    # recurse
    $debug && echo "sourceforge_get_file_urls: recurse from $folder_url to $next_folder_url" >&2
    sourceforge_get_file_urls "$next_folder_url"
  done < <(echo "$links" | grep '/$')
}



if ! [ -d tarballs ]; then
  if ! git worktree add tarballs tarballs; then
    echo "error: failed to mount the branch 'tarballs'"
    exit 1
  fi
fi

cd tarballs

sourceforge_get_file_urls https://sourceforge.net/projects/sevenzip/files/7-Zip/ 7zip-files |
while read folder_urls; do
  folder_urls=$(echo "$folder_urls" | tr ' ' $'\n')
  $debug && echo -e "folder_urls:\n$folder_urls"
  # pick only one file per folder
  file_url="$folder_urls"
  file_url=$(echo "$file_url" | grep -E '/7z[0-9]+(-src\.tar\.xz|-src\.7z|\.tar\.bz2)$')
  if [[ "$(echo "$file_url" | wc -l)" != 1 ]]; then
    # we still have multiple file urls
    # remove *.7z
    # example file urls:
    # https://downloads.sourceforge.net/project/sevenzip/7-Zip/22.01/7z2201-src.tar.xz
    # https://downloads.sourceforge.net/project/sevenzip/7-Zip/22.01/7z2201-src.7z
    file_url=$(echo "$file_url" | grep -E '/7z[0-9]+(-src\.tar\.xz|\.tar\.bz2)$')
  fi
  if [[ "$(echo "$file_url" | wc -l)" != 1 ]]; then
    # we still have multiple file urls
    echo "FIXME filter file urls:" >&2
    echo "$file_url" | sed 's/^/  /' >&2
  fi
  if [[ "$(echo "$file_url" | wc -l)" == 1 ]]; then
    $debug && echo "ok: $file_url" >&2
  fi
  echo "$file_url"
done |
xargs -n1 wget --no-clobber --recursive --level=1

cd ..

# note: "wget --no-clobber" assumes that existing files are valid

# list all downloaded files, sort by version
echo "downloaded files:"
find tarballs/downloads.sourceforge.net/ -type f | sort -V | sed 's/^/  /'
