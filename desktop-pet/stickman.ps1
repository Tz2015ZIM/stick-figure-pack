# stickman.ps1
# A stick figure that lives on your desktop.
#
# He walks the ground, walks across the tops of your open windows, climbs up
# their edges, and interacts with what is around him:
#
#   * walks the ground, window title bars and the buttons inside dialogs
#   * stands and walks on anything solid white on screen (tray menu toggle)
#   * climbs the desktop shortcuts and stands on them, when the desktop shows
#   * stamping on a shortcut opens it (tray menu, on by default, once a minute)
#   * drops off a title bar down onto the buttons below and stamps on them
#   * rides a window as you drag it around
#   * notices your mouse pointer and waves at it
#   * knocks on a window edge he does not feel like climbing
#   * shoves a window a little sideways (toggle it off in the tray menu)
#   * sits on the edge of a window and swings his legs
#   * runs over to wherever you left-click and cheers when he gets there
#   * run more than one and they meet up: they wave, high-five, chat, dance,
#     play tag, wave back across the screen, and join in when one cheers
#   * drag him with the left mouse button, click him for a jump
#   * right-click him, or the tray icon, to quit
#   * shows up in Task Manager as 'Stick figure', or as whatever you named the
#     symbol when you converted him
#   * tick Fight mode when you convert him and he takes on your mouse pointer,
#     Animator vs. Animation style: punches, kicks, grabbing it and dragging
#     it off, and windows thrown at it (they go back where they were
#     afterwards; with none to hand he throws little Flash panels of his own);
#     beat the pointer's health bar down and he smashes it to pieces and
#     celebrates, until it pulls itself back together for another round;
#     click him to hit back, Esc to stop. Hard mode (tray menu, or ticked
#     with Fight mode) makes him far tougher, faster and meaner

