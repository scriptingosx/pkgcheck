# Check Installer Pkgs for deprecated scripts

macOS 10.15 Catalina [deprecated the built-in `/bin/bash`](https://support.apple.com/en-us/HT208050). [I have talked about this at length](https://scriptingosx.com/2019/06/moving-to-zsh/).

The [release notes for Catalina](https://developer.apple.com/documentation/macos_release_notes/macos_catalina_10_15_beta_6_release_notes) also tell us that other built-in scripting runtimes, namely Python, Perl, and Ruby. Will not be included in future macOS releases (post-Catalina) any more.

[Starting with macOS 12.3](https://developer.apple.com/documentation/macos-release-notes/macos-12_3-release-notes), the Python 2.7 binary `/usr/bin/python` will _not_ work anymore. Calls to `python` will fail.

This means, that if you want to use bash, Python, Perl, or Ruby on macOS, you will have to install, and maintain your own version in the future.

However, scripts in installation packages, _cannot_ rely on any of these interpreters being available in future, post-Catalina versions of macOS. Installer pkgs can be run in all kinds of environments and at all times, and you would not want them to fail, because a dependency is missing.

If you are building installation scripts, you need to check if any of the installation scripts use one of these interpreters and fix them.

> I recommend to use `/bin/sh` for installation scripts, since that will run in _any_ macOS context, even the Recovery system and a 'future' macOS that may not have `/bin/bash` 

If you are using third-party installer packages, you may also want to check them for these interpreters, and notify the developer that these packages will break in future versions of macOS.

To check a flat installer package, you would expand it with `pkgutil --expand` and then look at script files in the `Scripts` folder. This will work fine for a package or two, but gets tedious really quickly, especially with large distribution pkgs with many components (e.g. Office).

So... I wrote a script to do it. The script should handle normal component pkgs, distribution pkgs and the legacy bundle pkgs and mpkgs. It will also 

## What the script does

Once I had written the code to inspect all these types of pkgs, I realized I could grab all _other_ kinds of information, as well. The `pkgcheck.sh` script will check for:

- Signature _and_ Notarization
- Type of Package: Component, Distribution, legacy bundle or mpkg
- Identifier and version (when present)
- Install-location
- for Distribution and mpkg types, shows the information for all components as well
- for every script in a pkg or component, checks the first line of the script for shebangs of the deprecated interpreters (`/bin/bash`, `/usr/bin/python`, `/usr/bin/perl`, and `/usr/bin/ruby`, also using these binaries with `/usr/bin/env`) and print a warning when found
- `/usr/bin/python` and `/usr/bin/env python` will show an error
- if the script contains the string `python` (that is not in a comment line) it will also show an error, this might generate some false positives (for example, calls to `python3` will also trigger this, but they would probably be problematic, as well)

## How to run pkgcheck.sh

Run the script with the target pkg file as an argument:

```
% ./pkgcheck.sh sample.pkg
```

You can give more than one file:

```
% ./pkgcheck.sh file1.pkg file2.pkg ...
```

When you pass a directory, `pkgcheck.sh` will _recursively_ search for all files or bundle directories with the `pkg` or `mpkg` extension in that directory:

```
% ./pkgcheck.sh SamplePkgs
```

## Features and Errors

There are a few more things that I think might be useful to check in this script. Most of all, I want to add an indicator whether a component is enabled by default or not. If you can think of any other valuable data to display, let me know. (Issue or Pull Request or just ping me on MacAdmins Slack)

I have tested the script against many pkgs that I came across. However, there are likely edge cases that I haven't anticipated, which might break the script. If you run into any of those, let me know. (File an Issue or Pull Request.) Having the troublesome pkg would of course be a great help.

Note: the script will create a `scratch` directory for temporary file extractions. The script doesn't actually expand the entire pkg file, only the `Scripts` sub-archive. The `scratch` folder will be cleaned out at the beginning of the next run, but not when the script ends, as you might want to do some further inspections.

## Sample outputs

This is a sample pkg I build in my book, it has pre- and postinstall scripts using a `/bin/bash` shebang:

```
% ./pkgcheck.sh SourceCodePro-2.030d.pkg
SourceCodePro-2.030d
SamplePkgs/SourceCodePro-2.030d.pkg
Signature:      None
Notarized:      No
Type:           Flat Component PKG
Identifier:     com.example.SourceCodePro
Version:        2.030d
Location:       /
Contains 2 resource files
postinstall has shebang #!/bin/bash
preinstall has shebang #!/bin/bash
```

This is the experimental _notarized_ pkg installer for [`desktoppr`](https://github.com/scriptingosx/desktoppr):

```
% ./pkgcheck.sh desktoppr-0.2.pkg
desktoppr-0.2
SamplePkgs/desktoppr-0.2.pkg
Signature:      Developer ID Installer: Armin Briegel (JME5BW3F3R)
Notarized:      Yes
Type:           Flat Component PKG
Identifier:     com.scriptingosx.desktoppr
Version:        0.2
Contains 0 resource files
```

And finally, this is a big one, the Microsoft Office installer: (they have some work to do to clean up those scripts)

```
% ./pkgcheck.sh Microsoft\ Office\ 16.27.19071500_Installer.pkg
Microsoft Office 16.27.19071500_Installer
SamplePkgs/Microsoft Office 16.27.19071500_Installer.pkg
Signature:      Developer ID Installer: Microsoft Corporation (UBF8T346G9)
Notarized:      No
Type:           Flat Distribution PKG
Contains 11 component pkgs

    Microsoft_Word_Internal
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_Word.app
    Version:        16.27.19071500
    Location:       /Applications
    Contains 3 resource files

    Microsoft_Excel_Internal
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_Excel.app
    Version:        16.27.19071500
    Location:       /Applications
    Contains 2 resource files

    Microsoft_PowerPoint_Internal
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_PowerPoint.app
    Version:        16.27.19071500
    Location:       /Applications
    Contains 2 resource files

    Microsoft_OneNote_Internal
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_OneNote.app
    Version:        16.27.19071500
    Location:       /Applications
    Contains 2 resource files

    Microsoft_Outlook_Internal
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_Outlook.app
    Version:        16.27.19071500
    Location:       /Applications
    Contains 2 resource files

    OneDrive
    Type:           Flat Component PKG
    Identifier:     com.microsoft.OneDrive
    Version:        19.70.410
    Location:       /Applications
    Contains 30 resource files
    postinstall has shebang #!/bin/bash
    od_logging has shebang #!/bin/bash
    od_service has shebang #!/bin/bash
    od_migration has shebang #!/bin/bash
    preinstall has shebang #!/bin/bash

    Office16_all_autoupdate
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Microsoft_AutoUpdate.app
    Version:        4.13.19071500
    Location:       /Library/Application Support/Microsoft/MAU2.0
    Contains 2 resource files
    postinstall has shebang #!/bin/bash
    preinstall has shebang #!/bin/bash

    Office16_all_licensing
    Type:           Flat Component PKG
    Identifier:     com.microsoft.pkg.licensing
    Version:        16.27.19071500
    Location:       /
    Contains 2 resource files
    dockutil has shebang #!/usr/bin/python

    Office_fonts
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.DFonts
    Version:        0
    Location:       /private/tmp/com.microsoft.package.DFonts
    Contains 1 resource files
    postinstall has shebang #!/bin/bash

    Office_frameworks
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Frameworks
    Version:        0
    Location:       /private/tmp/com.microsoft.package.Frameworks
    Contains 1 resource files
    postinstall has shebang #!/bin/bash

    Office_proofing
    Type:           Flat Component PKG
    Identifier:     com.microsoft.package.Proofing_Tools
    Version:        0
    Location:       /private/tmp/com.microsoft.package.Proofing_Tools
    Contains 1 resource files
    postinstall has shebang #!/bin/bash

```


