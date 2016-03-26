#
# Functions.psm1
#
function getPackage
{
	$toGet = $args[0]
	$newname = $args[1]
	$archiveName = [io.path]::GetFileNameWithoutExtension($toGet)
	$archiveExt = [io.path]::GetExtension($toGet)
	$isTar = [io.path]::GetExtension($archiveName)
	if ($isTar -eq ".tar") {
		$archiveExt = $isTar + $archiveExt
		$archiveName = [io.path]::GetFileNameWithoutExtension($archiveName)  
	}
	if ($archiveExt -eq ".git") {
		# the source is a git repo, so make a shallow clone
		# no need to store anything in the packages dir
		if (((Test-Path $root\src-stage1-dependencies\$archiveName) -and ($newname -eq $null)) -or
			(($newname -ne $null) -and (Test-Path $root\src-stage1-dependencies\$newname))) {
			"$archiveName already present"
		} else {
			cd $root\src-stage1-dependencies	
			if (Test-Path $root\src-stage1-dependencies\$archiveName) {
				Remove-Item  $root\src-stage1-dependencies\$archiveName -Force -Recurse
			}
			$ErrorActionPreference = "Continue"
			git clone --depth=1 $toGet  2>&1 | write-host
			$ErrorActionPreference = "Stop"
			if ($newname -ne $null) {
				if (Test-Path $root\src-stage1-dependencies\$newname) {
					Remove-Item  $root\src-stage1-dependencies\$newname -Force -Recurse
				}
				if (Test-Path $root\src-stage1-dependencies\$archiveName) {
					ren $root\src-stage1-dependencies\$archiveName $root\src-stage1-dependencies\$newname
				}
			}
		}
	} else {
		# source is a compressed package
		# store it in the packages dir so we can reuse it if we
		# clean the whole install
		if (!(Test-Path $root/packages/$archiveName)) {
			mkdir $root/packages/$archiveName
		}
		if (!(Test-Path $root/packages/$archiveName/$archiveName$archiveExt)) {
			cd $root/packages/$archiveName
			# user-agent is for sourceforge downloads
			wget $toGet -OutFile "$archiveName$archiveExt" -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
		} else {
			"$archiveName already present"
		}
		if (!(Test-Path $root\src-stage1-dependencies\$archiveName)) {
			$archive = "$root/packages/$archiveName/$archiveName$archiveExt"
			cd "$root\src-stage1-dependencies"
			if ($archiveExt -eq ".7z" -or ($archiveExt -eq ".zip")) {
				sz x -y $archive 2>&1 | write-host
			} elseif ($archiveExt -eq ".zip") {
				$destination = "$root/src-stage1-dependencies"
				[io.compression.zipfile]::ExtractToDirectory($archive, $destination)
			} elseif ($archiveExt -eq ".tar.gz11" ) {
				tar zxf $archive 2>&1 | write-host 
			} elseif ($archiveExt -eq ".tar.xz" -or $archiveExt -eq ".tgz" -or $archiveExt -eq ".tar.gz") {
				sz x -y $archive 
				if (!(Test-Path $root\src-stage1-dependencies\$archiveName.tar)) {
					# some python .tar.gz files put the tar in a dist subfolder
					cd dist
					sz x -aoa -ttar -o"$root\src-stage1-dependencies" "$archiveName.tar"
					cd ..
					rm -rf dist
				} else {
					sz x -aoa -ttar -o"$root\src-stage1-dependencies" "$archiveName.tar"
					}
				del "$archiveName.tar"
			} else {
				throw "Unknown file extension on $archiveName$archiveExt"
			}
			if ($newname -ne $null) {
				if (Test-Path $root\src-stage1-dependencies\$newname) {
					Remove-Item  $root\src-stage1-dependencies\$newname -Force -Recurse
					}
				if (Test-Path $root\src-stage1-dependencies\$archiveName) {
					ren $root\src-stage1-dependencies\$archiveName $root\src-stage1-dependencies\$newname
					}
			}
		}
	}
}

