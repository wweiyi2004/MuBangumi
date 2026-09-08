param([Parameter(Mandatory=$true)][int]$QaProcessId)
$ErrorActionPreference = 'Stop'
$qaRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ((Get-Process -Id $QaProcessId).Path -ne (Join-Path $qaRoot 'build\windows\x64\runner\Debug\mubangumi.exe')) {
    throw 'Only the native QA executable may be inspected.'
}
$qaInterop = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class QaDialogInfo {
 public delegate bool Callback(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback f,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,Callback f,IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 static string Class(IntPtr h) {var b=new StringBuilder(256);GetClassName(h,b,256);return b.ToString();}
 static string Title(IntPtr h) {var b=new StringBuilder(512);GetWindowText(h,b,512);return b.ToString();}
 static Dictionary<string,object> Row(IntPtr h) {return new Dictionary<string,object>{{"handle",h.ToInt64()},{"class",Class(h)},{"title",Title(h)}};}
 public static List<object> Inspect(uint pid) {
  var rows=new List<object>();
  EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);
   if(p==pid && IsWindowVisible(h) && Class(h)=="#32770" && Title(h).Contains("MuBangumi")) {
    var row=Row(h);var controls=new List<object>();
    EnumChildWindows(h,(c,x)=>{var type=Class(c);if(IsWindowVisible(c)&&(type=="Edit"||type=="Button"))controls.Add(Row(c));return true;},IntPtr.Zero);
    row["controls"]=controls;rows.Add(row);
   }return true;},IntPtr.Zero);
  return rows;
 }
}
'@
Add-Type -TypeDefinition $qaInterop
[QaDialogInfo]::Inspect($QaProcessId) | ConvertTo-Json -Depth 5