param(
    [string]$Handoff = ''       # set when another copy of him hands over to this one, see Switch-Body
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SELF = $PSCommandPath      # so the tray menu can start another copy of him
$errLog = Join-Path $env:TEMP 'stickman-error.log'

# ------------------------------------------------------------------ his process
# Task Manager lists a process under the name baked into its exe, and a running
# process can never change it. So he gets one small exe per name he goes by -
# 'Stick figure', or the name of the symbol you converted him to - built from
# stickhost.cs into processes\. When his name changes he starts up in the exe
# for the new one, and this copy bows out once that one is on screen.
$PLAIN  = 'Stick figure'
$BODIES = Join-Path $PSScriptRoot 'processes'
$BODY   = $StickBody        # set by stickhost.cs; $null when powershell.exe runs him
$MYEXE  = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# the exe that runs him under $name, compiled the first time it is needed;
# $null if it cannot be built
function Get-Body($name) {
    $src = Join-Path $PSScriptRoot 'stickhost.cs'
    if (-not (Test-Path $src)) { return $null }
    # Windows will not take every character in a file name
    $safe = ($name -replace '[\\/:*?"<>|\x00-\x1f]', '_').Trim().TrimEnd('.')
    if ($safe -eq '') { $safe = $PLAIN }
    if ($safe -match '^(con|prn|aux|nul|com\d|lpt\d)$') { $safe = "_$safe" }

    $exe = $null; $old = $false
    for ($n = 1; $n -le 50; $n++) {
        $exe = Join-Path $BODIES $(if ($n -eq 1) { "$safe.exe" } else { "$safe $n.exe" })
        if (-not (Test-Path $exe)) { break }
        $item = Get-Item $exe
        if ($item.VersionInfo.FileDescription -cne $name) { $exe = $null; continue }   # 'a?b' and 'a*b' both make a_b
        if ($item.LastWriteTime -ge (Get-Item $src).LastWriteTime) { return $exe }
        $old = $true; break                     # stickhost.cs changed since: build it again
    }
    if ($null -eq $exe) { return $null }

    $lit  = '"' + $name.Replace('\', '\\').Replace('"', '\"') + '"'
    $code = [System.IO.File]::ReadAllText($src).Replace(
        'const string Name = "Stick figure";', "const string Name = $lit;")
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.GenerateExecutable = $true
    $cp.OutputAssembly     = $exe
    $cp.CompilerOptions    = '/target:winexe /optimize'
    $ico = Join-Path $PSScriptRoot 'stickman.ico'
    if (Test-Path $ico) { $cp.CompilerOptions += " /win32icon:`"$ico`"" }
    [void]$cp.ReferencedAssemblies.Add('System.dll')
    [void]$cp.ReferencedAssemblies.Add('System.Core.dll')
    [void]$cp.ReferencedAssemblies.Add([psobject].Assembly.Location)    # System.Management.Automation
    [void](New-Item -ItemType Directory -Force -Path $BODIES)
    $res = (New-Object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($cp, $code)
    if (-not $res.Errors.HasErrors) { return $exe }
    "$(Get-Date -Format s)  could not build '$name': $($res.Errors[0].ErrorText)" |
        Out-File -FilePath $errLog -Append -Encoding utf8
    if ($old) { return $exe }                   # in use by another copy of him: the old build still works
    return $null
}

# started from powershell.exe (the shortcut, or by hand): move into his own
# process before anything else, so he never shows up as Windows PowerShell
if ($null -eq $BODY) {
    $exe = Get-Body $PLAIN
    if ($null -ne $exe) {
        try { Start-Process -FilePath $exe -ErrorAction Stop; return } catch { }
    }
}

# what the copy that started this one handed over, or $null
$INHERIT = $null
if ($Handoff) {
    try { $INHERIT = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Handoff)) | ConvertFrom-Json }
    catch { }
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class SM {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public struct WIN {
        public IntPtr H;
        public int Left, Top, Right, Bottom;    // visual frame
        public bool Maximized;
        public string Name;                     // desktop shortcuts carry their label
    }

    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT v, int s);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
    public static int GetExStyle(IntPtr h) { return GetWindowLong(h, -20); }

    // ---- per-pixel alpha ----------------------------------------------------
    // No colour key, no purple fringe: the window shows exactly the pixels we
    // draw, with their own alpha, and clicks fall through the clear ones.
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE  { public int CX, CY; }
    [StructLayout(LayoutKind.Sequential)] public struct BLEND { public byte Op, Flags, Alpha, Format; }

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dst, ref POINT pd,
        ref SIZE ps, IntPtr src, ref POINT psrc, int key, ref BLEND bf, int flags);

    // Draws the sprite and moves the window to (x, y) in one go.
    public static void Blit(IntPtr hwnd, IntPtr hbmp, int x, int y, int w, int h) {
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr mem    = CreateCompatibleDC(screen);
        IntPtr old    = SelectObject(mem, hbmp);

        POINT dst = new POINT(); dst.X = x; dst.Y = y;
        POINT src = new POINT();
        SIZE  sz  = new SIZE();  sz.CX = w; sz.CY = h;
        BLEND bf  = new BLEND(); bf.Alpha = 255; bf.Format = 1;   // AC_SRC_ALPHA

        UpdateLayeredWindow(hwnd, screen, ref dst, ref sz, mem, ref src, 0, ref bf, 2);  // ULW_ALPHA

        SelectObject(mem, old);
        DeleteDC(mem);
        ReleaseDC(IntPtr.Zero, screen);
    }
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    // Shove a window sideways without resizing it, raising it or stealing focus.
    public static bool Nudge(IntPtr h, int dx, int dy) {
        if (!IsWindow(h) || IsZoomed(h) || IsIconic(h)) return false;
        RECT r;
        if (!GetWindowRect(h, out r)) return false;
        return SetWindowPos(h, IntPtr.Zero, r.Left + dx, r.Top + dy, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }

    // ---- throwing windows, in a fight ----------------------------------------
    // All he ever does to a window is move it: same size, same place in the
    // stack, focus left where it was. Never closed, minimised or clicked.
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);

    // The window's full rectangle, the one SetWindowPos works in, or null.
    public static int[] Rect(IntPtr h) {
        RECT r;
        if (!IsWindow(h) || !GetWindowRect(h, out r)) return null;
        return new int[] { r.Left, r.Top, r.Right, r.Bottom };
    }

    public static bool Place(IntPtr h, int x, int y) {
        if (!IsWindow(h) || IsZoomed(h) || IsIconic(h) || IsHungAppWindow(h)) return false;
        return SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }

    // An ordinary window of some other program that is answering. Never Task
    // Manager or anything always-on-top, so you can always get at those to
    // stop him, and never a window of his own.
    public static bool Throwable(IntPtr h, int self) {
        if (!IsWindow(h) || IsZoomed(h) || IsIconic(h) || IsHungAppWindow(h)) return false;
        if ((GetWindowLong(h, -20) & 0x00000008) != 0) return false;     // WS_EX_TOPMOST
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        if ((int)pid == self) return false;
        StringBuilder cn = new StringBuilder(64);
        GetClassName(h, cn, 64);
        return cn.ToString() != "TaskManagerWindow";
    }

    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);

    // Is this window what you see at (x, y), and not something in front of it?
    public static bool Showing(IntPtr h, int x, int y) {
        POINT p = new POINT(); p.X = x; p.Y = y;
        return GetAncestor(WindowFromPoint(p), 2) == h;                  // GA_ROOT
    }

    // Real push-buttons, check boxes and radio buttons inside one window.
    // Only classic Win32 controls have their own window handle, so this finds
    // buttons in dialogs, Explorer, Control Panel and the like.
    public static WIN[] Kids(IntPtr parent, int minW, int minH, int maxW, int maxH, int cap) {
        List<WIN> list = new List<WIN>();
        EnumProc cb = delegate(IntPtr h, IntPtr l) {
            if (list.Count >= cap) return false;
            if (!IsWindowVisible(h)) return true;

            StringBuilder cn = new StringBuilder(128);
            GetClassName(h, cn, 128);
            string c = cn.ToString();
            if (c != "Button" && !c.EndsWith("Button") && c != "CheckBox" && c != "RadioButton") return true;

            int st = GetWindowLong(h, -16);                      // GWL_STYLE
            if ((st & 0x08000000) != 0) return true;             // WS_DISABLED

            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left, ht = r.Bottom - r.Top;
            if (w < minW || ht < minH || w > maxW || ht > maxH) return true;

            WIN b = new WIN();
            b.H = h; b.Left = r.Left; b.Top = r.Top; b.Right = r.Right; b.Bottom = r.Bottom;
            list.Add(b);
            return true;
        };
        EnumChildWindows(parent, cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        return list.ToArray();
    }

    public static void Click(IntPtr h) {
        if (!IsWindow(h)) return;
        SendMessage(h, 0x00F5, IntPtr.Zero, IntPtr.Zero);        // BM_CLICK
    }

    // ---- desktop shortcuts --------------------------------------------------
    // The desktop icons are items in Explorer's own list view, and it will only
    // report their positions into memory belonging to Explorer, so we borrow a
    // scratch RECT inside that process and read the answer back out.
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cls, string win);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr sz, uint t, uint pr);
    [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr sz, uint t);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, ref RECT b, UIntPtr n, out UIntPtr w);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, ref RECT b, UIntPtr n, out UIntPtr r);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr n, out UIntPtr r);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr a, ref LVITEM b, UIntPtr n, out UIntPtr w);

    [StructLayout(LayoutKind.Sequential)]
    struct LVITEM {
        public uint mask; public int iItem; public int iSubItem; public uint state; public uint stateMask;
        public IntPtr pszText; public int cchTextMax; public int iImage; public IntPtr lParam;
        public int iIndent; public int iGroupId; public uint cColumns; public IntPtr puColumns;
        public IntPtr piColFmt; public int iGroup;
    }

    static IntPtr DesktopListView() {
        IntPtr pm = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Progman", null);
        IntPtr dv = FindWindowEx(pm, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (dv == IntPtr.Zero) {                      // a slideshow wallpaper reparents it
            IntPtr found = IntPtr.Zero;
            EnumProc cb = delegate(IntPtr h, IntPtr l) {
                StringBuilder cn = new StringBuilder(64);
                GetClassName(h, cn, 64);
                if (cn.ToString() == "WorkerW") {
                    IntPtr d2 = FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null);
                    if (d2 != IntPtr.Zero) found = d2;
                }
                return true;
            };
            EnumWindows(cb, IntPtr.Zero);
            GC.KeepAlive(cb);
            dv = found;
        }
        if (dv == IntPtr.Zero) return IntPtr.Zero;
        return FindWindowEx(dv, IntPtr.Zero, "SysListView32", null);
    }

    public static WIN[] Shortcuts() {
        List<WIN> list = new List<WIN>();
        IntPtr lv = DesktopListView();
        if (lv == IntPtr.Zero) return list.ToArray();

        int n = (int)SendMessage(lv, 0x1004, IntPtr.Zero, IntPtr.Zero);       // LVM_GETITEMCOUNT
        if (n <= 0) return list.ToArray();

        uint pid; GetWindowThreadProcessId(lv, out pid);
        IntPtr ph = OpenProcess(0x0008 | 0x0010 | 0x0020, false, pid);        // VM_OPERATION|READ|WRITE
        if (ph == IntPtr.Zero) return list.ToArray();
        IntPtr rem = VirtualAllocEx(ph, IntPtr.Zero, (UIntPtr)16, 0x1000, 0x04);
        if (rem == IntPtr.Zero) { CloseHandle(ph); return list.ToArray(); }
        int isz = Marshal.SizeOf(typeof(LVITEM));
        IntPtr remItem = VirtualAllocEx(ph, IntPtr.Zero, (UIntPtr)(uint)isz, 0x1000, 0x04);
        IntPtr remTxt  = VirtualAllocEx(ph, IntPtr.Zero, (UIntPtr)520, 0x1000, 0x04);
        byte[] txt = new byte[520];

        for (int i = 0; i < n && i < 120; i++) {
            RECT r = new RECT(); r.Left = 1;                                  // LVIR_ICON
            UIntPtr done;
            if (!WriteProcessMemory(ph, rem, ref r, (UIntPtr)16, out done)) break;
            if (SendMessage(lv, 0x100E, (IntPtr)i, rem) == IntPtr.Zero) continue;  // LVM_GETITEMRECT
            if (!ReadProcessMemory(ph, rem, ref r, (UIntPtr)16, out done)) break;

            POINT tl = new POINT(); tl.X = r.Left;  tl.Y = r.Top;
            POINT br = new POINT(); br.X = r.Right; br.Y = r.Bottom;
            ClientToScreen(lv, ref tl);
            ClientToScreen(lv, ref br);

            // the cell is far wider than the picture in it, so keep a square of
            // it in the middle - that is the bit he can actually stand on
            int half = (br.Y - tl.Y) / 2;
            int cx   = (tl.X + br.X) / 2;

            string label = "";
            if (remItem != IntPtr.Zero && remTxt != IntPtr.Zero) {
                LVITEM li = new LVITEM();
                li.mask = 0x0001;                                            // LVIF_TEXT
                li.iItem = i; li.pszText = remTxt; li.cchTextMax = 260;
                if (WriteProcessMemory(ph, remItem, ref li, (UIntPtr)(uint)isz, out done)) {
                    SendMessage(lv, 0x1073, (IntPtr)i, remItem);              // LVM_GETITEMTEXTW
                    if (ReadProcessMemory(ph, remTxt, txt, (UIntPtr)520, out done)) {
                        label = Encoding.Unicode.GetString(txt);
                        int z = label.IndexOf((char)0);
                        if (z >= 0) label = label.Substring(0, z);
                    }
                }
            }

            WIN w = new WIN();
            w.H = (IntPtr)(-1000 - i);
            w.Left = cx - half; w.Right = cx + half;
            w.Top = tl.Y; w.Bottom = br.Y;
            w.Name = label;
            list.Add(w);
        }

        VirtualFreeEx(ph, rem, UIntPtr.Zero, 0x8000);
        if (remItem != IntPtr.Zero) VirtualFreeEx(ph, remItem, UIntPtr.Zero, 0x8000);
        if (remTxt  != IntPtr.Zero) VirtualFreeEx(ph, remTxt,  UIntPtr.Zero, 0x8000);
        CloseHandle(ph);
        return list.ToArray();
    }

    // Visible top-level windows, front to back, as things we can stand on.
    public static WIN[] Windows(IntPtr self) {
        List<WIN> list = new List<WIN>();
        EnumProc cb = delegate(IntPtr h, IntPtr l) {
            if (h == self) return true;
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            if (GetWindowTextLength(h) == 0) return true;

            int ex = GetWindowLong(h, -20);
            if ((ex & 0x00000080) != 0) return true;            // WS_EX_TOOLWINDOW

            int cloaked = 0;                                    // hidden UWP / other desktop
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;

            StringBuilder cn = new StringBuilder(256);
            GetClassName(h, cn, 256);
            string c = cn.ToString();
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" ||
                c == "Shell_SecondaryTrayWnd" || c == "Windows.UI.Core.CoreWindow") return true;

            RECT r;                                             // visual frame, not the fat resize border
            if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) {
                if (!GetWindowRect(h, out r)) return true;
            }
            if (r.Right - r.Left < 140 || r.Bottom - r.Top < 90) return true;

            WIN w = new WIN();
            w.H = h; w.Left = r.Left; w.Top = r.Top; w.Right = r.Right; w.Bottom = r.Bottom;
            w.Maximized = IsZoomed(h);
            list.Add(w);
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        return list.ToArray();
    }

    // ---- breaking the pointer, in a fight ------------------------------------
    [StructLayout(LayoutKind.Sequential)] struct CURSORINFO { public int Size, Flags; public IntPtr Shape; public POINT At; }
    [StructLayout(LayoutKind.Sequential)] struct ICONINFO { public bool IsIcon; public int HotX, HotY; public IntPtr Mask, Colour; }
    [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] static extern IntPtr CopyIcon(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetIconInfo(IntPtr h, out ICONINFO ii);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, int key, byte alpha, int flags);

    // A copy of the pointer as it looks right now, over whatever program it is
    // over, with its hot spot in hot[0], hot[1]; IntPtr.Zero if it is hidden.
    // Free it with DestroyIcon.
    public static IntPtr PointerShape(int[] hot) {
        CURSORINFO ci = new CURSORINFO();
        ci.Size = Marshal.SizeOf(typeof(CURSORINFO));
        if (!GetCursorInfo(ref ci) || (ci.Flags & 1) == 0 || ci.Shape == IntPtr.Zero) return IntPtr.Zero;  // CURSOR_SHOWING
        IntPtr h = CopyIcon(ci.Shape);
        if (h == IntPtr.Zero) return IntPtr.Zero;
        ICONINFO ii;
        if (GetIconInfo(h, out ii)) {
            hot[0] = ii.HotX; hot[1] = ii.HotY;
            if (ii.Mask != IntPtr.Zero)   DeleteObject(ii.Mask);
            if (ii.Colour != IntPtr.Zero) DeleteObject(ii.Colour);
        }
        return h;
    }

    // The whole window at alpha 1: nothing you can see, but clicks stop there.
    public static void Veil(IntPtr h) { SetLayeredWindowAttributes(h, 0, 1, 2); }      // LWA_ALPHA
}

public struct PEER { public int Slot, Pid, X, Y, Dir, State, With, Act; }

// Every running copy of him shares one small named block of memory, a slot
// each, and writes where he is and what he is up to into it every frame.
// Nothing else is needed for them to find each other.
public static class Peers {
    const int SLOTS = 16, SIZE = 48;
    const int HB = 0, PID = 4, X = 8, Y = 12, DIR = 16, STATE = 20, WITH = 24, ACT = 28, QUIT = 32;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateFileMapping(IntPtr f, IntPtr sa, uint prot, uint hi, uint lo, string name);
    [DllImport("kernel32.dll")] static extern IntPtr MapViewOfFile(IntPtr m, uint access, uint hi, uint lo, UIntPtr n);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();

    static IntPtr view = IntPtr.Zero;
    static System.Threading.Mutex lk;
    public static int Me = -1;

    static IntPtr Slot(int i) { return IntPtr.Add(view, i * SIZE); }
    static int Pid() { return (int)GetCurrentProcessId(); }
    static bool Live(IntPtr p, int now, int ms) {
        return Marshal.ReadInt32(p, PID) != 0 && unchecked(now - Marshal.ReadInt32(p, HB)) < ms;
    }

    public static int Join() {
        if (view == IntPtr.Zero) {
            IntPtr m = CreateFileMapping(new IntPtr(-1), IntPtr.Zero, 0x04, 0, SLOTS * SIZE, "Local\\DesktopStickmanPeers");
            if (m == IntPtr.Zero) return -1;
            view = MapViewOfFile(m, 0x0006, 0, 0, (UIntPtr)(uint)(SLOTS * SIZE));   // READ | WRITE
            if (view == IntPtr.Zero) return -1;
            lk = new System.Threading.Mutex(false, "Local\\DesktopStickmanPeersLock");
        }
        bool held = false;
        try { held = lk.WaitOne(1000); } catch (System.Threading.AbandonedMutexException) { held = true; }
        try {
            int now = Environment.TickCount;
            for (int i = 0; i < SLOTS; i++) {
                IntPtr p = Slot(i);
                if (Live(p, now, 3000)) continue;
                for (int b = 0; b < SIZE; b += 4) Marshal.WriteInt32(p, b, 0);
                Marshal.WriteInt32(p, WITH, -1);
                Marshal.WriteInt32(p, HB, now);
                Marshal.WriteInt32(p, PID, Pid());
                Me = i;
                return i;
            }
        } finally { if (held) lk.ReleaseMutex(); }
        return -1;
    }

    public static void Publish(int x, int y, int dir, int state, int with, int act) {
        if (Me < 0) return;
        IntPtr p = Slot(Me);
        if (Marshal.ReadInt32(p, PID) != Pid()) {          // stalled long enough to lose it
            Me = -1;
            if (Join() < 0) return;
            p = Slot(Me);
        }
        Marshal.WriteInt32(p, X, x);
        Marshal.WriteInt32(p, Y, y);
        Marshal.WriteInt32(p, DIR, dir);
        Marshal.WriteInt32(p, STATE, state);
        Marshal.WriteInt32(p, WITH, with);
        Marshal.WriteInt32(p, ACT, act);
        Marshal.WriteInt32(p, HB, Environment.TickCount);
    }

    public static PEER[] Others() {
        List<PEER> list = new List<PEER>();
        if (view == IntPtr.Zero) return list.ToArray();
        int now = Environment.TickCount;
        for (int i = 0; i < SLOTS; i++) {
            if (i == Me) continue;
            IntPtr p = Slot(i);
            if (!Live(p, now, 1500)) continue;
            PEER o = new PEER();
            o.Slot = i;
            o.Pid = Marshal.ReadInt32(p, PID);
            o.X = Marshal.ReadInt32(p, X);
            o.Y = Marshal.ReadInt32(p, Y);
            o.Dir = Marshal.ReadInt32(p, DIR);
            o.State = Marshal.ReadInt32(p, STATE);
            o.With = Marshal.ReadInt32(p, WITH);
            o.Act = Marshal.ReadInt32(p, ACT);
            list.Add(o);
        }
        return list.ToArray();
    }

    public static bool QuitAsked() { return Me >= 0 && Marshal.ReadInt32(Slot(Me), QUIT) != 0; }

    public static void QuitAll() {
        if (view == IntPtr.Zero) return;
        int now = Environment.TickCount;
        for (int i = 0; i < SLOTS; i++) {
            IntPtr p = Slot(i);
            if (Live(p, now, 3000)) Marshal.WriteInt32(p, QUIT, 1);
        }
    }

    public static void Leave() {
        if (Me < 0) return;
        IntPtr p = Slot(Me);
        if (Marshal.ReadInt32(p, PID) == Pid()) { Marshal.WriteInt32(p, PID, 0); Marshal.WriteInt32(p, HB, 0); }
        Me = -1;
    }
}
"@

# Black paint in Paint is solid to him, and so is every stroke on the Gravity
# Pencil web page when its tab is showing. A background thread finds Paint, has it
# render itself into a bitmap (so nothing on top of it - him included - gets
# in the picture), picks out the white canvas and marks every black pixel on
# it. The map is kept relative to the window, so it stays lined up while you
# drag Paint around between captures.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

public static class Ink {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);

    class Map { public int CL, CT, CR, CB, W; public bool[] M; }

    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);

    // Any solid white patch on screen is ground too. The screen is captured in
    // a box around him; his own sprite is a layered window, so it is not in it.
    class Scr { public int X, Y, W, H; public bool[] M; }
    static volatile Scr scr;
    public static volatile bool White = true;  // tray menu toggle
    public static volatile int FX, FY;         // main thread: where he is right now
    const int BOX_W = 1400, BOX_H = 1000;      // how much of the screen around him is looked at
    const int RUN = 10, THICK = 4;             // smallest white patch that counts, so text does not

    static volatile Map cur;
    static Thread th;
    static long target;                       // Paint's window (or the Gravity Pencil page), found by the thread
    static volatile bool web;                 // the target is the Gravity Pencil page in a browser
    public static volatile bool Active;       // main thread: he is in or near Paint
    static int ox, oy;                        // where the window is right now
    static IntPtr synced = IntPtr.Zero;       // the window ox, oy belong to

    public static IntPtr Target { get { return new IntPtr(Interlocked.Read(ref target)); } }

    public static void Start() {
        if (th != null) return;
        th = new Thread(Loop);
        th.IsBackground = true;
        th.Priority = ThreadPriority.BelowNormal;
        th.Start();
    }

    static void Loop() {
        int found = 0;
        while (true) {
            try {
                if (--found <= 0) { found = 8; Find(); }          // look about once a second
                IntPtr t = Target;
                if (!Active || t == IntPtr.Zero || !IsWindow(t) || IsIconic(t)) cur = null;
                else cur = Grab(t, web);
            } catch { cur = null; }
            try { scr = White ? Shoot(FX, FY) : null; } catch { scr = null; }
            // the web page's drawings move, so it is looked at more often
            int wait = Active ? (web ? 30 : 110) : 140;
            Thread.Sleep(White ? Math.Min(wait, 60) : wait);
        }
    }

    // The frontmost of: a Paint window, or a window titled "Gravity Pencil"
    // (the page's tab, when it is the one showing in the browser).
    static void Find() {
        System.Collections.Generic.HashSet<uint> paint = new System.Collections.Generic.HashSet<uint>();
        foreach (Process p in Process.GetProcessesByName("mspaint")) { paint.Add((uint)p.Id); p.Dispose(); }
        IntPtr hit = IntPtr.Zero;
        bool isWeb = false;
        EnumProc cb = delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            GetWindowText(h, sb, 256);
            string title = sb.ToString();
            if (title.Length == 0) return true;
            if (title.IndexOf("Gravity Pencil", StringComparison.OrdinalIgnoreCase) >= 0) { hit = h; isWeb = true; return false; }
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (paint.Contains(pid)) { hit = h; isWeb = false; return false; }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        if (hit.ToInt64() != Interlocked.Read(ref target)) cur = null;
        web = isWeb;
        Interlocked.Exchange(ref target, hit.ToInt64());
    }

    // Paint: pure white canvas, black ink. The Gravity Pencil page paints its
    // paper exactly #fdfcfa, and every stroke on it is ink, whatever colour.
    static bool Paper(byte[] px, int o, bool isWeb) {
        if (isWeb) return Math.Abs(px[o + 2] - 253) <= 1 && Math.Abs(px[o + 1] - 252) <= 1 && Math.Abs(px[o] - 250) <= 1;
        return px[o] >= 250 && px[o + 1] >= 250 && px[o + 2] >= 250;
    }
    static bool Stroke(byte[] px, int o, bool isWeb) {
        if (isWeb) return Math.Min(px[o], Math.Min(px[o + 1], px[o + 2])) < 190;
        return px[o] < 90 && px[o + 1] < 90 && px[o + 2] < 90;
    }

    static Map Grab(IntPtr h, bool isWeb) {
        RECT r;
        if (!GetWindowRect(h, out r)) return null;
        int w = r.Right - r.Left, ht = r.Bottom - r.Top;
        if (w < 50 || ht < 50) return null;

        byte[] px;
        int stride;
        using (Bitmap b = new Bitmap(w, ht, PixelFormat.Format32bppArgb)) {
            using (Graphics g = Graphics.FromImage(b)) {
                IntPtr dc = g.GetHdc();
                bool ok = PrintWindow(h, dc, 2);               // PW_RENDERFULLCONTENT
                g.ReleaseHdc(dc);
                if (!ok) return null;
            }
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, ht), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            stride = d.Stride;
            px = new byte[stride * ht];
            Marshal.Copy(d.Scan0, px, 0, px.Length);
            b.UnlockBits(d);
        }

        // The canvas is the one big pure-white area: find the rows and columns
        // that are mostly white. The toolbar's white swatch is far too small
        // to count, and the dark or light chrome around it is never pure white.
        int[] rows = new int[ht], cols = new int[w];
        for (int y = 0; y < ht; y++) {
            int o = y * stride;
            for (int x = 0; x < w; x++, o += 4) {
                if (Paper(px, o, isWeb)) { rows[y]++; cols[x]++; }
            }
        }
        int rMin = Math.Max(40, w / 6), cMin = Math.Max(40, ht / 6);
        int cl = -1, cr = -1, ct = -1, cb = -1;
        for (int x = 0; x < w; x++)  if (cols[x] >= cMin) { if (cl < 0) cl = x; cr = x; }
        for (int y = 0; y < ht; y++) if (rows[y] >= rMin) { if (ct < 0) ct = y; cb = y; }
        if (cl < 0 || ct < 0 || cr - cl < 20 || cb - ct < 20) return null;

        Map m = new Map();
        m.CL = cl; m.CT = ct; m.CR = cr; m.CB = cb; m.W = cr - cl + 1;
        m.M = new bool[m.W * (cb - ct + 1)];
        for (int y = ct; y <= cb; y++) {
            int o = y * stride + cl * 4, i = (y - ct) * m.W;
            for (int x = cl; x <= cr; x++, o += 4, i++) {
                m.M[i] = Stroke(px, o, isWeb);
            }
        }
        return m;
    }

    static Scr Shoot(int cx, int cy) {
        int vl = GetSystemMetrics(76), vt = GetSystemMetrics(77);     // SM_X/YVIRTUALSCREEN
        int vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);     // SM_CX/CYVIRTUALSCREEN
        int w = Math.Min(BOX_W, vw), h = Math.Min(BOX_H, vh);
        int x = Math.Max(vl, Math.Min(cx - w / 2, vl + vw - w));
        int y = Math.Max(vt, Math.Min(cy - h / 2, vt + vh - h));

        byte[] px;
        int stride;
        using (Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
            using (Graphics g = Graphics.FromImage(b)) {
                // plain SourceCopy, no CAPTUREBLT: layered windows (him) are left out
                g.CopyFromScreen(x, y, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
            }
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            stride = d.Stride;
            px = new byte[stride * h];
            Marshal.Copy(d.Scan0, px, 0, px.Length);
            b.UnlockBits(d);
        }

        // white runs at least RUN wide...
        bool[] row = new bool[w * h];
        for (int yy = 0; yy < h; yy++) {
            int o = yy * stride, i = yy * w, start = -1;
            for (int xx = 0; xx <= w; xx++, o += 4) {
                bool on = xx < w && px[o] >= 245 && px[o + 1] >= 245 && px[o + 2] >= 245;
                if (on) { if (start < 0) start = xx; continue; }
                if (start >= 0 && xx - start >= RUN) for (int k = start; k < xx; k++) row[i + k] = true;
                start = -1;
            }
        }
        // ...and at least THICK tall below each pixel
        Scr s = new Scr();
        s.X = x; s.Y = y; s.W = w; s.H = h;
        s.M = new bool[w * h];
        for (int i = 0; i + (THICK - 1) * w < w * h; i++) {
            bool ok = true;
            for (int k = 0; k < THICK && ok; k++) ok = row[i + k * w];
            s.M[i] = ok;
        }
        return s;
    }

    // Called from the animation loop: note where Paint is now, and say how far
    // it moved since last time so he can ride along when it is dragged.
    public static int[] Sync() {
        IntPtr t = Target;
        RECT r;
        if (t == IntPtr.Zero || !GetWindowRect(t, out r)) return new int[] { 0, 0 };
        int dx = r.Left - ox, dy = r.Top - oy;
        bool first = t != synced;                       // a different window: nothing moved
        synced = t;
        ox = r.Left; oy = r.Top;
        return first ? new int[] { 0, 0 } : new int[] { dx, dy };
    }

    static Map Live { get { return Active ? cur : null; } }
    public static bool Ready { get { return Live != null || scr != null; } }

    static bool InMap(Map m, int x, int y) {
        return m != null && x >= ox + m.CL && x <= ox + m.CR && y >= oy + m.CT - 2 && y <= oy + m.CB;
    }

    // On Paint's canvas (so he rides it when it is dragged), not just on white.
    public static bool InCanvas(int x, int y) { return InMap(Live, x, y); }

    // Left, right and bottom of whatever he is standing on at (x, y).
    public static double[] Bounds(int x, int y) {
        Map m = Live;
        if (InMap(m, x, y)) return new double[] { ox + m.CL, ox + m.CR, oy + m.CB };
        Scr s = scr;
        if (s != null) return new double[] { s.X, s.X + s.W - 1, s.Y + s.H - 1 };
        return new double[] { x - 1, x + 1, y + 1 };
    }

    // Paint's canvas wins where it is (its white paper is not ground, its ink
    // is); everywhere else anything white is solid.
    static bool At(Map m, Scr s, int x, int y) {
        if (m != null) {
            int mx = x - ox - m.CL, my = y - oy - m.CT;
            if (mx >= 0 && mx < m.W && my >= 0 && my <= m.CB - m.CT) return m.M[my * m.W + mx];
        }
        if (s == null) return false;
        x -= s.X; y -= s.Y;
        if (x < 0 || x >= s.W || y < 0 || y >= s.H) return false;
        return s.M[y * s.W + x];
    }

    public static bool Inside(int x, int y) {
        if (InMap(Live, x, y)) return true;
        Scr s = scr;
        return s != null && x >= s.X && x < s.X + s.W && y >= s.Y && y < s.Y + s.H;
    }

    // The first solid pixel going down from y0 to y1 under his feet, or -1.
    // Three columns wide, so a thin slanted line cannot slip between his toes.
    public static int Floor(int x, int y0, int y1) {
        Map m = Live; Scr s = scr;
        if (m == null && s == null) return -1;
        for (int y = y0; y <= y1; y++)
            if (At(m, s, x - 1, y) || At(m, s, x, y) || At(m, s, x + 1, y)) return y;
        return -1;
    }

    // Anything solid in this column between y0 and y1: a stroke in his way.
    public static bool Blocked(int x, int y0, int y1) {
        Map m = Live; Scr s = scr;
        if (m == null && s == null) return false;
        for (int y = y0; y <= y1; y++) if (At(m, s, x, y)) return true;
        return false;
    }
}
"@

# The little Flash panels he conjures to throw when none of your windows will
# do (see Conjure-Prop). They show up without taking the focus from whatever
# you are using, and stay out of the taskbar and Alt+Tab.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
public class PropWindow : System.Windows.Forms.Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override System.Windows.Forms.CreateParams CreateParams {
        get {
            System.Windows.Forms.CreateParams p = base.CreateParams;
            p.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008;     // NOACTIVATE | TOOLWINDOW | TOPMOST
            return p;
        }
    }
}
"@

[void][SM]::SetProcessDPIAware()
[Ink]::Start()
[System.Windows.Forms.Application]::EnableVisualStyles()

# ------------------------------------------------------------------------ scale
# He is drawn in 96-dpi design units and everything is multiplied by $SC, so he
# comes out the same physical size on a 100% and a 300% display.
$tmpBmp = New-Object System.Drawing.Bitmap 1, 1
$tmpG   = [System.Drawing.Graphics]::FromImage($tmpBmp)
$SC     = [Math]::Max(1.0, $tmpG.DpiX / 96.0)
$tmpG.Dispose(); $tmpBmp.Dispose()

$DW = 44.0; $DH = 68.0      # sprite box, design units
$DCX = 22.0; $DFT = 62.0    # centre line and foot line, design units

$BOXW = [int][Math]::Round($DW * $SC)
$BOXH = [int][Math]::Round($DH * $SC)
$CX   = $DCX * $SC
$FOOT = $DFT * $SC

$RNG = New-Object System.Random

$GRAVITY = 0.85 * $SC
$SPEED   = 1.9  * $SC
$CLIMB   = 2.0  * $SC
$VMAX    = 26.0 * $SC
$REACH   = 14.0 * $SC   # how far ahead he notices a wall
$MINWALL = 22.0 * $SC   # shortest wall worth climbing
$EDGE    = 6.0  * $SC   # how close to a ledge end he gets before deciding
$HUG     = 7.0  * $SC   # how far off the wall his body sits while climbing
$STEPIN  = 10.0 * $SC   # where he plants his feet after topping out
$NOTICE  = 120.0 * $SC  # how close the pointer has to be before he reacts

$BTN_MINW = [int](26 * $SC)     # what counts as a button he can stand on
$BTN_MINH = [int](14 * $SC)
$BTN_MAXW = [int](420 * $SC)
$BTN_MAXH = [int](80 * $SC)
$BTN_CAP  = 40
$OPEN_GAP = 1500        # frames between shortcut launches, about 45 seconds

# ----------------------------------------------------------------------- state
$S = @{
    x = 400.0; y = 200.0        # x = centre of body, y = the surface under his feet
    vx = 0.0;  vy = 0.0
    state = 'fall'              # walk fall climb idle sit wave knock push press
    dir   = 1                   # 1 right, -1 left
    phase = 0.0                 # animation clock
    ledge = $null               # what he is standing on
    wall  = $null               # what he is climbing / knocking on
    timer = 0                   # frames left in the current one-shot pose
    cool  = 0                   # frames until he will notice the pointer again
    tick  = 0
    drag  = $false
    grabX = 0; grabY = 0
    lastX = 0.0
    dragged = 0.0
    ledges = @()
    ignore = [IntPtr]::Zero     # window top to fall straight through, while diving in
    mdown  = $false             # left button was already down last frame
    tx = 0.0; ty = 0.0          # where you last clicked, which he runs to
    chase = 0                   # frames left before he gives up on getting there
    ly0 = 0.0                   # height he leapt from, to grab a window corner
    icons = @()                 # desktop shortcut rectangles, refreshed rarely
    desk = @{}                  # shortcut label -> the file it points at
    open = $true                # allowed to launch a shortcut he stamps on
    lastOpen = -99999           # tick of the last launch, to keep it occasional
    shove = $true               # allowed to push windows around
    click = $false              # allowed to really press the buttons he stands on
    throw = $true               # allowed to throw windows at the pointer in a fight
    grabPtr = $true             # allowed to grab the pointer and drag it off in a fight
    killPtr = $true             # allowed to break the pointer in a fight, see Break-Pointer
    hard    = $false            # fight in hard mode, see $LEVELS
    symbol  = $false            # he is wrapped in a symbol box, Flash style
    symName = ''                # what the instance was named in the dialog
    symType = 'Movie Clip'      # Movie Clip / Button / Graphic
    symReg  = 4                 # registration point, 0..8 across the 3x3 grid
    symNum  = 1                 # next default name, Symbol 1, Symbol 2, ...
    symFlash = 0                # frames left of the flash after converting
    symFlashMax = 14            # how long that flash was, so it can fade out
    char = ''                   # the Alan Becker figure he was named after
    ink  = $null                # that figure's colour, or $null for his own
    pending = ''                # his new figure's move, waiting for him to settle
    pendTTL = 0                 # frames it waits before being given up on
    peers   = @()               # the other stickmen running right now
    with    = -1                # slot of the one he is meeting, or -1
    act     = ''                # what the two of them are doing together
    meetT   = 0                 # frames spent getting to each other
    waiting = $false            # stood still, waiting for his friend to arrive
    social  = 300               # frames until he goes looking for company again
    chasePeer = -1              # slot of the friend he is chasing in a game of tag
}

function New-Ledge($h, $l, $t, $r, $b, $ground, $max, $btn, $uia = -1, $icon = $false, $name = '', $ink = $false) {
    [pscustomobject]@{
        H = $h; L = [double]$l; T = [double]$t; R = [double]$r; B = [double]$b
        Ground = $ground; Max = $max; Btn = $btn; Uia = $uia; Icon = $icon; Name = $name; Ink = $ink
    }
}

# ------------------------------------------------------------------ paint ink
# Black strokes on Paint's canvas are ground and walls (see [Ink]). Standing on
# ink he follows the stroke's top pixel by pixel: up small steps, down slopes,
# stopped by anything taller than a step, and he falls off where it ends.
$INK_H    = [IntPtr](-7777)
$INK_UP   = [int](7 * $SC)      # tallest bump he just steps over
$INK_DOWN = [int](12 * $SC)     # deepest dip he walks down rather than falls
$INK_BODY = [int](46 * $SC)     # how tall he is, for strokes in front of his face

function New-InkLedge($y) {
    $b = [Ink]::Bounds([int][Math]::Round($S.x), [int]$y)
    New-Ledge $INK_H $b[0] $y $b[1] $b[2] $false $false $false -1 $false '' $true
}

# Move him $dx along the ink he stands on. Returns 'ok', 'wall' (he did not
# move) or 'fall' (he stepped off the end and is now falling).
function Step-Ink($dx) {
    $nx = $S.x + $dx
    $ix = [int][Math]::Round($nx)
    $iy = [int][Math]::Round($S.y)
    $lead = $ix + [Math]::Sign($dx) * [int](4 * $SC)
    if ([Ink]::Blocked($lead, $iy - $INK_BODY, $iy - $INK_UP - 1)) { return 'wall' }
    $gy = -1
    if ([Ink]::Inside($ix, $iy)) { $gy = [Ink]::Floor($ix, $iy - $INK_UP, $iy + $INK_DOWN) }
    $S.x = $nx
    if ($gy -lt 0) {
        $S.ledge = $null; $S.state = 'fall'; $S.vy = 0.0; $S.vx = $dx * 0.6
        return 'fall'
    }
    $S.y = [double]$gy
    $S.ledge = New-InkLedge $gy
    return 'ok'
}

# What each desktop label actually points at. Only shortcuts, programs and
# folders are listed, so stray documents on the desktop are never launched.
function Update-DesktopFiles {
    $m = @{}
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))
    foreach ($d in $dirs) {
        if ([string]::IsNullOrEmpty($d) -or -not (Test-Path -LiteralPath $d)) { continue }
        foreach ($item in (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
            if (-not ($item.PSIsContainer -or @('.lnk', '.url', '.exe') -contains $item.Extension.ToLower())) { continue }
            $m[$item.Name.ToLower()]     = $item.FullName
            $m[$item.BaseName.ToLower()] = $item.FullName
        }
    }
    $S.desk = $m
}

function Open-Shortcut($label) {
    if ([string]::IsNullOrWhiteSpace($label)) { return $false }
    $path = $S.desk[$label.ToLower()]
    if ($null -eq $path) { return $false }          # Recycle Bin and friends match nothing
    try { Start-Process -FilePath $path -ErrorAction Stop } catch { return $false }
    return $true
}

# --------------------------------------------------------------- button finder
# Classic Win32 dialogs give every button its own window handle, but anything
# built on WPF, WinUI, Electron or the web does not. UI Automation sees those,
# and is far too slow to call from the animation loop, so it runs on its own
# thread and drops what it finds into $sync.
$sync = [hashtable]::Synchronized(@{
    Target   = [IntPtr]::Zero   # the window the scanner should look inside
    Buttons  = @()              # rectangles, as @(left, top, right, bottom)
    Elements = @()              # the matching automation elements, worker-only
    ClickIdx = -1               # main thread asks for a press by index
    ClickRect = @(0, 0, 0, 0)   # where that button was when he stepped on it
    Stop     = $false
})

$scanner = {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $AE = [System.Windows.Automation.AutomationElement]
    $kinds = @(
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::CheckBox,
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::SplitButton
    )
    $conds = $kinds | ForEach-Object {
        New-Object System.Windows.Automation.PropertyCondition ($AE::ControlTypeProperty), $_
    }
    $cond = New-Object System.Windows.Automation.OrCondition $conds
    $last = [IntPtr]::Zero

    while (-not $sync.Stop) {
        try {
            if ($sync.ClickIdx -ge 0) {
                $i  = $sync.ClickIdx
                $rq = $sync.ClickRect
                $sync.ClickIdx = -1
                if ($i -lt $sync.Elements.Count) {
                    # the list may have been rebuilt since he stepped on it, so
                    # only press the thing that is still where he is standing
                    $now = $sync.Elements[$i].Current.BoundingRectangle
                    if ([Math]::Abs($now.Left - $rq[0]) -lt 3 -and [Math]::Abs($now.Top - $rq[1]) -lt 3 -and
                        [Math]::Abs($now.Right - $rq[2]) -lt 3) {
                        $pat = $null
                        if ($sync.Elements[$i].TryGetCurrentPattern(
                                [System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
                            $pat.Invoke()
                        }
                    }
                }
            }

            $h = $sync.Target
            if ($h -eq [IntPtr]::Zero) {
                if ($last -ne [IntPtr]::Zero) { $sync.Buttons = @(); $sync.Elements = @(); $last = $h }
            } else {
                $root = $AE::FromHandle($h)
                if ($null -ne $root) {
                    $found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
                    $els = New-Object System.Collections.ArrayList
                    $rcs = New-Object System.Collections.ArrayList
                    foreach ($e in $found) {
                        if ($rcs.Count -ge 40) { break }
                        $c = $e.Current
                        if ($c.IsOffscreen) { continue }
                        $r = $c.BoundingRectangle
                        if ($r.Width -lt 22 -or $r.Height -lt 12 -or $r.Width -gt 700 -or $r.Height -gt 140) { continue }
                        [void]$els.Add($e)
                        [void]$rcs.Add(@([double]$r.Left, [double]$r.Top, [double]$r.Right, [double]$r.Bottom))
                    }
                    $sync.Elements = $els.ToArray()
                    $sync.Buttons  = $rcs.ToArray()
                    $last = $h
                }
            }
        } catch {
            $sync.Buttons = @(); $sync.Elements = @()
        }
        Start-Sleep -Milliseconds 900
    }
}

$scanRs = [runspacefactory]::CreateRunspace()
$scanRs.ApartmentState = 'MTA'
$scanRs.Open()
$scanRs.SessionStateProxy.SetVariable('sync', $sync)
$scanPs = [powershell]::Create()
$scanPs.Runspace = $scanRs
[void]$scanPs.AddScript($scanner)
[void]$scanPs.BeginInvoke()

function Get-Ground {
    $p  = New-Object System.Drawing.Point ([int]$S.x), ([int]$S.y)
    $scr = [System.Windows.Forms.Screen]::FromPoint($p)
    $a   = $scr.WorkingArea
    New-Ledge ([IntPtr]::Zero) ($a.Left + 4 * $SC) ([double]$a.Bottom) ($a.Right - 4 * $SC) 1e6 $true $false $false
}

# Rebuild the world, and carry him along with whatever he was holding on to,
# so he rides a window when you drag it instead of being left in mid-air.
function Update-World {
    $old = $S.ledge
    $ow  = $S.wall

    $list = New-Object System.Collections.ArrayList
    $wins = [SM]::Windows($script:handle)
    foreach ($w in $wins) {
        [void]$list.Add((New-Ledge $w.H $w.Left $w.Top $w.Right $w.Bottom $false $w.Maximized $false))
    }

    # Buttons, but only in the window he is standing on or wandering over, so we
    # are not walking every control on the desktop thirty times a second.
    $near = [IntPtr]::Zero
    if ($null -ne $S.ledge -and -not $S.ledge.Ground -and -not $S.ledge.Btn) {
        $near = $S.ledge.H
    } else {
        foreach ($w in $wins) {
            if ($S.x -ge $w.Left - 40 * $SC -and $S.x -le $w.Right + 40 * $SC -and
                $S.y -ge $w.Top  - 40 * $SC -and $S.y -le $w.Bottom + 40 * $SC) { $near = $w.H; break }
        }
    }
    $sync.Target = $near

    if ($near -ne [IntPtr]::Zero) {
        # classic Win32 controls: cheap, exact, and available right now
        foreach ($b in [SM]::Kids($near, $BTN_MINW, $BTN_MINH, $BTN_MAXW, $BTN_MAXH, $BTN_CAP)) {
            [void]$list.Add((New-Ledge $b.H $b.Left $b.Top $b.Right $b.Bottom $false $false $true))
        }
        # anything modern: whatever the UI Automation thread last saw
        $i = 0
        foreach ($r in $sync.Buttons) {
            [void]$list.Add((New-Ledge ([IntPtr](-1 - $i)) $r[0] $r[1] $r[2] $r[3] $false $false $true $i))
            $i++
        }
    }

    # desktop shortcuts, but only the ones actually in view - an icon under a
    # window is not something he can stand on
    if ($S.tick % 90 -eq 0 -or $S.icons.Count -eq 0) { $S.icons = [SM]::Shortcuts() }
    if ($S.tick % 900 -eq 0 -or $S.desk.Count -eq 0) { Update-DesktopFiles }
    foreach ($ic in $S.icons) {
        $cx = ($ic.Left + $ic.Right) / 2.0
        $cy = ($ic.Top + $ic.Bottom) / 2.0
        $hidden = $false
        foreach ($w in $wins) {
            if ($cx -ge $w.Left -and $cx -le $w.Right -and $cy -ge $w.Top -and $cy -le $w.Bottom) {
                $hidden = $true; break
            }
        }
        if (-not $hidden) {
            [void]$list.Add((New-Ledge $ic.H $ic.Left $ic.Top $ic.Right $ic.Bottom $false $false $false -1 $true $ic.Name))
        }
    }

    [void]$list.Add((Get-Ground))
    $S.ledges = $list.ToArray()

    # Paint's ink only counts where Paint is the window in front, so a stroke
    # hidden behind another window cannot hold him up
    $pw = [Ink]::Target
    $live = $false
    if ($pw -ne [IntPtr]::Zero) {
        $decided = $false
        foreach ($w in $wins) {
            if ($S.x -ge $w.Left -and $S.x -le $w.Right -and $S.y -ge $w.Top -and $S.y -le $w.Bottom) {
                $live = $w.H -eq $pw; $decided = $true; break
            }
        }
        if (-not $decided) {
            foreach ($w in $wins) {
                if ($w.H -eq $pw -and $S.x -ge $w.Left - 80 * $SC -and $S.x -le $w.Right + 80 * $SC -and
                    $S.y -ge $w.Top - 80 * $SC -and $S.y -le $w.Bottom + 80 * $SC) { $live = $true }
            }
        }
    }
    [Ink]::Active = $live
    [Ink]::FX = [int]$S.x; [Ink]::FY = [int]$S.y
    $moved = [Ink]::Sync()

    if ($S.state -eq 'fall' -or $S.drag) { return }

    if ($null -ne $old -and $old.Ink -and $S.state -ne 'climb' -and $S.state -ne 'leap') {
        # ride Paint when it is dragged, then find the stroke under him again
        if ([Ink]::InCanvas([int][Math]::Round($S.x), [int][Math]::Round($S.y))) {
            $S.x += $moved[0]; $S.y += $moved[1]
        }
        $iy = [int][Math]::Round($S.y)
        $gy = [Ink]::Floor([int][Math]::Round($S.x), $iy - $INK_UP, $iy + $INK_DOWN)
        if ($gy -lt 0) { $S.ledge = $null; $S.state = 'fall'; $S.vy = 0.0; return }
        $S.y = [double]$gy
        $S.ledge = New-InkLedge $gy
        return
    }

    if ($S.state -eq 'climb') {
        $m = $null
        if ($null -ne $ow) { foreach ($l in $S.ledges) { if ($l.H -eq $ow.H) { $m = $l; break } } }
        if ($null -eq $m) { $S.state = 'fall'; $S.vy = 0.0; $S.wall = $null; return }
        $S.x += if ($S.dir -gt 0) { $m.L - $ow.L } else { $m.R - $ow.R }
        $S.wall = $m
        if ($S.y -lt $m.T -or $S.y -gt $m.B) { $S.state = 'fall'; $S.vy = 0.0; $S.wall = $null }
        return
    }

    if ($null -eq $old) { $S.state = 'fall'; return }

    if ($old.Ground) { $S.ledge = Get-Ground; $S.y = $S.ledge.T; return }

    $match = $null
    foreach ($l in $S.ledges) { if ($l.H -eq $old.H) { $match = $l; break } }
    if ($null -eq $match) { $S.ledge = $null; $S.state = 'fall'; $S.vy = 0.0; return }

    $S.x += $match.L - $old.L      # ride it
    $S.y  = $match.T
    $S.ledge = $match
    if ($S.x -lt $match.L -or $S.x -gt $match.R) { $S.ledge = $null; $S.state = 'fall'; $S.vy = 0.0 }
}

# A window edge directly in front of him, tall enough to be worth bothering with.
function Find-Wall {
    foreach ($l in $S.ledges) {
        if ($l.Ground) { continue }
        $min = if ($l.Btn -or $l.Icon) { 9 * $SC } else { $MINWALL }   # a button or icon is a low step up
        if ($l.T -gt $S.y - $min) { continue }   # too short
        if ($l.B -lt $S.y - 4 * $SC)  { continue }   # ends above his feet
        if ($S.dir -gt 0) {
            if ($l.L -ge $S.x -and $l.L -le $S.x + $REACH) { return $l }
        } else {
            if ($l.R -le $S.x -and $l.R -ge $S.x - $REACH) { return $l }
        }
    }
    return $null
}

# A button sitting inside the window he is standing on, close enough below to
# drop down onto.
function Find-DropTarget($l) {
    foreach ($b in $S.ledges) {
        if (-not $b.Btn) { continue }
        if ($b.T -le $l.T + 12 * $SC -or $b.T -ge $l.B) { continue }
        if ($S.x -ge $b.L + $EDGE -and $S.x -le $b.R - $EDGE) { return $b }
    }
    return $null
}

# A window floating clear of the ground has no edge he can walk into, so he
# jumps up and grabs its bottom corner instead, and climbs from there.
function Find-Reach {
    foreach ($l in $S.ledges) {
        if ($l.Ground -or $l.Btn) { continue }
        if ($l.B -ge $S.y - 8 * $SC)   { continue }   # not above him
        if ($l.B -lt $S.y - 240 * $SC) { continue }   # out of jumping range
        if ($l.T -gt $l.B - 24 * $SC)  { continue }   # no side worth climbing
        if ($S.dir -gt 0) {
            if ($l.L -ge $S.x - $REACH -and $l.L -le $S.x + $REACH) { return $l }
        } else {
            if ($l.R -le $S.x + $REACH -and $l.R -ge $S.x - $REACH) { return $l }
        }
    }
    return $null
}

function Land-On($l) {
    $S.ledge  = $l
    $S.y      = $l.T
    $S.vy     = 0.0
    $S.state  = 'walk'
    $S.wall   = $null
    $S.ignore = [IntPtr]::Zero
    $F.air    = ''
    if ($F.on) { return }                   # mid-fight he never stamps on buttons or shortcuts
    if (($l.Btn -or $l.Icon) -and $RNG.Next(0, 3) -eq 0) {
        $S.state = 'press'; $S.timer = 42; $S.phase = 0.0
    } elseif ($S.chase -gt 0) {
        $S.state = 'chase'                 # he was on his way to you, carry on
    }
}

function Cursor-Distance {
    $c  = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - $S.x
    $dy = $c.Y - ($S.y - 30 * $SC)
    @{ D = [Math]::Sqrt($dx * $dx + $dy * $dy); X = $c.X }
}

# A window edge anywhere nearby that he could climb, so he goes looking for
# something to stand on instead of pacing the taskbar all day.
function Find-Climb {
    $best = $null
    $bd   = 700 * $SC
    foreach ($l in $S.ledges) {
        if ($l.Ground -or $l.Btn) { continue }
        if ($l.T -gt $S.y - $MINWALL) { continue }
        if ($l.B -lt $S.y - 4 * $SC)  { continue }
        foreach ($e in @($l.L, $l.R)) {
            $d = [Math]::Abs($e - $S.x)
            if ($d -lt $bd -and $d -gt $REACH) { $bd = $d; $best = $e }
        }
    }
    return $best
}

# ---------------------------------------------------------------- other stickmen
# Each copy of him publishes a slot in shared memory (see [Peers]), so they can
# see one another. A meeting is a handshake done entirely through those slots:
# one of them sets 'with' to the other and walks over, the other notices it is
# wanted, sets 'with' back, and once both are close they play the act together.
$ME = [Peers]::Join()
$STATE_CODE = @{
    walk = 1; fall = 2; climb = 3; idle = 4; sit = 5; wave = 6; knock = 7; push = 8
    press = 9; chase = 10; cheer = 11; leap = 12; meet = 13; social = 14
}
$ST_DRAG = 15
$ACTS     = @('', 'greet', 'highfive', 'chat', 'dance', 'tag')
$ACT_TIME = @{ greet = 60; highfive = 40; chat = 150; dance = 80; tag = 24 }
$ACT_GAP  = @{ greet = 34; highfive = 24; chat = 32; dance = 30; tag = 22 }   # how close they stand
$SOCIAL_POSE = @{ greet = 'wave'; highfive = 'hifive'; chat = 'chat'; dance = 'cheer'; tag = 'knock' }

function Publish-Self {
    $code = if ($S.drag) { $ST_DRAG } else { [int]$STATE_CODE[$S.state] }
    [Peers]::Publish([int]$S.x, [int]$S.y, [int]$S.dir, $code, [int]$S.with, [array]::IndexOf($ACTS, $S.act))
    $script:ME = [Peers]::Me
}

function Get-Peer($slot) {
    foreach ($p in $S.peers) { if ($p.Slot -eq $slot) { return $p } }
    return $null
}

# free to be walked up to: pottering about and not already with someone
function Test-Free($p) { $p.With -lt 0 -and $p.State -in @(1, 4, 5) }

function Stop-Meeting {
    $S.with    = -1
    $S.act     = ''
    $S.waiting = $false
    $S.social  = $RNG.Next(450, 1200)
    if ($S.state -eq 'meet' -or $S.state -eq 'social') { $S.state = 'walk' }
}

function Start-Meeting($p, $act) {
    $S.with    = $p.Slot
    $S.act     = $act
    $S.state   = 'meet'
    $S.meetT   = 0
    $S.waiting = $false
    $S.phase   = 0.0
    if ($p.X -ne [int]$S.x) { $S.dir = [Math]::Sign($p.X - $S.x) }
}

function Step-Friends {
    $S.peers = @([Peers]::Others())
    if ($S.social -gt 0) { $S.social-- }

    # something else took him out of the meeting: a click, a drag, a fall
    if ($S.with -ge 0 -and $S.state -ne 'meet' -and $S.state -ne 'social') { Stop-Meeting }
    if ($S.peers.Count -eq 0 -or $ME -lt 0) { return }
    if ($S.with -ge 0 -or $null -eq $S.ledge) { return }
    if ($S.state -notin @('walk', 'idle', 'sit', 'wave')) { return }

    # somebody is on their way over to see him
    foreach ($p in $S.peers) {
        if ($p.With -eq $ME -and $p.State -eq $STATE_CODE.meet -and [Math]::Abs($p.Y - $S.y) -lt 8 * $SC) {
            Start-Meeting $p $ACTS[[Math]::Max(0, $p.Act)]
            return
        }
    }
    if ($S.state -eq 'wave') { return }

    $same = $null; $sd = 1e9       # nearest friend on the same ledge
    $far  = $null; $fd = 1e9       # nearest one anywhere else
    foreach ($p in $S.peers) {
        $dx = $p.X - $S.x
        $d  = [Math]::Abs($dx)
        $level = [Math]::Abs($p.Y - $S.y) -lt 6 * $SC

        # walking straight into each other: step back round instead of through
        if ($level -and $S.state -eq 'walk' -and $d -lt 16 * $SC -and
            [Math]::Sign($dx) -eq $S.dir -and $p.Dir -eq -$S.dir) { $S.dir = -$S.dir }

        # one of them is cheering or waving: join in, facing them
        if ($S.social -le 0 -and $S.tick % 10 -eq 0 -and $d -lt 300 * $SC -and
            ($p.State -eq $STATE_CODE.cheer -or $p.State -eq $STATE_CODE.wave) -and $RNG.Next(0, 3) -eq 0) {
            if ($dx -ne 0) { $S.dir = [Math]::Sign($dx) }
            $S.state  = if ($p.State -eq $STATE_CODE.cheer) { 'cheer' } else { 'wave' }
            $S.timer  = 55; $S.phase = 0.0; $S.social = 400
            return
        }

        if (-not (Test-Free $p)) { continue }
        if ($level) { if ($d -lt $sd) { $sd = $d; $same = $p } }
        elseif ($d -lt $fd)       { $fd = $d; $far = $p }
    }

    # a friend stood about: look at them
    if ($S.state -eq 'idle' -and $null -ne $same -and $sd -lt 260 * $SC -and $same.X -ne [int]$S.x) {
        $S.dir = [Math]::Sign($same.X - $S.x)
    }

    if ($S.social -gt 0 -or $S.tick % 15 -ne 0) { return }

    # close by on the same ledge: go over and do something together
    if ($null -ne $same -and $sd -lt 280 * $SC -and $RNG.Next(0, 3) -eq 0) {
        Start-Meeting $same $ACTS[$RNG.Next(1, $ACTS.Count)]
        return
    }
    # out of reach: a wave across the gap, which they will usually return
    if ($null -ne $far -and $fd -lt 420 * $SC -and $RNG.Next(0, 6) -eq 0) {
        if ($far.X -ne [int]$S.x) { $S.dir = [Math]::Sign($far.X - $S.x) }
        $S.state = 'wave'; $S.timer = 60; $S.phase = 0.0; $S.social = 500
    }
}

# ------------------------------------------------------------------------ fight
# Fight mode, ticked in the Convert to Symbol dialog: Animator vs. Animation,
# with your pointer as the animator. He hunts it down, climbing whatever is in
# the way, and throws punches, kicks and flying kicks at it; a blow that lands
# pops a spark and knocks the pointer back a little. When the pointer is out of
# reach he picks up a window instead and throws it at it, and with the pointer
# far off that is his main weapon: he runs to windows along his ledge, jumps
# for ones hanging above him, and throws them one after another, up to three
# in the air at once. The pointer has hits too, and when they run out he
# breaks it and wins the round (see Break-Pointer), until it mends. Click
# him to hit back - eight hits and he is out, and when he comes round he
# gives up.
#
# It is all show. While he fights he never presses buttons or opens shortcuts.
# A window he throws is only ever moved: never closed, resized, minimised or
# clicked, never Task Manager or anything always-on-top, and it stays on
# screen. When the fight ends every one of them glides back to where it was,
# unless you have moved it yourself since. The pointer is only nudged, and a
# window only flies, while no mouse button is down, so nothing you are dragging
# gets pulled somewhere else. Esc ends it.
#
# PowerShell names ignore case, so no local variable may ever be called $f: it
# would hide this table from every function called while it is in scope.
$F = @{
    on    = $false
    hp    = 8; max = 8          # hits he can still take before he is knocked out, see $TUNE
    ko    = $false              # knocked out: he lies down as soon as he lands
    second = $false             # he has already got back up from one knockout
    intro = $false              # the first thing he does is square up to you
    inv   = 0                   # frames before he can be hit again
    hurt  = 0                   # frames left of the red flash
    cool  = 0                   # frames before his next attack
    combo = 0                   # jab, cross, jab...
    air   = ''                  # how he looks in the air: flykick, hurt, flip
    hitDone = $false            # a flying kick lands once at most
    gloat = $false              # taunt once the current blow is over
    kx = 0.0; ky = 0.0; kn = 0  # knock-back still owed to the pointer
    fx = 0; fxX = 0; fxY = 0; fxRot = 0.0   # the spark: frames left, where, angle
    px = 0; py = 0              # the pointer last frame, to see you swipe at him
    dodge = 0                   # frames before he will dodge again
    fly = $null                 # the window in his hands
    flying = New-Object System.Collections.ArrayList       # the windows he has thrown, still in the air
    fetch = $null               # the window he is walking over to pick up
    throwCool = 0               # frames before he will throw another
    far = $false                # the pointer is a long way off: time for windows
    skip = @{}                  # windows Windows would not let him move
    kd = 0.62                   # how fast the knock-back dies away, per frame
    grab = $false               # he has hold of your pointer
    grabCool = 0                # frames before he will grab it again
    gx = 0; gy = 0              # where he last put the pointer
    sx = 0; sy = 0              # where it was when he grabbed it
    run = 1                     # the way he is running off with it
    struggle = 0.0              # how hard you have been pulling it back
}
$FIGHT_STATES = @('hunt', 'guard', 'taunt', 'punch', 'kick', 'ko', 'fetch', 'heave', 'hurl', 'haul', 'fling', 'win', 'shock')
$FX_LEN = 10

# every window he has thrown, by handle: where it was before the fight (X0, Y0)
# and where he last put it (LX, LY), so it can be put back afterwards
$THROWN = @{}
$WGRAV      = 0.9 * $SC         # windows fall a little faster than he does
$HEAVE_LEN  = 20                # frames of wind-up before a window flies
$JUMP_RISE  = 10                # jumping for a window: frames going up,
$JUMP_HANG  = 6                 # hanging off its bottom edge,
$JUMP_PULL  = 12                # and dropping back down with it
$REACH_UP   = 240 * $SC         # highest window bottom, above his feet, he jumps for
$FAR_OFF    = 300 * $SC         # the pointer further off than this: the windows come out
$FETCH_FAR  = 700 * $SC         # and he goes this far along his ledge to get one

$GRAB_HOLD   = 84               # frames he runs about with your pointer before throwing it
$GRAB_SNATCH = 8                # the first of them, reaching out and taking it
$FLING_LEN   = 14               # the throw at the end
$FLING_AT    = 5                # the frame of the throw he lets go on

# Hard mode, ticked in the tray menu or the Convert to Symbol dialog: the same
# fight, but he takes far more beating, blocks, gets back up from his first
# knockout, attacks sooner and reaches further, runs faster, dodges more,
# throws more windows at once, holds on to your pointer harder, and your
# pointer breaks sooner. $TUNE is whichever of these is in force.
$LEVELS = @{
    normal = @{
        hp = 8; ptr = 10            # hits he can take, and hits the pointer can take
        pace = 1.0                  # multiplies every wait between his attacks, throws and grabs
        reach = 1.0; speed = 1.0    # multiply how far his blows reach, and how fast he closes in
        kick = 1                    # hits a kick or flying kick takes off the pointer
        block = 0                   # percent of the clicks he sees coming that he blocks
        second = $false             # gets back up from his first knockout
        dodge = 33; alert = 28      # percent chance he hops out of the way of a swipe this fast
        flying = 3                  # windows in the air at once
        struggle = 170              # how hard you have to pull, design units, to get your pointer back
        inv = 12                    # frames after a hit before he can be hit again
    }
    hard = @{
        hp = 20; ptr = 6
        pace = 0.5
        reach = 1.25; speed = 1.4
        kick = 2
        block = 40
        second = $true
        dodge = 67; alert = 20
        flying = 5
        struggle = 320
        inv = 18
    }
}
$TUNE = $LEVELS.normal

function Set-Hard($on) {
    $S.hard = [bool]$on
    $script:TUNE = if ($S.hard) { $LEVELS.hard } else { $LEVELS.normal }
    $hardItem.Checked = $S.hard
    # mid-fight, the bars change size but keep how full they were
    $F.hp = [Math]::Max(1, [int][Math]::Round($F.hp * $TUNE.hp / [double]$F.max)); $F.max = $TUNE.hp
    if (-not $PTR.dead) { $PTR.hp = [Math]::Max(1, [int][Math]::Round($PTR.hp * $TUNE.ptr / [double]$PTR.max)) }
    $PTR.shown = $PTR.shown * $TUNE.ptr / [double]$PTR.max; $PTR.max = $TUNE.ptr
    Sync-SymbolItem
}

function Start-Fight {
    $c = [System.Windows.Forms.Cursor]::Position
    $F.on = $true; $F.max = $TUNE.hp; $F.hp = $F.max; $F.ko = $false; $F.second = $false; $F.intro = $true
    $F.inv = 0; $F.cool = [int](20 * $TUNE.pace); $F.air = ''; $F.px = $c.X; $F.py = $c.Y
    $F.fly = $null; $F.fetch = $null; $F.flying.Clear(); $F.throwCool = [int](90 * $TUNE.pace)   # fists first
    $F.grab = $false; $F.grabCool = [int](60 * $TUNE.pace)
    $PTR.max = $TUNE.ptr; $PTR.hp = $PTR.max; $PTR.shown = [double]$PTR.max
    $S.pending = ''                         # squaring up is his entrance now
    $S.chase = 0; $S.chasePeer = -1
    if ($S.with -ge 0) { Stop-Meeting }
    Sync-SymbolItem
}

function End-Fight {
    Restore-Pointer                         # in pieces: whole again at once
    $PTR.bar = 0; Hide-PtrBar
    $F.on = $false; $F.ko = $false; $F.air = ''; $F.kn = 0
    $F.fly = $null; $F.fetch = $null; $F.flying.Clear()    # whatever he threw goes back, see Step-Tidy
    foreach ($prop in @($PROPS)) { Remove-Prop $prop }      # his own panels just go
    Release-Pointer
    if ($S.state -in $FIGHT_STATES) { $S.state = 'walk'; $S.phase = 0.0 }
    Sync-SymbolItem
}

function Pop-Spark($x, $y) {
    $F.fx = $FX_LEN; $F.fxX = [int]$x; $F.fxY = [int]$y; $F.fxRot = $RNG.NextDouble()
}

function Test-MouseHeld {
    [SM]::GetAsyncKeyState(1) -lt 0 -or [SM]::GetAsyncKeyState(2) -lt 0 -or [SM]::GetAsyncKeyState(4) -lt 0
}

# his fist or foot, or a window he threw, found the pointer: it is knocked
# ($kx, $ky) pixels the first frame, and a little less each frame after, and
# loses $dmg of its hits
function Land-Blow($kx = $S.dir * 14 * $SC, $ky = -5 * $SC, $dmg = 1) {
    if ($PTR.dead) { return }                       # nothing there to hit
    if (Hurt-Pointer $dmg $kx $ky) { return }       # that one broke it
    $c = [System.Windows.Forms.Cursor]::Position
    Pop-Spark $c.X $c.Y
    if (-not (Test-MouseHeld)) { $F.kx = $kx; $F.ky = $ky; $F.kn = 6; $F.kd = 0.62 }
    if ($RNG.Next(0, 4) -eq 0) { $F.gloat = $true }
}

# ------------------------------------------------------------- throwing windows
# A window he can get his hands on from somewhere on the ledge he is standing
# on, within $range of him: @{ L = the window; X = where he stands to grab it;
# Dir = which way he faces; Up = held overhead rather than by its side; Jump =
# out of his reach, so he jumps up for its bottom edge }, or $null. Nothing
# maximised, nothing too big to lift, nothing hanging off the screen or hidden
# behind other windows, nothing already in the air, and nothing that fails
# [SM]::Throwable.
function Find-Throwable($range) {
    $l = $S.ledge
    if ($null -eq $l) { return $null }
    $top = if ($l.Ink) { 70 * $SC } else { $REACH_UP }       # he does not jump off ink
    $best = $null; $bd = 1e9
    foreach ($w in $S.ledges) {
        if ($w.Ground -or $w.Btn -or $w.Icon -or $w.Ink -or $w.Max -or $w.H -eq $l.H) { continue }
        if ($w.T -gt $S.y - 20 * $SC -or $w.B -lt $S.y - $top) { continue }   # not within his reach
        if (Test-Flying $w.H) { continue }
        $up   = $w.B -lt $S.y - 38 * $SC
        $jump = $w.B -lt $S.y - 70 * $SC
        if ($up) {
            $gx = [Math]::Max($w.L + 12 * $SC, [Math]::Min($w.R - 12 * $SC, $S.x)); $dir = $S.dir
            # a spot on it just clear of where he will stand, to see it is not covered
            $px = if ($gx + 34 * $SC -le $w.R - 4) { $gx + 34 * $SC } else { $gx - 34 * $SC }
            $py = $w.B - 8 * $SC
        } else {
            # by its side: the nearer edge, never from in front of it
            $gl = $w.L - 14 * $SC; $gr = $w.R + 14 * $SC
            if ([Math]::Abs($S.x - $gl) -le [Math]::Abs($S.x - $gr)) { $gx = $gl; $dir = 1 } else { $gx = $gr; $dir = -1 }
            $px = if ($dir -gt 0) { $w.L + 30 * $SC } else { $w.R - 30 * $SC }
            $py = [Math]::Max($w.T + 8 * $SC, [Math]::Min($w.B - 8 * $SC, $S.y - 30 * $SC))
        }
        $d = [Math]::Abs($gx - $S.x)
        if ($d -gt $range -or $d -ge $bd) { continue }
        if ($l.Ink) { if ($d -gt 4 * $SC) { continue } }          # he does not walk ink to get there
        elseif ($gx -lt $l.L + $EDGE -or $gx -gt $l.R - $EDGE) { continue }
        if (-not (Test-Throwable $w)) { continue }
        # a window hidden behind others would fly where nobody can see it
        if (-not [SM]::Showing($w.H, [int]$px, [int]$py)) { continue }
        $bd = $d
        $best = @{ L = $w; X = [double]$gx; Dir = $dir; Up = $up; Jump = $jump }
    }
    return $best
}

function Test-Throwable($w) {
    if ($F.skip.ContainsKey($w.H.ToInt64())) { return $false }
    $mid = New-Object System.Drawing.Point ([int](($w.L + $w.R) / 2)), ([int](($w.T + $w.B) / 2))
    $a = [System.Windows.Forms.Screen]::FromPoint($mid).WorkingArea
    if ($w.R - $w.L -gt $a.Width * 0.7 -or $w.B - $w.T -gt $a.Height * 0.7) { return $false }
    if ($w.L -lt $a.Left - 2 -or $w.T -lt $a.Top - 2 -or $w.R -gt $a.Right + 2 -or $w.B -gt $a.Bottom + 2) { return $false }
    return [SM]::Throwable($w.H, $PID)
}

function Test-Flying($h) {
    foreach ($fl in $F.flying) { if ($fl.H -eq $h) { return $true } }
    return $false
}

# A throw is due: go and get a window. With -Conjure, when none of yours will
# do, a panel of his own pops up in his hands instead.
function Try-Throw($range, [switch]$Conjure) {
    if (-not $S.throw -or $F.throwCool -gt 0 -or $null -ne $F.fly -or $F.flying.Count -ge $TUNE.flying) { return $false }
    $t = Find-Throwable $range
    if ($null -eq $t) {
        if ($Conjure -and $null -ne $S.ledge) { return (Conjure-Prop) }
        return $false
    }
    $F.fetch = $t
    $S.state = 'fetch'; $S.phase = 0.0
    $S.timer = [int]([Math]::Abs($t.X - $S.x) / ($SPEED * 2.4)) + 40
    $S.dir = if ([Math]::Abs($t.X - $S.x) -gt 2 * $SC) { [Math]::Sign($t.X - $S.x) } else { $t.Dir }
    return $true
}

# at the window: take hold of it
function Start-Heave($t) {
    $w = $t.L
    $r = [SM]::Rect($w.H)
    if ($null -eq $r) { return $false }
    $k = $w.H.ToInt64()
    $was = $THROWN[$k]
    # the first time, or you have moved it since he last had it: this is home
    if ($null -eq $was -or [Math]::Abs($r[0] - $was.LX) -gt 3 -or [Math]::Abs($r[1] - $was.LY) -gt 3) {
        $THROWN[$k] = @{ H = $w.H; X0 = $r[0]; Y0 = $r[1]; LX = $r[0]; LY = $r[1] }
    }
    $len = $HEAVE_LEN; $g = 0.0
    if ($t.Jump) {
        $len = $JUMP_RISE + $JUMP_HANG + $JUMP_PULL
        $g   = $S.y - 58 * $SC - $w.B               # how far he has to jump for his hands to reach it
    }
    $F.fly = @{
        H  = $w.H
        OL = $w.L - $r[0]; OT = $w.T - $r[1]          # visible frame inside the full rectangle
        FW = $w.R - $w.L;  FH = $w.B - $w.T
        HX = $w.L; HY = $w.T                          # where it sat when he grabbed it
        X  = $w.L; Y  = $w.T                          # where it is now, frame top-left
        VX = 0.0; VY = 0.0; T = 0
        Up = $t.Up; Jump = $t.Jump; G = $g; Len = $len; Hit = $false
    }
    $S.dir = $t.Dir
    $S.state = 'heave'; $S.timer = $len; $S.phase = 0.0
    return $true
}

# How high off his ledge he is, $n frames into a jump for a window $g above
# his reach: up fast, a moment hanging off it, then down again, pulling it.
function Get-JumpLift($n, $g) {
    if ($n -le $JUMP_RISE) { $u = 1.0 - $n / [double]$JUMP_RISE; return $g * (1.0 - $u * $u) }
    if ($n -le $JUMP_RISE + $JUMP_HANG) { return $g }
    $u = [Math]::Min(1.0, ($n - $JUMP_RISE - $JUMP_HANG) / [double]$JUMP_PULL)
    return $g * (1.0 - $u * $u)
}

# puts window $fl at frame top-left ($x, $y), and notes where
function Move-Held($fl, $x, $y) {
    $rx = [int][Math]::Round($x - $fl.OL)
    $ry = [int][Math]::Round($y - $fl.OT)
    if (-not [SM]::Place($fl.H, $rx, $ry)) { return $false }
    $w = $THROWN[$fl.H.ToInt64()]
    $w.LX = $rx; $w.LY = $ry
    $fl.X = $x; $fl.Y = $y
    return $true
}

# still just where he last put it? If it was closed, or moved by you or by the
# program itself, he lets go of it there
function Test-Hold($fl) {
    $w = $THROWN[$fl.H.ToInt64()]
    $r = [SM]::Rect($fl.H)
    return $null -ne $r -and [Math]::Abs($r[0] - $w.LX) -le 3 -and [Math]::Abs($r[1] - $w.LY) -le 3
}

# end of the wind-up: it goes, on an arc that meets the pointer where it is now
function Launch-Window {
    $fl = $F.fly
    if ($null -eq $fl) { $S.state = 'guard'; return }
    $c  = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - ($fl.X + $fl.FW / 2.0)
    $dy = $c.Y - ($fl.Y + $fl.FH / 2.0)
    $n  = [Math]::Max(10.0, [Math]::Min(24.0, [Math]::Sqrt($dx * $dx + $dy * $dy) / (26 * $SC)))
    $fl.VX = $dx / $n
    $fl.VY = $dy / $n - 0.5 * $WGRAV * $n
    $fl.T  = 0
    [void]$F.flying.Add($fl)
    $F.fly = $null
    if ($c.X -ne [int]$S.x) { $S.dir = [Math]::Sign($c.X - $S.x) }
    $S.state = 'hurl'; $S.timer = 14; $S.phase = 0.0
    $F.throwCool = [int]($RNG.Next(120, 240) * $TUNE.pace)    # runs down four times as fast with the pointer far off
    $F.cool = 16
}

# every frame of a fight: the window in his hands, and every one in the air
function Step-Throw {
    if ($null -eq $F.fly -and $F.flying.Count -eq 0) { return }
    # a mouse button is down: never fight you over a window
    if (Test-MouseHeld) { $F.fly = $null; $F.flying.Clear(); return }
    if ($null -ne $F.fly) { Step-Held }
    foreach ($fl in @($F.flying)) {
        if (-not (Step-Flight $fl)) { $F.flying.Remove($fl) }
    }
}

# the wind-up, before a window flies
function Step-Held {
    $fl = $F.fly
    # knocked out of his hands, or moved under him
    if ($S.state -ne 'heave' -or -not (Test-Hold $fl)) { $F.fly = $null; return }
    $n = $fl.Len - $S.timer + 1             # frames in, as the heave state will count them
    $j = $SC * $(if ($S.tick % 2 -eq 0) { 1 } else { -1 })
    if ($fl.Jump) {
        # it rattles while he hangs off it, then comes down with him
        $x = $fl.HX; $y = $fl.HY
        if ($n -gt $JUMP_RISE + $JUMP_HANG) { $y += $fl.G - (Get-JumpLift $n $fl.G) }
        elseif ($n -gt $JUMP_RISE) { $x += 2 * $j }
    } else {
        # it rattles harder and harder, dragged back toward him
        $t = 1.0 - $S.timer / [double]$fl.Len
        $x = $fl.HX - $S.dir * 10 * $SC * $t * $t + (1.0 + 3.0 * $t) * $j
        $y = $fl.HY - $(if ($fl.Up) { 12 * $SC * $t } else { 4 * $SC * $t })
    }
    if (-not (Move-Held $fl $x $y)) {
        # Windows will not let him move this one: he gives up on it for good
        $F.skip[$fl.H.ToInt64()] = $true
        $F.fly = $null
        $S.state = 'taunt'; $S.timer = 40; $S.phase = 0.0
    }
}

# one frame of a thrown window; $false once it has come to rest
function Step-Flight($fl) {
    if (-not (Test-Hold $fl)) { return $false }
    $fl.T++
    $fl.VY += $WGRAV
    $x = $fl.X + $fl.VX
    $y = $fl.Y + $fl.VY
    # the edges of the screen it is over: it bounces off them, it never leaves
    $mid = New-Object System.Drawing.Point ([int]($x + $fl.FW / 2)), ([int]($y + $fl.FH / 2))
    $a = [System.Windows.Forms.Screen]::FromPoint($mid).WorkingArea
    if ($x -lt $a.Left) { $x = $a.Left; $fl.VX = -$fl.VX * 0.5 }
    elseif ($x + $fl.FW -gt $a.Right) { $x = [Math]::Max($a.Left, $a.Right - $fl.FW); $fl.VX = -$fl.VX * 0.5 }
    if ($y -lt $a.Top) { $y = $a.Top; $fl.VY = [Math]::Abs($fl.VY) * 0.3 }
    $rest = $false
    if ($y + $fl.FH -gt $a.Bottom) {
        $y = [Math]::Max($a.Top, $a.Bottom - $fl.FH)
        $fl.VY = if ($fl.VY -gt 4 * $SC) { -$fl.VY * 0.35 } else { 0.0 }
        $fl.VX *= 0.75
        $rest = $fl.VY -eq 0.0 -and [Math]::Abs($fl.VX) -lt 0.8 * $SC
    }
    if (-not (Move-Held $fl $x $y)) { return $false }

    # it caught the pointer: a spark, and the pointer is knocked the way it flew
    if (-not $fl.Hit) {
        $c = [System.Windows.Forms.Cursor]::Position
        if ($c.X -ge $x -and $c.X -le $x + $fl.FW -and $c.Y -ge $y -and $c.Y -le $y + $fl.FH) {
            $fl.Hit = $true
            $sp = [Math]::Max(1.0, [Math]::Sqrt($fl.VX * $fl.VX + $fl.VY * $fl.VY))
            Land-Blow ($fl.VX / $sp * 18 * $SC) ($fl.VY / $sp * 18 * $SC) 2
            $fl.VX *= 0.5
        }
    }
    return -not ($rest -or $fl.T -gt 90)
}

# ------------------------------------------------------------------ prop windows
# When none of your windows is one he can throw - they are all maximised, say -
# he makes his own: a little Flash panel pops up in his hands and is thrown
# like any other window. They are his, not yours, so once one has landed it
# hangs about a moment and vanishes, and any left go when the fight ends.
$PROPS       = New-Object System.Collections.ArrayList
$PROP_LINGER = 60               # frames one stays about after it lands
$PROP_KINDS  = @(
    @{ Title = 'Library';         Rows = @('Symbol 1', 'Stick figure', 'Tween 1', 'Sound 1') },
    @{ Title = 'Properties';      Rows = @('Movie Clip', 'W: 44    H: 68', 'X: 400   Y: 200', 'Instance of: Symbol 1') },
    @{ Title = 'Timeline';        Rows = @('Layer 1', 'Layer 2', 'Guide: Layer 1', 'Actions') },
    @{ Title = 'Actions - Frame'; Rows = @('stop();', 'this.fight();', 'gotoAndPlay("attack");', 'trace("run");') },
    @{ Title = 'Color Mixer';     Rows = @('#000000', '#FFFFFF', '#0099FF', '#FF0000') },
    @{ Title = 'Tools';           Rows = @('Selection', 'Pencil', 'Brush', 'Eraser') }
)

# a Flash panel of rows, drawn once into a bitmap for the window's background
function New-PropImage($kind, $w, $h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(255, 238, 238, 238))
    $font = New-Object System.Drawing.Font 'Segoe UI', ([single](12 * $SC)), ([System.Drawing.GraphicsUnit]::Pixel)
    $rowH = [int](22 * $SC)
    $pad  = [int](6 * $SC)
    $icon = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 153, 255))
    $alt  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 250, 250, 250))
    for ($i = 0; $i -lt $kind.Rows.Count; $i++) {
        $y = $pad + $i * $rowH
        if ($i % 2 -eq 0) { $g.FillRectangle($alt, $pad, $y, $w - 2 * $pad, $rowH) }
        $g.FillRectangle($icon, $pad * 2, $y + [int]($rowH * 0.3), [int]($rowH * 0.4), [int]($rowH * 0.4))
        $g.DrawString($kind.Rows[$i], $font, [System.Drawing.Brushes]::Black, [single]($pad * 3 + $rowH * 0.4), [single]($y + $rowH * 0.12))
    }
    $font.Dispose(); $icon.Dispose(); $alt.Dispose(); $g.Dispose()
    return $bmp
}

# nothing of yours to throw: a panel appears right in front of him, on the
# side the pointer is on, with a spark, and he takes hold of it
function Conjure-Prop {
    if ($PROPS.Count -ge $TUNE.flying) { return $false }
    $c = [System.Windows.Forms.Cursor]::Position
    $w = [int](220 * $SC); $h = [int](140 * $SC)
    $a = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point ([int]$S.x), ([int]($S.y - 30 * $SC)))).WorkingArea
    $dir = if ($c.X -ge $S.x) { 1 } else { -1 }
    $x = if ($dir -gt 0) { $S.x + 14 * $SC } else { $S.x - 14 * $SC - $w }
    if ($x -lt $a.Left -or $x + $w -gt $a.Right) {
        $dir = -$dir                                    # no room that side: the other
        $x = if ($dir -gt 0) { $S.x + 14 * $SC } else { $S.x - 14 * $SC - $w }
    }
    $x = [Math]::Max($a.Left, [Math]::Min($a.Right - $w, $x))
    $y = [Math]::Max($a.Top,  [Math]::Min($a.Bottom - $h, $S.y - 34 * $SC - $h / 2))

    $kind = $PROP_KINDS[$RNG.Next(0, $PROP_KINDS.Count)]
    $panel = New-Object PropWindow
    $panel.FormBorderStyle = 'FixedToolWindow'
    $panel.StartPosition   = 'Manual'
    $panel.ShowInTaskbar   = $false
    $panel.Text            = $kind.Title
    $panel.Location        = New-Object System.Drawing.Point ([int]$x), ([int]$y)
    $panel.Size            = New-Object System.Drawing.Size $w, $h
    $panel.BackgroundImage = New-PropImage $kind $panel.ClientSize.Width $panel.ClientSize.Height
    $panel.Show()
    $prop = @{ Form = $panel; H = $panel.Handle; Life = $PROP_LINGER }
    [void]$PROPS.Add($prop)

    $r = [SM]::Rect($prop.H)
    if ($null -eq $r) { Remove-Prop $prop; return $false }
    Pop-Spark (($r[0] + $r[2]) / 2) (($r[1] + $r[3]) / 2)
    $t = @{
        L = (New-Ledge $prop.H $r[0] $r[1] $r[2] $r[3] $false $false $false)
        X = $S.x; Dir = $dir; Up = $false; Jump = $false
    }
    if (-not (Start-Heave $t)) { Remove-Prop $prop; return $false }
    return $true
}

function Remove-Prop($prop) {
    [void]$THROWN.Remove($prop.H.ToInt64())             # nothing to put back
    try { $prop.Form.Close(); $prop.Form.BackgroundImage.Dispose(); $prop.Form.Dispose() } catch { }
    $PROPS.Remove($prop)
}

# every frame: a prop in his hands or in the air stays; one that has landed
# counts down and goes. Closed by you with its X, it is simply forgotten.
function Step-Props {
    foreach ($prop in @($PROPS)) {
        if (-not [SM]::IsWindow($prop.H)) { Remove-Prop $prop; continue }
        $busy = $F.on -and (($null -ne $F.fly -and $F.fly.H -eq $prop.H) -or (Test-Flying $prop.H))
        if ($busy) { $prop.Life = $PROP_LINGER; continue }
        if (--$prop.Life -le 0) { Remove-Prop $prop }
    }
}

# ----------------------------------------------------------- grabbing the pointer
# In reach, now and then he grabs your pointer instead of hitting it, runs off
# dragging it behind him, and throws it. Wiggle or yank the mouse hard enough
# and it comes free; click him (the click lands on him, see the grip window),
# or press Esc, and he lets go. He never takes it, or moves it, while a mouse
# button is down, and he never clicks anything.

function Start-Grab {
    $c = [System.Windows.Forms.Cursor]::Position
    $F.grab = $true; $F.struggle = 0.0; $F.kn = 0
    $F.sx = $c.X; $F.sy = $c.Y; $F.gx = $c.X; $F.gy = $c.Y
    # he runs off with it whichever way there is more room
    $l = $S.ledge
    $F.run = if ($null -ne $l -and ($l.R - $S.x) -lt ($S.x - $l.L)) { -1 } else { 1 }
    $S.state = 'haul'; $S.timer = $GRAB_HOLD; $S.phase = 0.0
}

function Release-Pointer {
    if (-not $F.grab) { return }
    $F.grab = $false; $F.struggle = 0.0
    $F.grabCool = [int]($RNG.Next(150, 270) * $TUNE.pace)
    Hide-Grip
}

# where his holding hand is, in design units: reaching out for your pointer,
# trailing it behind him as he runs, then swinging it up over his head and
# out in front to throw it. The arm is 15 long, from his shoulder.
function Get-GrabHand {
    if ($S.state -eq 'fling') {
        $e  = [Math]::Min(1.0, ($FLING_LEN - $S.timer) / [double]($FLING_LEN - $FLING_AT))
        $th = 200.0 - 170.0 * $e
    } elseif ($GRAB_HOLD - $S.timer -lt $GRAB_SNATCH) {
        $th = 10.0
    } else {
        $th = 200.0
    }
    $th *= [Math]::PI / 180.0
    , @((22.0 + $S.dir * (1.0 + 15.0 * [Math]::Cos($th))), (27.0 - 15.0 * [Math]::Sin($th)))
}

# every frame he has it: it stays in his hand, unless you pull it free
function Step-Grab {
    if (-not $F.on -or $S.drag -or $S.state -notin @('haul', 'fling')) { Release-Pointer; return }
    if (Test-MouseHeld) { Release-Pointer; return }       # a button is down: hands off
    # anything it moved since he last put it was you, pulling against him
    $c  = [System.Windows.Forms.Cursor]::Position
    $ux = $c.X - $F.gx; $uy = $c.Y - $F.gy
    $F.struggle = $F.struggle * 0.85 + [Math]::Sqrt($ux * $ux + $uy * $uy)
    if ($F.struggle -gt $TUNE.struggle * $SC) {
        # you yanked it out of his hand, and he stumbles
        Release-Pointer
        $S.state = 'fall'; $F.air = 'hurt'; $S.wall = $null
        $S.vy = -5.0 * $SC; $S.vx = -$S.dir * 3.0 * $SC
        return
    }
    $h = Get-GrabHand
    $x = $S.x + ($h[0] - $DCX) * $SC
    $y = $S.y + ($h[1] - $DFT) * $SC
    $k = ($GRAB_HOLD - $S.timer) / [double]$GRAB_SNATCH
    if ($S.state -eq 'haul' -and $k -lt 1.0) {
        # still snatching it: it is pulled from where it was into his hand
        $x = $F.sx + ($x - $F.sx) * $k; $y = $F.sy + ($y - $F.sy) * $k
    }
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $nx = [Math]::Max($vs.Left, [Math]::Min($vs.Right - 1, [int][Math]::Round($x)))
    $ny = [Math]::Max($vs.Top,  [Math]::Min($vs.Bottom - 1, [int][Math]::Round($y)))
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $nx, $ny
    $c = [System.Windows.Forms.Cursor]::Position        # where it really went
    $F.gx = $c.X; $F.gy = $c.Y
    Show-Grip $c.X $c.Y
}

# the end of the throw: he lets go and your pointer sails off the way it went
function Fling-Pointer {
    Release-Pointer
    if (Test-MouseHeld) { return }
    if (Hurt-Pointer 2 ($S.dir * 44 * $SC) (-22 * $SC)) { return }     # it breaks as it leaves his hand
    $F.kx = $S.dir * 44 * $SC; $F.ky = -22 * $SC; $F.kn = 12; $F.kd = 0.8
}

# After a fight every window he threw glides back where it was. One you have
# moved yourself since is left where you put it, and nothing moves while a
# mouse button is down.
function Step-Tidy {
    if (Test-MouseHeld) { return }
    foreach ($k in @($THROWN.Keys)) {
        $w = $THROWN[$k]
        $r = [SM]::Rect($w.H)
        if ($null -eq $r -or [Math]::Abs($r[0] - $w.LX) -gt 3 -or [Math]::Abs($r[1] - $w.LY) -gt 3) { $THROWN.Remove($k); continue }
        $dx = $w.X0 - $r[0]; $dy = $w.Y0 - $r[1]
        if ([Math]::Abs($dx) -le 2 -and [Math]::Abs($dy) -le 2) {
            [void][SM]::Place($w.H, $w.X0, $w.Y0)
            $THROWN.Remove($k); continue
        }
        $nx = $r[0] + [int][Math]::Round($dx * 0.25) + [Math]::Sign($dx)
        $ny = $r[1] + [int][Math]::Round($dy * 0.25) + [Math]::Sign($dy)
        if (-not [SM]::Place($w.H, $nx, $ny)) { $THROWN.Remove($k); continue }
        $w.LX = $nx; $w.LY = $ny
    }
}

# he is going away: everything he threw goes straight back
function Put-WindowsBack {
    foreach ($w in @($THROWN.Values)) {
        $r = [SM]::Rect($w.H)
        if ($null -ne $r -and [Math]::Abs($r[0] - $w.LX) -le 3 -and [Math]::Abs($r[1] - $w.LY) -le 3) {
            [void][SM]::Place($w.H, $w.X0, $w.Y0)
        }
    }
    $THROWN.Clear()
}

# you clicked him: he is thrown back, still facing you. On his feet and
# facing you, he often sees it coming, blocks it, and hits straight back.
function Hit-Him($c) {
    if ($F.inv -gt 0 -or $S.state -eq 'ko') { return }
    Pop-Spark $c.X $c.Y
    $facing = $c.X -eq [int]$S.x -or [Math]::Sign($c.X - $S.x) -eq $S.dir
    if ($facing -and $S.state -in @('guard', 'taunt', 'hunt', 'punch', 'kick') -and $RNG.Next(0, 100) -lt $TUNE.block) {
        $F.inv = 8; $F.cool = 0
        $S.state = 'guard'; $S.phase = 0.0
        return
    }
    $F.hp--; $F.inv = $TUNE.inv; $F.hurt = 12
    if ($F.hp -le 0) { $F.ko = $true }
    $away = if ($c.X -gt $S.x) { -1 } else { 1 }
    $S.dir   = -$away
    $S.state = 'fall'; $F.air = 'hurt'
    $S.vy    = -7.0 * $SC
    $S.vx    = $away * 5.0 * $SC
    $S.wall  = $null
}

function Jump-Kick($dx, $dy) {
    # rise just far enough for his foot to meet the pointer at the top
    $h = [Math]::Min(240 * $SC, [Math]::Max(40 * $SC, -$dy - 6 * $SC))
    $S.vy = -[Math]::Sqrt(2 * $GRAVITY * $h)
    $S.vx = [Math]::Max(-9 * $SC, [Math]::Min(9 * $SC, $dx / (-$S.vy / $GRAVITY)))
    if ($dx -ne 0) { $S.dir = [Math]::Sign($dx) }
    $S.state = 'fall'; $F.air = 'flykick'; $F.hitDone = $false; $S.phase = 0.0
    $F.cool = 10
}

# every frame of a fight, before his state moves him
function Step-FightFrame {
    if ($F.inv -gt 0)   { $F.inv-- }
    if ($F.hurt -gt 0)  { $F.hurt-- }
    if ($F.cool -gt 0)  { $F.cool-- }
    if ($F.dodge -gt 0) { $F.dodge-- }
    Step-Throw

    # the pointer sliding away from a blow, a little less each frame
    if ($F.kn -gt 0) {
        $F.kn--
        if ((Test-MouseHeld) -or $PTR.dead) { $F.kn = 0 }
        else {
            $c  = [System.Windows.Forms.Cursor]::Position
            $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $nx = [Math]::Max($vs.Left, [Math]::Min($vs.Right - 1, [int]($c.X + $F.kx)))
            $ny = [Math]::Max($vs.Top,  [Math]::Min($vs.Bottom - 1, [int]($c.Y + $F.ky)))
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $nx, $ny
            $F.kx *= $F.kd; $F.ky *= $F.kd
        }
    }

    $c = [System.Windows.Forms.Cursor]::Position
    $swipe = [Math]::Sqrt(($c.X - $F.px) * ($c.X - $F.px) + ($c.Y - $F.py) * ($c.Y - $F.py))
    $F.px = $c.X; $F.py = $c.Y

    # the pointer a long way off: out come the windows, one after another
    $fdx = $c.X - $S.x; $fdy = $c.Y - ($S.y - 34 * $SC)
    $F.far = ($fdx * $fdx + $fdy * $fdy) -gt $FAR_OFF * $FAR_OFF -or $fdy -le -250 * $SC
    if ($F.throwCool -gt 0) { $F.throwCool -= $(if ($F.far) { 4 } else { 1 }) }
    if ($F.grabCool -gt 0) { $F.grabCool-- }

    # a flying kick: does his foot find the pointer on the way up?
    if ($S.state -eq 'fall' -and $F.air -eq 'flykick' -and -not $F.hitDone) {
        $fx = $S.x + $S.dir * 19 * $SC - $c.X
        $fy = $S.y - 28 * $SC - $c.Y
        $rr = 26 * $SC * $TUNE.reach
        if ($fx * $fx + $fy * $fy -lt $rr * $rr) {
            $F.hitDone = $true
            Land-Blow ($S.dir * 14 * $SC) (-5 * $SC) $TUNE.kick
        }
    }

    # anything he was doing on his own gives way to the fight
    if ($S.state -in @('walk', 'idle', 'sit', 'wave', 'cheer', 'chase', 'knock', 'push', 'press', 'meet', 'social')) {
        $S.wall = $null; $S.phase = 0.0
        if ($F.ko)        { $S.state = 'ko'; $S.timer = 160 }
        elseif ($F.intro) { $F.intro = $false; $S.state = 'taunt'; $S.timer = 50 }
        else              { $S.state = 'guard' }
    }

    # the pointer lies in pieces: he celebrates, and when it starts pulling
    # itself back together he jumps
    if ($PTR.dead) {
        if ($PTR.mend -and $S.state -in @('guard', 'hunt', 'taunt', 'hurl', 'win')) {
            $S.state = 'shock'; $S.timer = 0; $S.phase = 0.0
        } elseif (-not $PTR.mend -and $S.state -in @('guard', 'hunt', 'taunt', 'hurl')) {
            $S.state = 'win'; $S.timer = 0; $S.phase = 0.0
        }
        if ($S.state -in @('win', 'shock') -and $PTR.x -ne [int]$S.x) { $S.dir = [Math]::Sign($PTR.x - $S.x) }
    }

    # you swiped at him: now and then he hops back out of the way
    if ($S.state -in @('guard', 'hunt', 'taunt') -and $F.dodge -le 0 -and $swipe -gt $TUNE.alert * $SC) {
        $dx = $c.X - $S.x; $dy = $c.Y - ($S.y - 34 * $SC)
        $rr = 100 * $SC * $TUNE.reach
        if ($dx * $dx + $dy * $dy -lt $rr * $rr) {
            $F.dodge = [int](40 * $TUNE.pace)
            if ($RNG.Next(0, 100) -lt $TUNE.dodge) {
                if ($dx -ne 0) { $S.dir = [Math]::Sign($dx) }
                $S.state = 'fall'; $F.air = 'flip'
                $S.vy = -7.5 * $SC
                $S.vx = -$S.dir * 4.5 * $SC
            }
        }
    }
}

# squared up to the pointer: attack it in reach, go after it out of reach
function Step-Guard {
    $l = $S.ledge
    if ($null -eq $l) { $S.state = 'fall'; return }
    $c  = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - $S.x
    $dy = $c.Y - ($S.y - 34 * $SC)          # from his chest
    $ax = [Math]::Abs($dx)
    if ($ax -gt 2 * $SC) { $S.dir = [Math]::Sign($dx) }

    if ($S.state -eq 'taunt') {
        $S.phase += 0.25
        if (--$S.timer -gt 0) { return }
        $S.state = 'guard'
    }
    $S.phase += 0.20
    if ($F.cool -gt 0) { return }

    if ($ax -lt 30 * $SC * $TUNE.reach -and $dy -gt -44 * $SC -and $dy -lt 24 * $SC) {
        # in reach: now and then he grabs it and runs off with it
        if ($S.grabPtr -and $F.grabCool -le 0 -and -not (Test-MouseHeld) -and $RNG.Next(0, 2) -eq 0) {
            Start-Grab; return
        }
        # otherwise jab, cross, and a kick for anything low or now and then
        $S.state = if ($dy -gt 10 * $SC -or $RNG.Next(0, 10) -ge 7) { 'kick' } else { 'punch' }
        $S.timer = if ($S.state -eq 'punch') { 14 } else { 20 }
        $S.phase = 0.0
    } elseif ($ax -lt 110 * $SC -and $dy -le -44 * $SC -and $dy -gt -250 * $SC) {
        Jump-Kick $dx $dy                   # above him, but not by much
    } elseif ($F.far -and (Try-Throw $FETCH_FAR -Conjure)) {
        # a long way off, whichever way: a window thrown at it, one of his own if need be
    } elseif ($ax -lt 110 * $SC -and $dy -le -250 * $SC) {
        $S.state = 'taunt'; $S.timer = 60; $S.phase = 0.0   # well out of reach: 'come on, then'
    } elseif ($ax -ge 80 * $SC) {
        $S.state = 'hunt'; $S.phase = 0.0
    } elseif ($ax -ge 30 * $SC) {
        # shuffle in with his fists up, never off the edge
        $v = $SPEED * 0.7 * $TUNE.speed
        if ($l.Ink) { [void](Step-Ink ($S.dir * $v)); return }
        $S.x = [Math]::Max($l.L + $EDGE, [Math]::Min($l.R - $EDGE, $S.x + $S.dir * $v))
    }
}

# a punch or kick: the blow lands, or misses, at full stretch
function Step-Strike {
    $S.phase += 0.2
    $len = if ($S.state -eq 'punch') { 14 } else { 20 }
    $S.timer--
    if ($S.timer -eq [int]($len / 2)) {
        $c  = [System.Windows.Forms.Cursor]::Position
        $hx = $S.x + $S.dir * 19 * $SC - $c.X
        $hy = $S.y - $(if ($S.state -eq 'punch') { 35 } else { 28 }) * $SC - $c.Y
        $rr = 28 * $SC * $TUNE.reach
        if ($hx * $hx + $hy * $hy -lt $rr * $rr) {
            Land-Blow ($S.dir * 14 * $SC) (-5 * $SC) $(if ($S.state -eq 'kick') { $TUNE.kick } else { 1 })
        }
    }
    if ($S.timer -le 0) {
        $F.combo++
        $F.cool  = [int]($RNG.Next(5, 16) * $TUNE.pace)
        $S.phase = 0.0
        if ($F.gloat) { $F.gloat = $false; $S.state = 'taunt'; $S.timer = 45 }
        else          { $S.state = 'guard' }
    }
}

# running at the pointer, climbing or leaping at whatever is in the way
function Step-Hunt {
    $l = $S.ledge
    if ($null -eq $l) { $S.state = 'fall'; return }
    $c  = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - $S.x
    $dy = $c.Y - ($S.y - 34 * $SC)
    $ax = [Math]::Abs($dx)
    if ($ax -lt 60 * $SC -or ($ax -lt 110 * $SC -and $dy -lt -44 * $SC)) {
        $S.state = 'guard'; return          # close enough to fight
    }
    $S.phase += 0.40
    $S.dir = [Math]::Sign($dx)

    # a throw is due: a window right at hand, the one he was about to climb
    # included, or with the pointer far off, any he can get to on this ledge,
    # and failing that one of his own
    if ($S.tick % 4 -eq 0) {
        $threw = if ($F.far) { Try-Throw $FETCH_FAR -Conjure } else { Try-Throw (30 * $SC) }
        if ($threw) { return }
    }

    $wall = Find-Wall
    if ($null -ne $wall) {
        $S.wall  = $wall
        $S.state = 'climb'
        $S.x     = if ($S.dir -gt 0) { $wall.L - $HUG } else { $wall.R + $HUG }
        $S.phase = 0.0
        return
    }
    if ($dy -lt -44 * $SC) {                 # it is up there: jump for a window corner
        $up = Find-Reach
        if ($null -ne $up) {
            $S.wall  = $up
            $S.state = 'leap'
            $S.timer = 18
            $S.ly0   = $S.y
            $S.phase = 0.0
            $S.x     = if ($S.dir -gt 0) { $up.L - $HUG } else { $up.R + $HUG }
            return
        }
    }
    if ($l.Ink) {
        if ((Step-Ink ($S.dir * $SPEED * 2.2 * $TUNE.speed)) -eq 'wall') { $S.state = 'taunt'; $S.timer = 40 }
        return
    }

    $S.x += $S.dir * $SPEED * 2.2 * $TUNE.speed
    # he jumps off an edge to get at it; the floor's edge stops him
    if ($S.x -lt $l.L + $EDGE) {
        if ($l.Ground) { $S.x = $l.L + $EDGE; $S.state = 'taunt'; $S.timer = 40 }
        else { $S.state = 'fall'; $S.vx = -2.4 * $SC; $S.vy = -3.0 * $SC }
    } elseif ($S.x -gt $l.R - $EDGE) {
        if ($l.Ground) { $S.x = $l.R - $EDGE; $S.state = 'taunt'; $S.timer = 40 }
        else { $S.state = 'fall'; $S.vx = 2.4 * $SC; $S.vy = -3.0 * $SC }
    }
}

function Step-Physics {
    $S.tick++
    if ($S.tick % 5 -eq 0) { Update-World }
    if ($PROPS.Count -gt 0) { Step-Props }
    if (-not $F.on -and $THROWN.Count -gt 0) { Step-Tidy }
    if ($S.cool -gt 0) { $S.cool-- }
    if ($S.chase -gt 0) { $S.chase-- }

    # Esc ends a fight, whichever window has the keyboard
    if ($F.on -and [SM]::GetAsyncKeyState(0x1B) -lt 0) { End-Fight }

    # you clicked somewhere: he drops what he is doing and runs over to look
    $down = [SM]::GetAsyncKeyState(1) -lt 0
    if ($down -and -not $S.mdown) {
        $S.mdown = $true
        $c = [System.Windows.Forms.Cursor]::Position
        $onHim = ($c.X -ge $S.x - $CX -and $c.X -le $S.x - $CX + $BOXW -and
                  $c.Y -ge $S.y - $FOOT -and $c.Y -le $S.y - $FOOT + $BOXH)
        if ($F.on) {
            # in a fight, a click on him is a hit, and a click anywhere else is
            # ignored; with the pointer in pieces a click is not aimed at anything
            if ($onHim -and -not $PTR.dead) { Hit-Him $c }
        } elseif (-not $onHim -and -not $S.drag -and $S.state -ne 'climb') {
            $S.tx    = [double]$c.X
            $S.ty    = [double]$c.Y
            $S.chase = 300
            $S.state = 'chase'
            $S.phase = 0.0
            $S.chasePeer = -1
            if ($c.X -ne $S.x) { $S.dir = [Math]::Sign($c.X - $S.x) }
        }
    } elseif (-not $down) {
        $S.mdown = $false
    }

    if ($S.drag) {
        $c = [System.Windows.Forms.Cursor]::Position
        $S.lastX = $S.x
        $S.x = $c.X - $S.grabX + $CX
        $S.y = $c.Y - $S.grabY + $FOOT
        $S.dragged += [Math]::Abs($S.x - $S.lastX)
        $S.phase += 0.2
        return
    }

    if ($F.on) { Step-FightFrame } else { Step-Friends }

    # A figure's move waits here until he is settled enough to perform it. The
    # dialog he was named in is a window like any other, so he is often standing
    # on it when you press OK; it shuts, the ledge under him goes, and anything
    # set at that moment would be thrown away by the fall. This survives that.
    if ($S.pending -ne '') {
        if (--$S.pendTTL -le 0) {
            $S.pending = ''
        } elseif (-not $S.drag -and $null -ne $S.ledge -and
                  $S.state -notin @('climb', 'leap', 'fall', 'knock', 'push')) {
            $act = $S.pending
            $S.pending = ''
            Do-EggAct $act
        }
    }

    switch ($S.state) {

        'hunt'  { Step-Hunt }
        'guard' { Step-Guard }
        'taunt' { Step-Guard }
        'punch' { Step-Strike }
        'kick'  { Step-Strike }
        'fetch' {
            # on his way over to a window he means to throw
            $t = $F.fetch
            $l = $S.ledge
            if ($null -eq $t -or $null -eq $l -or --$S.timer -le 0) { $F.fetch = $null; $S.state = 'guard'; return }
            # still there, just as it was?
            $w = $null
            foreach ($o in $S.ledges) { if ($o.H -eq $t.L.H) { $w = $o; break } }
            if ($null -eq $w -or [Math]::Abs($w.L - $t.L.L) -gt 2 -or [Math]::Abs($w.T - $t.L.T) -gt 2) {
                $F.fetch = $null; $S.state = 'guard'; return
            }
            $gap = $t.X - $S.x
            if ([Math]::Abs($gap) -le 4 * $SC) {
                $S.x = $t.X; $t.L = $w
                $F.fetch = $null
                if (-not (Start-Heave $t)) { $S.state = 'guard' }
                return
            }
            $S.phase += 0.40
            $S.dir = [Math]::Sign($gap)
            $S.x += $S.dir * [Math]::Min([Math]::Abs($gap), $SPEED * 2.4)
        }
        'heave' {
            # wrenching it loose, see Step-Held; then it flies
            $S.phase += 0.5
            $fl = $F.fly
            if ($null -eq $fl -or $null -eq $S.ledge) { $F.fly = $null; $S.state = 'guard'; return }
            # one out of reach: he jumps up to its bottom edge and drops back down with it
            if ($fl.Jump) { $S.y = $S.ledge.T - (Get-JumpLift ($fl.Len - $S.timer + 1) $fl.G) }
            if (--$S.timer -le 0) { Launch-Window }
        }
        'hurl' {
            $S.phase += 0.2
            if (--$S.timer -le 0) { $S.state = 'guard'; $S.phase = 0.0 }
        }
        'haul' {
            # off he goes with your pointer, see Step-Grab, turning at the ends
            $S.phase += 0.42
            $l = $S.ledge
            if ($null -eq $l) { $S.state = 'fall'; $S.vy = 0.0 }
            elseif ($GRAB_HOLD - $S.timer -ge $GRAB_SNATCH) {
                $S.dir = $F.run
                if ($l.Ink) {
                    if ((Step-Ink ($S.dir * $SPEED * 1.8)) -eq 'wall') { $F.run = -$F.run }
                } else {
                    $S.x += $S.dir * $SPEED * 1.8
                    if ($S.x -lt $l.L + $EDGE)     { $S.x = $l.L + $EDGE; $F.run = 1 }
                    elseif ($S.x -gt $l.R - $EDGE) { $S.x = $l.R - $EDGE; $F.run = -1 }
                }
            }
            if ($S.state -eq 'haul' -and --$S.timer -le 0) { $S.state = 'fling'; $S.timer = $FLING_LEN; $S.phase = 0.0 }
        }
        'fling' {
            $S.phase += 0.2
            if ($S.timer -eq $FLING_AT) { Fling-Pointer }
            if (--$S.timer -le 0) { $S.state = 'guard'; $S.phase = 0.0 }
        }
        'ko' {
            $S.phase += 0.15
            if (--$S.timer -le 0) {
                if ($TUNE.second -and -not $F.second) {
                    # hard mode: the first time, he gets back up with half his hits
                    $F.second = $true; $F.ko = $false
                    $F.hp = [int][Math]::Ceiling($F.max / 2.0)
                    $F.cool = 0
                    $S.state = 'taunt'; $S.timer = 50; $S.phase = 0.0
                } else {
                    End-Fight                       # he has had enough, and says so
                    $S.state = 'wave'; $S.timer = 70; $S.phase = 0.0
                }
            }
        }
        'win' {
            # he broke your pointer: punching the air, then jumping for joy
            $S.phase += 0.30
            $S.timer++
            if (-not $PTR.dead) { $S.state = 'guard'; $S.phase = 0.0 }
        }
        'shock' {
            # ...and it is putting itself back together
            $S.phase += 0.30
            $S.timer++
            if (-not $PTR.dead) { $S.state = 'taunt'; $S.timer = 50; $S.phase = 0.0 }
        }

        'walk' {
            $S.phase += 0.26
            $l = $S.ledge
            if ($null -eq $l) { $S.state = 'fall'; return }

            # something is in front of him
            $wall = Find-Wall
            if ($null -ne $wall) {
                if ($wall.Btn -or $wall.Icon) {        # a button or a shortcut is just a step up
                    $S.wall  = $wall
                    $S.state = 'climb'
                    $S.x     = if ($S.dir -gt 0) { $wall.L - $HUG } else { $wall.R + $HUG }
                    $S.phase = 0.0
                    return
                }
                $roll = $RNG.Next(0, 100)
                if ($roll -lt 80) {
                    $S.wall  = $wall
                    $S.state = 'climb'
                    $S.x     = if ($S.dir -gt 0) { $wall.L - $HUG } else { $wall.R + $HUG }
                    $S.phase = 0.0
                } elseif ($roll -lt 90) {
                    $S.wall = $wall; $S.state = 'knock'; $S.timer = 54; $S.phase = 0.0
                } elseif ($roll -lt 98 -and $S.shove -and -not $wall.Max) {
                    $S.wall = $wall; $S.state = 'push'; $S.timer = 60; $S.phase = 0.0
                } else {
                    $S.dir = -$S.dir
                }
                return
            }

            # the pointer came near
            $cd = Cursor-Distance
            if ($S.cool -le 0 -and $cd.D -lt $NOTICE) {
                if ($cd.X -ne $S.x) { $S.dir = [Math]::Sign($cd.X - $S.x) }
                $S.state = 'wave'; $S.timer = 60; $S.cool = 200; $S.phase = 0.0
                return
            }

            # a window hanging overhead: jump for the corner
            $up = Find-Reach
            if ($null -ne $up -and $RNG.Next(0, 100) -lt 75) {
                $S.wall  = $up
                $S.state = 'leap'
                $S.timer = 18
                $S.ly0   = $S.y
                $S.phase = 0.0
                $S.x     = if ($S.dir -gt 0) { $up.L - $HUG } else { $up.R + $HUG }
                return
            }

            # nothing to stand on down here: go and find a window to get onto
            if ($l.Ground -and $S.tick % 40 -eq 0) {
                $e = Find-Climb
                if ($null -ne $e) { $S.dir = [Math]::Sign($e - $S.x) }
            }

            # drop off the title bar down onto the buttons inside the window
            if (-not $l.Ground -and -not $l.Btn -and $RNG.Next(0, 45) -eq 0) {
                if ($null -ne (Find-DropTarget $l)) {
                    $S.ignore = $l.H
                    $S.state  = 'fall'
                    $S.vy     = 0.0
                    $S.vx     = 0.0
                    return
                }
            }

            # standing on top of Paint with ink on the canvas below: hop down in
            if (-not $l.Ink -and $l.H -eq [Ink]::Target -and [Ink]::Ready -and $RNG.Next(0, 90) -eq 0 -and
                [Ink]::Floor([int]$S.x, [int]($l.T + 30 * $SC), [int]$l.B) -ge 0) {
                $S.ignore = $l.H
                $S.state  = 'fall'
                $S.vy     = 0.0
                $S.vx     = 0.0
                return
            }

            if ($l.Ink) {
                # a stroke taller than a step is a wall: turn round
                if ((Step-Ink ($S.dir * $SPEED)) -eq 'wall') { $S.dir = -$S.dir }
                if ($S.state -eq 'walk' -and $RNG.Next(0, 260) -eq 0) { $S.state = 'idle'; $S.timer = 40 }
                return
            }

            $S.x += $S.dir * $SPEED

            # at the end of a ledge he almost always stays on it, and now and
            # then sits down on the edge instead of turning round
            if ($S.x -lt $l.L + $EDGE) {
                if ($l.Ground -or $RNG.Next(0, 100) -lt 96) {
                    $S.x = $l.L + $EDGE
                    if (-not $l.Ground -and -not $l.Btn -and $RNG.Next(0, 4) -eq 0) {
                        $S.state = 'sit'; $S.timer = $RNG.Next(90, 260); $S.phase = 0.0
                    } else { $S.dir = 1 }
                } else {
                    $S.state = 'fall'; $S.vx = -1.2 * $SC; $S.vy = 0.0
                }
            } elseif ($S.x -gt $l.R - $EDGE) {
                if ($l.Ground -or $RNG.Next(0, 100) -lt 96) {
                    $S.x = $l.R - $EDGE
                    if (-not $l.Ground -and -not $l.Btn -and $RNG.Next(0, 4) -eq 0) {
                        $S.state = 'sit'; $S.timer = $RNG.Next(90, 260); $S.phase = 0.0
                    } else { $S.dir = -1 }
                } else {
                    $S.state = 'fall'; $S.vx = 1.2 * $SC; $S.vy = 0.0
                }
            }

            if ($RNG.Next(0, 260) -eq 0) { $S.state = 'idle'; $S.timer = 40 }
        }

        'chase' {
            $S.phase += 0.36
            $l = $S.ledge
            if ($null -eq $l) { $S.state = 'fall'; return }

            # playing tag: the target is a friend, and they keep moving
            if ($S.chasePeer -ge 0) {
                $p = Get-Peer $S.chasePeer
                if ($null -eq $p) { $S.chasePeer = -1 } else { $S.tx = [double]$p.X; $S.ty = [double]$p.Y }
            }

            $gap = $S.tx - $S.x
            if ([Math]::Abs($gap) -gt 4 * $SC) { $S.dir = [Math]::Sign($gap) }

            # got there: a hop and a cheer
            if ([Math]::Abs($gap) -lt 16 * $SC -and [Math]::Abs($S.ty - $S.y) -lt 90 * $SC) {
                $S.state = 'cheer'; $S.timer = 60; $S.phase = 0.0; $S.cool = 120; $S.chasePeer = -1
                return
            }
            if ($S.chase -le 0) { $S.state = 'walk'; $S.chasePeer = -1; return }

            # anything in the way gets climbed, no dithering about it
            $wall = Find-Wall
            if ($null -ne $wall) {
                $S.wall  = $wall
                $S.state = 'climb'
                $S.x     = if ($S.dir -gt 0) { $wall.L - $HUG } else { $wall.R + $HUG }
                $S.phase = 0.0
                return
            }

            $up = Find-Reach
            if ($null -ne $up) {
                $S.wall  = $up
                $S.state = 'leap'
                $S.timer = 18
                $S.ly0   = $S.y
                $S.phase = 0.0
                $S.x     = if ($S.dir -gt 0) { $up.L - $HUG } else { $up.R + $HUG }
                return
            }

            if ($l.Ink) {
                # a stroke taller than a step is in the way: he gives up
                if ((Step-Ink ($S.dir * $SPEED * 1.9)) -eq 'wall') {
                    $S.state = 'walk'; $S.chase = 0; $S.chasePeer = -1; $S.dir = -$S.dir
                }
                return
            }

            $S.x += $S.dir * $SPEED * 1.9

            # he will run off an edge to get to you
            if ($S.x -lt $l.L + $EDGE) {
                if ($l.Ground) { $S.x = $l.L + $EDGE; $S.dir = 1 }
                else { $S.state = 'fall'; $S.vx = -1.6 * $SC; $S.vy = 0.0 }
            } elseif ($S.x -gt $l.R - $EDGE) {
                if ($l.Ground) { $S.x = $l.R - $EDGE; $S.dir = -1 }
                else { $S.state = 'fall'; $S.vx = 1.6 * $SC; $S.vy = 0.0 }
            }
        }

        'cheer' {
            $S.phase += 0.30
            if (--$S.timer -le 0) { $S.state = 'walk' }
        }

        'meet' {
            $l = $S.ledge
            $p = Get-Peer $S.with
            if ($null -eq $l -or $null -eq $p -or [Math]::Abs($p.Y - $S.y) -gt 8 * $SC -or ++$S.meetT -gt 240) {
                Stop-Meeting; return
            }
            $answered = $p.With -eq $ME
            if (-not $answered -and $S.meetT -gt 30) { Stop-Meeting; return }   # busy with someone else
            # if both asked at once, the lower slot's idea wins
            if ($answered -and $p.Slot -lt $ME -and $p.Act -gt 0) { $S.act = $ACTS[$p.Act] }

            $gap = $p.X - $S.x
            if ([Math]::Abs($gap) -gt 1) { $S.dir = [Math]::Sign($gap) }
            if ([Math]::Abs($gap) -gt $ACT_GAP[$S.act] * $SC) {
                if ($null -ne (Find-Wall)) { Stop-Meeting; return }   # a window in the way
                $S.waiting = $false
                $S.phase  += 0.26
                if ($l.Ink) {
                    $r = Step-Ink ($S.dir * $SPEED)
                    if ($r -eq 'wall') { $S.waiting = $true }
                    elseif ($r -eq 'fall') { Stop-Meeting; $S.state = 'fall' }
                    return
                }
                $S.x      += $S.dir * $SPEED
                if ($S.x -lt $l.L + $EDGE) { $S.x = $l.L + $EDGE; $S.waiting = $true }
                if ($S.x -gt $l.R - $EDGE) { $S.x = $l.R - $EDGE; $S.waiting = $true }
            } else {
                $S.waiting = $true
                $S.phase  += 0.12
                if ($answered -and ($p.State -eq $STATE_CODE.meet -or $p.State -eq $STATE_CODE.social)) {
                    $S.state = 'social'; $S.timer = $ACT_TIME[$S.act]; $S.phase = 0.0
                }
            }
        }

        'social' {
            $p = Get-Peer $S.with
            # they quit, or finished and wandered off a moment before him
            if ($null -eq $p -or ($p.With -ne $ME -and $S.timer -gt 10)) { Stop-Meeting; return }
            if ($p.X -ne [int]$S.x) { $S.dir = [Math]::Sign($p.X - $S.x) }
            $S.phase += if ($S.act -eq 'chat') { 0.14 } elseif ($S.act -eq 'greet') { 0.34 } else { 0.30 }
            if (--$S.timer -le 0) {
                $act = $S.act; $who = $S.with
                Stop-Meeting
                if ($act -eq 'tag') {
                    # the lower slot is 'it' and runs for it, the other gives chase
                    if ($ME -lt $who) {
                        $S.tx = $S.x - $S.dir * 600 * $SC; $S.ty = $S.y; $S.chase = 150
                    } else {
                        $S.chasePeer = $who; $S.tx = [double]$p.X; $S.ty = [double]$p.Y; $S.chase = 260
                    }
                    $S.dir = [Math]::Sign($S.tx - $S.x)
                    $S.state = 'chase'; $S.phase = 0.0
                } else {
                    $S.dir = -$S.dir       # and off they go their separate ways
                }
            }
        }

        'leap' {
            $S.phase += 0.30
            $w = $S.wall
            if ($null -eq $w) { $S.state = 'fall'; $S.vy = 0.0; return }
            $S.timer--
            $t = 1.0 - ($S.timer / 18.0)
            $S.y = $S.ly0 + ($w.B - $S.ly0) * [Math]::Pow($t, 0.55)   # fast off the mark, easing into the grab
            $S.x = if ($S.dir -gt 0) { $w.L - $HUG } else { $w.R + $HUG }
            if ($S.timer -le 0) { $S.y = $w.B; $S.state = 'climb'; $S.phase = 0.0 }
        }

        'idle' {
            $S.phase += 0.12
            if (--$S.timer -le 0) {
                $S.state = 'walk'
                if ($RNG.Next(0, 2) -eq 0) { $S.dir = -$S.dir }
            }
        }

        'sit' {
            $S.phase += 0.14
            # he looks at the pointer while he sits
            $cd = Cursor-Distance
            if ($cd.D -lt $NOTICE -and $cd.X -ne $S.x) { $S.dir = [Math]::Sign($cd.X - $S.x) }
            if (--$S.timer -le 0) { $S.state = 'walk'; $S.dir = -$S.dir }
        }

        'wave' {
            $S.phase += 0.34
            if (--$S.timer -le 0) { $S.state = 'walk' }
        }

        'knock' {
            $S.phase += 0.30
            $w = $S.wall
            if ($null -eq $w) { $S.state = 'walk'; return }
            # a rap on the glass, and the window rattles back
            if ($S.shove -and -not $w.Max) {
                $k = $S.timer % 18
                if ($k -eq 9) { [void][SM]::Nudge($w.H, [int]($S.dir * 3 * $SC), 0) }
                if ($k -eq 5) { [void][SM]::Nudge($w.H, [int](-$S.dir * 3 * $SC), 0) }
            }
            if (--$S.timer -le 0) { $S.state = 'walk'; $S.dir = -$S.dir; $S.wall = $null }
        }

        'push' {
            $S.phase += 0.18
            $w = $S.wall
            if ($null -eq $w -or $w.Max) { $S.state = 'walk'; $S.wall = $null; return }
            if ($S.timer % 2 -eq 0) {
                if (-not [SM]::Nudge($w.H, [int]($S.dir * 2 * $SC), 0)) {
                    $S.state = 'walk'; $S.wall = $null; return
                }
            }
            if (--$S.timer -le 0) {
                $S.state = 'walk'
                $S.wall = $null
                if ($RNG.Next(0, 2) -eq 0) { $S.dir = -$S.dir }
            }
        }

        'press' {
            $S.phase += 0.16
            $l = $S.ledge
            if ($null -eq $l -or -not ($l.Btn -or $l.Icon)) { $S.state = 'walk'; return }
            # he crouches, then stamps on it halfway through
            if ($S.timer -eq 22) {
                if ($l.Icon) {
                    # jumping on a shortcut opens it, but not more than once in a while
                    if ($S.open -and ($S.tick - $S.lastOpen) -gt $OPEN_GAP) {
                        if (Open-Shortcut $l.Name) { $S.lastOpen = $S.tick }
                    }
                } elseif ($S.click) {
                    if ($l.Uia -ge 0) {
                        $sync.ClickRect = @($l.L, $l.T, $l.R, $l.B)
                        $sync.ClickIdx  = $l.Uia
                    } else { [SM]::Click($l.H) }
                }
            }
            if (--$S.timer -le 0) {
                $S.state = 'walk'
                if ($RNG.Next(0, 2) -eq 0) { $S.dir = -$S.dir }
            }
        }

        'climb' {
            $S.phase += 0.30
            $w = $S.wall
            if ($null -eq $w) { $S.state = 'fall'; return }
            $S.x = if ($S.dir -gt 0) { $w.L - $HUG } else { $w.R + $HUG }
            $S.y -= $CLIMB
            if ($S.y -le $w.T) {
                Land-On $w
                $S.x = if ($S.dir -gt 0) { $w.L + $STEPIN } else { $w.R - $STEPIN }
            }
        }

        'fall' {
            $prev = $S.y
            $S.vy = [Math]::Min($S.vy + $GRAVITY, $VMAX)
            $S.y += $S.vy
            $S.x += $S.vx
            $S.vx *= 0.985
            $S.phase += 0.2

            # black paint, or anything white, catches him on the way down
            if ([Ink]::Ready) {
                $ix = [int][Math]::Round($S.x)
                $gy = [Ink]::Floor($ix, [int][Math]::Floor($prev) + 1, [int][Math]::Round($S.y))
                if ($gy -ge 0 -and [Ink]::Inside($ix, $gy)) {
                    Land-On (New-InkLedge $gy)
                    $S.y = [double]$gy
                    return
                }
            }

            foreach ($l in $S.ledges) {
                if ($l.H -eq $S.ignore -and $S.ignore -ne [IntPtr]::Zero) { continue }
                if ($S.x -ge $l.L + 5 * $SC -and $S.x -le $l.R - 5 * $SC -and
                    $prev -le $l.T + $SC -and $S.y -ge $l.T) {
                    Land-On $l
                    break
                }
            }

            $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
            if ($S.state -eq 'fall' -and $S.y -gt $vs.Bottom + 120 * $SC) {
                $S.x  = $RNG.Next([int]($vs.Left + 150 * $SC), [int]($vs.Right - 150 * $SC))
                $S.y  = [double]$vs.Top + 10 * $SC
                $S.vy = 0.0; $S.vx = 0.0
            }
        }
    }

    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    if ($S.x -lt $vs.Left + 8 * $SC)  { $S.x = $vs.Left + 8 * $SC;  $S.dir = 1 }
    if ($S.x -gt $vs.Right - 8 * $SC) { $S.x = $vs.Right - 8 * $SC; $S.dir = -1 }
}

# ------------------------------------------------------------------- the sprite
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.AutoScaleMode   = 'None'
$form.ShowInTaskbar   = $false
$form.TopMost         = $true
$form.StartPosition   = 'Manual'
$form.Text            = 'Stickman'

# He is drawn into this and pushed to the screen with UpdateLayeredWindow, so
# there is no background at all - just the figure and clear pixels around it.
$sprite = New-Object System.Drawing.Bitmap $BOXW, $BOXH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sg     = [System.Drawing.Graphics]::FromImage($sprite)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$penHalo = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), 6.5
$penMain = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 24, 24, 28)), 3.0
foreach ($p in @($penHalo, $penMain)) {
    $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'
}
$headFill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))

# the symbol box he gets wrapped in once you convert him: a white halo so the
# thin blue line survives a light wallpaper, then the line itself
$penSymHalo = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 255, 255, 255)), 3.2
$penSym     = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 0, 153, 255)), 1.3
$penReg     = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 0, 153, 255)), 1.7
$dotBrush   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)

# fight mode: the red he flashes when you land one, the stars he sees when he
# is knocked out, and the little bar of hits he has left
$HURT_INK    = [System.Drawing.Color]::FromArgb(255, 226, 46, 46)
$penStar     = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 214, 0)), 1.5
$penStarHalo = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 24, 24, 28)), 3.3
foreach ($p in @($penStar, $penStarHalo)) { $p.StartCap = 'Round'; $p.EndCap = 'Round' }
$hpHalo = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$hpBack = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 90, 24, 24))
$hpFill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 232, 52, 52))

function Seg($ax, $ay, $bx, $by) { ,@([single]$ax, [single]$ay, [single]$bx, [single]$by) }

function Draw-Figure($g) {
    $g.ResetTransform()
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform([single]$SC, [single]$SC)   # design units from here on

    # whichever figure he currently is. A pale colour needs a dark halo or he
    # disappears into a light wallpaper, so the outline flips with the ink.
    $ink = if ($null -ne $S.ink) { $S.ink } else { $EGG_INK }
    if ($F.hurt -gt 0 -and $F.hurt % 4 -lt 2) { $ink = $HURT_INK }    # you landed one
    $penMain.Color = $ink
    $lum = (0.299 * $ink.R + 0.587 * $ink.G + 0.114 * $ink.B) / 255.0
    $penHalo.Color = if ($lum -gt 0.62) { [System.Drawing.Color]::FromArgb(255, 24, 24, 28) }
                     else               { [System.Drawing.Color]::FromArgb(255, 255, 255, 255) }

    $ph    = $S.phase
    $sin   = [Math]::Sin($ph)
    $d     = $S.dir
    $lean  = 0.0
    $headY = 14.0
    $headX = 22.0
    $segs  = New-Object System.Collections.ArrayList
    $dots  = 0                     # speech dots over his head while he chats

    $pose = if ($S.drag) { 'fall' } else { $S.state }
    if ($pose -eq 'meet')   { $pose = if ($S.waiting) { 'idle' } else { 'walk' } }
    if ($pose -eq 'social') { $pose = $SOCIAL_POSE[$S.act] }
    if ($pose -eq 'fall' -and $F.air -and -not $S.drag) { $pose = $F.air }
    if ($pose -eq 'win' -and $S.timer -ge $PUMP_LEN) { $pose = 'cheer' }   # done punching the air
    if ($pose -eq 'cheer') {
        # the whole figure leaves the ground for the hop
        $g.TranslateTransform(0.0, [single](-[Math]::Abs([Math]::Sin($ph * 1.4)) * 9.0))
    }
    if ($pose -eq 'shock' -and $S.timer -lt 12) {
        $g.TranslateTransform(0.0, [single](-[Math]::Sin($S.timer / 12.0 * [Math]::PI) * 7.0))   # a start
    }

    switch ($pose) {
        'climb' {
            [void]$segs.Add((Seg 22 21 22 40))                          # spine
            [void]$segs.Add((Seg 22 25 14 (13 - $sin * 5)))             # arms reaching up
            [void]$segs.Add((Seg 22 25 30 (13 + $sin * 5)))
            [void]$segs.Add((Seg 22 40 14 (52 + $sin * 5)))             # bent legs
            [void]$segs.Add((Seg 22 40 30 (52 - $sin * 5)))
        }
        'fall' {
            $headY = 15.0
            [void]$segs.Add((Seg 22 22 22 40))
            [void]$segs.Add((Seg 22 26 11 15))
            [void]$segs.Add((Seg 22 26 33 17))
            [void]$segs.Add((Seg 22 40 13 60))
            [void]$segs.Add((Seg 22 40 30 62))
        }
        'idle' {
            $bob   = $sin * 1.2
            $headY = 14.0 + $bob
            [void]$segs.Add((Seg 22 (21 + $bob) 22 (40 + $bob)))
            [void]$segs.Add((Seg 22 (26 + $bob) 16 (38 + $bob)))
            [void]$segs.Add((Seg 22 (26 + $bob) 28 (38 + $bob)))
            [void]$segs.Add((Seg 22 (40 + $bob) 17 62))
            [void]$segs.Add((Seg 22 (40 + $bob) 27 62))
        }
        'leap' {
            # stretched out, both arms reaching for the corner
            $headY = 16.0
            [void]$segs.Add((Seg 22 23 22 41))
            [void]$segs.Add((Seg 22 26 (22 - $d * 6) 9))
            [void]$segs.Add((Seg 22 26 (22 + $d * 9) 11))
            [void]$segs.Add((Seg 22 41 (22 - $d * 7) 56))          # legs tucked and trailing
            [void]$segs.Add((Seg (22 - $d * 7) 56 (22 - $d * 12) 62))
            [void]$segs.Add((Seg 22 41 (22 - $d * 2) 60))
        }
        'cheer' {
            $sw = [Math]::Sin($ph * 1.4)
            [void]$segs.Add((Seg 22 21 22 40))
            [void]$segs.Add((Seg 22 26 12 (13 - $sw * 3)))          # both arms up
            [void]$segs.Add((Seg 22 26 32 (13 + $sw * 3)))
            [void]$segs.Add((Seg 22 40 (22 - 5 - $sw * 3) 62))      # legs kicking out
            [void]$segs.Add((Seg 22 40 (22 + 5 + $sw * 3) 62))
        }
        'wave' {
            $headX = 22 + $d * 1.5
            [void]$segs.Add((Seg 22 21 22 40))
            [void]$segs.Add((Seg 22 26 (22 - $d * 7) 38))               # arm down
            [void]$segs.Add((Seg 22 26 (22 + $d * 10) (15 + $sin * 5))) # arm waving
            [void]$segs.Add((Seg 22 40 17 62))
            [void]$segs.Add((Seg 22 40 27 62))
        }
        'sit' {
            $headY = 30.0
            $headX = 22 + $d * 1.5
            [void]$segs.Add((Seg 22 37 (22 - $d * 2) 54))               # spine, leaning back
            [void]$segs.Add((Seg 22 41 (22 - $d * 8) 55))               # arm propped behind
            [void]$segs.Add((Seg 22 41 (22 + $d * 5) 50))
            [void]$segs.Add((Seg (22 - $d * 2) 54 (22 + $d * 12) 53))   # thigh along the edge
            [void]$segs.Add((Seg (22 + $d * 12) 53 (22 + $d * 12 + $sin * 3) 64))  # shin swinging
        }
        'press' {
            # squat down and stamp on the button
            $c = [Math]::Sin(((42.0 - $S.timer) / 42.0) * [Math]::PI)
            $headY = 14.0 + 11.0 * $c
            [void]$segs.Add((Seg 22 (21 + 11 * $c) 22 (40 + 6 * $c)))
            [void]$segs.Add((Seg 22 (26 + 10 * $c) (22 - $d * 8) (30 + 14 * $c)))
            [void]$segs.Add((Seg 22 (26 + 10 * $c) (22 + $d * 8) (30 + 14 * $c)))
            [void]$segs.Add((Seg 22 (40 + 6 * $c) (22 - 6 - 5 * $c) (52 + 2 * $c)))   # knees out
            [void]$segs.Add((Seg (22 - 6 - 5 * $c) (52 + 2 * $c) (22 - 6) 62))
            [void]$segs.Add((Seg 22 (40 + 6 * $c) (22 + 6 + 5 * $c) (52 + 2 * $c)))
            [void]$segs.Add((Seg (22 + 6 + 5 * $c) (52 + 2 * $c) (22 + 6) 62))
        }
        'knock' {
            $rap = [Math]::Max(0.0, $sin)
            [void]$segs.Add((Seg 22 21 22 40))
            [void]$segs.Add((Seg 22 26 (22 + $d * (8 + $rap * 4)) 25))  # knuckles on the glass
            [void]$segs.Add((Seg 22 26 (22 - $d * 6) 38))
            [void]$segs.Add((Seg 22 40 (22 - $d * 4) 62))
            [void]$segs.Add((Seg 22 40 (22 + $d * 4) 62))
        }
        'push' {
            $lean  = $d * 4.0
            $headX = 22 + $lean * 1.3
            $headY = 16.0
            [void]$segs.Add((Seg (22 + $lean) 23 (22 - $lean * 0.3) 40))
            [void]$segs.Add((Seg (22 + $lean * 0.6) 27 (22 + $d * 12) 29))
            [void]$segs.Add((Seg (22 + $lean * 0.6) 27 (22 + $d * 12) 33))
            [void]$segs.Add((Seg (22 - $lean * 0.3) 40 (22 - $d * 11) 62))  # braced back leg
            [void]$segs.Add((Seg (22 - $lean * 0.3) 40 (22 + $d * 3) 62))
        }
        'hifive' {
            # the arm goes up and out to meet his friend's hand in the middle
            $r = [Math]::Sin(((40.0 - $S.timer) / 40.0) * [Math]::PI)
            $lean  = $d * 1.5 * $r
            $headX = 22 + $lean
            [void]$segs.Add((Seg (22 + $lean * 0.6) 21 22 40))
            [void]$segs.Add((Seg (22 + $lean * 0.4) 26 (22 + $d * (4 + 8 * $r)) (24 - 14 * $r)))
            [void]$segs.Add((Seg (22 + $lean * 0.4) 26 (22 - $d * 6) 38))
            [void]$segs.Add((Seg 22 40 (22 - $d * 6) 62))
            [void]$segs.Add((Seg 22 40 (22 + $d * 4) 62))
        }
        'chat' {
            # they take turns: one talks with his hands, the other nods along
            $first = if ($ME -lt $S.with) { 0 } else { 1 }
            $talk  = ([Math]::Floor($S.timer / 35) % 2) -eq $first
            [void]$segs.Add((Seg 22 21 22 40))
            [void]$segs.Add((Seg 22 26 (22 - $d * 5) 38))
            if ($talk) {
                $gs = [Math]::Sin($ph * 3.0)
                [void]$segs.Add((Seg 22 26 (22 + $d * 8) 34))
                [void]$segs.Add((Seg (22 + $d * 8) 34 (22 + $d * 13) (27 + $gs * 3)))
                $dots = 1 + [int]([Math]::Floor($ph * 1.5) % 3)
            } else {
                $headY = 14.0 + [Math]::Abs($sin) * 1.5
                [void]$segs.Add((Seg 22 26 (22 + $d * 5) 38))
            }
            [void]$segs.Add((Seg 22 40 18 62))
            [void]$segs.Add((Seg 22 40 26 62))
        }
        'guard' {
            # fists up, knees bent, bouncing on his toes
            $b = [Math]::Abs([Math]::Sin($ph * 1.6)) * 1.6
            $headX = 22 + $d * 2.0
            $headY = 18.0 + $b
            [void]$segs.Add((Seg (22 + $d * 1.5) (25 + $b) (22 - $d * 0.5) (42 + $b)))
            [void]$segs.Add((Seg (22 + $d * 1.2) (29 + $b) (22 + $d * 9) (35 + $b)))      # lead fist out front
            [void]$segs.Add((Seg (22 + $d * 9) (35 + $b) (22 + $d * 12) (27 + $b)))
            [void]$segs.Add((Seg (22 + $d * 1.2) (29 + $b) (22 + $d * 3) (37 + $b)))      # rear fist by his chin
            [void]$segs.Add((Seg (22 + $d * 3) (37 + $b) (22 + $d * 7) (29 + $b)))
            [void]$segs.Add((Seg (22 - $d * 0.5) (42 + $b) (22 + $d * 7) (52 + $b / 2)))  # lead leg
            [void]$segs.Add((Seg (22 + $d * 7) (52 + $b / 2) (22 + $d * 9) 62))
            [void]$segs.Add((Seg (22 - $d * 0.5) (42 + $b) (22 - $d * 6) (52 + $b / 2)))  # back leg
            [void]$segs.Add((Seg (22 - $d * 6) (52 + $b / 2) (22 - $d * 10) 62))
        }
        'taunt' {
            # 'come on, then': hand out, palm up, fingers beckoning
            $k = [Math]::Max(0.0, [Math]::Sin($ph * 3.0))
            $headX = 22 + $d * 1.0
            $headY = 17.0
            [void]$segs.Add((Seg (22 + $d * 1) 24 22 42))
            [void]$segs.Add((Seg (22 + $d * 1) 28 (22 + $d * 13) 31))
            [void]$segs.Add((Seg (22 + $d * 13) 31 (22 + $d * (17 - 3 * $k)) (31 - 5 * $k)))
            [void]$segs.Add((Seg (22 + $d * 1) 28 (22 - $d * 5) 35))                     # other hand on his hip
            [void]$segs.Add((Seg (22 - $d * 5) 35 (22 - $d * 1) 40))
            [void]$segs.Add((Seg 22 42 (22 + $d * 7) 52))
            [void]$segs.Add((Seg (22 + $d * 7) 52 (22 + $d * 9) 62))
            [void]$segs.Add((Seg 22 42 (22 - $d * 6) 52))
            [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 10) 62))
        }
        'punch' {
            # jab and cross in turn, lunging in behind it
            $e = [Math]::Sin(((14.0 - $S.timer) / 14.0) * [Math]::PI)
            $lean  = $d * 2.5 * $e
            $headX = 22 + $d * 2 + $lean
            $headY = 18.0
            $sx = 22 + $d * 1.2 + $lean
            [void]$segs.Add((Seg (22 + $d * 1.5 + $lean) 25 (22 - $d * 0.5) 42))
            $ex = 22 + $d * (8 + 6 * $e) + $lean * 0.4
            $fx = 22 + $d * (11 + 7.5 * $e) + $lean * 0.4
            [void]$segs.Add((Seg $sx 29 $ex (34 - 7 * $e)))                                # the punching arm
            [void]$segs.Add((Seg $ex (34 - 7 * $e) $fx (27 - $e)))
            [void]$segs.Add((Seg $sx 29 (22 + $d * 3) 37))                                  # the other stays up
            [void]$segs.Add((Seg (22 + $d * 3) 37 (22 + $d * 7) 29))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 + $d * 8) 51))
            [void]$segs.Add((Seg (22 + $d * 8) 51 (22 + $d * 10) 62))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 - $d * 6) 52))
            [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 11) 62))
        }
        'kick' {
            # leans back and snaps a kick out at the pointer
            $e = [Math]::Sin(((20.0 - $S.timer) / 20.0) * [Math]::PI)
            $back  = $d * 4.0 * $e
            $headX = 22 + $d * 1 - $back
            $headY = 17.0 + 2 * $e
            [void]$segs.Add((Seg (22 + $d * 1 - $back * 0.9) (24 + 2 * $e) (22 - $d * 1) 42))
            [void]$segs.Add((Seg (22 + $d * 1 - $back * 0.7) (28 + 2 * $e) (22 - $d * 9) 34))       # arm out for balance
            [void]$segs.Add((Seg (22 + $d * 1 - $back * 0.7) (28 + 2 * $e) (22 + $d * 7) (25 + 2 * $e)))
            [void]$segs.Add((Seg (22 - $d * 1) 42 (22 - $d * 3) 52))                                 # standing leg
            [void]$segs.Add((Seg (22 - $d * 3) 52 (22 - $d * 5) 62))
            [void]$segs.Add((Seg (22 - $d * 1) 42 (22 + $d * (4 + 8 * $e)) (50 - 10 * $e)))          # kicking leg
            [void]$segs.Add((Seg (22 + $d * (4 + 8 * $e)) (50 - 10 * $e) (22 + $d * (6 + 13 * $e)) (60 - 26 * $e)))
        }
        'heave' {
            # wrenching a window loose, trembling with the effort
            $k = [Math]::Sin($ph * 6.0) * 0.7
            if ($null -ne $F.fly -and $F.fly.Up) {
                # hands up under its bottom edge, knees bent
                $headY = 18.0
                [void]$segs.Add((Seg 22 25 22 42))
                [void]$segs.Add((Seg 22 28 (22 - $d * 9) (18 + $k)))
                [void]$segs.Add((Seg (22 - $d * 9) (18 + $k) (22 - $d * 4) (4.5 + $k)))
                [void]$segs.Add((Seg 22 28 (22 + $d * 9) (18 - $k)))
                [void]$segs.Add((Seg (22 + $d * 9) (18 - $k) (22 + $d * 4) (4.5 - $k)))
                [void]$segs.Add((Seg 22 42 16 52)); [void]$segs.Add((Seg 16 52 17 62))
                [void]$segs.Add((Seg 22 42 28 52)); [void]$segs.Add((Seg 28 52 27 62))
            } else {
                # both hands on its side, leaning back further and further
                $t  = 1.0 - $S.timer / [double]$(if ($null -ne $F.fly) { $F.fly.Len } else { $HEAVE_LEN })
                $bk = $d * 3.5 * $t
                $headX = 22 - $bk * 1.2
                $headY = 17.0
                [void]$segs.Add((Seg (22 - $bk) 24 22 41))
                [void]$segs.Add((Seg (22 - $bk * 0.8) 28 (22 + $d * 7 - $bk * 0.5) (29 + $k)))
                [void]$segs.Add((Seg (22 + $d * 7 - $bk * 0.5) (29 + $k) (22 + $d * 14) (27 + $k)))
                [void]$segs.Add((Seg (22 - $bk * 0.8) 28 (22 + $d * 7 - $bk * 0.5) (33 + $k)))
                [void]$segs.Add((Seg (22 + $d * 7 - $bk * 0.5) (33 + $k) (22 + $d * 14) (31 + $k)))
                [void]$segs.Add((Seg 22 41 (22 + $d * 6) 51)); [void]$segs.Add((Seg (22 + $d * 6) 51 (22 + $d * 9) 62))
                [void]$segs.Add((Seg 22 41 (22 - $d * 6) 52)); [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 11) 62))
            }
        }
        'hurl' {
            # the follow-through: lunging after it, arms out at the pointer
            $e = [Math]::Sin(((14.0 - $S.timer) / 14.0) * [Math]::PI)
            $lean  = $d * 3.0 * $e
            $headX = 22 + $d * 2 + $lean
            $headY = 17.0 + $e
            $sx = 22 + $d * 1.2 + $lean * 0.8
            [void]$segs.Add((Seg (22 + $d * 1.5 + $lean) (24 + $e) (22 - $d * 0.5) 42))
            [void]$segs.Add((Seg $sx 28 (22 + $d * (8 + 3 * $e) + $lean * 0.5) (24 - 2 * $e)))
            [void]$segs.Add((Seg (22 + $d * (8 + 3 * $e) + $lean * 0.5) (24 - 2 * $e) (22 + $d * (14 + 4 * $e)) (20 - 3 * $e)))
            [void]$segs.Add((Seg $sx 28 (22 + $d * (7 + 3 * $e)) 31))
            [void]$segs.Add((Seg (22 + $d * (7 + 3 * $e)) 31 (22 + $d * (13 + 3 * $e)) 28))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 + $d * 8) 51)); [void]$segs.Add((Seg (22 + $d * 8) 51 (22 + $d * 11) 62))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 - $d * 6) 52)); [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 12) 62))
        }
        'haul' {
            # the arm with your pointer in it comes from Get-GrabHand, which
            # Step-Grab uses too, so the pointer sits right in his fist
            $hd = Get-GrabHand
            if ($GRAB_HOLD - $S.timer -lt $GRAB_SNATCH) {
                # lunging in to take it, other fist up
                $headX = 22 + $d * 3; $headY = 17.0
                [void]$segs.Add((Seg (22 + $d * 2.5) 24 (22 - $d * 0.5) 42))
                [void]$segs.Add((Seg (22 + $d * 1) 27 $hd[0] $hd[1]))
                [void]$segs.Add((Seg (22 + $d * 1) 29 (22 + $d * 3) 37)); [void]$segs.Add((Seg (22 + $d * 3) 37 (22 + $d * 7) 29))
                [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 + $d * 8) 51)); [void]$segs.Add((Seg (22 + $d * 8) 51 (22 + $d * 10) 62))
                [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 - $d * 6) 52)); [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 11) 62))
            } else {
                # running off, dragging it along behind him
                $sw = $sin * 9.0
                $headX = 22 + $d * 3.5; $headY = 16.0
                [void]$segs.Add((Seg (22 + $d * 2.5) 23 22 40))
                [void]$segs.Add((Seg (22 + $d * 1) 27 $hd[0] $hd[1]))
                [void]$segs.Add((Seg (22 + $d * 1) 27 (22 + $d * 1 + $sw * 0.7) 37))
                [void]$segs.Add((Seg 22 40 (22 + $sw) 62))
                [void]$segs.Add((Seg 22 40 (22 - $sw) 62))
            }
        }
        'fling' {
            # swinging it up over his head and letting fly
            $hd = Get-GrabHand
            $e  = [Math]::Min(1.0, ($FLING_LEN - $S.timer) / [double]($FLING_LEN - $FLING_AT))
            $lean  = $d * 3.0 * $e
            $headX = 22 + $d * 1 + $lean; $headY = 17.0
            [void]$segs.Add((Seg (22 + $d * 1.5 + $lean * 0.8) 24 (22 - $d * 0.5) 42))
            [void]$segs.Add((Seg (22 + $d * 1) 27 $hd[0] $hd[1]))
            [void]$segs.Add((Seg (22 + $d * 1) 28 (22 - $d * 10) (33 - 4 * $e)))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 + $d * 8) 51)); [void]$segs.Add((Seg (22 + $d * 8) 51 (22 + $d * 11) 62))
            [void]$segs.Add((Seg (22 - $d * 0.5) 42 (22 - $d * 6) 52)); [void]$segs.Add((Seg (22 - $d * 6) 52 (22 - $d * 12) 62))
        }
        'flykick' {
            # one leg straight out at the pointer, the other tucked under
            $headX = 22 - $d * 5
            $headY = 15.0
            [void]$segs.Add((Seg (22 - $d * 4) 22 (22 + $d * 1) 38))
            [void]$segs.Add((Seg (22 + $d * 1) 38 (22 + $d * 19) 34))
            [void]$segs.Add((Seg (22 + $d * 1) 38 (22 - $d * 3) 49))
            [void]$segs.Add((Seg (22 - $d * 3) 49 (22 - $d * 10) 45))
            [void]$segs.Add((Seg (22 - $d * 3) 26 (22 + $d * 7) 21))
            [void]$segs.Add((Seg (22 - $d * 3) 26 (22 - $d * 13) 30))
        }
        'hurt' {
            # knocked back: head snapped back, arms and legs flung forward
            $headX = 22 - $d * 6
            $headY = 16.0
            [void]$segs.Add((Seg (22 - $d * 4.5) 22.5 (22 + $d * 1) 40))
            [void]$segs.Add((Seg (22 - $d * 3) 27 (22 + $d * 9) 19))
            [void]$segs.Add((Seg (22 - $d * 3) 27 (22 + $d * 10) 31))
            [void]$segs.Add((Seg (22 + $d * 1) 40 (22 + $d * 10) 55))
            [void]$segs.Add((Seg (22 + $d * 1) 40 (22 + $d * 4) 61))
        }
        'flip' {
            # a quick hop back out of the way, knees tucked
            $headX = 22 - $d * 2
            $headY = 19.0
            [void]$segs.Add((Seg (22 - $d * 1.5) 25.5 22 40))
            [void]$segs.Add((Seg (22 - $d * 1) 29 (22 + $d * 9) 25))
            [void]$segs.Add((Seg (22 - $d * 1) 29 (22 - $d * 9) 33))
            [void]$segs.Add((Seg 22 40 (22 + $d * 7) 47))
            [void]$segs.Add((Seg (22 + $d * 7) 47 (22 + $d * 2) 55))
            [void]$segs.Add((Seg 22 40 (22 + $d * 4) 50))
            [void]$segs.Add((Seg (22 + $d * 4) 50 (22 - $d * 2) 58))
        }
        'win' {
            # punching the air over the pieces, other hand on his hip
            $pump  = [Math]::Abs([Math]::Sin($ph * 1.3))
            $headX = 22 + $d * 1.0
            $headY = 14.0 + $pump * 0.8
            [void]$segs.Add((Seg 22 (21 + $pump * 0.8) 22 40))
            [void]$segs.Add((Seg 22 26 (22 + $d * 9) (21 - 2 * $pump)))                  # fist to the sky
            [void]$segs.Add((Seg (22 + $d * 9) (21 - 2 * $pump) (22 + $d * 10) (10 - 3 * $pump)))
            [void]$segs.Add((Seg 22 26 (22 - $d * 6) 33))                                  # hand on his hip
            [void]$segs.Add((Seg (22 - $d * 6) 33 (22 - $d * 2) 39))
            [void]$segs.Add((Seg 22 40 (22 - $d * 6) 62))                                  # feet planted wide
            [void]$segs.Add((Seg 22 40 (22 + $d * 6) 62))
        }
        'shock' {
            # it is mending: he jumps back, hands up, trembling, with a '!'
            $q = [Math]::Sin($ph * 9.0) * 0.5
            $headX = 22 - $d * 3 + $q
            $headY = 16.0
            [void]$segs.Add((Seg (22 - $d * 2 + $q) 23 22 41))
            [void]$segs.Add((Seg (22 - $d * 1.5 + $q) 27 (22 + $d * 5) 23))
            [void]$segs.Add((Seg (22 + $d * 5) 23 (22 + $d * 8) (15 + $q)))
            [void]$segs.Add((Seg (22 - $d * 1.5 + $q) 27 (22 + $d * 4) 32))
            [void]$segs.Add((Seg (22 + $d * 4) 32 (22 + $d * 10) (27 - $q)))
            [void]$segs.Add((Seg 22 41 (22 + $d * 5) 51)); [void]$segs.Add((Seg (22 + $d * 5) 51 (22 + $d * 4) 62))
            [void]$segs.Add((Seg 22 41 (22 - $d * 5) 52)); [void]$segs.Add((Seg (22 - $d * 5) 52 (22 - $d * 9) 62))
            $ex = 22 + $d * 16
            [void]$segs.Add((Seg $ex 7 $ex 13.5))
            [void]$segs.Add((Seg $ex 17.4 $ex 17.8))
        }
        'ko' {
            # flat on his back with his knees up
            $headX = 22 - $d * 12
            $headY = 55.0
            [void]$segs.Add((Seg (22 - $d * 5.5) 58 (22 + $d * 5) 60))
            [void]$segs.Add((Seg (22 - $d * 4) 58 (22 + $d * 1) 51))
            [void]$segs.Add((Seg (22 - $d * 4) 58 (22 - $d * 10) 62))
            [void]$segs.Add((Seg (22 + $d * 5) 60 (22 + $d * 11) 50))
            [void]$segs.Add((Seg (22 + $d * 11) 50 (22 + $d * 17) 61))
            [void]$segs.Add((Seg (22 + $d * 5) 60 (22 + $d * 13) 53))
            [void]$segs.Add((Seg (22 + $d * 13) 53 (22 + $d * 18) 62))
        }
        default {   # walk
            $lean  = $d * 2.0
            $swing = $sin * 7.0
            $headX = 22 + $lean * 0.9
            [void]$segs.Add((Seg (22 + $lean * 0.7) 21 22 40))
            [void]$segs.Add((Seg (22 + $lean * 0.4) 26 (22 - $swing) (37 - [Math]::Abs($sin) * 2)))
            [void]$segs.Add((Seg (22 + $lean * 0.4) 26 (22 + $swing) (37 - [Math]::Abs($sin) * 2)))
            [void]$segs.Add((Seg 22 40 (22 + $swing) 62))
            [void]$segs.Add((Seg 22 40 (22 - $swing) 62))
        }
    }

    $head = New-Object System.Drawing.RectangleF ([single]($headX - 6.5)), ([single]($headY - 6.5)), 13.0, 13.0

    foreach ($seg in $segs) { $g.DrawLine($penHalo, $seg[0], $seg[1], $seg[2], $seg[3]) }
    $g.DrawEllipse($penHalo, $head)
    $g.FillEllipse($headFill, $head)
    foreach ($seg in $segs) { $g.DrawLine($penMain, $seg[0], $seg[1], $seg[2], $seg[3]) }
    $g.DrawEllipse($penMain, $head)

    for ($i = 0; $i -lt $dots; $i++) {
        $dx = [single](22 + $d * (9 + $i * 4))
        $dotBrush.Color = $penHalo.Color
        $g.FillEllipse($dotBrush, [single]($dx - 2.2), [single]1.3, [single]4.4, [single]4.4)
        $dotBrush.Color = $ink
        $g.FillEllipse($dotBrush, [single]($dx - 1.3), [single]2.2, [single]2.6, [single]2.6)
    }

    if ($pose -eq 'ko') {
        # stars going round his head
        for ($i = 0; $i -lt 3; $i++) {
            $a  = $ph * 2.2 + $i * 2.0944
            $sx = [single]($headX + [Math]::Cos($a) * 8.0)
            $sy = [single]($headY - 11.0 + [Math]::Sin($a) * 2.5)
            foreach ($p in @($penStarHalo, $penStar)) {
                $g.DrawLine($p, [single]($sx - 2.6), $sy, [single]($sx + 2.6), $sy)
                $g.DrawLine($p, $sx, [single]($sy - 2.6), $sx, [single]($sy + 2.6))
            }
        }
    }
    if ($F.on) {
        # the hits he can still take, staying put while he hops about
        $g.ResetTransform()
        $g.ScaleTransform([single]$SC, [single]$SC)
        $hpHalo.Color = $penHalo.Color
        $g.FillRectangle($hpHalo, [single]7.0, [single]3.0, [single]30.0, [single]4.5)
        $g.FillRectangle($hpBack, [single]8.0, [single]4.0, [single]28.0, [single]2.5)
        $g.FillRectangle($hpFill, [single]8.0, [single]4.0, [single](28.0 * [Math]::Max(0, $F.hp) / $F.max), [single]2.5)
    }

    if ($S.symbol -or $S.symFlash -gt 0) { Draw-SymbolBox $g }
}

# The Flash-style wrapper: the selection rectangle plus the little registration
# cross at whichever of the nine points you picked in the dialog.
function Draw-SymbolBox($g) {
    $g.ResetTransform()                              # the cheer hop must not move it
    $g.ScaleTransform([single]$SC, [single]$SC)

    $bx = 1.5; $by = 1.5
    $bw = [single]($DW - 3.0); $bh = [single]($DH - 3.0)

    # the box takes the figure's colour when he is one of the hidden names,
    # and stays Flash blue when he is just a symbol
    $tint = if ($null -ne $S.ink) { $S.ink } else { [System.Drawing.Color]::FromArgb(255, 0, 153, 255) }
    $penSym.Color = $tint
    $penReg.Color = $tint

    if ($S.symFlash -gt 0) {
        $a = [int](80.0 * $S.symFlash / [Math]::Max(1, $S.symFlashMax))
        $fb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $tint.R, $tint.G, $tint.B))
        $g.FillRectangle($fb, [single]$bx, [single]$by, $bw, $bh)
        $fb.Dispose()
    }
    if (-not $S.symbol) { return }

    $g.DrawRectangle($penSymHalo, [single]$bx, [single]$by, $bw, $bh)
    $g.DrawRectangle($penSym,     [single]$bx, [single]$by, $bw, $bh)

    $rx = [single]($bx + $bw * (($S.symReg % 3) / 2.0))
    $ry = [single]($by + $bh * ([Math]::Floor($S.symReg / 3) / 2.0))
    $arm = [single]3.0
    $g.DrawLine($penSymHalo, ($rx - $arm), $ry, ($rx + $arm), $ry)
    $g.DrawLine($penSymHalo, $rx, ($ry - $arm), $rx, ($ry + $arm))
    $g.DrawLine($penReg, ($rx - $arm), $ry, ($rx + $arm), $ry)
    $g.DrawLine($penReg, $rx, ($ry - $arm), $rx, ($ry + $arm))
}

# ----------------------------------------------------------------------- sparks
# A blow that lands pops a comic-book spark where it hit. His own window is only
# as big as he is, so the spark gets a window of its own, made the first time
# it is needed. Clicks go straight through it, so it never catches one.
$FXS    = 72.0                                  # spark window, design units
$FXW    = [int][Math]::Round($FXS * $SC)
$fxForm = $null

function New-FxWindow {
    $script:fxForm = New-Object System.Windows.Forms.Form
    $fxForm.FormBorderStyle = 'None'
    $fxForm.ShowInTaskbar   = $false
    $fxForm.StartPosition   = 'Manual'
    $fxForm.Text            = 'Stickman spark'
    $script:fxBmp  = New-Object System.Drawing.Bitmap $FXW, $FXW, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $script:fxG    = [System.Drawing.Graphics]::FromImage($fxBmp)
    $fxG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $script:fxFill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $script:fxCore = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $script:fxPen  = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), 1.8
    $fxPen.LineJoin = 'Round'
    $h = $fxForm.Handle
    # LAYERED | TRANSPARENT (clicks fall through) | TOOLWINDOW | NOACTIVATE
    [void][SM]::SetWindowLong($h, -20, ([SM]::GetExStyle($h) -bor 0x00080000 -bor 0x00000020 -bor 0x00000080 -bor 0x08000000))
}

# the points of an eight-pointed star round the middle of the spark window
function Get-StarPoints($ro, $ri, $rot) {
    $m   = $FXS / 2.0
    $pts = New-Object 'System.Drawing.PointF[]' 16
    for ($i = 0; $i -lt 16; $i++) {
        $r = if ($i % 2 -eq 0) { $ro } else { $ri }
        $a = $i * [Math]::PI / 8 + $rot
        $pts[$i] = New-Object System.Drawing.PointF ([single]($m + [Math]::Cos($a) * $r)), ([single]($m + [Math]::Sin($a) * $r))
    }
    , $pts
}

# one frame of the spark: it pops out and fades, then the window hides
function Draw-Fx {
    if ($null -eq $fxForm) { New-FxWindow }
    $h = $fxForm.Handle
    if (--$F.fx -le 0) {
        [void][SM]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 0, 0, 0x0097)   # HIDE | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
        return
    }
    $t  = 1.0 - $F.fx / [double]$FX_LEN
    $a  = [int](255 * (1.0 - $t * $t))
    $ro = 9.0 + 22.0 * [Math]::Sqrt($t)
    $fxG.ResetTransform()
    $fxG.Clear([System.Drawing.Color]::Transparent)
    $fxG.ScaleTransform([single]$SC, [single]$SC)
    $fxFill.Color = [System.Drawing.Color]::FromArgb($a, 255, 255, 255)
    $fxCore.Color = [System.Drawing.Color]::FromArgb($a, 255, 204, 0)
    $fxPen.Color  = [System.Drawing.Color]::FromArgb($a, 24, 24, 28)
    $outer = Get-StarPoints $ro ($ro * 0.45) $F.fxRot
    $fxG.FillPolygon($fxFill, $outer)
    $fxG.DrawPolygon($fxPen, $outer)
    $fxG.FillPolygon($fxCore, (Get-StarPoints ($ro * 0.55) ($ro * 0.25) ($F.fxRot + 0.2)))
    $hb = $fxBmp.GetHbitmap([System.Drawing.Color]::FromArgb(0))
    [SM]::Blit($h, $hb, [int]($F.fxX - $FXW / 2), [int]($F.fxY - $FXW / 2), $FXW, $FXW)
    [void][SM]::DeleteObject($hb)
    [void][SM]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0053)     # TOPMOST, SHOW | NOACTIVATE | NOMOVE | NOSIZE
}

# ------------------------------------------------------------------------- grip
# While he has hold of your pointer, a small pad you can barely see sits under
# it. A click lands on the pad and never on the program underneath, so a
# click meant to fight him off cannot press something by accident; it counts
# as a hit on him instead, and he lets go. Made the first time it is needed.
$GRIP     = [int][Math]::Round(120 * $SC)
$gripForm = $null

function New-GripWindow {
    $script:gripForm = New-Object System.Windows.Forms.Form
    $gripForm.FormBorderStyle = 'None'
    $gripForm.ShowInTaskbar   = $false
    $gripForm.StartPosition   = 'Manual'
    $gripForm.Text            = 'Stickman grip'
    # alpha 1 rather than 0: invisible, but clicks stop here instead of going through
    $bmp = New-Object System.Drawing.Bitmap $GRIP, $GRIP, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(1, 0, 0, 0))
    $g.Dispose()
    $script:gripHb = $bmp.GetHbitmap([System.Drawing.Color]::FromArgb(0))
    $bmp.Dispose()
    $h = $gripForm.Handle
    # LAYERED | TOOLWINDOW | NOACTIVATE, and not TRANSPARENT: catching clicks is its job
    [void][SM]::SetWindowLong($h, -20, ([SM]::GetExStyle($h) -bor 0x00080000 -bor 0x00000080 -bor 0x08000000))
    $gripForm.Add_MouseDown({
        Release-Pointer
        if ($F.on) { Hit-Him ([System.Windows.Forms.Cursor]::Position) }
    })
}

function Show-Grip($x, $y) {
    if ($null -eq $gripForm) { New-GripWindow }
    $h = $gripForm.Handle
    [SM]::Blit($h, $gripHb, [int]($x - $GRIP / 2), [int]($y - $GRIP / 2), $GRIP, $GRIP)
    [void][SM]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0053)     # TOPMOST, SHOW | NOACTIVATE | NOMOVE | NOSIZE
}

function Hide-Grip {
    if ($null -eq $gripForm) { return }
    [void][SM]::SetWindowPos($gripForm.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0097)   # HIDE | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
}

# --------------------------------------------------------- breaking the pointer
# In a fight your pointer has hits of its own: the little bar that shows under
# it for a moment each time he lands one. Run it down to nothing and he breaks
# it. It hangs there cracking while everything freezes, bursts into pieces
# that clatter down onto whatever is below, and he celebrates. Then the pieces
# shiver, fly back together, and with a flash it is whole again, at full
# strength - and he squares up for another round.
#
# While it is in pieces there is no pointer: it stays where it broke, you
# cannot see it and nothing on screen can be clicked. That is all one window,
# the shroud: a sheet over every screen at alpha 1, which takes the clicks and
# shows a blank pointer. Nothing about the pointer is changed in Windows, so if
# he quits or crashes mid-way the sheet goes with him and your pointer is just
# there. A click mends it sooner, and Esc ends the fight at once.
#
# The pieces are cut from a picture of the pointer as it looked the moment it
# broke, whatever shape it had; failing that, a plain white arrow.
$PTR = @{
    hp = 10; max = 10           # hits it can take, see $TUNE
    shown = 10.0                # what the bar shows, easing after hp
    bar = 0                     # frames left of the bar showing
    dead = $false               # in pieces
    t = 0                       # frames since it broke
    mend = $false               # pulling itself back together
    mt = 0                      # frames into that
    hurry = $false              # you clicked: mend as soon as the pieces are down
    x = 0; y = 0                # where it broke, and where it stays meanwhile
    kx = 0.0; ky = 0.0          # the way the blow that broke it was going
    img = $null                 # the picture the pieces are cut from
    hx = 0; hy = 0              # its hot spot in that picture
    cx = 0.0; cy = 0.0          # where the cracks start, in the picture
    brush = $null               # the picture, as a brush to fill the pieces with
    shards = New-Object System.Collections.ArrayList
    wx = 0; wy = 0; ww = 0; wh = 0     # the wreck window, on screen
    floor = 0.0                 # what the pieces land on
    bmp = $null; g = $null      # the wreck window's picture
}
$CRACK_LEN  = 10        # frames it hangs there cracking, everything frozen, before it bursts
$DEAD_LEN   = 120       # frames from breaking to starting to mend, unless you click
$SHIVER_LEN = 14        # the pieces shiver where they lie,
$REJOIN_LEN = 24        # fly back together,
$GLOW_LEN   = 14        # and it flashes whole again
$PUMP_LEN   = 48        # he punches the air this long, then jumps for joy
$BAR_SHOW   = 60        # frames the bar stays up after a hit
$SHARDS     = 8
$SHARD_GRAV = 0.55 * $SC

# a blow landed on the pointer: $true if that broke it
function Hurt-Pointer($dmg, $kx, $ky) {
    if (-not $S.killPtr -or $PTR.dead) { return $false }
    $PTR.hp  = [Math]::Max(0, $PTR.hp - $dmg)
    $PTR.bar = $BAR_SHOW
    if ($PTR.hp -gt 0) { return $false }
    # never with a mouse button down: it hangs on by a thread instead
    if (Test-MouseHeld) { $PTR.hp = 1; return $false }
    $null = Break-Pointer $kx $ky
    return $true
}

function Break-Pointer($kx, $ky) {
    $c = [System.Windows.Forms.Cursor]::Position
    Release-Pointer
    $F.kn = 0
    $PTR.dead = $true; $PTR.t = 0; $PTR.mend = $false; $PTR.mt = 0; $PTR.hurry = $false
    $PTR.x = $c.X; $PTR.y = $c.Y; $PTR.kx = [double]$kx; $PTR.ky = [double]$ky
    $PTR.bar = 0
    Hide-PtrBar
    Get-PointerImage                        # before the shroud blanks it out
    Open-Wreck
    New-Shards
    Show-Shroud
    # a nudge there and back, so Windows looks again at what is under the
    # pointer and finds the shroud's blank one
    if (-not (Test-MouseHeld)) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ($PTR.x + 1), $PTR.y
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $PTR.x, $PTR.y
    }
    [System.Windows.Forms.Cursor]::Current = $blankCursor
    Draw-Wreck
    [void][SM]::SetWindowPos($wreckForm.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0053)   # TOPMOST, SHOW | NOACTIVATE | NOMOVE | NOSIZE
    # whatever he had hold of it with, he lets go to celebrate
    if ($S.state -in @('haul', 'fling')) { $S.state = 'guard'; $S.phase = 0.0 }
}

# a picture of the pointer as it looks right now, its hot spot, and where the
# cracks start from; a plain arrow if it cannot be had
function Get-PointerImage {
    $img = $null
    $hot = New-Object 'int[]' 2
    $h = [SM]::PointerShape($hot)
    if ($h -ne [IntPtr]::Zero) {
        try {
            $ic  = [System.Drawing.Icon]::FromHandle($h)
            $img = $ic.ToBitmap()
            $ic.Dispose()
        } catch { $img = $null }
        [void][SM]::DestroyIcon($h)
    }
    $mid = if ($null -ne $img) { Get-PictureMiddle $img } else { $null }
    if ($null -eq $mid) {
        if ($null -ne $img) { $img.Dispose() }
        $img = New-ArrowImage
        $hot[0] = [int][Math]::Round(1.5 * $SC); $hot[1] = $hot[0]
        $mid = Get-PictureMiddle $img
        if ($null -eq $mid) { $mid = @(($img.Width / 3.0), ($img.Height / 2.0)) }
    }
    $PTR.img = $img; $PTR.hx = $hot[0]; $PTR.hy = $hot[1]
    $PTR.cx = [double]$mid[0]; $PTR.cy = [double]$mid[1]
}

# the middle of what can be seen of a picture; $null if there is hardly
# anything, or if it is solid all over (a pointer read back without its
# see-through parts)
function Get-PictureMiddle($img) {
    $w = $img.Width; $h = $img.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $px = New-Object 'int[]' ($w * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
    $img.UnlockBits($data)
    $step = [Math]::Max(1, [int]($w / 40))
    $n = 0; $all = 0; $mx = 0.0; $my = 0.0
    for ($y = 0; $y -lt $h; $y += $step) {
        for ($x = 0; $x -lt $w; $x += $step) {
            $all++
            if ((($px[$y * $w + $x] -shr 24) -band 0xFF) -gt 60) { $n++; $mx += $x; $my += $y }
        }
    }
    if ($n -lt 12 -or $n -gt 0.85 * $all) { return $null }
    , @(($mx / $n), ($my / $n))
}

# the plain white arrow with a black edge
function New-ArrowImage {
    $bmp = New-Object System.Drawing.Bitmap ([int][Math]::Ceiling(15 * $SC)), ([int][Math]::Ceiling(23 * $SC)), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.ScaleTransform([single]$SC, [single]$SC)
    $g.TranslateTransform([single]1.5, [single]1.5)
    $xy  = @(0, 0, 0, 16.5, 4, 12.6, 6.8, 19.2, 9.4, 18.1, 6.7, 11.7, 11.8, 11.7)
    $pts = New-Object 'System.Drawing.PointF[]' 7
    for ($i = 0; $i -lt 7; $i++) { $pts[$i] = New-Object System.Drawing.PointF ([single]$xy[2 * $i]), ([single]$xy[2 * $i + 1]) }
    $g.FillPolygon([System.Drawing.Brushes]::White, $pts)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), ([single]1.2)
    $pen.LineJoin = 'Round'
    $g.DrawPolygon($pen, $pts)
    $pen.Dispose(); $g.Dispose()
    return $bmp
}

# the top of whatever is under the spot where it broke: a window, a button, a
# shortcut, or the bottom of the screen
function Find-PieceFloor {
    $at  = New-Object System.Drawing.Point $PTR.x, $PTR.y
    $scr = [System.Windows.Forms.Screen]::FromPoint($at)
    $best = [double]$scr.WorkingArea.Bottom
    if ($best -lt $PTR.y + 12 * $SC) { $best = [double]$scr.Bounds.Bottom }    # it broke down on the taskbar
    foreach ($l in $S.ledges) {
        if ($l.Ground -or $l.Ink) { continue }
        if ($PTR.x -lt $l.L -or $PTR.x -gt $l.R) { continue }
        if ($l.T -gt $PTR.y + 12 * $SC -and $l.T -lt $best) { $best = $l.T }
    }
    return [Math]::Max($best, $PTR.y + 12 * $SC)
}

# the wreck window: wide enough for the pieces to scatter, and reaching down to
# where they land. Clicks go straight through it, to the shroud underneath.
$wreckForm = $null

function New-WreckWindow {
    $script:wreckForm = New-Object System.Windows.Forms.Form
    $wreckForm.FormBorderStyle = 'None'
    $wreckForm.ShowInTaskbar   = $false
    $wreckForm.StartPosition   = 'Manual'
    $wreckForm.Text            = 'Stickman wreck'
    $script:wreckIA   = New-Object System.Drawing.Imaging.ImageAttributes
    $script:wreckHalo = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([single](4 * $SC))
    $script:wreckRing = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 0, 153, 255)), ([single](2 * $SC))
    $h = $wreckForm.Handle
    # LAYERED | TRANSPARENT (clicks fall through) | TOOLWINDOW | NOACTIVATE
    [void][SM]::SetWindowLong($h, -20, ([SM]::GetExStyle($h) -bor 0x00080000 -bor 0x00000020 -bor 0x00000080 -bor 0x08000000))
}

function Open-Wreck {
    if ($null -eq $wreckForm) { New-WreckWindow }
    $half = [int](170 * $SC)
    $PTR.floor = Find-PieceFloor
    $PTR.wx = $PTR.x - $half; $PTR.ww = 2 * $half
    $PTR.wy = $PTR.y - [int](110 * $SC)
    $PTR.wh = [int][Math]::Ceiling($PTR.floor - $PTR.wy + 6 * $SC)
    $PTR.bmp = New-Object System.Drawing.Bitmap ($PTR.ww), ($PTR.wh), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $PTR.g = [System.Drawing.Graphics]::FromImage($PTR.bmp)
    $PTR.g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $PTR.brush = New-Object System.Drawing.TextureBrush ($PTR.img), ([System.Drawing.Drawing2D.WrapMode]::Clamp)
}

# The picture cut into wedges from the middle out. Each is a triangle far
# bigger than the pointer, so between them they cover all of it, and filled
# with the picture it shows just its own piece.
function New-Shards {
    foreach ($sh in $PTR.shards) { $sh.Path.Dispose() }
    $PTR.shards.Clear()
    $img  = $PTR.img
    $far  = 2.0 * ($img.Width + $img.Height)
    $step = 2 * [Math]::PI / $SHARDS
    $a0   = $RNG.NextDouble() * $step
    $cuts = New-Object 'double[]' $SHARDS
    for ($i = 0; $i -lt $SHARDS; $i++) { $cuts[$i] = $a0 + $i * $step + ($RNG.NextDouble() - 0.5) * 0.5 * $step }
    $left = $PTR.x - $PTR.hx; $top = $PTR.y - $PTR.hy          # where the picture sits on screen
    $pr   = 0.18 * [Math]::Min($img.Width, $img.Height)
    for ($i = 0; $i -lt $SHARDS; $i++) {
        $a = $cuts[$i]
        $b = if ($i + 1 -lt $SHARDS) { $cuts[$i + 1] } else { $cuts[0] + 2 * [Math]::PI }
        $m = ($a + $b) / 2.0
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddPolygon([System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF ([single]$PTR.cx), ([single]$PTR.cy)),
            (New-Object System.Drawing.PointF ([single]($PTR.cx + [Math]::Cos($a) * $far)), ([single]($PTR.cy + [Math]::Sin($a) * $far))),
            (New-Object System.Drawing.PointF ([single]($PTR.cx + [Math]::Cos($b) * $far)), ([single]($PTR.cy + [Math]::Sin($b) * $far)))))
        $px = $PTR.cx + [Math]::Cos($m) * $pr
        $py = $PTR.cy + [Math]::Sin($m) * $pr
        [void]$PTR.shards.Add(@{
            Path = $path
            PX = $px; PY = $py                          # what it turns about, in the picture
            DX = [Math]::Cos($m); DY = [Math]::Sin($m)  # which way it faces out from the middle
            HX = $left + $px; HY = $top + $py           # home: where that sits with the pointer whole
            X = $left + $px; Y = $top + $py; VX = 0.0; VY = 0.0; Rot = 0.0; VR = 0.0; Rest = $false
            SX = 0.0; SY = 0.0; SR = 0.0                # where it set off from, mending
        })
    }
}

# the moment it bursts: a spark, and every piece goes flying, out from the
# middle and on the way the blow was going
function Burst-Pointer {
    Pop-Spark $PTR.x $PTR.y
    $kl = [Math]::Max(1.0, [Math]::Sqrt($PTR.kx * $PTR.kx + $PTR.ky * $PTR.ky))
    foreach ($sh in $PTR.shards) {
        $v = (2.5 + 3.5 * $RNG.NextDouble()) * $SC
        $sh.VX = $sh.DX * $v * 0.8 + $PTR.kx / $kl * 2.5 * $SC
        $sh.VY = $sh.DY * $v - (2.5 + 2.0 * $RNG.NextDouble()) * $SC + $PTR.ky / $kl * 1.5 * $SC
        $sh.VR = ($RNG.NextDouble() * 2 - 1) * 16.0
    }
}

# one piece, one frame, flying or bouncing; $false once it lies still
function Step-Shard($sh) {
    if ($sh.Rest) { return $false }
    $sh.VY += $SHARD_GRAV
    $sh.VX *= 0.96
    $sh.X  += $sh.VX; $sh.Y += $sh.VY
    $sh.Rot += $sh.VR
    $lo = $PTR.floor - 2 * $SC
    if ($sh.Y -gt $lo) {
        $sh.Y = $lo
        $sh.VY = if ($sh.VY -gt 3 * $SC) { -$sh.VY * 0.4 } else { 0.0 }
        $sh.VX *= 0.6; $sh.VR *= 0.6
        if ($sh.VY -eq 0.0 -and [Math]::Abs($sh.VX) -lt 0.3 * $SC) { $sh.Rest = $true }
    }
    # the edges of the wreck window hold them in
    $edge = 6 * $SC
    if ($sh.X -lt $PTR.wx + $edge) { $sh.X = $PTR.wx + $edge; $sh.VX = [Math]::Abs($sh.VX) * 0.4 }
    elseif ($sh.X -gt $PTR.wx + $PTR.ww - $edge) { $sh.X = $PTR.wx + $PTR.ww - $edge; $sh.VX = -[Math]::Abs($sh.VX) * 0.4 }
    if ($sh.Y -lt $PTR.wy + $edge) { $sh.Y = $PTR.wy + $edge; $sh.VY = [Math]::Abs($sh.VY) * 0.3 }
    return $true
}

function Start-Mend {
    $PTR.mend = $true; $PTR.mt = 0
    foreach ($sh in $PTR.shards) {
        $sh.SX = $sh.X; $sh.SY = $sh.Y
        $r = $sh.Rot % 360.0                        # the short way back round to upright
        if ($r -gt 180) { $r -= 360 } elseif ($r -lt -180) { $r += 360 }
        $sh.SR = $r
    }
}

# every frame it is in pieces
function Step-Wreck {
    $PTR.t++
    if ($PTR.t -gt $DEAD_LEN + 300) { Restore-Pointer; return }    # never stuck like this
    # it stays where it broke, unless you are holding a button down
    if (-not (Test-MouseHeld)) {
        $c = [System.Windows.Forms.Cursor]::Position
        if ($c.X -ne $PTR.x -or $c.Y -ne $PTR.y) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $PTR.x, $PTR.y
        }
    }
    # the shroud blanks it whenever Windows asks, but asks late while this
    # thread is busy, so it is blanked again every frame as well
    [System.Windows.Forms.Cursor]::Current = $blankCursor
    if ($PTR.t -lt $CRACK_LEN) { Draw-Wreck; return }
    if ($PTR.t -eq $CRACK_LEN) { Burst-Pointer }

    if (-not $PTR.mend) {
        if ($PTR.t -ge $DEAD_LEN -or ($PTR.hurry -and $PTR.t -ge $CRACK_LEN + 24)) {
            Start-Mend
        } else {
            $moving = $false
            foreach ($sh in $PTR.shards) { if (Step-Shard $sh) { $moving = $true } }
            if ($moving) { Draw-Wreck }
            return
        }
    }
    $PTR.mt++
    Draw-Wreck
    if ($PTR.mt -ge $SHIVER_LEN + $REJOIN_LEN + $GLOW_LEN) { Restore-Pointer }
}

# where a piece is drawn this frame: x, y on screen, and its turn in degrees
function Get-ShardPose($sh) {
    if ($PTR.t -lt $CRACK_LEN) {
        # still in one piece, but the cracks are opening and it shakes
        $gap = [Math]::Pow($PTR.t / [double]$CRACK_LEN, 2) * 1.6 * $SC
        $j = $(if ($PTR.t % 2 -eq 0) { 1 } else { -1 }) * 0.8 * $SC
        return , @(($sh.HX + $sh.DX * $gap + $j), ($sh.HY + $sh.DY * $gap), 0.0)
    }
    if (-not $PTR.mend) { return , @($sh.X, $sh.Y, $sh.Rot) }
    if ($PTR.mt -le $SHIVER_LEN) {
        $j = 1.2 * $SC
        return , @(($sh.SX + ($RNG.NextDouble() * 2 - 1) * $j), ($sh.SY + ($RNG.NextDouble() * 2 - 1) * $j),
                   ($sh.SR + ($RNG.NextDouble() * 2 - 1) * 6))
    }
    # home on an arc, easing in and out, turning upright as it goes
    $u = [Math]::Min(1.0, ($PTR.mt - $SHIVER_LEN) / [double]$REJOIN_LEN)
    $e = $u * $u * (3 - 2 * $u)
    $lift = [Math]::Sin($u * [Math]::PI) * 36 * $SC
    return , @(($sh.SX + ($sh.HX - $sh.SX) * $e), ($sh.SY + ($sh.HY - $sh.SY) * $e - $lift), ($sh.SR * (1 - $e)))
}

function Draw-Wreck {
    $g = $PTR.g
    $g.ResetTransform()
    $g.Clear([System.Drawing.Color]::Transparent)
    $glow = if ($PTR.mend) { $PTR.mt - $SHIVER_LEN - $REJOIN_LEN } else { -1 }
    if ($glow -ge 0) {
        Draw-Mended $g $glow
    } else {
        foreach ($sh in $PTR.shards) {
            $at = Get-ShardPose $sh
            $g.ResetTransform()
            $g.TranslateTransform([single]($at[0] - $PTR.wx), [single]($at[1] - $PTR.wy))
            $g.RotateTransform([single]$at[2])
            $g.TranslateTransform([single](-$sh.PX), [single](-$sh.PY))
            $g.FillPath($PTR.brush, $sh.Path)
        }
    }
    $hb = $PTR.bmp.GetHbitmap([System.Drawing.Color]::FromArgb(0))
    [SM]::Blit($wreckForm.Handle, $hb, [int]$PTR.wx, [int]$PTR.wy, [int]$PTR.ww, [int]$PTR.wh)
    [void][SM]::DeleteObject($hb)
}

# whole again: it flashes blue-white and fades back to itself, and a ring
# goes out from it
function Draw-Mended($g, $n) {
    $k = 1.0 - $n / [double]$GLOW_LEN
    $cm = New-Object System.Drawing.Imaging.ColorMatrix
    $cm.Matrix00 = [single](1 - $k); $cm.Matrix11 = [single](1 - $k); $cm.Matrix22 = [single](1 - $k)
    $cm.Matrix40 = [single](0.55 * $k); $cm.Matrix41 = [single](0.8 * $k); $cm.Matrix42 = [single]$k
    $wreckIA.SetColorMatrix($cm)
    $img = $PTR.img
    $ix = [int]($PTR.x - $PTR.hx - $PTR.wx); $iy = [int]($PTR.y - $PTR.hy - $PTR.wy)
    $g.ResetTransform()
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle $ix, $iy, $img.Width, $img.Height),
        0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $wreckIA)
    $r  = (6 + 34 * (1 - $k)) * $SC
    $mx = $ix + $PTR.cx; $my = $iy + $PTR.cy
    $a  = [int](255 * $k)
    $wreckHalo.Color = [System.Drawing.Color]::FromArgb($a, 255, 255, 255)
    $wreckRing.Color = [System.Drawing.Color]::FromArgb($a, 0, 153, 255)
    foreach ($pen in @($wreckHalo, $wreckRing)) {
        $g.DrawEllipse($pen, [single]($mx - $r), [single]($my - $r), [single](2 * $r), [single](2 * $r))
    }
}

# whole again, and yours: full strength, right where it broke
function Restore-Pointer {
    if (-not $PTR.dead) { return }
    $PTR.dead = $false; $PTR.mend = $false
    Hide-Shroud                             # first, whatever else goes wrong
    if ($null -ne $wreckForm) { [void][SM]::SetWindowPos($wreckForm.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0097) }
    if (-not (Test-MouseHeld)) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ($PTR.x + 1), $PTR.y
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point $PTR.x, $PTR.y
    }
    $PTR.hp = $PTR.max; $PTR.shown = 0.0; $PTR.bar = $BAR_SHOW     # the bar fills back up
    $F.kn = 0
    foreach ($sh in $PTR.shards) { $sh.Path.Dispose() }
    $PTR.shards.Clear()
    foreach ($o in @($PTR.brush, $PTR.g, $PTR.bmp, $PTR.img)) { if ($null -ne $o) { $o.Dispose() } }
    $PTR.brush = $null; $PTR.g = $null; $PTR.bmp = $null; $PTR.img = $null
    if ($S.state -in @('win', 'shock')) { $S.state = 'taunt'; $S.timer = 50; $S.phase = 0.0 }
}

# The shroud. Alpha 1 all over: you cannot see it, but it catches every click,
# and over it the pointer is a blank one. Made the first time it is needed.
$shroudForm = $null

function New-Shroud {
    $script:shroudForm = New-Object System.Windows.Forms.Form
    $shroudForm.FormBorderStyle = 'None'
    $shroudForm.ShowInTaskbar   = $false
    $shroudForm.StartPosition   = 'Manual'
    $shroudForm.Text            = 'Stickman shroud'
    $shroudForm.BackColor       = [System.Drawing.Color]::Black
    $blank = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bg = [System.Drawing.Graphics]::FromImage($blank)
    $bg.Clear([System.Drawing.Color]::Transparent)
    $bg.Dispose()
    $script:blankCursor = New-Object System.Windows.Forms.Cursor ($blank.GetHicon())
    $blank.Dispose()
    $shroudForm.Cursor = $blankCursor
    $h = $shroudForm.Handle
    # LAYERED | TOOLWINDOW | NOACTIVATE, and not TRANSPARENT: catching clicks is its job
    [void][SM]::SetWindowLong($h, -20, ([SM]::GetExStyle($h) -bor 0x00080000 -bor 0x00000080 -bor 0x08000000))
    [SM]::Veil($h)
    $shroudForm.Add_MouseDown({ $PTR.hurry = $true })
}

function Show-Shroud {
    if ($null -eq $shroudForm) { New-Shroud }
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    # TOPMOST, over every screen: SHOWWINDOW | NOACTIVATE
    [void][SM]::SetWindowPos($shroudForm.Handle, [IntPtr](-1), $vs.Left, $vs.Top, $vs.Width, $vs.Height, 0x0050)
}

function Hide-Shroud {
    if ($null -eq $shroudForm) { return }
    [void][SM]::SetWindowPos($shroudForm.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0097)   # HIDE | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
}

# The pointer's bar, just under it, for a moment after each hit: blue, going
# red when it is nearly done for. Made the first time it is needed.
$PBW = [int][Math]::Round(34 * $SC)
$PBH = [int][Math]::Round(6 * $SC)
$barForm = $null

function New-BarWindow {
    $script:barForm = New-Object System.Windows.Forms.Form
    $barForm.FormBorderStyle = 'None'
    $barForm.ShowInTaskbar   = $false
    $barForm.StartPosition   = 'Manual'
    $barForm.Text            = 'Stickman pointer bar'
    $script:barBmp  = New-Object System.Drawing.Bitmap $PBW, $PBH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $script:barG    = [System.Drawing.Graphics]::FromImage($barBmp)
    $script:barHalo = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $script:barBack = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)
    $script:barFill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $h = $barForm.Handle
    # LAYERED | TRANSPARENT (clicks fall through) | TOOLWINDOW | NOACTIVATE
    [void][SM]::SetWindowLong($h, -20, ([SM]::GetExStyle($h) -bor 0x00080000 -bor 0x00000020 -bor 0x00000080 -bor 0x08000000))
}

function Draw-PtrBar {
    if ($null -eq $barForm) { New-BarWindow }
    if (--$PTR.bar -le 0 -or $PTR.dead -or -not $F.on) { $PTR.bar = 0; Hide-PtrBar; return }
    $PTR.shown += ($PTR.hp - $PTR.shown) * 0.2
    $a   = [int](255 * [Math]::Min(1.0, $PTR.bar / 12.0))          # it fades at the end
    $low = $PTR.hp -le $PTR.max * 0.34
    $barHalo.Color = [System.Drawing.Color]::FromArgb($a, 255, 255, 255)
    $barBack.Color = if ($low) { [System.Drawing.Color]::FromArgb($a, 90, 24, 24) } else { [System.Drawing.Color]::FromArgb($a, 16, 48, 84) }
    $barFill.Color = if ($low) { [System.Drawing.Color]::FromArgb($a, 232, 52, 52) } else { [System.Drawing.Color]::FromArgb($a, 0, 153, 255) }
    $bd = [single]$SC
    $iw = [single]($PBW - 2 * $SC); $ih = [single]($PBH - 2 * $SC)
    $barG.Clear([System.Drawing.Color]::Transparent)
    $barG.FillRectangle($barHalo, [single]0, [single]0, [single]$PBW, [single]$PBH)
    $barG.FillRectangle($barBack, $bd, $bd, $iw, $ih)
    $barG.FillRectangle($barFill, $bd, $bd, [single]($iw * [Math]::Max(0.0, $PTR.shown) / $PTR.max), $ih)
    $c  = [System.Windows.Forms.Cursor]::Position
    $h  = $barForm.Handle
    $hb = $barBmp.GetHbitmap([System.Drawing.Color]::FromArgb(0))
    [SM]::Blit($h, $hb, [int]($c.X - 11 * $SC), [int]($c.Y + 24 * $SC), $PBW, $PBH)
    [void][SM]::DeleteObject($hb)
    [void][SM]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0053)     # TOPMOST, SHOW | NOACTIVATE | NOMOVE | NOSIZE
}

function Hide-PtrBar {
    if ($null -eq $barForm) { return }
    [void][SM]::SetWindowPos($barForm.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0097)
}

# ----------------------------------------------------------- convert to symbol
# Hidden names. Call the symbol after one of Alan Becker's stick figures and he
# becomes it: he takes its colour and does the thing that figure is known for.
$EGG_INK = [System.Drawing.Color]::FromArgb(255, 24, 24, 28)   # his own ink
$EGGS = @{
    'victim'       = @{ Name = 'The Victim';       R =  20; G =  20; B =  26; Act = 'launch' }
    'chosenone'    = @{ Name = 'The Chosen One';   R =  40; G =  46; B =  64; Act = 'launch' }
    'tco'          = @{ Name = 'The Chosen One';   R =  40; G =  46; B =  64; Act = 'launch' }
    'chosen'       = @{ Name = 'The Chosen One';   R =  40; G =  46; B =  64; Act = 'launch' }
    'darklord'     = @{ Name = 'The Dark Lord';    R =  58; G =  30; B =  74; Act = 'chase'  }
    'dark'         = @{ Name = 'The Dark Lord';    R =  58; G =  30; B =  74; Act = 'chase'  }
    'secondcoming' = @{ Name = 'The Second Coming';R = 247; G = 148; B =  29; Act = 'cheer'  }
    'tsc'          = @{ Name = 'The Second Coming';R = 247; G = 148; B =  29; Act = 'cheer'  }
    'orange'       = @{ Name = 'The Second Coming';R = 247; G = 148; B =  29; Act = 'cheer'  }
    'red'          = @{ Name = 'Red';              R = 224; G =  49; B =  49; Act = 'launch' }
    'green'        = @{ Name = 'Green';            R =  47; G = 158; B =  68; Act = 'wave'   }
    'blue'         = @{ Name = 'Blue';             R =  28; G = 126; B = 214; Act = 'chase'  }
    'yellow'       = @{ Name = 'Yellow';           R = 240; G = 180; B =  20; Act = 'cheer'  }
    'purple'       = @{ Name = 'Purple';           R = 146; G =  58; B = 190; Act = 'wave'   }
    'alanbecker'   = @{ Name = 'Alan Becker';      R =  60; G =  60; B =  66; Act = 'wave'   }
    'alan'         = @{ Name = 'Alan Becker';      R =  60; G =  60; B =  66; Act = 'wave'   }
    'becker'       = @{ Name = 'Alan Becker';      R =  60; G =  60; B =  66; Act = 'wave'   }
    'animator'     = @{ Name = 'Alan Becker';      R =  60; G =  60; B =  66; Act = 'wave'   }
    'noogai'       = @{ Name = 'Alan Becker';      R =  60; G =  60; B =  66; Act = 'wave'   }
}

# the names offered in the dialog as you type, so you do not have to guess
$EGG_NAMES = [string[]]($EGGS.Values | ForEach-Object { $_.Name } | Sort-Object -Unique)

# 'The Second Coming', 'second coming' and 'TSC' all have to land on one key.
# Case, spaces, punctuation and a leading 'the' are thrown away first, and if
# that still misses, a name with the character buried in it counts too, so
# 'red guy', 'chosen one 2' and 'blue stickman' all find their figure.
function Find-Egg($name) {
    $k = ([string]$name).ToLower() -replace '[^a-z0-9]', ''
    if ($k -eq '') { return $null }
    $k = $k -replace '^the', ''
    if ($EGGS.ContainsKey($k)) { return $EGGS[$k] }
    foreach ($key in ($EGGS.Keys | Sort-Object -Property Length -Descending)) {
        if ($k.Contains($key)) { return $EGGS[$key] }
    }
    return $null
}

# he takes the colour at once, and his move is queued for the moment he is back
# on something solid - see the pending block in Step-Physics
function Apply-Egg($egg) {
    $S.char    = $egg.Name
    $S.ink     = [System.Drawing.Color]::FromArgb(255, $egg.R, $egg.G, $egg.B)
    $S.pending = $egg.Act
    $S.pendTTL = 400
}

# the moves themselves, each one built only out of states the rest of the
# script already knows how to get back out of
function Do-EggAct($act) {
    switch ($act) {
        'cheer'  { $S.state = 'cheer'; $S.timer = 90; $S.cool = 180; $S.phase = 0.0 }
        'wave'   { $S.state = 'wave';  $S.timer = 90; $S.cool = 180; $S.phase = 0.0 }
        'launch' {
            $S.drag  = $false
            $S.state = 'fall'
            $S.vy    = -14.0 * $SC
            $S.vx    = $RNG.Next(-3, 4) * $SC
        }
        'chase'  {
            $c = [System.Windows.Forms.Cursor]::Position
            $S.tx    = [double]$c.X
            $S.ty    = [double]$c.Y
            $S.chase = 300
            $S.state = 'chase'
            $S.phase = 0.0
            $S.chasePeer = -1
            if ($c.X -ne $S.x) { $S.dir = [Math]::Sign($c.X - $S.x) }
        }
    }
}

# A small stand-in for Flash's F8 dialog: a name, a symbol type and the 3x3
# registration grid. Returns a hashtable, or $null if you cancelled.
function Show-SymbolDialog {
    $U = { param($n) [int][Math]::Round($n * $SC) }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Convert to Symbol'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.ShowInTaskbar   = $false
    $dlg.TopMost         = $true
    $dlg.ClientSize      = New-Object System.Drawing.Size (& $U 344), (& $U 254)

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text     = 'Name:'
    $lblName.AutoSize = $true
    $lblName.Location = New-Object System.Drawing.Point (& $U 16), (& $U 20)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location  = New-Object System.Drawing.Point (& $U 104), (& $U 16)
    $txtName.Size      = New-Object System.Drawing.Size (& $U 224), (& $U 22)
    $txtName.MaxLength = 24
    $txtName.Text      = "Symbol $($S.symNum)"
    # start typing a figure's name and the rest of it is offered
    $ac = New-Object System.Windows.Forms.AutoCompleteStringCollection
    [void]$ac.AddRange($EGG_NAMES)
    $txtName.AutoCompleteCustomSource = $ac
    $txtName.AutoCompleteSource       = 'CustomSource'
    $txtName.AutoCompleteMode         = 'SuggestAppend'

    $lblType = New-Object System.Windows.Forms.Label
    $lblType.Text     = 'Type:'
    $lblType.AutoSize = $true
    $lblType.Location = New-Object System.Drawing.Point (& $U 16), (& $U 56)

    $cmbType = New-Object System.Windows.Forms.ComboBox
    $cmbType.DropDownStyle = 'DropDownList'
    $cmbType.Location = New-Object System.Drawing.Point (& $U 104), (& $U 52)
    $cmbType.Size     = New-Object System.Drawing.Size (& $U 140), (& $U 22)
    [void]$cmbType.Items.AddRange(@('Movie Clip', 'Button', 'Graphic'))
    $cmbType.SelectedIndex = [Math]::Max(0, $cmbType.Items.IndexOf($S.symType))

    $lblReg = New-Object System.Windows.Forms.Label
    $lblReg.Text     = 'Registration:'
    $lblReg.AutoSize = $true
    $lblReg.Location = New-Object System.Drawing.Point (& $U 16), (& $U 96)

    $regPanel = New-Object System.Windows.Forms.Panel
    $regPanel.Location    = New-Object System.Drawing.Point (& $U 104), (& $U 88)
    $regPanel.Size        = New-Object System.Drawing.Size (& $U 56), (& $U 56)
    $regPanel.BorderStyle = 'FixedSingle'

    $regBtns = @()
    for ($i = 0; $i -lt 9; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Appearance = 'Button'
        $rb.Size       = New-Object System.Drawing.Size (& $U 17), (& $U 17)
        $rb.Location   = New-Object System.Drawing.Point (& $U (1 + ($i % 3) * 18)), (& $U (1 + [Math]::Floor($i / 3) * 18))
        $rb.Tag        = $i
        $rb.TabStop    = $false
        $regPanel.Controls.Add($rb)
        $regBtns += $rb
    }
    $regBtns[[Math]::Min(8, [Math]::Max(0, $S.symReg))].Checked = $true

    # Animator vs. Animation, with your pointer as the animator (see Start-Fight)
    $chkFight = New-Object System.Windows.Forms.CheckBox
    $chkFight.Text     = 'Fight mode'
    $chkFight.AutoSize = $true
    $chkFight.Location = New-Object System.Drawing.Point (& $U 176), (& $U 90)
    $chkFight.Checked  = $F.on

    # the same fight, far harder (see $LEVELS)
    $chkHard = New-Object System.Windows.Forms.CheckBox
    $chkHard.Text     = 'Hard mode'
    $chkHard.AutoSize = $true
    $chkHard.Location = New-Object System.Drawing.Point (& $U 176), (& $U 112)
    $chkHard.Checked  = $S.hard
    $chkHard.Enabled  = $chkFight.Checked
    $chkFight.Add_CheckedChanged({ $chkHard.Enabled = $chkFight.Checked })

    $lblFight = New-Object System.Windows.Forms.Label
    $lblFight.Text      = 'He fights your pointer: grabs it, drags it off, throws windows at it (they go back after). Click him to hit back, Esc stops it.'
    $lblFight.ForeColor = [System.Drawing.SystemColors]::GrayText
    $lblFight.Location  = New-Object System.Drawing.Point (& $U 176), (& $U 134)
    $lblFight.Size      = New-Object System.Drawing.Size (& $U 160), (& $U 72)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text         = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location     = New-Object System.Drawing.Point (& $U 168), (& $U 218)
    $ok.Size         = New-Object System.Drawing.Size (& $U 76), (& $U 26)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text         = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location     = New-Object System.Drawing.Point (& $U 252), (& $U 218)
    $cancel.Size         = New-Object System.Drawing.Size (& $U 76), (& $U 26)

    $dlg.Controls.AddRange(@($lblName, $txtName, $lblType, $cmbType, $lblReg, $regPanel, $chkFight, $chkHard, $lblFight, $ok, $cancel))
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Add_Shown({ $dlg.Activate(); $txtName.SelectAll(); $txtName.Focus() })

    $res  = $dlg.ShowDialog()
    $name = $txtName.Text.Trim()
    $type = [string]$cmbType.SelectedItem
    $reg  = [int]($regBtns | Where-Object { $_.Checked } | Select-Object -First 1).Tag
    $fight = $chkFight.Checked
    $hard  = $chkHard.Checked
    $dlg.Dispose()

    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    if ($name -eq '') { $name = "Symbol $($S.symNum)" }
    return @{ name = $name; type = $type; reg = $reg; fight = $fight; hard = $hard }
}

# keeps the menu entries and the tray tooltip in step with what he currently is
function Sync-SymbolItem {
    $moving = $null -ne $script:heir            # starting up in his new process
    $symItem.Enabled   = -not $moving
    $breakItem.Enabled = $S.symbol -and -not $moving
    $fightItem.Visible = $F.on
    if ($S.symbol) {
        $symItem.ToolTipText = "He is the symbol '$($S.symName)' ($($S.symType)). Converting again just swaps him."
        $tray.Text           = if ($S.char) { "Desktop Stickman - $($S.char)" }
                               else         { "Desktop Stickman - $($S.symName)" }
    } else {
        $symItem.ToolTipText = 'Wraps him in a symbol box with a registration point, the way F8 does in Flash.'
        $tray.Text           = 'Desktop Stickman'
    }
    if ($F.on) { $tray.Text += $(if ($S.hard) { ' (fighting, hard)' } else { ' (fighting)' }) }
}

# ------------------------------------------------------------------ interaction
$shoveItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him push windows'
$shoveItem.CheckOnClick = $true
$shoveItem.Checked = $true
$shoveItem.Add_Click({ $S.shove = $shoveItem.Checked })

$whiteItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him stand on anything white'
$whiteItem.CheckOnClick = $true
$whiteItem.Checked = $true
$whiteItem.Add_Click({ [Ink]::White = $whiteItem.Checked })

$clickItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him really press buttons'
$clickItem.CheckOnClick = $true
$clickItem.Checked = $false
$clickItem.ToolTipText = 'Off by default: when on, standing on a button actually clicks it.'
$clickItem.Add_Click({ $S.click = $clickItem.Checked })

$openItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him open desktop shortcuts'
$openItem.CheckOnClick = $true
$openItem.Checked = $true
$openItem.ToolTipText = 'When he stamps on a shortcut it launches, at most once every 45 seconds.'
$openItem.Add_Click({ $S.open = $openItem.Checked })

$throwItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him throw windows in a fight'
$throwItem.CheckOnClick = $true
$throwItem.Checked = $true
$throwItem.ToolTipText = 'In fight mode he throws windows at your pointer. They are only moved, never closed, and go back where they were when the fight ends.'
$throwItem.Add_Click({ $S.throw = $throwItem.Checked })

$grabItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him grab the pointer in a fight'
$grabItem.CheckOnClick = $true
$grabItem.Checked = $true
$grabItem.ToolTipText = 'In fight mode he grabs your pointer and drags it off. Wiggle the mouse hard or click him to get it back; he never clicks anything.'
$grabItem.Add_Click({ $S.grabPtr = $grabItem.Checked; if (-not $S.grabPtr) { Release-Pointer } })

$killItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Let him break the pointer in a fight'
$killItem.CheckOnClick = $true
$killItem.Checked = $true
$killItem.ToolTipText = 'In fight mode the pointer has hits too (the bar under it). When they run out he smashes it and celebrates, and a few seconds later it mends itself. Click to mend it sooner; Esc ends the fight.'
$killItem.Add_Click({ $S.killPtr = $killItem.Checked })

$hardItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Hard mode'
$hardItem.CheckOnClick = $true
$hardItem.Checked = $false
$hardItem.ToolTipText = 'A much harder fight: he takes 20 hits instead of 8, blocks, gets back up once, attacks faster, dodges more, throws more windows, and your pointer breaks after 6 hits. Can be switched mid-fight.'
$hardItem.Add_Click({ Set-Hard $hardItem.Checked })

# wraps him in the symbol the dialog came back with
function Convert-Symbol($r) {
    $S.symbol   = $true
    $S.symType  = $r.type
    $S.symReg   = $r.reg
    $S.char     = ''
    $S.ink      = $null
    $S.symNum++

    $egg = Find-Egg $r.name
    if ($null -ne $egg) {
        Apply-Egg $egg
        $S.symName = $egg.Name              # 'tsc' fills itself in properly
        $S.symFlashMax = 26                 # a longer flash, in his new colour
    } else {
        $S.symName = $r.name
        $S.symFlashMax = 14
    }
    $S.symFlash = $S.symFlashMax
    if ($null -ne $r.hard) { Set-Hard $r.hard }
    if ($r.fight) { Start-Fight } elseif ($F.on) { End-Fight }
    Sync-SymbolItem
}

function Break-Symbol {
    $S.symbol      = $false
    $S.char        = ''
    $S.ink         = $null
    $S.pending     = ''
    $S.symFlashMax = 8
    $S.symFlash    = 8
    if ($F.on) { End-Fight }
    Sync-SymbolItem
}

# $sym is what the dialog came back with, or $null to break him apart
function Set-Look($sym) { if ($null -eq $sym) { Break-Symbol } else { Convert-Symbol $sym } }

# the name Task Manager should list him under once $sym is applied: the
# symbol's name (in full, for one of the hidden figures), or 'Stick figure'
function Get-BodyName($sym) {
    if ($null -eq $sym) { return $PLAIN }
    $egg = Find-Egg $sym.name
    if ($null -ne $egg) { return $egg.Name }
    return $sym.name
}

# Converting or breaking apart: start him up in the exe for his new name and
# let that copy apply $sym, carrying over where he is and how he is set up.
# This one keeps going until the new one is on screen (see Test-Heir).
$heir = $null
function Switch-Body($sym) {
    $exe = Get-Body (Get-BodyName $sym)
    if ($null -eq $exe -or $exe -eq $MYEXE) { Set-Look $sym; return }   # already the right name
    $h = @{
        from   = $PID
        shove  = $S.shove; white = [Ink]::White; click = $S.click; open = $S.open; throw = $S.throw
        grab   = $S.grabPtr
        kill   = $S.killPtr
        hard   = $S.hard
        symNum = $S.symNum
        sym    = $sym
        unwrap = ($null -eq $sym)
    }
    $arg = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($h | ConvertTo-Json -Compress)))
    try { $p = Start-Process -FilePath $exe -ArgumentList '-Handoff', $arg -PassThru -ErrorAction Stop }
    catch { Set-Look $sym; return }
    $script:heir = @{ Proc = $p; Wait = 0; Sym = $sym }
    Sync-SymbolItem                             # one move at a time
}

# checked every frame while he is moving: $true once the new copy has drawn
# him. If it dies or never turns up, he stays in this process instead.
function Test-Heir {
    $h = $script:heir
    foreach ($p in [Peers]::Others()) {
        if ($p.Pid -eq $h.Proc.Id -and ($p.X -ne 0 -or $p.Y -ne 0)) { return $true }
    }
    $h.Wait++
    if ($h.Proc.HasExited -or $h.Wait -gt 700) {         # about 20 seconds
        "$(Get-Date -Format s)  his new process never showed up, staying in this one" |
            Out-File -FilePath $errLog -Append -Encoding utf8
        try { if (-not $h.Proc.HasExited) { $h.Proc.Kill() } } catch { }
        $script:heir = $null
        Set-Look $h.Sym
    }
    return $false
}

# picks up where the copy that started this one left off (see Switch-Body)
function Restore-Handoff {
    foreach ($p in [Peers]::Others()) {
        if ($p.Pid -eq $INHERIT.from) {
            $S.x = [double]$p.X; $S.y = [double]$p.Y
            if ($p.Dir -ne 0) { $S.dir = $p.Dir }
        }
    }
    $S.shove = [bool]$INHERIT.shove;  $shoveItem.Checked = $S.shove
    [Ink]::White = [bool]$INHERIT.white; $whiteItem.Checked = [Ink]::White
    $S.click = [bool]$INHERIT.click;  $clickItem.Checked = $S.click
    $S.open  = [bool]$INHERIT.open;   $openItem.Checked  = $S.open
    if ($null -ne $INHERIT.throw) { $S.throw = [bool]$INHERIT.throw; $throwItem.Checked = $S.throw }
    if ($null -ne $INHERIT.grab)  { $S.grabPtr = [bool]$INHERIT.grab; $grabItem.Checked = $S.grabPtr }
    if ($null -ne $INHERIT.kill)  { $S.killPtr = [bool]$INHERIT.kill; $killItem.Checked = $S.killPtr }
    if ($null -ne $INHERIT.hard)  { Set-Hard $INHERIT.hard }
    $S.symNum = [int]$INHERIT.symNum
    if ($null -ne $INHERIT.sym) { Convert-Symbol $INHERIT.sym }
    elseif ($INHERIT.unwrap)    { Break-Symbol }
}

$symItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Convert to Symbol...'
$symItem.ToolTipText = 'Wraps him in a symbol box with a registration point, the way F8 does in Flash.'
$symItem.Add_Click({
    $r = Show-SymbolDialog
    if ($null -ne $r) { Switch-Body $r }
})

# converting again while he already is one just swaps the figure, so this is
# the only way back to his plain self
$breakItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Break apart'
$breakItem.Enabled     = $false
$breakItem.ToolTipText = 'Unwraps the symbol and gives him his own ink back.'
$breakItem.Add_Click({ Switch-Body $null })

$fightItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Stop the fight'
$fightItem.Visible     = $false
$fightItem.ToolTipText = 'Ends fight mode. Esc does the same.'
$fightItem.Add_Click({ End-Fight })

$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Toss in the air', $null, {
    $S.drag  = $false
    $S.state = 'fall'
    $S.vy    = -13.0 * $SC
    $S.vx    = $RNG.Next(-3, 4) * $SC
})
[void]$menu.Items.Add($shoveItem)
[void]$menu.Items.Add($whiteItem)
[void]$menu.Items.Add($clickItem)
[void]$menu.Items.Add($openItem)
[void]$menu.Items.Add($throwItem)
[void]$menu.Items.Add($grabItem)
[void]$menu.Items.Add($killItem)
[void]$menu.Items.Add($hardItem)
[void]$menu.Items.Add('-')
[void]$menu.Items.Add($symItem)
[void]$menu.Items.Add($breakItem)
[void]$menu.Items.Add($fightItem)
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Add another stickman', $null, {
    $exe = Get-Body $PLAIN
    if ($null -ne $exe) { Start-Process -FilePath $exe; return }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$SELF`"")
})
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Quit', $null, { $form.Close() })
[void]$menu.Items.Add('Quit all stickmen', $null, { [Peers]::QuitAll(); $form.Close() })
$menu.ShowItemToolTips = $true
# not $form.ContextMenuStrip: his window is NOACTIVATE, so it never becomes the
# foreground window and WinForms shuts the menu the moment it opens. Pull him
# to the front first, then show it by hand.

$form.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $c = [System.Windows.Forms.Cursor]::Position
        $S.grabX = $c.X - ($S.x - $CX)
        $S.grabY = $c.Y - ($S.y - $FOOT)
        $S.lastX = $S.x
        $S.dragged = 0.0
        $S.drag  = $true
        # a click on him in a fight is a hit. Step-Physics sees most clicks
        # too, but a quick one can come and go between two of its frames.
        if ($F.on) { Hit-Him $c }
    }
})
$form.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        [void][SM]::SetForegroundWindow($script:handle)
        $menu.Show([System.Windows.Forms.Cursor]::Position)
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $S.drag) {
        $S.drag = $false
        if ($F.on -and $S.dragged -lt 4 * $SC) { return }    # just a hit, already dealt with
        $F.air = ''
        if ($S.dragged -lt 4 * $SC -and $null -ne $S.ledge) {
            # a click rather than a drag: he jumps on the spot
            $S.state = 'cheer'; $S.timer = 70; $S.cool = 160; $S.phase = 0.0
            $c = [System.Windows.Forms.Cursor]::Position
            if ($c.X -ne $S.x) { $S.dir = [Math]::Sign($c.X - $S.x) }
            return
        }
        $S.state = 'fall'
        $S.vy    = 0.0
        $S.vx    = [Math]::Max(-9.0 * $SC, [Math]::Min(9.0 * $SC, ($S.x - $S.lastX) * 0.7))
        if ($S.vx -ne 0) { $S.dir = [Math]::Sign($S.vx) }
    }
})

