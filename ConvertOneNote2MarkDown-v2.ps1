[CmdletBinding()]
param ()

Function Validate-Dependencies {
    [CmdletBinding()]
    param ()

    # Validate assemblies
    if ( ($env:OS -imatch 'Windows') -and ! (Get-Item -Path $env:windir\assembly\GAC_MSIL\*onenote*) ) {
        "There are missing onenote assemblies. Please ensure the Desktop version of Onenote 2016 or above is installed." | Write-Warning
    }

    # Validate dependencies
    if (! (Get-Command -Name 'pandoc.exe') ) {
        throw "Could not locate pandoc.exe. Please ensure pandoc is installed."
    }
}

Function Get-DefaultConfiguration {
    [CmdletBinding()]
    param ()

    # The default configuration
    $config = [ordered]@{
        notesdestpath = @{
            description = @'
Specify folder path that will contain your resulting Notes structure - Default: c:\temp\notes
'@
            default = 'c:\temp\notes'
            validateOptions = 'directoryexists'
        }
        targetNotebook = @{
            description = @'
Specify a notebook name to convert
'': Convert all notebooks - Default
'mynotebook': Convert specific notebook named 'mynotebook'
'@
            default = ''
        }
        usedocx = @{
            description = @'
Whether to create new word docs or reuse existing ones
1: Always create new .docx files - Default
2: Use existing .docx files (90% faster)
'@
            default = 1
        }
        keepdocx = @{
            description = @'
Whether to discard word docs after conversion
1: Discard intermediate .docx files - Default
2: Keep .docx files
'@
            default = 1
        }
        prefixFolders = @{
            description = @'
Whether to use prefix vs subfolders
1: Create folders for subpages (e.g. Page\Subpage.md) - Default
2: Add prefixes for subpages (e.g. Page_Subpage.md)
'@
            default = 1
        }
        medialocation = @{
            description = @'
Whether to store media in single or multiple folders
1: Images stored in single 'media' folder at Notebook-level - Default
2: Separate 'media' folder for each folder in the hierarchy
'@
            default = 1
        }
        conversion = @{
            description = @'
Specify conversion type
1: markdown (Pandoc) - Default
2: commonmark (CommonMark Markdown)
3: gfm (GitHub-Flavored Markdown)
4: markdown_mmd (MultiMarkdown)
5: markdown_phpextra (PHP Markdown Extra)
6: markdown_strict (original unextended Markdown)
'@
            default = 1
        }
        headerTimestampEnabled = @{
            description = @'
Whether to include page timestamp and separator at top of document
1: Include - Default
2: Don't include
'@
            default = 1
        }
        keepspaces = @{
            description = @'
Whether to clear double spaces between bullets
1: Clear double spaces in bullets - Default
2: Keep double spaces
'@
            default = 1
        }
        keepescape = @{
            description = @'
Whether to clear escape symbols from md files
1: Clear '\' symbol escape character from files - Default
2: Keep '\' symbol escape
'@
            default = 1
        }
        keepPathSpaces = @{
            description = @'
Whether to replace spaces with dashes i.e. '-' in file and folder names
1: Replace spaces with dashes in file and folder names - Default
2: Keep spaces in file and folder names (1 space between words, removes preceding and trailing spaces)"
'@
            default = 1
        }
    }

    $config
}

