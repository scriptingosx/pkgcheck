#!/bin/zsh

# pkgcheck.sh

# 2019 - Armin Briegel - Scripting OS X

# this script will look into pkg files and warn if any of the installation scripts
# use one of the following shebangs:
# 
# /bin/bash
# /usr/bin/python
# /usr/bin/perl
# /usr/bin/ruby
#
# also checks for signatures and notarization and other information 


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

function getPkgSignature() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    signature=$(pkgutil --check-signature "$pkgpath" | fgrep '1. ' | cut -c 8- )
    if [[ -z $signature ]]; then
        signature="$fg[yellow]None$reset_color"
    fi
    echo "$fg[green]$signature$reset_color"
    return
}

function getPkgNotarized() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    
    notary_source=$(spctl --assess -vvv --type install $pkgpath 2>&1 | awk -F '=' '/source/ { print $2 }')

    if [[ $notary_source == "Notarized Developer ID" ]]; then
        echo "$fg[green]Yes, $notary_source$reset_color"
    else
        echo "$fg[yellow]No${notary_source:+, $notary_source}$reset_color"
    fi
}

function getInfoPlistValueForKey() { # $1: pkgpath $2: key
    local pkgpath=${1:?"no pkg path"}
    local key=${2:?"no key"}
    
    infoplist="$pkgpath/Contents/Info.plist"
    if [[ -r "$infoplist" ]]; then
        /usr/libexec/PlistBuddy -c "print $key" "$infoplist"
    fi
    return
}

