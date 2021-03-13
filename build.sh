#!/bin/bash

###############################
# FHEM - Create update script #
# v1.0.0 by Florian Asche     #
###############################

echo "publish changes in CHANGED logfile"
rm ${changed_file}
echo "Last updates ($(date +%d.%m.%Y))" > "${changed_file}"
git log -5 HEAD --pretty="  %h %ad %s" --date=format:"%d.%m.%Y %H:%M" FHEM/  >> ${changed_file}

echo "publish controlfile"
rm $CONTROLFILE
find ./www/pgm2 -type f \( ! -iname ".*" \) -print0 | while IFS= read -r -d '' f;
do
    out="UPD `stat --format "%z %s" $f | sed -e "s#\([0-9-]*\)\ \([0-9:]*\)\.[0-9]*\ [+0-9]*#\1_\2#"` $f"
    echo ${out//.\//} >> $CONTROLFILE
done

echo "add all files to git..."
git add -A

echo "...commit changes"
git commit -a -m "$*"

echo "...pull from github"
git pull

echo "...push to github"
git push





module_file="FHEM/77_Nina.pm"
commandref_de_source="CommandRef.de.md"
commandref_en_source="CommandRef.en.md"
meta_source="meta.json"
controls_file="controls_nina.txt"
changed_file="CHANGED"

#   +------------------------------------------------------------
#
#       Substitute the place holders in the module file with
#       the converted markdown documentation
#
#   +------------------------------------------------------------
substitute() {
    echo "" >> .${commandref_de_source}.html
    pandoc -fmarkdown_github -t html ${commandref_de_source} | \
        tidy -qi -w --show-body-only yes - >> .${commandref_de_source}.html
    echo "" >> .${commandref_de_source}.html
    sed -i -ne "/^=begin html_DE$/ {p; r .${commandref_de_source}.html" -e ":a; n; /^=end html_DE$/ {p; b}; ba}; p" ${module_file}

    echo "" >> .${commandref_en_source}.html
    pandoc -fmarkdown_github -t html ${commandref_en_source} | \
        tidy -qi -w --show-body-only yes - >> .${commandref_en_source}.html
    echo "" >> .${commandref_en_source}.html
    sed -i -ne "/^=begin html$/ {p; r .${commandref_en_source}.html" -e ":a; n; /^=end html$/ {p; b}; ba}; p" ${module_file}

    sed -i -ne "/^=for :application\/json;q=META.json "$module_file"$/ {p; r ${meta_source}" -e ":a; n; /^=end :application\/json;q=META.json$/ {p; b}; ba}; p" ${module_file}

    # clean up
    rm -rf .CommandRef.*

    # add created files
    git add FHEM/*.pm
    git add CommandRef.*
    git add meta.json
}

create_controlfile() {
    rm ${controls_file}
    find -type f \( -path './FHEM/*' -o -path './www/*' \) -print0 | while IFS= read -r -d '' f;
    do
        echo "DEL ${f}" >> ${controls_file}
        out="UPD `stat --format "%z %s" $f | sed -e "s#\([0-9-]*\)\ \([0-9:]*\)\.[0-9]*\ [+0-9]*#\1_\2#"` $f"
        echo ${out//.\//} >> ${controls_file}
    done

    git add ${controls_file}
}

update_changed() {
    rm ${changed_file}
    echo "Last Nina updates ($(date +%d.%m.%Y))" > "${changed_file}"
    # echo "" >> ${changed_file}
    git log -5 HEAD --pretty="  %h %ad %s" --date=format:"%d.%m.%Y %H:%M" FHEM/  >> ${changed_file}

    git add CHANGED
}

substitute
create_controlfile
update_changed