Function New-ConfigurationFile {
    [CmdletBinding()]
    param ()

    # Generate a configuration file config.example.ps1
    @'
#
# Note: This config file is for those who are lazy to type in configuration everytime you run ./ConvertOneNote2MarkDown-v2.ps1
#
# Steps:
#   1) Rename this file to config.ps1. Ensure it is in the same folder as the ConvertOneNote2MarkDown-v2.ps1 script
#   2) Configure the options below to your liking
#   3) Run the main script: ./ConvertOneNote2MarkDown-v2.ps1. Sit back while the script starts converting immediately.
'@ | Out-File "$PSScriptRoot/config.example.ps1" -Encoding utf8

    $defaultConfig = Get-DefaultConfiguration
    foreach ($key in $defaultConfig.Keys) {
        # Add a '#' in front of each line of the option description
        $defaultConfig[$key]['description'].Trim() -replace "^|`n", "`n# " | Out-File "$PSScriptRoot/config.example.ps1" -Encoding utf8 -Append

        # Write the variable
        if ( $defaultConfig[$key]['default'] -is [string]) {
            "`$$key = '$( $defaultConfig[$key]['default'] )'" | Out-File "$PSScriptRoot/config.example.ps1" -Encoding utf8 -Append
        }else {
            "`$$key = $( $defaultConfig[$key]['default'] )" | Out-File "$PSScriptRoot/config.example.ps1" -Encoding utf8 -Append
        }
    }
}

Function Compile-Configuration {
    [CmdletBinding()]
    param ()

    # Get a default configuration
    $config = Get-DefaultConfiguration

    # Override configuration
    if (Test-Path $PSScriptRoot/config.ps1) {
        # Get override configuration from config file ./config.ps1
        & {
            . $PSScriptRoot/config.ps1
            foreach ($key in @($config.Keys)) {
                $config[$key]['value'] = Get-Variable -Name $key -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
                # Trim string
                if ($config[$key]['value'] -is [string]) {
                    $config[$key]['value'] = $config[$key]['value'].Trim()
                }
                # Remove trailing slash(es) for paths
                if ($key -match 'path' -and $config[$key]['value'] -match '[/\\]') {
                    $config[$key]['value'] = $config[$key]['value'].TrimEnd('/').TrimEnd('\')
                }
            }
        }
    }else {
        # Get override configuration from interactive prompts
        foreach ($key in $config.Keys) {
            "" | Write-Host -ForegroundColor Cyan
            $config[$key]['description'] | Write-Host -ForegroundColor Cyan
            # E.g. 'string', 'int'
            $typeName = [Microsoft.PowerShell.ToStringCodeMethods]::Type($config[$key]['default'].GetType())
            # Keep prompting until we get a answer of castable type
            do {
                # Cast the input as a type. E.g. Read-Host -Prompt 'Entry' -as [int]
                $config[$key]['value'] = Invoke-Expression -Command "(Read-Host -Prompt 'Entry') -as [$typeName]"
            }while ($null -eq $config[$key]['value'])
            # Fallback on default value if the input is empty string
            if ($config[$key]['value'] -is [string] -and $config[$key]['value'] -eq '') {
                $config[$key]['value'] = $config[$key]['default']
            }
            # Fallback on default value if the input is empty integer (0)
            if ($config[$key]['value'] -is [int] -and $config[$key]['value'] -eq 0) {
                $config[$key]['value'] = $config[$key]['default']
            }
        }
    }

    $config
}

Function Validate-Configuration {
    [CmdletBinding(DefaultParameterSetName='default')]
    param (
        [Parameter(ParameterSetName='default',Position=0)]
        [object]
        $Config
    ,
        [Parameter(ParameterSetName='pipeline',ValueFromPipeline)]
        [object]
        $InputObject
    )
    process {
        if ($InputObject) {
            $Config = $InputObject
        }
        if ($null -eq $Config) {
            throw "No input parameters specified."
        }

        # Validate a given configuration against a prototype configuration
        $defaultConfig = Get-DefaultConfiguration
        foreach ($key in $defaultConfig.Keys) {
            if (! $Config.Contains($key)) {
                throw "Missing configuration option '$key'"
            }
            if ($defaultConfig[$key]['default'].GetType().FullName -ne $Config[$key]['value'].GetType().FullName) {
                throw "Invalid configuration option '$key'. Expected a value of type $( $defaultConfig[$key]['default'].GetType().FullName ), but value was of type $( $config[$key]['value'].GetType().FullName )"
            }
            if ($defaultConfig[$key].Contains('validateOptions')) {
                if ($defaultConfig[$key]['validateOptions'] -contains 'directoryexists') {
                    if ( ! $config[$key]['value'] -or ! (Test-Path $config[$key]['value'] -PathType Container -ErrorAction SilentlyContinue) ) {
                        throw "Invalid configuration option '$key'. The directory '$( $config[$key]['value'] )' does not exist, or is a file"
                    }
                }
            }
        }

        # Warn of unknown configuration options
        foreach ($key in $config.Keys) {
            if (! $defaultConfig.Contains($key)) {
                "Unknown configuration option '$key'" | Write-Warning
            }
        }

        $Config
    }
}

Function Remove-InvalidFileNameChars {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string]$Name,
        [switch]$KeepPathSpaces
    )

    $newName = $Name.Split([IO.Path]::GetInvalidFileNameChars()) -join '-'
    $newName = $newName -replace "\[", "("
    $newName = $newName -replace "\]", ")"
    $newName =  if ($KeepPathSpaces) {
                    $newName -replace "\s", " "
                } else {
                    $newName -replace "\s", "-"
                }
    $newName = $newName.Substring(0, $(@{$true = 130; $false = $newName.length }[$newName.length -gt 150]))
    return $newName.Trim() # Remove boundary whitespaces
}

Function Remove-InvalidFileNameCharsInsertedFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string]$Name,
        [string]$Replacement = "",
        [string]$SpecialChars = "#$%^*[]'<>!@{};",
        [switch]$KeepPathSpaces
    )

    $rePattern = ($SpecialChars.ToCharArray() | ForEach-Object { [regex]::Escape($_) }) -join "|"

    $newName = $Name.Split([IO.Path]::GetInvalidFileNameChars()) -join '-'
    $newName = $newName -replace $rePattern, ""
    $newName =  if ($KeepPathSpaces) {
                    $newName -replace "\s", " "
                } else {
                    $newName -replace "\s", "-"
                }
    return $newName.Trim() # Remove boundary whitespaces
}

Function ProcessSections {
    [CmdletBinding()]
    param (
        [object]$Config
    ,
        [object]$Group
    ,
        [object]$NotebookFilePath
    ,
        [object]$FilePath
    ,
        [int]$LevelsFromRoot
    )

    # Determine some configuration
    if ($config['prefixFolders']['value'] -eq 2) {
        $prefixjoiner = "_"
    }else {
        $prefixjoiner = "\"
    }
    if ($config['conversion']['value'] -eq 2) { $converter = "commonmark" }
    elseif ($config['conversion']['value'] -eq 3) { $converter = "gfm" }
    elseif ($config['conversion']['value'] -eq 4) { $converter = "markdown_mmd" }
    elseif ($config['conversion']['value'] -eq 5) { $converter = "markdown_phpextra" }
    elseif ($config['conversion']['value'] -eq 6) { $converter = "markdown_strict" }
    else { $converter = "markdown" }

    foreach ($section in $Group.Section) {
        $sectionFileName = "$($section.Name)" | Remove-InvalidFileNameChars -KeepPathSpaces:($config['keepPathSpaces']['value'] -eq 2)
        "" | Write-Host
        "$( '#' * $levelsfromroot ) $( $sectionFileName ) (Section)".Trim() | Write-Host
        $item = New-Item -Path "$($FilePath)" -Name "$($sectionFileName)" -ItemType "directory" -Force -ErrorAction SilentlyContinue
        "Directory: $($item.FullName)" | Write-Host
        [int]$previouspagelevel = 1
        [string]$previouspagenamelevel1 = ""
        [string]$previouspagenamelevel2 = ""
        [string]$pageprefix = ""

        foreach ($page in $section.Page) {
            # set page variables
            $recurrence = 1
            $pagelevel = $page.pagelevel
            $pagelevel = $pagelevel -as [int]
            $pageid = ""
            $pageid = $page.ID
            $pagename = ""
            $pagename = $page.name | Remove-InvalidFileNameChars -KeepPathSpaces:($config['keepPathSpaces']['value'] -eq 2)
            $fullexportdirpath = ""
            $fullexportdirpath = "$($FilePath)\$($sectionFileName)"
            $fullfilepathwithoutextension = ""
            $fullfilepathwithoutextension = "$($fullexportdirpath)\$($pagename)"
            $fullexportpath = ""
            #$fullexportpath = "$($fullfilepathwithoutextension).docx"


            # process for subpage prefixes
            if ($pagelevel -eq 1) {
                $pageprefix = ""
                $previouspagenamelevel1 = $pagename
                $previouspagenamelevel2 = ""
                $previouspagelevel = 1
            }
            elseif ($pagelevel -eq 2) {
                $pageprefix = "$($previouspagenamelevel1)"
                $previouspagenamelevel2 = $pagename
                $previouspagelevel = 2
            }
            elseif ($pagelevel -eq 3) {
                if ($previouspagelevel -eq 2) {
                    $pageprefix = "$($previouspagenamelevel1)$($prefixjoiner)$($previouspagenamelevel2)"
                }
                # level 3 under level 1, without a level 2
                elseif ($previouspagelevel -eq 1) {
                    $pageprefix = "$($previouspagenamelevel1)$($prefixjoiner)"
                }
                #and if previous was 3, do nothing/keep previous label
                $previouspagelevel = 3
            }
            "" | Write-Host
            "$( '#' * $levelsfromroot )$( '#' * $pagelevel ) $( $pagename ) (Page, level $pagelevel)".Trim() | Write-Host

            #if level 2 or 3 (i.e. has a non-blank pageprefix)
            if ($pageprefix) {
                #create filename prefixes and filepath if prefixes selected
                if ($config['prefixFolders']['value'] -eq 2) {
                    $pagename = "$($pageprefix)_$($pagename)"
                    $fullfilepathwithoutextension = "$($fullexportdirpath)\$($pagename)"
                }
                #all else/default, create subfolders and filepath if subfolders selected
                else {
                    $item = New-Item -Path "$($fullexportdirpath)\$($pageprefix)" -ItemType "directory" -Force -ErrorAction SilentlyContinue
                    "Directory: $($item.FullName)" | Write-Host
                    $fullexportdirpath = "$($fullexportdirpath)\$($pageprefix)"
                    $fullfilepathwithoutextension = "$($fullexportdirpath)\$($pagename)"
                    $levelsprefix = "../" * ($levelsfromroot + $pagelevel - 1) + ".."
                }
            }
            else {
                $levelsprefix = "../" * ($levelsfromroot) + ".."
            }

            # set media location (central media folder at notebook-level or adjacent to .md file) based on initial user prompt
            if ($config['medialocation']['value'] -eq 2) {
                $mediaPath = $fullexportdirpath.Replace('\', '/') # Normalize markdown media paths to use front slashes, i.e. '/'
                $levelsprefix = ""
            }
            else {
                $mediaPath = $NotebookFilePath.Replace('\', '/') # Normalize markdown media paths to use front slashes, i.e. '/'
            }
            $mediaPath = $mediaPath.Substring(0, 1).tolower() + $mediaPath.Substring(1) # Normalize markdown media paths to use a lowercased drive letter

            # in case multiple pages with the same name exist in a section, postfix the filename. Run after pages
            if ([System.IO.File]::Exists("$($fullfilepathwithoutextension).md")) {
                #continue
                $pagename = "$($pagename)-$recurrence"
                $recurrence++
            }

            $fullexportpath = "$($NotebookFilePath)\docx\$($pagename).docx"

            # use existing or create new docx files
            if ($config['usedocx']['value'] -eq 2) {
                # Only create new docx if doesn't exist
                if (![System.IO.File]::Exists($fullexportpath)) {
                    # publish OneNote page to Word
                    try {
                        $OneNote.Publish($pageid, $fullexportpath, "pfWord", "")
                    }
                    catch {
                        Write-Error "Error while publishing file '$($page.name)' to docx: $( $_.Exception.Message )"
                    }
                }
            }
            else {
                # remove any existing docx files
                if ([System.IO.File]::Exists($fullexportpath)) {
                    try {
                        Remove-Item -path $fullexportpath -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        Write-Error "Error removing intermediary '$($page.name)' docx file: $( $_.Exception.Message )"
                    }
                }

                # publish OneNote page to Word
                try {
                    $OneNote.Publish($pageid, $fullexportpath, "pfWord", "")
                }
                catch {
                    Write-Error "Error while publishing file '$($page.name)' to docx: $( $_.Exception.Message )"
                }
            }

            # https://gist.github.com/heardk/ded40b72056cee33abb18f3724e0a580
            try {
                pandoc.exe -f  docx -t $converter-simple_tables-multiline_tables-grid_tables+pipe_tables -i $fullexportpath -o "$($fullfilepathwithoutextension).md" --wrap=none --markdown-headings=atx --extract-media="$($mediaPath)"
            }
            catch {
                Write-Error "Error while converting file '$($page.name)' to md: $( $_.Exception.Message )"
            }

            # export inserted file objects, removing any escaped symbols from filename so that links to them actually work
            [xml]$pagexml = ""
            $OneNote.GetPageContent($pageid, [ref]$pagexml, 7)
            $pageinsertedfiles = $pagexml.Page.Outline.OEChildren.OE | Where-Object { $_.InsertedFile }
            foreach ($pageinsertedfile in $pageinsertedfiles) {
                $item = New-Item -Path "$($mediaPath)" -Name "media" -ItemType "directory" -Force -ErrorAction SilentlyContinue
                "Directory: $($item.FullName)" | Write-Host
                $destfilename = ""
                try {
                    $destfilename = $pageinsertedfile.InsertedFile.preferredName | Remove-InvalidFileNameCharsInsertedFiles -KeepPathSpaces:($config['keepPathSpaces']['value'] -eq 2)
                    Copy-Item -Path "$($pageinsertedfile.InsertedFile.pathCache)" -Destination "$($mediaPath)\media\$($destfilename)" -Force
                }
                catch {
                    Write-Error "Error while copying file object '$($pageinsertedfile.InsertedFile.preferredName)' for page '$($page.name)': $( $_.Exception.Message )"
                }
                # Change MD file Object Name References
                try {
                    $pageinsertedfile2 = $pageinsertedfile.InsertedFile.preferredName.Replace("$", "\$").Replace("^", "\^").Replace("'", "\'")
                    ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw).Replace("$($pageinsertedfile2)", "[$($destfilename)]($($mediaPath)/media/$($destfilename))")) | Set-Content -Path "$($fullfilepathwithoutextension).md"

                }
                catch {
                    Write-Host "Error while renaming file object name references to '$($pageinsertedfile.InsertedFile.preferredName)' for file '$($page.name)': $( $_.Exception.Message )"
                }
            }

            # add YAML
            $orig = @(
                Get-Content -path "$($fullfilepathwithoutextension).md"
            )
            $orig[0] = "# $($page.name)"
            if ($config['headerTimestampEnabled']['value'] -eq 2) {
                Set-Content -Path "$($fullfilepathwithoutextension).md" -Value $orig[0..0], $orig[6..($orig.Count - 1)]
            }else {
                $insert1 = "$($page.dateTime)"
                $insert1 = [Datetime]::ParseExact($insert1, 'yyyy-MM-ddTHH:mm:ss.fffZ', $null)
                $insert1 = $insert1.ToString("`nyyyy-MM-dd HH:mm:ss")
                $insert2 = "`n---"
                Set-Content -Path "$($fullfilepathwithoutextension).md" -Value $orig[0..0], $insert1, $insert2, $orig[6..($orig.Count - 1)]
            }

            #Clear double spaces from bullets and nonbreaking spaces from blank lines
            if ($config['keepspaces']['value'] -eq 2 ) {
                #do nothing
            }
            else {
                try {
                    ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw -encoding utf8).Replace([char]0x00A0, [char]0x000A).Replace([char]0x000A, [char]0x000A).Replace("`r`n`r`n", "`r`n")) | Set-Content -Path "$($fullfilepathwithoutextension).md"
                }
                catch {
                    Write-Error "Error while clearing double spaces from file '$($fullfilepathwithoutextension)': $( $_.Exception.Message )"
                }
            }

            # rename images to have unique names - NoteName-Image#-HHmmssff.xyz
            $timeStamp = (Get-Date -Format HHmmssff).ToString()
            $timeStamp = $timeStamp.replace(':', '')
            $images = Get-ChildItem -Path "$($mediaPath)/media" -Include "*.png", "*.gif", "*.jpg", "*.jpeg" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name.SubString(0, 5) -match "image" }
            foreach ($image in $images) {
                $newimageName = "$($pagename.SubString(0,[math]::min(30,$pagename.length)))-$($image.BaseName)-$($timeStamp)$($image.Extension)"
                # Rename Image
                try {
                    Rename-Item -Path "$($image.FullName)" -NewName $newimageName -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Error "Error while renaming image '$($image.FullName)' for page '$($page.name)': $( $_.Exception.Message )"
                }
                # Change MD file Image filename References
                try {
                    ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw).Replace("$($image.Name)", "$($newimageName)")) | Set-Content -Path "$($fullfilepathwithoutextension).md"
                }
                catch {
                    Write-Error "Error while renaming image file name references to '$($image.Name)' for file '$($page.name)': $( $_.Exception.Message )"
                }
            }

            # change MD file Image Path References
            try {
                # Change MD file Image Path References in Markdown
                ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw).Replace("$($mediaPath)/media/", "$($levelsprefix)/media/")) | Set-Content -Path "$($fullfilepathwithoutextension).md"
                # Change MD file Image Path References in HTML
                ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw).Replace("$($mediaPath)", "$($levelsprefix)")) | Set-Content -Path "$($fullfilepathwithoutextension).md"
            }
            catch {
                Write-Error "Error while renaming image file path references for file '$($page.name)': $( $_.Exception.Message )"
            }

            # Clear backslash escape symbols
            if ($config['keepescape']['value'] -eq 2 ) {
                #do nothing
            }
            else {
                try {
                    ((Get-Content -path "$($fullfilepathwithoutextension).md" -Raw).Replace("\", '')) | Set-Content -Path "$($fullfilepathwithoutextension).md"
                }catch {
                    Write-Error "Error clearing backslash escape symbols in file '$fullfilepathwithoutextension.md': $( $_.Exception.Message )"
                }
            }

            # Cleanup Word files
            try {
                if ($config['keepdocx']['value'] -ne 2) {
                    Remove-Item -path "$fullexportpath" -Force -ErrorAction Stop
                }
            }
            catch {
                Write-Error "Error removing intermediary '$($page.name)' docx file: $( $_.Exception.Message )"
            }
        }
    }
}