function checkFilesInDir() { # $1: dirpath $2: level
    local dirpath=${1:?"no directory path"}
    
    local level=${2:-0}
    if [[ level -gt 0 ]]; then
        indent="    "
    else
        indent=""
    fi
    
    local foundscripts=$(find "$dirpath" -type f -print0 )
    local scriptfiles=( ${(0)foundscripts} )
    local scripts_count=${#scriptfiles}
    
    echo "${indent}Contains $scripts_count resource files"
    
    for f in "${scriptfiles[@]}"; do
        if [[ -e "$f" ]]; then
            relpath="${f#"$dirpath/"}"
            
            file_description="$(file -b "$f")"
            #echo "$indent$file_description"
            if [[ "$file_description" == *"script text executable"* ]]; then
                
                # check for deprecated shebangs
                shebang=$(head -n 1 "$f" | tr -d $'\n')
                lastelement=${shebang##*/}
                if [[ $shebang == "#!/bin/bash" || \
                      $shebang == "#!/usr/bin/env bash" || \
                      $shebang == "#!/usr/bin/ruby" || \
                      $shebang == "#!/usr/bin/env ruby" || \
                      $shebang == "#!/usr/bin/perl" || \
                      $shebang == "#!/usr/bin/env perl" ]]; then
                    echo "$indent$fg[yellow]$relpath has shebang $shebang$reset_color"
                fi
                
                # python gets extra treatment since it will break in macOS 12.3+
                if [[ $shebang == "#!/usr/bin/python" || \
                      $shebang == "#!/usr/bin/env python" ]]; then
                    echo "$indent$fg[red]$relpath has shebang $shebang$reset_color"
                fi

                # check for uses of 'python' in code
                if grep --invert-match '^#' "$f" | grep --quiet 'python'; then
                    echo "$indent$fg[red]$relpath calls 'python' in code$reset_color"
                fi
            fi
        fi
    done
}

function checkBundlePKG() { # $1: pkgpath $2: level
    local pkgpath=${1:?"no pkg path"}
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension
    
    local level=${2:-0}
    if [[ level -gt 0 ]]; then
        indent="    "
        echo $indent$bold_color$pkgname$reset_color
        #echo $indent$pkgpath
    else
        indent=""
    fi
    
    echo $indent"Type:           PKG Bundle"    
    
    # get version and identifier
    
    pkgidentifier=$(getInfoPlistValueForKey "$pkgpath" "CFBundleIdentifier")
    if [[ -n $pkgidentifier ]]; then
        echo $indent"Identifier:     $pkgidentifier" 
    fi
    
    pkgversion=$(getInfoPlistValueForKey "$pkgpath" "CFBundleShortVersionString")
    if [[ -n $pkgversion ]]; then
        echo $indent"Version:        $pkgversion" 
    fi

    pkglocation=$(getInfoPlistValueForKey "$pkgpath" "IFPkgFlagDefaultLocation")
    if [[ -n $pkglocation ]]; then
        echo $indent"Location:       $pkglocation" 
    fi
    
    # check files resources folder
    resourcesfolder="$pkgpath/Contents/Resources"
    if [[ -d $resourcesfolder ]]; then
        checkFilesInDir "$resourcesfolder" "$level"
    fi
    
    echo
}

function checkBundleMPKG() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension
    
    echo "Type:           MPKG Bundle"
    
    IFS=$'\n'
    components=( $(find "$pkgpath" -iname '*.pkg') )
    components_count=${#components}
    echo "Contains $components_count component pkgs"
    echo
        
    for component in "${components[@]}"; do
        checkBundlePKG "$component" 1
    done
}

function checkComponentPKG() { # $1: pkgpath $2: level
    local pkgpath=${1:?"no pkg path"}
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension

    local level=${2:-0}
    if [[ level -gt 0 ]]; then
        indent="    "
        echo
        echo $indent$bold_color$pkgname$reset_color
        echo $indent$pkgpath
    else
        indent=""
    fi
    
    echo $indent"Type:           Flat Component PKG"
    
    # expand the flat pkg
    local pkgdir="$scratchdir/$pkgname"
        
    if [[ -d "$pkgdir" ]] ; then
        rm -r "$pkgdir" || return 1
    fi
    pkgutil --expand "$pkgpath" "$pkgdir"
    
    # determine identifier and version, if present
    pkginfo="$pkgdir/PackageInfo"
    if [[ -f "$pkginfo" ]]; then
        # try to extract identifier
        pkgidentifier=$(xmllint --xpath "string(//pkg-info/@identifier)" ${pkginfo})
        if [[ -n $pkgidentifier ]]; then
            echo "Identifier:     $pkgidentifier"
        fi
        pkgversion=$(xmllint --xpath "string(//pkg-info/@version)" ${pkginfo})
        if [[ -n $pkgversion ]]; then
            echo "Version:        $pkgversion"
        fi
        pkglocation=$(xmllint --xpath "string(//pkg-info/@install-location)" ${pkginfo})
        if [[ -n $pkglocation ]]; then
            echo "Location:       $pkglocation"
        fi

    fi

    # does the pkg have a Scripts dir?
    if [[ -d "$pkgdir/Scripts" ]] ; then
        checkFilesInDir "$pkgdir/Scripts" "$level"
    fi
    
    echo
    # clean up
    rm -rf "$pkgdir"
}

function checkDistributionPKG() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension

    echo "Type:           Flat Distribution PKG"
    
    # expand the flat pkg
    local pkgdir="$scratchdir/$pkgname"
        
    if [[ -d "$pkgdir" ]] ; then
        rm -r "$pkgdir" || return 1
    fi
    pkgutil --expand "$pkgpath" "$pkgdir"
    
    # determine identifier and version, if present
    distributionxml="$pkgdir/Distribution"
    if [[ -f "$distributionxml" ]]; then
        # distribution pkg, try to extract identifier
        pkgidentifier=$(xmllint --xpath "string(//installer-gui-script/product/@id)" ${distributionxml})
        if [[ -n $pkgidentifier ]]; then
            echo "Identifier:     $pkgidentifier"
        fi
        pkgversion=$(xmllint --xpath "string(//installer-gui-script/product/@version)" ${distributionxml})
        if [[ -n $pkgversion ]]; then
            echo "Version:        $pkgversion"
        fi
    fi

    # find component pkgs
    IFS=$'\n'
    components=($(ls -d1 "$pkgdir"/*.pkg))
    components_count=${#components}
    echo "Contains ${#components} component pkgs"
    echo

    if [[ $components_count -gt 0 ]]; then
        for c in $components ; do
            echo "    $bold_color$cname$reset_color"
            echo "    Type:           Flat Component PKG"
            
            # determine identifier and version, if present
            pkginfo="$c/PackageInfo"
            if [[ -f "$pkginfo" ]]; then
                # try to extract identifier
                pkgidentifier=$(xmllint --xpath "string(//pkg-info/@identifier)" "${pkginfo}")
                if [[ -n $pkgidentifier ]]; then
                    echo "    Identifier:     $pkgidentifier"
                fi
                pkgversion=$(xmllint --xpath "string(//pkg-info/@version)" "${pkginfo}")
                if [[ -n $pkgversion ]]; then
                    echo "    Version:        $pkgversion"
                fi
                pkglocation=$(xmllint --xpath "string(//pkg-info/@install-location)" "${pkginfo}")
                if [[ -n $pkglocation ]]; then
                    echo "    Location:       $pkglocation"
                fi
            fi

            
            # does the pkg have a Scripts directory?
            if [[ -d "$c/Scripts" ]] ; then
                checkFilesInDir "$c/Scripts" 1
            fi
            echo
        done
    fi
    # clean up
    rm -rf "$pkgdir"
}

function checkPkg() { # $1: pkgpath
    local pkgpath=${1:?"no pkg path"}
    local pkgfullname=$(basename $pkgpath)
    local pkgname=${pkgfullname%.*} # remove extension

    type=""    

    # if extension is not pkg or mpkg: no pkg installer
    if [[ $pkgpath != *.(pkg|mpkg) ]]; then
        type="no_pkg"
        echo "$pkgname has no pkg or mpkg file extension"
        return 1
    fi
    
    echo $bold_color$pkgname$reset_color
    echo $pkgpath
    echo "Signature:      "$(getPkgSignature "$pkgpath")
    if [[ $devtools == "installed" ]]; then
        echo "Notarized:      "$(getPkgNotarized "$pkgpath")
    fi
    
    # mpkg extension : mpkg bundle type
    if [[ $pkgpath == *.mpkg ]]; then
        checkBundleMPKG "$pkgpath"
        return 0
    elif [[ -d $pkgpath ]]; then
        checkBundlePKG "$pkgpath"
    else
        # flat pkg, look for Distribution
        distribution=$(xar -tf "$pkgpath" | grep Distribution 2>/dev/null )
        if [[ $? == 0 ]]; then
            checkDistributionPKG "$pkgpath"
        else
            # no distribution xml, likely a component pkg
            checkComponentPKG "$pkgpath"
        fi
    fi

}

function checkDmg() { # $1: dmgpath
    local dmgpath=${1:?"no dmg path"}
    
    if [[ ! -f $dmgpath ]]; then
        return 1
    fi
    
    # mount dmg
    # piping in 'Y' on stdin to auto-approve license agreements
    dmg_volume_path=$(echo 'Y' | hdiutil attach "$dmgpath" -noverify -nobrowse -readonly | tail -n 1 | cut -c 54- )
    
    echo "$fg[blue]Mounted $dmgpath to $dmg_volume_path${reset_color}"
    echo
    
    # check dmg
    checkDirectory "$dmg_volume_path"
    
    # unmount dmg
    if hdiutil detach "$dmg_volume_path" >/dev/null ; then
        echo "$fg[blue]unmounted $dmg_volume_path ($dmgpath)$reset_color"
    else
        echo "$fg[red]could not unmount $dmg_volume_path ($dmgpath)$reset_color"
    fi
    echo
}

function checkDirectory() { # $1: dirpath
    local dirpath=${1:?"no directory path"}
    
    if [[ ! -d $dirpath ]]; then
        return 1
    fi
        
    local foundpkgs=$(find "$dirpath" -not -ipath '*.mpkg/*' -and \( -iname '*.pkg' -or -iname '*.mpkg' \) -print0 )
    local pkglist=( ${(0)foundpkgs} )
    # find all pkg and mpkgs in the directory, excluding component pkgs in mpkgs
    for x in $pkglist ; do
        checkPkg "$x"
    done
    
    local founddmgs=$(find "$dirpath" -iname '*.dmg' -print0 )
    local dmglist=( ${(0)founddmgs} )
    # find all the dmgs in the directory
    for x in $dmglist; do
        checkDmg "$x"
    done
}

# reset zsh
emulate -LR zsh

# set -x

# load colors for nicer output
autoload -U colors && colors

# are the dev tools installed (this is required for the stapler tool)
if xcode-select -p >/dev/null; then
    devtools="installed"
else
    devtools="none"
fi

# this script's dir:
scriptdir=$(dirname $0)

# scratch space
scratchdir="$scriptdir/scratch/"
if ! mkcleandir "$scratchdir"; then
    echo "couldn't clean $scratchdir"
    exit 1
fi

for arg in "$@"; do
    arg_ext="${arg##*.}"
    if [[ $arg_ext == "pkg" || $arg_ext == "mpkg" ]]; then
        checkPkg "$arg"
    elif [[ $arg_ext == "dmg" ]]; then
        checkDmg "$arg"
    elif [[ -d $arg ]]; then
        checkDirectory "$arg"
    else
        echo
        echo "$fg[red]pkgcheck: cannot process $arg$reset_color"
        echo
    fi
done

exit 0

# todo
# √ check if pkg is signed
# √ check if pkg is notarized
# √ get pkg version when available
# √ get pkg identifier when available
# √ when arg 1 ends in pkg or mpkg use that as the only target
# - show if components are enabled or disabled
# - clean up code to work on flat components inside a distribution pkg
# √ show install location
# - mount dmg files and inspect pkgs inside