# tray icon, drawn from the same stick figure
$iconBmp = New-Object System.Drawing.Bitmap 32, 32
$ig = [System.Drawing.Graphics]::FromImage($iconBmp)
$ig.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$ip = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2.6
$ip.StartCap = 'Round'; $ip.EndCap = 'Round'
$ig.DrawEllipse($ip, 11, 3, 10, 10)
$ig.DrawLine($ip, 16, 13, 16, 21)
$ig.DrawLine($ip, 16, 15, 9, 20); $ig.DrawLine($ip, 16, 15, 23, 20)
$ig.DrawLine($ip, 16, 21, 10, 29); $ig.DrawLine($ip, 16, 21, 22, 29)
$ig.Dispose()

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon())
$tray.Text    = 'Desktop Stickman'
$tray.Visible = $true
$tray.ContextMenuStrip = $menu
$tray.Add_MouseDoubleClick({ $S.state = 'wave'; $S.timer = 70; $S.phase = 0.0 })

# -------------------------------------------------------------------- main loop
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30
$timer.Add_Tick({
    try {
        # while the pointer cracks, everything stops, him included
        if (-not ($PTR.dead -and $PTR.t -lt $CRACK_LEN)) {
            Step-Physics
            if ($F.grab) { Step-Grab }      # after he has moved, so it sits right in his hand
        }
    }
    catch {
        # he runs with no console, so leave a trail if something goes wrong
        "$(Get-Date -Format s)  $($_.Exception.Message)  @ $($_.InvocationInfo.ScriptLineNumber)" |
            Out-File -FilePath $errLog -Append -Encoding utf8
        $S.state = 'fall'; $S.vy = 0.0
    }
    if ($PTR.dead) {
        try { Step-Wreck }
        catch {
            # anything going wrong with the pieces: the pointer is simply back
            "$(Get-Date -Format s)  pointer: $($_.Exception.Message)  @ $($_.InvocationInfo.ScriptLineNumber)" |
                Out-File -FilePath $errLog -Append -Encoding utf8
            try { Restore-Pointer } catch { $PTR.dead = $false; Hide-Shroud }
        }
    }
    if ($PTR.bar -gt 0) {
        try { Draw-PtrBar } catch { $PTR.bar = 0 }
    }
    # tell the others where he is, and see if one of them asked everyone to go
    try { Publish-Self } catch { }
    if ([Peers]::QuitAsked()) { $form.Close(); return }
    # his new process has him on screen now, so this one can go
    if ($null -ne $script:heir -and (Test-Heir)) { $form.Close(); return }
    if ($S.symFlash -gt 0) { $S.symFlash-- }
    # one call draws him and moves the window, with his own alpha intact
    Draw-Figure $sg
    $hbmp = $sprite.GetHbitmap([System.Drawing.Color]::FromArgb(0))
    [SM]::Blit($script:handle, $hbmp, [int]($S.x - $CX), [int]($S.y - $FOOT), $BOXW, $BOXH)
    [void][SM]::DeleteObject($hbmp)
    if ($F.fx -gt 0) {
        try { Draw-Fx }
        catch {
            "$(Get-Date -Format s)  spark: $($_.Exception.Message)  @ $($_.InvocationInfo.ScriptLineNumber)" |
                Out-File -FilePath $errLog -Append -Encoding utf8
            $F.fx = 0
        }
    }
    if ($S.tick % 50 -eq 0 -and -not $PTR.dead) {
        # stay above other topmost windows without ever stealing focus (but
        # under the shroud while the pointer is in pieces, see Break-Pointer)
        [void][SM]::SetWindowPos($script:handle, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
    }
})

$form.Add_Shown({
    $script:handle = $form.Handle
    $form.ClientSize = New-Object System.Drawing.Size $BOXW, $BOXH
    # add to the styles the window already has - overwriting them would strip
    # WS_EX_LAYERED and leave a solid rectangle behind him
    $ex = [SM]::GetExStyle($script:handle) -bor 0x00080000 -bor 0x00000080 -bor 0x08000000
    [void][SM]::SetWindowLong($script:handle, -20, $ex)   # LAYERED | TOOLWINDOW | NOACTIVATE
    $vs  = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $S.x = $RNG.Next([int]($vs.Left + 150 * $SC), [int]($vs.Right - 150 * $SC))
    $S.y = [double]$vs.Top + 40 * $SC
    if ($null -ne $INHERIT) { Restore-Handoff }
    Update-World
    $timer.Start()
})

$form.Add_FormClosed({
    $timer.Stop()
    try { foreach ($prop in @($PROPS)) { Remove-Prop $prop } } catch { }
    try { Put-WindowsBack } catch { }
    [Peers]::Leave()
    $sync.Stop = $true
    try { $scanPs.Dispose(); $scanRs.Close() } catch { }
    try { $sg.Dispose(); $sprite.Dispose() } catch { }
    try { if ($null -ne $fxForm) { $fxForm.Dispose(); $fxG.Dispose(); $fxBmp.Dispose() } } catch { }
    try { if ($null -ne $gripForm) { $gripForm.Dispose(); [void][SM]::DeleteObject($gripHb) } } catch { }
    try { foreach ($o in @($shroudForm, $wreckForm, $barForm)) { if ($null -ne $o) { $o.Dispose() } } } catch { }
    try { $penSymHalo.Dispose(); $penSym.Dispose(); $penReg.Dispose() } catch { }
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

[System.Windows.Forms.Application]::Run($form)
