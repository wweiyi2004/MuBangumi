param(
    [Parameter(Mandatory=$true)][int]$QaProcessId,
    [Parameter(Mandatory=$true)][long]$DialogHandle,
    [Parameter(Mandatory=$true)][long]$InputHandle,
    [Parameter(Mandatory=$true)][long]$ButtonHandle,
    [Parameter(Mandatory=$true)][ValidateSet('save','open')][string]$Action,
    [Parameter(Mandatory=$true)][string]$FilePath
)
$ErrorActionPreference = 'Stop'
$qaRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$qaExecutable = Join-Path $qaRoot 'build\windows\x64\runner\Debug\mubangumi.exe'
if ((Get-Process -Id $QaProcessId).Path -ne $qaExecutable) { throw 'Only the native QA debug executable is allowed.' }
$qaFiles = Join-Path $qaRoot '.dart_tool\m6-native'
$qaFile = [IO.Path]::GetFullPath($FilePath)
if (-not $qaFile.StartsWith($qaFiles + '\', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($qaFile) -ne '.json') {
    throw 'Only JSON files inside the native QA directory are allowed.'
}
if ($Action -eq 'save' -and (Test-Path -LiteralPath $qaFile)) { throw 'Refusing to overwrite an existing QA file.' }
if ($Action -eq 'open' -and -not (Test-Path -LiteralPath $qaFile -PathType Leaf)) { throw 'QA input file is missing.' }
$qaInterop = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class QaFileDialog {
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] static extern bool IsChild(IntPtr parent,IntPtr child);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,StringBuilder s,uint f,uint t,out IntPtr r);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,string s,uint f,uint t,out IntPtr r);
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 static void Owner(IntPtr h,uint pid) { uint actual;GetWindowThreadProcessId(h,out actual);if(actual!=pid)throw new Exception("Unexpected window owner"); }
 public static void Apply(uint pid,long dialog,long input,long button,string title,string file) {
  var d=new IntPtr(dialog);var e=new IntPtr(input);var b=new IntPtr(button);Owner(d,pid);Owner(e,pid);Owner(b,pid);
  if(!IsChild(d,e)||!IsChild(d,b))throw new Exception("Controls are not inside the expected dialog");
  var text=new StringBuilder(512);IntPtr result;
  SendMessageTimeout(d,13,new IntPtr(512),text,2,3000,out result);
  if(text.ToString()!=title)throw new Exception("Unexpected dialog title");
  if(SendMessageTimeout(e,12,IntPtr.Zero,file,2,3000,out result)==IntPtr.Zero)throw new Exception("Unable to set file name");
  if(!PostMessage(b,245,IntPtr.Zero,IntPtr.Zero))throw new Exception("Unable to press dialog button");
 }
}
'@
Add-Type -TypeDefinition $qaInterop
$qaTitle = if ($Action -eq 'save') { '保存 MuBangumi 备份' } else { '选择 MuBangumi 备份' }
[QaFileDialog]::Apply($QaProcessId,$DialogHandle,$InputHandle,$ButtonHandle,$qaTitle,$qaFile)
Write-Output "QA $Action submitted: $qaFile"