# Patches are overlaid on top of the main source for gnuradio-specific adjustments
function getPatch
{
	$toGet = $args[0]
	$whereToPlace = $args[1]
	$archiveName = [io.path]::GetFileNameWithoutExtension($toGet)
	$archiveExt = [io.path]::GetExtension($toGet)
	$isTar = [io.path]::GetExtension($archiveName)
	if ($isTar -eq ".tar") {
		$archiveExt = $isTar + $archiveExt
		$archiveName = [io.path]::GetFileNameWithoutExtension($archiveName)  
	}
	$url = "http://www.gcndevelopment.com/gnuradio/downloads/sources/" + $toGet 
	if (!(Test-Path $root/packages/patches)) {
		mkdir $root/packages/patches
	}
	cd $root/packages/patches
	wget $url -OutFile $toGet
	$archive = "$root/packages/patches/$toGet"
	$destination = "$root/src-stage1-dependencies/$whereToPlace"
	if ($archiveExt -eq ".7z" -or $archiveExt -eq ".zip") {
		New-Item -path $destination -type directory -force
		cd $destination 
		sz x -y $archive 2>&1 | write-host
	} elseif ($archiveExt -eq ".tar.gz") {
		New-Item -path $destination -type directory -force
		cd $destination 
		tar zxf $archive 2>&1 | write-host 
	} elseif ($archiveExt -eq ".tar.xz") {
		New-Item -path $destination -type directory -force
		cd $destination 
		sz x -y $archive 
		sz x -aoa -ttar "$archiveName.tar"
		del "$archiveName.tar"
	} else {
		throw "Unknown file extension on $archiveName$archiveExt"
	}
}

function Exec
{
    [CmdletBinding()]
    param (
        [Parameter(Position=0, Mandatory=1)]
        [scriptblock]$Command,
        [Parameter(Position=1, Mandatory=0)]
        [string]$ErrorMessage = "Execution of command failed.`n$Command"
    )
    & $Command
    if ($LastExitCode -ne 0) {
        throw "Exec: $ErrorMessage"
    }
}

function Setup
{
	$Config = Import-LocalizedData -BaseDirectory $mypath -FileName ConfigInfo.psd1 

	# setup paths
	$Global:root = $env:grwinbuildroot 
	if (!$Global:root) {$Global:root = "C:/gr-build"}
	
	# ensure on a 64-bit machine
	if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {throw "Script only compatible with 64-bit Windows"}

	# Check for binary dependencies
	if (-not (test-path "$root\bin\7za.exe")) {throw "7-zip (7za.exe) needed in bin folder"} 

	# check for git/tar
	if (-not (test-path "$env:ProgramFiles\Git\usr\bin\tar.exe")) {throw "Git For Windows must be installed"} 
	set-alias tar "$env:ProgramFiles\Git\usr\bin\tar.exe"  

	# CMake (to build gnuradio)
	if (-not (test-path "${env:ProgramFiles(x86)}\Cmake\bin\cmake.exe")) {throw "CMake must be installed"} 
	
	# ActivePerl (to build OpenSSL)
	if (-not (test-path "$env:ProgramFiles\perl64\bin\perl.exe")) {throw "ActiveState Perl must be installed"} 
	
	# MSVC 2015
	if (-not (test-path "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\VC")) {throw "Visual Studio 2015 must be installed"} 
	
	# set VS 2015 environment
	pushd "${env:ProgramFiles(x86)}\Microsoft Visual Studio 14.0\VC"
	cmd /c "vcvarsall.bat amd64&set" |
	foreach {
	  if ($_ -match "=") {
		$v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
	  }
	}
	popd
	write-host "Visual Studio 2015 Command Prompt variables set." -ForegroundColor Yellow

	# set initial state
	cd $root
	set-alias sz "$root\bin\7za.exe"  
	$oldpath = $env:Path
}