Function Convert-OneNote2MarkDown {
    [CmdletBinding()]
    param ()

    try {
        # Fix encoding problems for languages other than English
        $PSDefaultParameterValues['*:Encoding'] = 'utf8'

        # Validate dependencies
        Validate-Dependencies

        # Compile and validate configuration
        $config = Compile-Configuration | Validate-Configuration

        # Open OneNote hierarchy
        if ($PSVersionTable.PSVersion.Major -le 5) {
            $OneNote = New-Object -ComObject OneNote.Application
        }else {
            # Works between powershell 6.0 and 7.0, but not >= 7.1
            Add-Type -Path $env:windir\assembly\GAC_MSIL\Microsoft.Office.Interop.OneNote\15.0.0.0__71e9bce111e9429c\Microsoft.Office.Interop.OneNote.dll # -PassThru
            $OneNote = [Microsoft.Office.Interop.OneNote.ApplicationClass]::new()
        }
        [xml]$Hierarchy = ""
        $totalerr = @()
        $OneNote.GetHierarchy("", [Microsoft.Office.InterOp.OneNote.HierarchyScope]::hsPages, [ref]$Hierarchy)

        # Validate the notebooks to convert
        $notebooks = @(
            if ($config['targetNotebook']['value']) {
                $Hierarchy.Notebooks.Notebook | Where-Object { $_.Name -eq $config['targetNotebook']['value'] }
            }else {
                $Hierarchy.Notebooks.Notebook
            }
        )
        if ($notebooks.Count -eq 0) {
            if ($config['targetNotebook']['value']) {
                throw "Could not find notebook of name '$( $config['targetNotebook']['value'] )'"
            }else {
                throw "Could not find notebooks"
            }
        }

        foreach ($notebook in $notebooks) {
            # Process notebook top level. Think of a notebook itself as a section group
            $levelsfromroot = 0
            if ($levelsfromroot -eq 0) {
                $sectiongroup = $notebook
                $sectiongroupName = $notebook.Name | Remove-InvalidFileNameChars -KeepPathSpaces:($config['keepPathSpaces']['value'] -eq 2)
                "==============" | Write-Host
                "Notebook: $( $sectiongroup.Name )" | Write-Host
                $notesDestinationBaseDirectory = New-Item -Path ( Join-Path $config['notesdestpath']['value'] $sectiongroupName ) -ItemType "directory" -Force -ErrorAction SilentlyContinue
                "Notes destination directory: $($notesDestinationBaseDirectory.FullName)" | Write-Host
                $item = New-Item -Path "$( $notesDestinationBaseDirectory.FullName )\docx" -ItemType "directory" -Force -ErrorAction SilentlyContinue
                "Notes docx directory: $( $item.FullName )" | Write-Host
                "==============" | Write-Host
                ProcessSections -Config $config -Group $sectiongroup -NotebookFilePath $notesDestinationBaseDirectory.FullName -FilePath $notesDestinationBaseDirectory.FullName -LevelsFromRoot $levelsfromroot -ErrorVariable +totalerr
            }

            # Process section group(s) recursively until no more are found
            while ($sectiongroups = $sectiongroup.SectionGroup) {
                $levelsfromroot++
                $notesDestinationParentDirectory = if ($levelsfromroot -eq 1) { $notesDestinationBaseDirectory } else { $notesDestinationDirectory }
                foreach ($sectiongroup in $sectiongroups) {
                    $sectiongroupName = $sectiongroup.Name | Remove-InvalidFileNameChars -KeepPathSpaces:($config['keepPathSpaces']['value'] -eq 2)
                    "" | Write-Host
                    "$( '#' * $levelsfromroot ) $( $sectiongroup.Name ) (Section Group)".Trim() | Write-Host
                    if ($sectiongroup.isRecycleBin -ne 'true') {
                        $notesDestinationDirectory = New-Item -Path ( Join-Path $notesDestinationParentDirectory.FullName $sectiongroupName ) -ItemType "directory" -Force -ErrorAction SilentlyContinue
                        "Directory: $( $notesDestinationDirectory.FullName )" | Write-Host
                        ProcessSections -Config $config -Group $sectiongroup -NotebookFilePath $notesDestinationBaseDirectory.FullName -FilePath $notesDestinationDirectory.FullName -LevelsFromRoot $levelsfromroot -ErrorVariable +totalerr
                    }
                }
            }
        }
    }catch {
        throw
    }finally {
        'Cleaning up' | Write-Host

        # Release OneNote hierarchy
        if (Get-Variable -Name OneNote -ErrorAction SilentlyContinue) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($OneNote) | Out-Null
            Remove-Variable -Name OneNote -Force
        }
        if ($totalerr) {
            "Errors: " | Write-Host
            $totalerr | Where-Object { $_.CategoryInfo.Reason -eq 'WriteErrorException' } | Write-Host
        }
    }
}

# Entrypoint
Convert-OneNote2MarkDown
