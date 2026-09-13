# Read-only MSAA hit testing, including Flutter's native Windows accessibility
# bridge. Run alongside background_drag_benchmark.dart on a disposable build.
# Prints counts and HRESULTs only; does not inspect labels or user data.
param([Parameter(Mandatory)][int]$PreviewProcessId, [ValidateRange(1, 300)][int]$Seconds = 30)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Accessibility
Add-Type -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Accessibility;
public static class BackgroundAccessibilityProbe {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left, top, right, bottom; }
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window, uint command);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect bounds);
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IAccessible accessible);
  public static IAccessible Root(IntPtr window) {
    var id = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
    IAccessible accessible;
    Marshal.ThrowExceptionForHR(AccessibleObjectFromWindow(window, 0xFFFFFFFC, ref id, out accessible));
    return accessible;
  }
}
'@
$bgQueries = 0
$bgErrors = 0
$bgExitRaces = 0
$bgHResults = @{}
$bgEnd = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $bgEnd) {
  $bgProcess = Get-Process -Id $PreviewProcessId -ErrorAction SilentlyContinue
  if (-not $bgProcess) { break }
  if ($bgProcess.MainWindowHandle -eq 0) { Start-Sleep -Milliseconds 100; continue }
  $bgRoot = $null
  try {
    $bgChild = [BackgroundAccessibilityProbe]::GetWindow($bgProcess.MainWindowHandle, 5)
    if ($bgChild -eq [IntPtr]::Zero) { $bgChild = $bgProcess.MainWindowHandle }
    $bgBounds = New-Object BackgroundAccessibilityProbe+Rect
    [void][BackgroundAccessibilityProbe]::GetWindowRect($bgChild, [ref]$bgBounds)
    $bgRoot = [BackgroundAccessibilityProbe]::Root($bgChild)
    for ($bgY=1; $bgY -le 4; $bgY++) {
      for ($bgX=1; $bgX -le 4; $bgX++) {
        $bgHit = $bgRoot.accHitTest($bgBounds.left + ($bgBounds.right-$bgBounds.left)*$bgX/5, $bgBounds.top + ($bgBounds.bottom-$bgBounds.top)*$bgY/5)
        $bgQueries++
        if ($null -ne $bgHit -and [Runtime.InteropServices.Marshal]::IsComObject($bgHit)) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($bgHit) }
      }
    }
  } catch {
    if (-not (Get-Process -Id $PreviewProcessId -ErrorAction SilentlyContinue)) {
      $bgExitRaces++
      break
    }
    $bgErrors++
    $bgCode = $_.Exception.HResult.ToString('X8')
    $bgHResults[$bgCode] = 1 + $bgHResults[$bgCode]
  } finally {
    if ($null -ne $bgRoot -and [Runtime.InteropServices.Marshal]::IsComObject($bgRoot)) {
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($bgRoot)
    }
  }
  Start-Sleep -Milliseconds 50
}
@{ Queries=$bgQueries; Errors=$bgErrors; ExitDuringQuery=$bgExitRaces; HResults=$bgHResults; ProcessId=$PreviewProcessId; End=(Get-Date).ToString('o') } | ConvertTo-Json
