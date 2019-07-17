#!/bin/zsh

# CheckInstallationScripts.zsh

# this script will look into pkg files and warn if any of the installation scripts
# use one of the following shebangs:
# 
# /bin/bash
# /usr/bin/python
# /usr/bin/perl
# /usr/bin/ruby
#
# also checks for signatures and notarization


function mkcleandir() { # $1: dirpath
    local dirpath=${1:?"no dir path"}
    if [[ -d $dirpath ]]; then
        if ! rm -rf "${dirpath:?no dir path}"; then
            return 1
        fi
    fi
    if ! mkdir -p "$dirpath"; then
        return 2
    fi
}

function pkgType() { #1: path to pkg
    local pkgpath=${1:?"no pkg path"}
    
    # if extension is not pkg or mpkg: no pkg installer
    if [[ $pkgpath != *.(pkg|mpkg) ]]; then
        echo "no_pkg"
        return 1
    fi
    
    # mpkg extension : mpkg bundle type
    if [[ $pkgpath == *.mpkg ]]; then
        echo "bundle_mpkg"
        return 0
    fi
    
    # if it is a directory with a pkg extension it is probably a bundle pkg
    if [[ -d $pkgpath ]]; then
        echo "bundle_pkg"
        return 0
    else
        # flat pkg, try to extract Distribution XML
        distributionxml=$(tar -xOf "$pkgpath" Distribution 2>/dev/null )
        if [[ $? == 0 ]]; then
            # distribution pkg, try to extract identifier
            identifier=$(xmllint --xpath "string(//installer-gui-script/product/@id)" - <<<${distributionxml})
            if [[ $? != 0 ]]; then
                # no identifier, normal distribution pkg
                echo "flat_distribution"
                return 0
            else
                echo "flat_distribution_productarchive"
                return 0
            fi
        else
            # no distribution xml, likely a component pkg
            echo "flat_component"
            return 0
        fi
    fi
}

function getComponentPkgScriptDir() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension
    
    local extractiondir="$scratchdir/$pkgname"
    if ! mkcleandir $extractiondir; then
        #echo "couldn't clean $extractiondir"
        return 1
    fi
    
    # does the pkg _have_ a Scripts archive
    if tar -tf "$pkgpath" Scripts &>/dev/null; then
        # extract the Scripts archive to scratch
        if ! tar -x -C "$extractiondir" -f "$pkgpath" Scripts; then
            #echo "error extracting Scripts Archive from $pkgpath"
            return 2
        fi
    
        # extract the resources from the Scripts archive
        if ! tar -x -C "$extractiondir" -f "$extractiondir/Scripts"; then
            #echo "error extracting Scripts from $extractiondir/Scripts"
            return 3
        fi
    
        # remove the ScriptsArchive
        rm "$extractiondir/Scripts"
    fi
    
    # return the dir with the extracted scripts
    echo "$extractiondir"
    
    return
}

function getDistributionPkgScriptDirs() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    
    local pkgpath=${1:?"no pkg path"}
    
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension
    
    local pkgdir="$scratchdir/$pkgname"
    
    scriptdirs=( )
    
    if ! mkcleandir $pkgdir; then
        #echo "couldn't clean $pkgdir"
        return 1
    fi
    
    # does the pkg _have_ Scripts archives?
    if components=( $(tar -tf "$pkgpath" '*.pkg$' 2>/dev/null) ); then
        for c in $components ; do
            # get the components's name
            local cname=${c%.*} # remove extension
            
            # create a subdir in extractiondir
            local extractiondir="$pkgdir/$cname"
            if ! mkcleandir $extractiondir; then
                #echo "couldn't clean $extractiondir"
                return 1
            fi
            
            # does the pkg _have_ a Scripts archive
            if tar -tf "$pkgpath" "$c/Scripts" &>/dev/null; then
                # extract the Scripts archive to scratch
                if ! tar -x -C "$extractiondir" -f "$pkgpath" "$c/Scripts"; then
                    #echo "error extracting Scripts Archive from $pkgpath"
                    return 2
                fi
    
                # extract the resources from the Scripts archive
                if ! tar -x -C "$extractiondir" -f "$extractiondir/$c/Scripts"; then
                    #echo "error extracting Scripts from $extractiondir/$c/Scripts"
                    return 3
                fi
    
                # remove the ScriptsArchive
                rm -rf "$extractiondir/$c"
            fi
    
            # return the dir with the extracted scripts
            scriptdirs+="$extractiondir"
        done
    fi
    
    return
}


function getScriptDirs() { #$1: pkgpath, $2: pkgType
    local pkgpath=${1:?"no pkg path"}
    local pkgtype=${2:?"no pkg type"}
    
    case $pkgtype in
        bundle_mpkg)
            scriptdirs=( $pkgpath/Contents/Packages/*.pkg/Contents/Resources )
            ;;
        bundle_pkg)
            scriptdirs=( $pkgpath/Contents/Resources )
            ;;
        flat_component)
            scriptdirs=( "$(getComponentPkgScriptDir $pkgpath)" )
            ;;
        flat_distribution*)
            getDistributionPkgScriptDirs $pkgpath
            ;;
        *)
            :
            ;;
    esac
    return
}

function checkFile() { # $1: file path
    local filepath=${1:?"no file path"}
    
    file "$filepath"
}

# reset zsh
emulate -LR zsh

#set -x

setopt shwordsplit

# load colors for nicer output
autoload -U colors && colors

# this script's dir:
scriptdir=$(dirname $0)

typeset -a scriptdirs
scriptdirs=( )

# scratch space
scratchdir="$scriptdir/scratch/"
if ! mkcleandir "$scratchdir"; then
    echo "couldn't clean $scratchdir"
    exit 1
fi

# sample file
targetdir=${1:-"$scriptdir/SamplePkgs"}
if [[ ! -d $targetdir ]]; then
    echo "argument 1 should be a directory"
    exit 1
fi

IFS=$'\n'
for x in $(find "$targetdir" -not -ipath '*.mpkg/*' -and \( -iname '*.pkg' -or -iname '*.mpkg' \) ) ; do
    t=$(pkgType "$x")
    getScriptDirs "$x" "$t"
    echo $bold_color$x$reset_color
    echo "Type:          " $t
    
    #echo "Script Dirs:   " $scriptdirs
    for sdir in $scriptdirs; do
        #echo $sdir
        for f in $(find "$sdir" -type f ); do
            if [[ -e "$f" ]]; then
                if [[ $(file "$f") == *"script text executable"* ]]; then
                    shebang=$(head -n 1 "$f" | tr -d $'\n')
                    lastelement=${shebang##*/}
                    if [[ $shebang == "#!/bin/bash" || \
                          $shebang == "#!/usr/bin/python" || \
                          $shebang == "#!/usr/bin/ruby" || \
                          $shebang == "#!/usr/bin/perl" ]]; then
                        echo "$fg[yellow]$f has shebang $shebang$reset_color"
                    fi
                fi
            fi
        done
    done
done

