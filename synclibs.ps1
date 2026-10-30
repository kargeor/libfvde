# Script that synchronizes the local library dependencies
#
# Version: 20260621

Param (
	[switch]$UseHead = $false
)

# Diagnostic branch: use the tagged library versions, as the AppVeyor jobs do
$UseHead = $false


$GitUrlPrefix = "https://github.com/libyal"
$LocalLibs = "libbfio libcaes libcdata libcerror libcfile libclocale libcnotify libcpath libcsplit libcthreads libfcache libfdata libfguid libfplist libfvalue libhmac libuna"
$LocalLibs = ${LocalLibs} -split " "

$Git = "git"
$WinFlex = "..\win_flex_bison\win_flex.exe"
$WinBison = "..\win_flex_bison\win_bison.exe"

$Result = 0

ForEach (${LocalLib} in ${LocalLibs})
{
	# Split will return an array of a single empty string when LocalLibs is empty.
	If (-Not (${LocalLib}))
	{
		Continue
	}
	$GitUrl = "${GitUrlPrefix}/${LocalLib}.git"

	# PowerShell will raise NativeCommandError if git writes to stdout or stderr
	# therefore 2>&1 is added and the output is stored in a variable.
	$Output = Invoke-Expression -Command "${Git} clone --depth 1 ${GitUrl} ${LocalLib}-${pid} 2>&1"

	If (-Not (Test-Path -Path ${LocalLib}-${pid}))
	{
		Write-Warning "Unable to download: ${LocalLib}"
		Write-Host ${Output}

		$Result = 1

		Continue
	}
	Push-Location "${LocalLib}-${pid}"

	Try
	{
		$Output = Invoke-Expression -Command "${Git} fetch --quiet --all --tags --prune 2>&1"

		$LatestTag = Invoke-Expression -Command "${Git} tag --sort=-v:refname 2>&1" | Select-Object -First 1

		If (${LatestTag} -and -not ${UseHead})
		{
			Write-Host "Synchronizing: ${LocalLib} from ${GitUrl} tag ${LatestTag}"

			$Output = Invoke-Expression -Command "${Git} checkout --quiet tags/${LatestTag} 2>&1"
		}
		Else
		{
			Write-Host "Synchronizing: ${LocalLib} from ${GitUrl} HEAD"
		}
	}
	Finally
	{
		Pop-Location
	}
	$LocalLibVersion = Get-Content -Path ${LocalLib}-${pid}\configure.ac |
		select -skip 4 -first 1 |
		% { $_ -Replace " \[","" } |
		% { $_ -Replace "\],","" }

	If (Test-Path ${LocalLib})
	{
		Remove-Item -Path ${LocalLib} -Force -Recurse
	}
	New-Item -ItemType directory -Path ${LocalLib} -Force | Out-Null

	If (Test-Path ${LocalLib})
	{
		Copy-Item -Path ${LocalLib}-${pid}\${LocalLib}\*.[chly] -Destination ${LocalLib}\

		Get-Content -Path ${LocalLib}-${pid}\${LocalLib}\${LocalLib}_definitions.h.in |
			% { $_ -Replace "@VERSION@",${LocalLibVersion} } > ${LocalLib}\${LocalLib}_definitions.h
	}
	Remove-Item -Path ${LocalLib}-${pid} -Force -Recurse

	$NamePrefix = ""

	ForEach (${DirectoryElement} in Get-ChildItem -Path "${LocalLib}\*.l")
	{
		$OutputFile = ${DirectoryElement} -Replace ".l$",".c"

		$NamePrefix = Split-Path -path ${DirectoryElement} -leaf
		$NamePrefix = ${NamePrefix} -Replace "^${LocalLib}_",""
		$NamePrefix = ${NamePrefix} -Replace ".l$","_"

		$WinFlexArguments = @(
			"-Cf",
			"${DirectoryElement}"
		)
		# PowerShell will raise NativeCommandError if win_flex writes to stdout or stderr
		# therefore 2>&1 is added and the output is stored in a variable.
		$Output = Invoke-Expression -Command "& '${WinFlex}' $($WinFlexArguments -join ' ') 2>&1" | %{ "$_" }
		Write-Host ${Output}

		# Moving manually since win_flex -o <filename> does not provide the expected behavior.
		Move-Item "lex.yy.c" ${OutputFile} -force
	}
	ForEach (${DirectoryElement} in Get-ChildItem -Path "${LocalLib}\*.y")
	{
		$OutputFile = ${DirectoryElement} -Replace ".y$",".c"

		$WinBisonArguments = @(
			"-d"
			"-v"
			"-l"
			"-p", "${NamePrefix}"
			"-o", "${OutputFile}"
			"${DirectoryElement}"
		)
		# PowerShell will raise NativeCommandError if win_bison writes to stdout or stderr
		# therefore 2>&1 is added and the output is stored in a variable.
		$Output = Invoke-Expression -Command "& '${WinBison}' $($WinBisonArguments -join ' ') 2>&1" | %{ "$_" }
		Write-Host ${Output}
	}
}


# Diagnostic branch: apply the proposed libcaes fix for the MSVC /RTCc failure in libcaes_crypt_xts
$CaesFile = "libcaes\libcaes_tweaked_context.c"
$CaesOld = "byte_value = ( encrypted_tweak_value[ block_index ] << 1 ) | carry_bit;"
$CaesNew = "byte_value = ( ( encrypted_tweak_value[ block_index ] << 1 ) | carry_bit ) & 0xff;"
$CaesText = Get-Content -Raw ${CaesFile}
Write-Host "libcaes fix: $(([regex]::Matches(${CaesText}, [regex]::Escape(${CaesOld}))).Count) occurrences replaced"
Set-Content -NoNewline -Path ${CaesFile} -Value ${CaesText}.Replace(${CaesOld}, ${CaesNew})

Exit ${Result}
