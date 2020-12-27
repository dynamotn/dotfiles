#!/bin/bash

DIR=$(dirname "$(readlink -f "$0")")

if ! command -v fontforge &> /dev/null; then
  echo "You must install python-fontforge to use this script"
fi
# Make custom Iosevka fonts with ligatures from Fira Code v2
iosevka_version=$(curl -sSL https://api.github.com/repos/be5invis/Iosevka/releases/latest | grep -Po "tag_name\": \"(\K.*)(?=\",)")
temp_dir=$(mktemp -dp $DIR)
trap "rm -rf $temp_dir" EXIT
mkdir -p $DIR/../files/Community/Iosevka
curl -sSL https://github.com/be5invis/Iosevka/releases/download/$iosevka_version/ttf-iosevka-term-ss05-${iosevka_version:1}.zip -o $temp_dir/original.zip
unzip -qqo $temp_dir/original.zip -d $temp_dir
cd $DIR/liga
styles=(regular bold italic bolditalic)
style_names=("" " Bold" " Italic" " Bold Italic")
style_count=0
set -x
for style in ${styles[@]}; do
  fontforge -lang py -script ligaturize.py $temp_dir/iosevka-term-ss05-$style.ttf \
    --output-dir $DIR/../files/Community/Iosevka \
    --output-name="Iosevka Dynamo${style_names[$style_count]}" \
    --ligature-font-file $DIR/FiraCode/distr/otf/FiraCode-Regular.otf \
    --prefix="" --copy-character-glyphs
  ((style_count++))
done
