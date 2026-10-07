# u9030ctl.ps1 start|ipl|stop [dir] - run the Univac 90/30 emulator with its windows hidden and press IPL by message
param([string]$Action = 'start', [string]$Dir = (Join-Path $PSScriptRoot 'run-u9030'))
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class U9030Win {
	[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
	struct STARTUPINFO { public int cb; public string r, d, t; public int x, y, w, h, cx, cy, fill, flags; public short show, r2; public IntPtr r3, i, o, e; }
	[StructLayout(LayoutKind.Sequential)]
	struct PROCINFO { public IntPtr hp, ht; public int pid, tid; }
	[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
	static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inh, int flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCINFO pi);
	delegate bool EnumProc(IntPtr h, IntPtr p);
	[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
	[DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr w, EnumProc f, IntPtr p);
	[DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
	[DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
	[DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
	public static int Start(string exe, string args, string dir) {
		var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si); si.flags = 1; si.show = 7; // SW_SHOWMINNOACTIVE
		PROCINFO pi;
		if (!CreateProcess(exe, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, dir, ref si, out pi))
			throw new Exception("CreateProcess failed " + Marshal.GetLastWin32Error());
		return pi.pid;
	}
	public static List<IntPtr> Windows(int pid) {
		var l = new List<IntPtr>();
		EnumWindows((h, p) => { int q; GetWindowThreadProcessId(h, out q); if (q == pid) l.Add(h); return true; }, IntPtr.Zero);
		return l;
	}
	public static string Text(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
	public static string Class(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
	public static IntPtr Child(IntPtr w, string cls, string text) {
		IntPtr found = IntPtr.Zero;
		EnumChildWindows(w, (h, p) => { if (Class(h) == cls && Text(h) == text) { found = h; return false; } return true; }, IntPtr.Zero);
		return found;
	}
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, StringBuilder l);
	public static List<string> Fields(IntPtr w) {
		var l = new List<string>();
		EnumChildWindows(w, (h, p) => { var s = new StringBuilder(512); SendMessage(h, 0x000D, (IntPtr)512, s); l.Add(Class(h) + " " + s.ToString()); return true; }, IntPtr.Zero);
		return l;
	}
	public static void Click(IntPtr button) {
		// BN_CLICKED to the parent: the VCL reflects it to the button as a click, visible or not; posted, because the IPL handler then runs the CPU
		PostMessage(GetParent(button), 0x0111, IntPtr.Zero, button);
	}
}
'@
$exe = Join-Path $Dir 'U9030.exe'
$pidFile = Join-Path $Dir 'u9030.pid'
function Get-Ours {
	if (Test-Path $pidFile) {
		$p = Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue
		if ($p -and $p.Path -eq $exe) { return $p }
	}
	return $null
}
switch ($Action) {
	'start' {
		if (Get-Ours) { throw 'already running' }
		$id = [U9030Win]::Start($exe, '-c sasalfa.cfg', $Dir)
		Set-Content $pidFile $id
		# hide every window it opens during its first seconds; hidden windows still take messages
		for ($i = 0; $i -lt 40; $i++) {
			Start-Sleep -Milliseconds 100
			foreach ($h in [U9030Win]::Windows($id)) { [void][U9030Win]::ShowWindow($h, 0) }
		}
		"started $id"
	}
	'ipl' {
		$p = Get-Ours
		if (-not $p) { throw 'not running' }
		foreach ($h in [U9030Win]::Windows($p.Id)) {
			$b = [U9030Win]::Child($h, 'TButton', 'IPL')
			if ($b -ne [IntPtr]::Zero) { [U9030Win]::Click($b); 'IPL pressed'; return }
		}
		throw 'IPL button not found'
	}
	'stop' {
		$p = Get-Ours
		if ($p) { Stop-Process -Id $p.Id -Force; 'stopped' }
		Remove-Item $pidFile -ErrorAction SilentlyContinue
	}
	'state' {
		$p = Get-Ours
		foreach ($h in [U9030Win]::Windows($p.Id)) {
			if ([U9030Win]::Class($h) -eq 'TU9030Form') { [U9030Win]::Fields($h) | Where-Object { $_ -match '^T(Edit|Memo|Button|CheckBox)' } }
		}
	}
	'windows' {
		$p = Get-Ours
		foreach ($h in [U9030Win]::Windows($p.Id)) { '{0} [{1}] {2}' -f $h, [U9030Win]::Class($h), [U9030Win]::Text($h) }
	}
}
