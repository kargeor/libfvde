# Diagnostic only, not for upstream: run fvde_test_volume on cs_single_volume.raw from the
# VSDebug Win32 build and, if it hangs, print the process's window texts and thread stacks.

Add-Type -TypeDefinition @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static List<string> Texts(uint pid) {
    var r = new List<string>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) {
      var s = new StringBuilder(4096); GetWindowText(h, s, 4096); r.Add("window: " + s);
      EnumChildWindows(h, (c, l2) => { var t = new StringBuilder(4096); GetWindowText(c, t, 4096); if (t.Length > 0) r.Add("  text: " + t); return true; }, IntPtr.Zero); }
      return true; }, IntPtr.Zero);
    return r; } }
"@

$Exe = (Get-ChildItem -Path . -Recurse -Filter fvde_test_volume.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\vs20[0-9][0-9]\\' } | Select-Object -First 1).FullName
If (-Not ${Exe}) { Write-Host "fvde_test_volume.exe not found"; Exit 1 }
$Dir = Split-Path ${Exe}
$Image = (Resolve-Path "tests\input\public\cs_single_volume.raw").Path
Write-Host "test: ${Exe}"
Write-Host "image: ${Image}"
Get-ChildItem ${Dir} -Filter *.pdb | ForEach-Object { Write-Host "pdb: $($_.Name)" }

$Out = "${Env:RUNNER_TEMP}\fvde_test_volume.out"
$Err = "${Env:RUNNER_TEMP}\fvde_test_volume.err"
$Process = Start-Process -FilePath ${Exe} -ArgumentList "`"${Image}`"" -WorkingDirectory ${Dir} -PassThru -RedirectStandardOutput ${Out} -RedirectStandardError ${Err}

If ($Process.WaitForExit(120000))
{
	Write-Host "fvde_test_volume exited with $($Process.ExitCode) (no hang)"
	Get-Content ${Out}, ${Err}
	Write-Host "=== running the complete test suite (original runtests.ps1)"
	& .\runtests_orig.ps1
	Exit ${LastExitCode}
}
Write-Host "=== still running after 120 s: HANG reproduced"
[Win]::Texts([uint32]$Process.Id) | ForEach-Object { Write-Host $_ }

$Cdb = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\Debuggers" -Recurse -Filter cdb.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\x86\\' } | Select-Object -First 1
If (-Not ${Cdb}) { $Cdb = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\Debuggers" -Recurse -Filter cdb.exe -ErrorAction SilentlyContinue | Select-Object -First 1 }
Write-Host "cdb: $(${Cdb}.FullName)"
If (${Cdb})
{
	& $Cdb.FullName -pv -p $Process.Id -y "${Dir};srv*${Env:RUNNER_TEMP}\sym*https://msdl.microsoft.com/download/symbols" -c ".lines -e; .reload /f; ~*kpn 60; q" 2>&1 | Out-Host
}
Stop-Process -Id $Process.Id -Force
Get-Content ${Out}, ${Err}
Exit 1
