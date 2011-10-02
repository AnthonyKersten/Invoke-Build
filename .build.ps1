
<#
.Synopsis
	Build script (https://github.com/nightroman/Invoke-Build)

.Description
	There is nothing to compile in this project. But Invoke-Build is suitable
	for automating all operations on project files, not just classic builds.

.Link
	Invoke-Build
#>

param
(
	[switch]$SkipTestDiff
)

# Set strict mode
Set-StrictMode -Version 2

# Requires: 7z.exe
Set-Alias 7z @(Get-Command 7z)[0].Definition

# Import markdown tasks ConvertMarkdown and RemoveMarkdownHtml.
# <https://github.com/nightroman/Invoke-Build/wiki/Partial-Incremental-Tasks>
Markdown.tasks.ps1

# Remove generated HTML and temp files.
task Clean RemoveMarkdownHtml, {
	Remove-Item z -Force -Recurse -ErrorAction 0
}

# Warn about not empty git status if .git exists.
task GitStatus -If (Test-Path .git) {
	$status = exec { git status -s }
	if ($status) {
		Write-Warning "Git status: $($status -join ', ')"
	}
}

# Copy Invoke-Build.ps1 and help from working location to the project.
# Fail (assert) if the project file is newer, it is not supposed to be.
task UpdateScript {
	$target = Get-Item Invoke-Build.ps1 -ErrorAction 0
	$source = Get-Item (Get-Command Invoke-Build.ps1).Definition
	assert (!$target -or ($target.LastWriteTime -le $source.LastWriteTime))
	Copy-Item $source.FullName, "$($source.FullName)-Help.xml" .
}

# Build the XML help file.
task Help {
	$script = (Get-Command Invoke-Build.ps1).Definition
	$dir = Split-Path $script

	. Helps.ps1
	Convert-Helps Invoke-Build.ps1-Help.ps1 $dir\Invoke-Build.ps1-Help.xml
}

# Make the package in z\tools for Zip and NuGet.
task Package ConvertMarkdown, Help, UpdateScript, GitStatus, {
	# temp package folder
	Remove-Item [z] -Force -Recurse
	$null = mkdir z\tools

	# copy project files
	Copy-Item -Destination z\tools -Recurse @(
		'Demo'
		'Invoke-Build.ps1'
		'LICENSE.txt'
	)

	# move generated files
	Move-Item -Destination z\tools @(
		'Invoke-Build.ps1-Help.xml'
		'README.htm'
		'Release-Notes.htm'
	)
}

# Make the zip package.
task Zip Package, {
	Set-Location z\tools
	exec { & 7z a ..\..\Invoke-Build.$(Get-BuildVersion).zip * }
}

# Make the NuGet package.
task NuGet Package, {
	# nuspec
	Set-Content z\Package.nuspec @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
	<metadata>
		<id>Invoke-Build</id>
		<version>$(Get-BuildVersion)</version>
		<authors>Roman Kuzmin</authors>
		<owners>Roman Kuzmin</owners>
		<projectUrl>https://github.com/nightroman/Invoke-Build</projectUrl>
		<requireLicenseAcceptance>false</requireLicenseAcceptance>
		<description>
Invoke-Build.ps1 is a build automation tool implemented as a standalone
PowerShell script. It invokes tasks defined in build scripts written in
PowerShell with a few domain-specific language constructs. Build flow and
concepts are similar to MSBuild. Scripts are similar to psake but not
compatible.
		</description>
		<summary>Invoke-Build.ps1 - Build Automation in PowerShell</summary>
		<tags>build powershell</tags>
	</metadata>
</package>
"@
	# pack
	exec { NuGet pack z\Package.nuspec -NoDefaultExcludes }
}

# Calls the tests infinitely.
task Loop {
	for(;;) {
		$BuildInfo.AllTasks.Clear()
		$BuildInfo.AllMessages.Clear()
		Invoke-Build . Demo\.build.ps1
	}
}

# Tests Demo scripts and compares the output with expected. It creates and
# keeps Invoke-Build-Test.log in $env:TEMP. Then it compares it with a new
# output file in this directory. If they are the same then the new file is
# removed. Otherwise an application $env:MERGE is started.
task Test {
	# invoke tests, get the output and result
	$output = Invoke-Build . Demo\.build.ps1 -Result result | Out-String -Width:9999

	assert ($result.AllTasks.Count -eq 116) $result.AllTasks.Count
	assert ($result.Tasks.Count -eq 28) $result.Tasks.Count

	assert ($result.AllErrorCount -eq 26) $result.AllErrorCount
	assert ($result.ErrorCount -eq 0) $result.AllErrorCount

	assert ($result.AllWarningCount -ge 1)
	assert ($result.WarningCount -ge 1)

	assert ($result.AllMessages.Count -ge 1)
	assert ($result.Messages.Count -ge 1)

	if ($SkipTestDiff) { return }

	# process and save the output
	$outputPath = 'Invoke-Build-Test.log'
	$samplePath = "$env:TEMP\Invoke-Build-Test.log"
	$output = $output -replace '\d\d:\d\d:\d\d(?:\.\d+)?', '00:00:00.0000'
	Set-Content $outputPath $output

	# compare outputs
	$toCopy = $false
	if (Test-Path $samplePath) {
		$sample = (Get-Content $samplePath) -join "`r`n"
		if ($output -ceq $sample) {
			Write-BuildText Green 'The result is expected.'
			Remove-Item $outputPath
		}
		else {
			Write-Warning 'The result is not the same as expected.'
			if ($env:MERGE) {
				& $env:MERGE $outputPath $samplePath
			}
			$toCopy = 1 -eq (Read-Host 'Save the result as expected? Yes: [1]')
		}
	}
	else {
		$toCopy = $true
	}

	# copy actual to expected
	if ($toCopy) {
		Write-BuildText Cyan 'Saving the result as expected.'
		Move-Item $outputPath $samplePath -Force
	}
}

# Test all and clean.
task . Help, Test, Zip, NuGet, {
	Remove-Item Invoke-Build.$(Get-BuildVersion).zip
	Remove-Item Invoke-Build.$(Get-BuildVersion).nupkg
},
Clean
