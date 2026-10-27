<#
  gui.ps1 — 屏幕读取与鼠标键盘控制（Windows / PowerShell 5.1+）

  用法示例：
    .\gui.ps1 windows                        列出可见顶层窗口
    .\gui.ps1 shot out.png                   截全屏（虚拟桌面）
    .\gui.ps1 shot out.png -window "记事本"   截指定窗口
    .\gui.ps1 shot out.png -region 0,0,800,600
    .\gui.ps1 shot out.png -cursor           截图并标出光标位置
    .\gui.ps1 shot out.png -grid             叠加坐标网格与刻度标签
    .\gui.ps1 shot out.png -maxwidth 1440    按长边缩放并返回 scale（坐标换算用）
    .\gui.ps1 elements                       枚举前台窗口的 UIA 控件（名称 + 中心坐标）
    .\gui.ps1 elements -window "记事本" -filter 保存
    .\gui.ps1 ocr shot.png                   本地 OCR：文字 + 每行外框坐标
    .\gui.ps1 click -uia "保存"              按控件名称点击（UIA 定位，不用算坐标）
    .\gui.ps1 seq -file ops.json             一个进程内顺序执行多个动作
    .\gui.ps1 pos                            打印光标当前坐标
    .\gui.ps1 move 800 500                   移动光标
    .\gui.ps1 click 800 500                  左键单击
    .\gui.ps1 click 800 500 -button right -count 2
    .\gui.ps1 drag 100 100 400 300           左键拖拽
    .\gui.ps1 scroll 800 500 3               滚轮（正=上，负=下，1=120单位）
    .\gui.ps1 type "hello 中文"              逐字符 Unicode 输入
    .\gui.ps1 key "ctrl+s"                   组合键
    .\gui.ps1 key "enter"
    .\gui.ps1 activate "DeepSeek"            激活窗口到前台

  约定：所有坐标都是物理像素（脚本内部开启 per-monitor DPI v2），
  与 `shot` 输出的图片像素一一对应，可放心把图上的像素坐标直接当参数用。
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]] $Argv
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

if (-not ('GuiNative' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class GuiNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT
    {
        [FieldOffset(0)] public uint type;
        [FieldOffset(4)] public MOUSEINPUT mi;
        [FieldOffset(4)] public KEYBDINPUT ki;
    }

    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);

    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    const uint MOUSEEVENTF_WHEEL = 0x0800;
    const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint KEYEVENTF_UNICODE = 0x0004;

    public static void EnableDpiAwareness()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
    }

    static INPUT MouseInput(uint flags, int dx, int dy, uint data)
    {
        INPUT i = new INPUT();
        i.type = 0;
        i.mi.dx = dx;
        i.mi.dy = dy;
        i.mi.mouseData = data;
        i.mi.dwFlags = flags;
        return i;
    }

    static INPUT KeyInput(ushort vk, ushort scan, uint flags)
    {
        INPUT i = new INPUT();
        i.type = 1;
        i.ki.wVk = vk;
        i.ki.wScan = scan;
        i.ki.dwFlags = flags;
        return i;
    }

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SendInput")]
    static extern uint SendRaw(uint nInputs, IntPtr pInputs, int cbSize);
    [DllImport("user32.dll")]
    static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    static int Cb() { return Marshal.SizeOf(typeof(INPUT)); }

    static uint SendAll(INPUT[] arr)
    {
        int size = Cb();
        IntPtr buf = Marshal.AllocHGlobal(size * arr.Length);
        try
        {
            for (int i = 0; i < arr.Length; i++)
                Marshal.StructureToPtr(arr[i], new IntPtr(buf.ToInt64() + (long)i * size), false);
            return SendRaw((uint)arr.Length, buf, size);
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    public static bool MoveTo(int x, int y)
    {
        if (SetCursorPos(x, y))
        {
            POINT p;
            if (GetCursorPos(out p) && Math.Abs(p.X - x) <= 2 && Math.Abs(p.Y - y) <= 2) return true;
        }
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77);
        int vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
        if (vw <= 1) vw = 2;
        if (vh <= 1) vh = 2;
        int ax = (int)Math.Round((double)(x - vx) * 65535.0 / (vw - 1));
        int ay = (int)Math.Round((double)(y - vy) * 65535.0 / (vh - 1));
        mouse_event(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, ax, ay, 0, UIntPtr.Zero);
        POINT q;
        return GetCursorPos(out q) && Math.Abs(q.X - x) <= 2 && Math.Abs(q.Y - y) <= 2;
    }

    public static void MouseButton(string button, bool down)
    {
        string b = (button ?? "left").ToLowerInvariant();
        uint mf;
        if (b.StartsWith("r")) mf = down ? 0x0008u : 0x0010u;
        else if (b.StartsWith("m")) mf = down ? 0x0020u : 0x0040u;
        else mf = down ? 0x0002u : 0x0004u;
        mouse_event(mf, 0, 0, 0, UIntPtr.Zero);
    }

    public static void Scroll(int notches)
    {
        uint data = (uint)(int)(notches * 120);
        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, data, UIntPtr.Zero);
    }

    public static void KeyDown(ushort vk) { keybd_event((byte)vk, 0, 0, UIntPtr.Zero); }
    public static void KeyUp(ushort vk) { keybd_event((byte)vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); }

    public static void TypeText(string s)
    {
        if (string.IsNullOrEmpty(s)) return;
        List<INPUT> list = new List<INPUT>();
        foreach (char c in s)
        {
            ushort scan = (ushort)c;
            list.Add(KeyInput(0, scan, KEYEVENTF_UNICODE));
            list.Add(KeyInput(0, scan, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
        }
        SendAll(list.ToArray());
    }

    public static POINT Cursor()
    {
        POINT p;
        GetCursorPos(out p);
        return p;
    }

    public static string[] ListWindows()
    {
        List<string> rows = new List<string>();
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(1024);
            GetWindowText(h, sb, sb.Capacity);
            string title = sb.ToString();
            if (title.Trim().Length == 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left, ht = r.Bottom - r.Top;
            if (w < 40 || ht < 40) return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            string proc = "";
            try { proc = Process.GetProcessById((int)pid).ProcessName; } catch { }
            rows.Add(string.Format("{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}",
                h.ToInt64(), title, r.Left, r.Top, w, ht, pid, proc));
            return true;
        }, IntPtr.Zero);
        return rows.ToArray();
    }

    public static IntPtr FindWindow(string needle)
    {
        if (string.IsNullOrEmpty(needle)) return IntPtr.Zero;
        string n = needle.ToLowerInvariant();
        IntPtr best = IntPtr.Zero;
        int bestScore = 0;
        foreach (string row in ListWindows())
        {
            string[] p = row.Split('\t');
            if (p.Length < 8) continue;
            string title = p[1].ToLowerInvariant();
            string proc = p[7].ToLowerInvariant();
            int score = 0;
            if (title == n) score = 100;
            else if (title.StartsWith(n)) score = 80;
            else if (title.Contains(n)) score = 60;
            else if (proc == n) score = 50;
            else if (proc.Contains(n)) score = 40;
            if (score > bestScore)
            {
                bestScore = score;
                best = new IntPtr(long.Parse(p[0]));
            }
        }
        return best;
    }

    public static bool ForceForeground(IntPtr h)
    {
        if (h == IntPtr.Zero) return false;
        if (IsIconic(h)) ShowWindow(h, 9);
        uint pid;
        uint tid = GetWindowThreadProcessId(h, out pid);
        uint cur = GetCurrentThreadId();
        bool ok;
        if (tid != cur)
        {
            AttachThreadInput(cur, tid, true);
            BringWindowToTop(h);
            ok = SetForegroundWindow(h);
            AttachThreadInput(cur, tid, false);
        }
        else
        {
            BringWindowToTop(h);
            ok = SetForegroundWindow(h);
        }
        if (!ok) { ShowWindow(h, 9); ShowWindow(h, 5); ok = SetForegroundWindow(h); }
        return ok;
    }

    public static bool GetRect(IntPtr h, out int left, out int top, out int width, out int height)
    {
        RECT r;
        left = top = width = height = 0;
        if (h == IntPtr.Zero || !GetWindowRect(h, out r)) return false;
        left = r.Left; top = r.Top;
        width = r.Right - r.Left; height = r.Bottom - r.Top;
        return true;
    }

    /// Root (top-level) window under a point: used to refuse clicks that would land
    /// on a different window than the one the caller named.
    public static IntPtr HitTestRoot(int x, int y)
    {
        POINT p;
        p.X = x; p.Y = y;
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) return IntPtr.Zero;
        IntPtr root = GetAncestor(h, 2); // GA_ROOT
        return root == IntPtr.Zero ? h : root;
    }

    /// Owning process id of a window: popups/dropdowns of the same app are separate
    /// top-level windows, so hit-testing must compare processes, not only handles.
    public static uint PidOf(IntPtr h)
    {
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return pid;
    }

    /// Root ancestor of a window. UWP apps live inside an ApplicationFrameHost window of
    /// a *different* process, so hit-testing must compare roots, not raw handles.
    public static IntPtr RootOf(IntPtr h)
    {
        if (h == IntPtr.Zero) return IntPtr.Zero;
        IntPtr root = GetAncestor(h, 2);
        return root == IntPtr.Zero ? h : root;
    }
}
'@
}

[GuiNative]::EnableDpiAwareness()

# ---- UI Automation：只在 elements / click -uia 时才编译，普通截图不付这份开销 ----
function Initialize-Uia {
    if ('UiaNative' -as [type]) { return }
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
    $refs = @(
        [System.Windows.Automation.AutomationElement].Assembly.Location,
        [System.Windows.Automation.ControlType].Assembly.Location,
        [System.Windows.Rect].Assembly.Location
    ) | Select-Object -Unique
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Windows.Automation;

public class UiaRow
{
    public int X, Y, W, H, Depth;
    public string Type = "";
    public string Name = "";
    public string Id = "";
    public bool Enabled;
    public bool Invokable;
}

public class UiaNative
{
    public static List<UiaRow> Walk(IntPtr hwnd, int maxNodes, int maxDepth)
    {
        List<UiaRow> list = new List<UiaRow>();
        AutomationElement root = AutomationElement.FromHandle(hwnd);
        if (root == null) return list;
        WalkRec(root, 0, maxNodes, maxDepth, list);
        return list;
    }

    static void WalkRec(AutomationElement el, int depth, int maxNodes, int maxDepth, List<UiaRow> list)
    {
        if (list.Count >= maxNodes) return;
        string type = "";
        string name = "";
        string aid = "";
        System.Windows.Rect r = System.Windows.Rect.Empty;
        bool enabled = false;
        bool invokable = false;
        try
        {
            object ct = el.GetCurrentPropertyValue(AutomationElement.ControlTypeProperty);
            if (ct is ControlType) type = ((ControlType)ct).ProgrammaticName.Replace("ControlType.", "");
            name = el.Current.Name ?? "";
            aid = el.Current.AutomationId ?? "";
            r = el.Current.BoundingRectangle;
            enabled = el.Current.IsEnabled;
        }
        catch { return; }

        if (!r.IsEmpty && r.Width >= 1 && r.Height >= 1)
        {
            try { invokable = el.GetCurrentPattern(InvokePattern.Pattern) != null; }
            catch { invokable = false; }
            UiaRow row = new UiaRow();
            row.X = (int)r.X; row.Y = (int)r.Y;
            row.W = (int)r.Width; row.H = (int)r.Height;
            row.Depth = depth; row.Type = type; row.Name = name; row.Id = aid;
            row.Enabled = enabled; row.Invokable = invokable;
            list.Add(row);
        }

        if (depth >= maxDepth || list.Count >= maxNodes) return;
        TreeWalker tw = TreeWalker.RawViewWalker;
        AutomationElement child = tw.GetFirstChild(el);
        while (child != null)
        {
            WalkRec(child, depth + 1, maxNodes, maxDepth, list);
            if (list.Count >= maxNodes) break;
            child = tw.GetNextSibling(child);
        }
    }

    /// Focus snapshot: lets `type -verify` prove the target is editable and read the
    /// value back after pasting.
    public class UiaFocusInfo
    {
        public bool Ok;
        public string Name = "";
        public string Type = "";
        public string Id = "";
        public string Value = "";
        public bool Editable;
        public bool NonEditable;
    }

    public static UiaFocusInfo FocusedInfo()
    {
        UiaFocusInfo info = new UiaFocusInfo();
        try
        {
            AutomationElement el = AutomationElement.FocusedElement;
            if (el == null) return info;
            info.Ok = true;
            info.Name = el.Current.Name ?? "";
            info.Id = el.Current.AutomationId ?? "";
            object ct = el.GetCurrentPropertyValue(AutomationElement.ControlTypeProperty);
            if (ct is ControlType) info.Type = ((ControlType)ct).ProgrammaticName.Replace("ControlType.", "");
            object vp = null;
            try { vp = el.GetCurrentPattern(ValuePattern.Pattern); } catch { vp = null; }
            if (vp != null)
            {
                try
                {
                    ValuePattern value = (ValuePattern)vp;
                    info.Value = value.Current.Value ?? "";
                    info.Editable = !value.Current.IsReadOnly;
                }
                catch { }
            }
            if (!info.Editable && (info.Type == "Edit" || info.Type == "Document")) info.Editable = true;
            if (!info.Editable && string.IsNullOrEmpty(info.Value))
            {
                try
                {
                    object tp = el.GetCurrentPattern(TextPattern.Pattern);
                    if (tp != null) info.Value = ((TextPattern)tp).DocumentRange.GetText(512);
                }
                catch { }
            }
            string[] nonEditable = { "Button", "MenuItem", "CheckBox", "RadioButton", "TabItem", "ToolBar", "Image", "ScrollBar", "Slider" };
            if (!info.Editable && Array.IndexOf(nonEditable, info.Type) >= 0) info.NonEditable = true;
        }
        catch { }
        return info;
    }

    public static bool InvokeAt(int x, int y)
    {
        try
        {
            AutomationElement el = AutomationElement.FromPoint(new System.Windows.Point(x, y));
            if (el == null) return false;
            object pat = el.GetCurrentPattern(InvokePattern.Pattern);
            if (pat == null) return false;
            ((InvokePattern)pat).Invoke();
            return true;
        }
        catch { return false; }
    }
}
'@
}

# ---- 参数解析：位置参数 + -name value ----
$pos = New-Object System.Collections.ArrayList
$opt = @{}
$literal = $false
for ($i = 0; $i -lt $Argv.Count; $i++) {
    $a = $Argv[$i]
    if (-not $literal -and $a -is [string] -and $a -eq '--') { $literal = $true; continue }
    if (-not $literal -and $a -is [string] -and $a.Length -gt 1 -and $a.StartsWith('-') -and $a -notmatch '^-?\d') {
        $name = $a.TrimStart('-').ToLowerInvariant()
        $val = $null
        if ($i + 1 -lt $Argv.Count) {
            $nxt = $Argv[$i + 1]
            if (-not ($nxt -is [string] -and $nxt.Length -gt 1 -and $nxt.StartsWith('-') -and $nxt -notmatch '^-?\d')) {
                $val = $nxt; $i++
            }
        }
        if ($null -eq $val) { $opt[$name] = $true } else { $opt[$name] = $val }
    }
    else { [void]$pos.Add($a) }
}

if ($pos.Count -eq 0) { Get-Help $PSCommandPath -ErrorAction SilentlyContinue; Write-Host "`n没有参数。用 'shot out.png' 或 'windows' 开始。" ; return }

$cmd = ([string]$pos[0]).ToLowerInvariant()
$rest = @()
if ($pos.Count -gt 1) { $rest = $pos[1..($pos.Count - 1)] }

function Get-RectFromString([string]$s) {
    $p = $s -split ','
    if ($p.Count -ne 4) { throw "region 需要 x,y,w,h 四段，例如 0,0,800,600" }
    @{ X = [int]$p[0]; Y = [int]$p[1]; W = [int]$p[2]; H = [int]$p[3] }
}

# ---- 快速原图截图（find 用；不带网格/缩放，避免污染 OCR）----
function Save-QuickShot {
    param([IntPtr]$Hwnd, $Region, [string]$Out, [switch]$Print)

    if ($Hwnd -ne [IntPtr]::Zero) {
        $l = 0; $t = 0; $w = 0; $h = 0
        if (-not [GuiNative]::GetRect($Hwnd, [ref]$l, [ref]$t, [ref]$w, [ref]$h)) { throw '拿不到窗口矩形' }
    }
    elseif ($null -ne $Region) {
        $l = $Region.X; $t = $Region.Y; $w = $Region.W; $h = $Region.H
    }
    else {
        $l = [GuiNative]::GetSystemMetrics(76); $t = [GuiNative]::GetSystemMetrics(77)
        $w = [GuiNative]::GetSystemMetrics(78); $h = [GuiNative]::GetSystemMetrics(79)
    }
    if ($w -le 0 -or $h -le 0) { throw "截图区域无效: ${w}x${h}" }

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            if ($Print -and $Hwnd -ne [IntPtr]::Zero) {
                # PrintWindow 不受遮挡影响；Electron/Chromium 窗口也能截到内容
                $hdc = $g.GetHdc()
                try { [void][GuiNative]::PrintWindow($Hwnd, $hdc, 2) }
                finally { $g.ReleaseHdc($hdc) }
            }
            else {
                $g.CopyFromScreen($l, $t, 0, 0, (New-Object System.Drawing.Size $w, $h))
            }
        }
        finally { $g.Dispose() }
        $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $bmp.Dispose() }

    [pscustomobject]@{ X = $l; Y = $t; W = $w; H = $h }
}

# ---- 本地 OCR（Windows.Media.Ocr）：ocr 与 find 共用 ----
function Invoke-OcrFile {
    param([string]$Path, [double]$Zoom = 2.0, [string]$Filter = '')

    $path = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path $path)) { throw "找不到图片: $path" }
    if ($Zoom -lt 1.0) { $Zoom = 1.0 }
    if ($Zoom -gt 4.0) { $Zoom = 4.0 }

    $src = $path
    $zoomTemp = $null
    if ($Zoom -ne 1.0) {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($path)
        try {
            $zw = [int][Math]::Max(1, [Math]::Round($img.Width * $Zoom))
            $zh = [int][Math]::Max(1, [Math]::Round($img.Height * $Zoom))
            $zb = New-Object System.Drawing.Bitmap $zw, $zh
            try {
                $zg = [System.Drawing.Graphics]::FromImage($zb)
                try {
                    $zg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $zg.DrawImage($img, 0, 0, $zw, $zh)
                }
                finally { $zg.Dispose() }
                $zoomTemp = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($path), '__ocr_zoom_' + [Guid]::NewGuid().ToString('N') + '.png')
                $zb.Save($zoomTemp, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $zb.Dispose() }
        }
        finally { $img.Dispose() }
        $src = $zoomTemp
    }

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Foundation, ContentType = WindowsRuntime]

    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Await-Op($op, [Type]$type) {
        if ($null -eq $op) { throw "ocr: 空的异步句柄（$type）" }
        $m = $asTaskGeneric.MakeGenericMethod($type)
        $task = $m.Invoke($null, @($op))
        try { [void]$task.Wait(-1) }
        catch {
            $e = $_.Exception
            while ($e.InnerException) { $e = $e.InnerException }
            throw "ocr: $($type.Name) 失败 - $($e.Message) [$($e.GetType().Name)]"
        }
        $task.Result
    }

    $result = $null
    try {
        $file = Await-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($src)) ([Windows.Storage.StorageFile])
        $stream = Await-Op ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        try {
            $decoder = Await-Op ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $bitmap = Await-Op ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
            if ($null -eq $engine) { throw 'ocr: 本机没有可用的 OCR 语言包（设置 → 时间和语言 → 语言 → 该语言的“光学字符识别”可选功能）' }
            $result = Await-Op ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        }
        finally { $stream.Dispose() }
    }
    finally {
        if ($zoomTemp) { Remove-Item -LiteralPath $zoomTemp -Force -ErrorAction SilentlyContinue }
    }

    $rows = @()
    foreach ($line in $result.Lines) {
        $txt = $line.Text
        # Windows OCR 会在汉字之间插空格；先去掉，再做过滤和输出
        $txt = $txt -replace '(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])', ''
        if ($Filter -and $txt -notlike "*$Filter*") { continue }
        $minX = [double]::MaxValue; $minY = [double]::MaxValue
        $maxX = 0.0; $maxY = 0.0
        foreach ($word in $line.Words) {
            $r = $word.BoundingRect
            if ($r.X -lt $minX) { $minX = $r.X }
            if ($r.Y -lt $minY) { $minY = $r.Y }
            if (($r.X + $r.Width) -gt $maxX) { $maxX = $r.X + $r.Width }
            if (($r.Y + $r.Height) -gt $maxY) { $maxY = $r.Y + $r.Height }
        }
        if ($maxX -le 0) { continue }
        $rows += [pscustomobject]@{
            X    = [int][Math]::Round((($minX + $maxX) / 2.0) / $Zoom)
            Y    = [int][Math]::Round((($minY + $maxY) / 2.0) / $Zoom)
            W    = [int][Math]::Round(($maxX - $minX) / $Zoom)
            H    = [int][Math]::Round(($maxY - $minY) / $Zoom)
            Text = $txt
        }
    }

    [pscustomobject]@{
        Rows      = $rows
        Zoom      = $Zoom
        Lang      = $engine.RecognizerLanguage.LanguageTag
        LineCount = @($result.Lines).Count
    }
}

# ---- 文字相似度：OCR 会错字，靠包含关系 + 字符重叠兜底 ----
function Get-MatchScore {
    param([string]$Candidate, [string]$Needle)

    $a = $Candidate.ToLowerInvariant().Trim()
    $b = $Needle.ToLowerInvariant().Trim()
    if ($a.Length -eq 0 -or $b.Length -eq 0) { return 0.0 }
    if ($a -eq $b) { return 1.0 }
    if ($a.Contains($b)) { return 0.92 }
    if ($b.Contains($a)) { return 0.78 }

    $set = New-Object 'System.Collections.Generic.HashSet[char]'
    foreach ($ch in $b.ToCharArray()) { [void]$set.Add($ch) }
    $hit = 0
    foreach ($ch in $a.ToCharArray()) { if ($set.Contains($ch)) { $hit++ } }
    [Math]::Min(0.7, $hit / [double][Math]::Max($a.Length, $b.Length))
}

# ---- 校验辅助：读回文本比较 / 焦点转对象 / 截断 ----
function Normalize-UiText([string]$s) { return (($s -replace '\s', '').ToLowerInvariant()) }
function Truncate-UiText([string]$s, [int]$n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0, $n) + '…'
}
function Focus-Object($f) {
    if ($null -eq $f -or -not $f.Ok) { return @{ ok = $false } }
    return @{ ok = $true; name = $f.Name; type = $f.Type; id = $f.Id; editable = $f.Editable }
}
function Get-ReadbackVerdict($focus, [string]$expected) {
    if ($null -eq $focus -or -not $focus.Ok) {
        return @{ status = 'unknown'; method = 'uia-value'; detail = '当前控件没有可读文本（UIA 不可见），无法确认输入是否落地' }
    }
    $want = Normalize-UiText $expected
    $got = Normalize-UiText $focus.Value
    if ($got.Length -eq 0) {
        return @{ status = 'unverified'; method = 'uia-value'; detail = '读回为空：输入可能被目标控件丢弃' }
    }
    if ($want.Length -gt 0 -and $got.Contains($want)) {
        return @{ status = 'verified'; method = 'uia-value'; detail = '读回内容包含刚输入的文本'; readback = (Truncate-UiText $focus.Value 120) }
    }
    return @{ status = 'unverified'; method = 'uia-value'; detail = '读回内容与输入不一致'; readback = (Truncate-UiText $focus.Value 120) }
}

# ---- 前台保障：SetForegroundWindow 常被前台锁拒绝。先重试，再点一次标题栏
#      制造本进程的真实输入事件（文档里的合法路径），最后仍失败就返回 false，
#      调用方必须拒绝输入，绝不能把文字打进别的窗口。 ----
function Ensure-Foreground([IntPtr]$hwnd, [int]$timeoutMs = 900) {
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    if ([GuiNative]::GetForegroundWindow() -eq $hwnd) { return $true }
    if ([GuiNative]::IsIconic($hwnd)) { [void][GuiNative]::ShowWindow($hwnd, 9) }
    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        [void][GuiNative]::ForceForeground($hwnd)
        Start-Sleep -Milliseconds 90
        if ([GuiNative]::GetForegroundWindow() -eq $hwnd) { return $true }
    }
    $l = 0; $t = 0; $w = 0; $h = 0
    if ([GuiNative]::GetRect($hwnd, [ref]$l, [ref]$t, [ref]$w, [ref]$h)) {
        [void][GuiNative]::MoveTo([int]($l + $w / 2), [int]($t + 8))
        Start-Sleep -Milliseconds 50
        [GuiNative]::MouseButton('left', $true)
        Start-Sleep -Milliseconds 30
        [GuiNative]::MouseButton('left', $false)
        Start-Sleep -Milliseconds 150
        if ([GuiNative]::GetForegroundWindow() -eq $hwnd) { return $true }
    }
    return $false
}

function Invoke-GuiCmd {
    param($cmd, $rest, $opt)

switch ($cmd) {

    'windows' {
        $rows = [GuiNative]::ListWindows()
        $limit = if ($opt.ContainsKey('top')) { [int]$opt['top'] } else { 0 }
        "{0,-14} {1,-10} {2,-26} {3}" -f 'HWND', 'PID', 'RECT', 'TITLE'
        $shown = 0
        foreach ($row in $rows) {
            if ($limit -gt 0 -and $shown -ge $limit) { break }
            $shown++
            $p = $row -split "`t"
            $hw = [long]$p[0]
            "{0,-14} {1,-10} {2,-26} {3}" -f ('0x' + $hw.ToString('X')), $p[6], ("{0},{1} {2}x{3}" -f $p[2], $p[3], $p[4], $p[5]), ($p[1] + "  [" + $p[7] + "]")
        }
    }

    'pos' {
        $pt = [GuiNative]::Cursor()
        "{0},{1}" -f $pt.X, $pt.Y
    }

    'fg' {
        $h = [GuiNative]::GetForegroundWindow()
        $sb = New-Object System.Text.StringBuilder 512
        [void][GuiNative]::GetWindowText($h, $sb, 512)
        [pscustomobject]@{ hwnd = ('0x' + $h.ToInt64().ToString('X')); title = $sb.ToString() } | ConvertTo-Json -Compress
    }

    'shot' {
        $out = if ($rest.Count -ge 1) { [string]$rest[0] } else { 'shot.png' }
        if (-not [System.IO.Path]::IsPathRooted($out)) { $out = Join-Path (Get-Location).Path $out }
        $dir = [System.IO.Path]::GetDirectoryName($out)
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

        $hwnd = [IntPtr]::Zero
        if ($opt.ContainsKey('window')) { $hwnd = [GuiNative]::FindWindow([string]$opt['window']) }
        elseif ($opt.ContainsKey('hwnd')) { $hwnd = [IntPtr]([long]$opt['hwnd']) }

        # 指定了窗口却找不到时直接报错，绝不静默退回全屏（那会截到别的窗口，模型按错坐标点）
        if ($opt.ContainsKey('window') -and $hwnd -eq [IntPtr]::Zero) { throw "shot: 找不到窗口 ""$($opt['window'])""" }
        if ($hwnd -ne [IntPtr]::Zero -and [GuiNative]::IsIconic($hwnd)) { throw 'shot: 目标窗口已最小化，先用 activate 还原' }

        if ($hwnd -ne [IntPtr]::Zero) {
            $l = 0; $t = 0; $w = 0; $h = 0
            if (-not [GuiNative]::GetRect($hwnd, [ref]$l, [ref]$t, [ref]$w, [ref]$h)) { throw "拿不到窗口矩形" }
            $x = $l; $y = $t; $width = $w; $height = $h
        }
        elseif ($opt.ContainsKey('region')) {
            $r = Get-RectFromString ([string]$opt['region'])
            $x = $r.X; $y = $r.Y; $width = $r.W; $height = $r.H
        }
        else {
            $x = [GuiNative]::GetSystemMetrics(76)
            $y = [GuiNative]::GetSystemMetrics(77)
            $width = [GuiNative]::GetSystemMetrics(78)
            $height = [GuiNative]::GetSystemMetrics(79)
        }
        if ($width -le 0 -or $height -le 0) { throw "截图区域无效: ${width}x${height}" }

        $bmp = New-Object System.Drawing.Bitmap $width, $height
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                if ($hwnd -ne [IntPtr]::Zero -and $opt.ContainsKey('print')) {
                    $hdc = $g.GetHdc()
                    try { [void][GuiNative]::PrintWindow($hwnd, $hdc, 2) }
                    finally { $g.ReleaseHdc($hdc) }
                }
                else {
                    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $width, $height))
                }
            }
            finally { $g.Dispose() }

            # ---- 可选缩放：长边压到 -maxwidth 以内，返回 scale 供模型换算物理坐标 ----
            $scale = 1.0
            $maxW = if ($opt.ContainsKey('maxwidth')) { [int]$opt['maxwidth'] } else { 0 }
            if ($maxW -gt 0 -and $width -gt $maxW) {
                $scale = [double]$maxW / [double]$width
                $nw = [int][Math]::Max(1, [Math]::Round($width * $scale))
                $nh = [int][Math]::Max(1, [Math]::Round($height * $scale))
                $small = New-Object System.Drawing.Bitmap $nw, $nh
                $gs = [System.Drawing.Graphics]::FromImage($small)
                try {
                    $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $gs.DrawImage($bmp, 0, 0, $nw, $nh)
                }
                finally { $gs.Dispose() }
                $bmp.Dispose()
                $bmp = $small
            }
            $outW = $bmp.Width
            $outH = $bmp.Height

            $gridStep = 0
            $g2 = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

                # ---- 坐标网格：线上带物理坐标刻度，模型不用目测 ----
                if ($opt.ContainsKey('grid')) {
                    $gridStep = if ($opt.ContainsKey('gridstep')) { [int]$opt['gridstep'] } else { 100 }
                    if ($gridStep -lt 20) { $gridStep = 100 }
                    while ($gridStep * $scale -lt 56) { $gridStep *= 2 }

                    $linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 0, 120, 235)), 1
                    $fontSize = [float][Math]::Max(9.0, 10.0 * [Math]::Max($scale, 0.85))
                    $font = New-Object System.Drawing.Font 'Consolas', $fontSize, ([System.Drawing.FontStyle]::Bold)
                    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 85, 185))
                    $padBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(205, 255, 255, 255))
                    try {
                        for ($gx = 0; $gx -lt $width; $gx += $gridStep) {
                            $px = [int][Math]::Round($gx * $scale)
                            if ($px -le 0 -or $px -ge $outW) { continue }
                            $g2.DrawLine($linePen, $px, 0, $px, $outH)
                            $label = "x=$($x + $gx)"
                            $sz = $g2.MeasureString($label, $font)
                            $g2.FillRectangle($padBrush, [float]($px + 1), [float]1, $sz.Width, $sz.Height)
                            $g2.DrawString($label, $font, $textBrush, [float]($px + 1), [float]1)
                        }
                        for ($gy = 0; $gy -lt $height; $gy += $gridStep) {
                            $py = [int][Math]::Round($gy * $scale)
                            if ($py -le 0 -or $py -ge $outH) { continue }
                            $g2.DrawLine($linePen, 0, $py, $outW, $py)
                            $label = "y=$($y + $gy)"
                            $sz = $g2.MeasureString($label, $font)
                            $g2.FillRectangle($padBrush, [float]1, [float]($py + 1), $sz.Width, $sz.Height)
                            $g2.DrawString($label, $font, $textBrush, [float]1, [float]($py + 1))
                        }
                    }
                    finally {
                        $linePen.Dispose(); $font.Dispose(); $textBrush.Dispose(); $padBrush.Dispose()
                    }
                }

                # ---- 光标标记（位置同样按 scale 映射）----
                if ($opt.ContainsKey('cursor')) {
                    $pt = [GuiNative]::Cursor()
                    $cx = [int][Math]::Round(($pt.X - $x) * $scale)
                    $cy = [int][Math]::Round(($pt.Y - $y) * $scale)
                    if ($cx -ge 0 -and $cy -ge 0 -and $cx -lt $outW -and $cy -lt $outH) {
                        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
                        try {
                            $g2.DrawEllipse($pen, $cx - 14, $cy - 14, 28, 28)
                            $g2.DrawLine($pen, $cx - 22, $cy, $cx + 22, $cy)
                            $g2.DrawLine($pen, $cx, $cy - 22, $cx, $cy + 22)
                        }
                        finally { $pen.Dispose() }
                    }
                }
            }
            finally { $g2.Dispose() }

            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bmp.Dispose() }

        [pscustomobject]@{
            path       = $out
            x          = $x
            y          = $y
            width      = $outW
            height     = $outH
            physWidth  = $width
            physHeight = $height
            scale      = [Math]::Round($scale, 4)
            gridStep   = $gridStep
            bytes      = (Get-Item $out).Length
        } | ConvertTo-Json -Compress
    }

    'activate' {
        if ($rest.Count -lt 1) { throw "activate 需要窗口标题关键字" }
        $h = [GuiNative]::FindWindow([string]$rest[0])
        if ($h -eq [IntPtr]::Zero) { throw "找不到窗口: $($rest[0])" }
        $ok = (Ensure-Foreground $h 900)
        [pscustomobject]@{ ok = $ok; hwnd = ('0x' + $h.ToInt64().ToString('X')) } | ConvertTo-Json -Compress
    }

    'move' {
        if ($rest.Count -lt 2) { throw "move 需要 x y" }
        $x = [int]$rest[0]; $y = [int]$rest[1]
        [GuiNative]::MoveTo($x, $y)
        Start-Sleep -Milliseconds 40
        $pt = [GuiNative]::Cursor()
        "{0},{1}" -f $pt.X, $pt.Y
    }

    'click' {
        $verify = $opt.ContainsKey('verify')

        # ---- 按控件名称点击：UIA 定位中心，不用模型算坐标 ----
        if ($opt.ContainsKey('uia')) {
            Initialize-Uia
            $needle = [string]$opt['uia']
            $hwnd = [IntPtr]::Zero
            if ($opt.ContainsKey('hwnd')) { $hwnd = [IntPtr]([long]$opt['hwnd']) }
            elseif ($opt.ContainsKey('window')) { $hwnd = [GuiNative]::FindWindow([string]$opt['window']) }
            else { $hwnd = [GuiNative]::GetForegroundWindow() }
            if ($hwnd -eq [IntPtr]::Zero) { throw 'click -uia: 找不到目标窗口' }

            $rows = [UiaNative]::Walk($hwnd, 600, 12)
            $hit = $null
            foreach ($row in $rows) {
                if (-not $row.Enabled) { continue }
                if (($row.Name -like "*$needle*") -or ($row.Id -like "*$needle*")) { $hit = $row; break }
            }
            if ($null -eq $hit) { throw "click -uia: 没找到控件 ""$needle""（先跑 elements 看有哪些）" }

            $cx = [int]($hit.X + [Math]::Floor($hit.W / 2))
            $cy = [int]($hit.Y + [Math]::Floor($hit.H / 2))
            $invoked = $false
            if ($opt.ContainsKey('invoke')) { $invoked = [UiaNative]::InvokeAt($cx, $cy) }
            if (-not $invoked) {
                [void][GuiNative]::MoveTo($cx, $cy)
                Start-Sleep -Milliseconds 60
                [GuiNative]::MouseButton('left', $true)
                Start-Sleep -Milliseconds 40
                [GuiNative]::MouseButton('left', $false)
            }
            $obj = [ordered]@{
                ok      = $true
                uia     = $needle
                found   = $hit.Name
                type    = $hit.Type
                x       = $cx
                y       = $cy
                invoked = $invoked
            }
            if ($verify) {
                $focus = [UiaNative]::FocusedInfo()
                $obj.focus = (Focus-Object $focus)
                $obj.hitTest = @{ match = $true; method = 'uia-element' }
                $obj.verification = @{ status = 'unknown'; method = 'uia-target'; detail = '已点击 UIA 控件；应用侧结果需另行确认' }
            }
            [pscustomobject]$obj | ConvertTo-Json -Compress -Depth 6
            break
        }

        $x = $null; $y = $null
        if ($rest.Count -ge 2) { $x = [int]$rest[0]; $y = [int]$rest[1] }
        $button = if ($opt.ContainsKey('button')) { [string]$opt['button'] } else { 'left' }
        $count = if ($opt.ContainsKey('count')) { [int]$opt['count'] } else { 1 }
        $gap = if ($opt.ContainsKey('gap')) { [int]$opt['gap'] } else { 90 }

        $hwnd = [IntPtr]::Zero
        $hitTest = $null
        if ($opt.ContainsKey('window')) {
            $hwnd = [GuiNative]::FindWindow([string]$opt['window'])
            if ($hwnd -eq [IntPtr]::Zero) { throw "click: 找不到窗口 ""$($opt['window'])""" }
        }
        if ($verify -and $hwnd -ne [IntPtr]::Zero -and $null -ne $x) {
            $root = [GuiNative]::HitTestRoot($x, $y)
            $expectedRoot = [GuiNative]::RootOf($hwnd)
            $exactMatch = ($root -eq $expectedRoot)
            $sameProcess = $false
            if (-not $exactMatch -and $root -ne [IntPtr]::Zero) {
                $sameProcess = ([GuiNative]::PidOf($root) -eq [GuiNative]::PidOf($expectedRoot))
            }
            if (-not $exactMatch -and -not $sameProcess) {
                [pscustomobject]@{
                    ok      = $false
                    reason  = "落点 ($x,$y) 属于另一个窗口，已拒绝点击（防止点到别的程序上）"
                    clicked = @{ x = $x; y = $y }
                    hitTest = @{
                        match    = $false
                        expected = ('0x' + $hwnd.ToInt64().ToString('X'))
                        actual   = ('0x' + $root.ToInt64().ToString('X'))
                    }
                } | ConvertTo-Json -Compress -Depth 6
                break
            }
            $hitTest = @{
                match    = $true
                method   = $(if ($exactMatch) { 'hwnd' } else { 'same-pid-popup' })
                expected = ('0x' + $hwnd.ToInt64().ToString('X'))
                actual   = ('0x' + $root.ToInt64().ToString('X'))
            }
        }

        # 坐标可能过期：要求落点附近真的出现预期文字才点。
        # 窗被遮挡时不能截屏幕（会读到别的程序），优先对目标窗口做 PrintWindow 整窗 OCR。
        if ($null -ne $x -and $opt.ContainsKey('expect')) {
            $needle = [string]$opt['expect']
            $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dsh-expect-' + [Guid]::NewGuid().ToString('N') + '.png')
            $padX = 90; $padY = 50
            try {
                $shot = $null
                # 优先按“落点所属窗口”捕获：弹窗/下拉是独立窗口，PrintWindow 目标窗口截不到它；
                # 没有命中窗口时退回目标窗口，再退回屏幕区域。
                $capHwnd = [GuiNative]::HitTestRoot($x, $y)
                if ($capHwnd -ne [IntPtr]::Zero) {
                    $shot = Save-QuickShot -Hwnd $capHwnd -Out $tmp -Print
                }
                elseif ($hwnd -ne [IntPtr]::Zero) {
                    $shot = Save-QuickShot -Hwnd $hwnd -Out $tmp -Print
                }
                else {
                    $ex = [Math]::Max(0, $x - $padX)
                    $ey = [Math]::Max(0, $y - $padY)
                    $region = @{ X = [int]$ex; Y = [int]$ey; W = [int]($padX * 2); H = [int]($padY * 2) }
                    $shot = Save-QuickShot -Hwnd ([IntPtr]::Zero) -Region $region -Out $tmp
                }
                $ocr = Invoke-OcrFile -Path $tmp -Zoom 2 -Filter ''
                $wantNorm = Normalize-UiText $needle
                $found = $false
                foreach ($row in $ocr.Rows) {
                    if (-not (Normalize-UiText $row.Text).Contains($wantNorm)) { continue }
                    $absX = $shot.X + $row.X
                    $absY = $shot.Y + $row.Y
                    if ([Math]::Abs($absX - $x) -le $padX -and [Math]::Abs($absY - $y) -le $padY) {
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    [pscustomobject]@{
                        ok     = $false
                        reason = "落点附近没有找到预期文字「$needle」，已拒绝点击（坐标可能已过期，先截图确认再重试）。"
                        expect = @{ text = $needle; found = $false; point = @{ x = $x; y = $y } }
                    } | ConvertTo-Json -Compress -Depth 6
                    break
                }
            }
            catch {
                [pscustomobject]@{
                    ok     = $false
                    reason = "expect 校验失败（$($_.Exception.Message)），按安全默认拒绝点击。"
                } | ConvertTo-Json -Compress -Depth 6
                break
            }
            finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }

        if ($null -ne $x) {
            [void][GuiNative]::MoveTo($x, $y)
            Start-Sleep -Milliseconds 60
        }
        for ($k = 0; $k -lt $count; $k++) {
            [GuiNative]::MouseButton($button, $true)
            Start-Sleep -Milliseconds 40
            [GuiNative]::MouseButton($button, $false)
            if ($k -lt $count - 1) { Start-Sleep -Milliseconds $gap }
        }
        $pt = [GuiNative]::Cursor()
        if ($verify) {
            Initialize-Uia
            $focus = [UiaNative]::FocusedInfo()
            $obj = [ordered]@{
                ok           = $true
                clicked      = @{ x = $pt.X; y = $pt.Y }
                focus        = (Focus-Object $focus)
                verification = @{ status = 'unknown'; method = 'hit-test'; detail = '落点已校验；应用侧结果需另行确认' }
            }
            if ($null -ne $hitTest) { $obj.hitTest = $hitTest }
            [pscustomobject]$obj | ConvertTo-Json -Compress -Depth 6
        } else {
            "click {0} x{1} @ {2},{3}" -f $button, $count, $pt.X, $pt.Y
        }
    }

    'drag' {
        if ($rest.Count -lt 4) { throw "drag 需要 x1 y1 x2 y2" }
        $button = if ($opt.ContainsKey('button')) { [string]$opt['button'] } else { 'left' }
        [GuiNative]::MoveTo([int]$rest[0], [int]$rest[1])
        Start-Sleep -Milliseconds 60
        [GuiNative]::MouseButton($button, $true)
        Start-Sleep -Milliseconds 80
        $x1 = [int]$rest[0]; $y1 = [int]$rest[1]; $x2 = [int]$rest[2]; $y2 = [int]$rest[3]
        for ($s = 1; $s -le 10; $s++) {
            $mx = [int]($x1 + ($x2 - $x1) * $s / 10.0)
            $my = [int]($y1 + ($y2 - $y1) * $s / 10.0)
            [GuiNative]::MoveTo($mx, $my)
            Start-Sleep -Milliseconds 15
        }
        Start-Sleep -Milliseconds 80
        [GuiNative]::MouseButton($button, $false)
        "drag {0} ({1},{2}) -> ({3},{4})" -f $button, $x1, $y1, $x2, $y2
    }

    'scroll' {
        if ($rest.Count -ge 3) { [GuiNative]::MoveTo([int]$rest[0], [int]$rest[1]); Start-Sleep -Milliseconds 40 }
        $d = if ($rest.Count -ge 3) { [int]$rest[2] } else { [int]$rest[0] }
        [GuiNative]::Scroll($d)
        "scroll $d"
    }

    'type' {
        # 文本走 base64：PowerShell 5.1 的 -File 绑定不接受 `--`，且以 - 开头的文本
        # 会被当成参数；base64 两种情况都能避开。
        $text = ''
        if ($opt.ContainsKey('b64')) {
            try { $text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String([string]$opt['b64'])) }
            catch { throw 'type: -b64 参数不是合法的 base64' }
        } else {
            $text = [string]::Join(' ', ($rest | ForEach-Object { [string]$_ }))
        }
        if ($text -eq '') { throw "type 需要文本" }
        $text = $text -replace '\\n', "`n" -replace '\\t', "`t"

        $verify = $opt.ContainsKey('verify')
        $activation = $null
        if ($opt.ContainsKey('window')) {
            $hwnd = [GuiNative]::FindWindow([string]$opt['window'])
            if ($hwnd -eq [IntPtr]::Zero) { throw "type: 找不到窗口 ""$($opt['window'])""" }
            $activation = (Ensure-Foreground $hwnd 900)
            if (-not $activation) {
                Initialize-Uia
                [pscustomobject]@{
                    ok        = $false
                    reason    = '目标窗口未能切到前台，已拒绝输入（否则文字会打进当前焦点窗口）。请让用户先切到目标窗口，或改用 click 激活后再试。'
                    activated = $false
                    focus     = (Focus-Object ([UiaNative]::FocusedInfo()))
                } | ConvertTo-Json -Compress -Depth 6
                break
            }
        }

        # 输入前再确认一次前台：激活到这里之间用户可能又切走了。
        if ($opt.ContainsKey('window') -and ([GuiNative]::GetForegroundWindow() -ne $hwnd)) {
            [pscustomobject]@{ ok = $false; reason = '输入前目标窗口失去前台，已拒绝输入'; activated = $false } |
                ConvertTo-Json -Compress -Depth 6
            break
        }

        if ($verify) {
            Initialize-Uia
            $focus = [UiaNative]::FocusedInfo()
            if ($focus.Ok -and $focus.NonEditable) {
                [pscustomobject]@{
                    ok     = $false
                    reason = "焦点控件「$($focus.Name)」($($focus.Type)) 不可编辑，已拒绝输入（否则键盘输入会静默丢失）。先用 click 点中输入框再重试。"
                    focus  = (Focus-Object $focus)
                } | ConvertTo-Json -Compress -Depth 6
                break
            }
        }

        if ($opt.ContainsKey('raw')) {
            [GuiNative]::TypeText($text)
            if ($verify) {
                Start-Sleep -Milliseconds 120
                $after = [UiaNative]::FocusedInfo()
                [pscustomobject]@{
                    ok           = $true
                    typed        = $text.Length
                    verification = (Get-ReadbackVerdict $after $text)
                    focus        = (Focus-Object $after)
                    activated    = $activation
                } | ConvertTo-Json -Compress -Depth 6
            } else {
                "typed {0} chars (raw)" -f $text.Length
            }
            break
        }

        # 默认走剪贴板粘贴：对中文/任意 Unicode 都可靠，且结束后还原原剪贴板
        $old = $null
        try { $old = Get-Clipboard -Raw -ErrorAction Stop } catch { }
        try { Set-Clipboard -Value $text -ErrorAction Stop }
        catch { [System.Windows.Forms.Clipboard]::SetText($text) }
        Start-Sleep -Milliseconds 120

        [GuiNative]::KeyDown(0x11)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyDown(0x56)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyUp(0x56)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyUp(0x11)
        Start-Sleep -Milliseconds 180

        if ($null -ne $old -and $old -ne '') {
            try { Set-Clipboard -Value $old -ErrorAction Stop }
            catch { try { [System.Windows.Forms.Clipboard]::SetText($old) } catch { } }
        }

        if ($verify) {
            Start-Sleep -Milliseconds 120
            $after = [UiaNative]::FocusedInfo()
            [pscustomobject]@{
                ok           = $true
                typed        = $text.Length
                verification = (Get-ReadbackVerdict $after $text)
                focus        = (Focus-Object $after)
                activated    = $activation
            } | ConvertTo-Json -Compress -Depth 6
        } else {
            "pasted {0} chars" -f $text.Length
        }
    }

    'key' {
        if ($rest.Count -lt 1) { throw "key 需要组合键，例如 ctrl+s" }
        $combo = [string]::Join('+', ($rest | ForEach-Object { [string]$_ }))

        $map = @{
            'ctrl' = 0x11; 'control' = 0x11; 'shift' = 0x10; 'alt' = 0x12; 'win' = 0x5B; 'lwin' = 0x5B; 'rwin' = 0x5C
            'enter' = 0x0D; 'return' = 0x0D; 'esc' = 0x1B; 'escape' = 0x1B; 'space' = 0x20; 'tab' = 0x09
            'backspace' = 0x08; 'bs' = 0x08; 'delete' = 0x2E; 'del' = 0x2E; 'insert' = 0x2D; 'ins' = 0x2D
            'home' = 0x24; 'end' = 0x23; 'pageup' = 0x21; 'pgup' = 0x21; 'pagedown' = 0x22; 'pgdn' = 0x22
            'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27
            'capslock' = 0x14; 'printscreen' = 0x2C; 'pause' = 0x13; 'apps' = 0x5D
        }
        for ($n = 1; $n -le 24; $n++) { $map["f$n"] = 0x6F + $n }

        function Resolve-Vk([string]$t) {
            $t = $t.Trim().ToLowerInvariant()
            if ($map.ContainsKey($t)) { return [int]$map[$t] }
            if ($t -match '^[a-z]$') { return [int][char]([char]::ToUpperInvariant($t)) }
            if ($t -match '^\d$') { return 0x30 + [int]$t }
            $aliases = @{
                '-' = 0xBD; '=' = 0xBB; '[' = 0xDB; ']' = 0xDD; '\' = 0xDC; ';' = 0xBA; "'" = 0xDE
                ',' = 0xBC; '.' = 0xBE; '/' = 0xBF; '`' = 0xC0
            }
            if ($aliases.ContainsKey($t)) { return [int]$aliases[$t] }
            throw "无法识别的按键: $t"
        }

        $parts = $combo -split '\+'
        $vks = @()
        foreach ($p in $parts) { if ($p.Trim() -ne '') { $vks += (Resolve-Vk $p) } }
        if ($vks.Count -eq 0) { throw "组合键为空" }

        $mods = @()
        foreach ($v in $vks[0..($vks.Count - 2)]) { $mods += [uint16]$v }
        $last = [uint16]$vks[$vks.Count - 1]

        foreach ($m in $mods) { [GuiNative]::KeyDown($m); Start-Sleep -Milliseconds 25 }
        [GuiNative]::KeyDown($last)
        Start-Sleep -Milliseconds 35
        [GuiNative]::KeyUp($last)
        for ($k = $mods.Count - 1; $k -ge 0; $k--) { [GuiNative]::KeyUp($mods[$k]); Start-Sleep -Milliseconds 25 }
        "key $combo"
    }

    'wait' {
        $ms = if ($rest.Count -ge 1) { [int]$rest[0] } else { 500 }
        Start-Sleep -Milliseconds $ms
        "waited $ms ms"
    }

    'elements' {
        Initialize-Uia
        $hwnd = [IntPtr]::Zero
        if ($opt.ContainsKey('hwnd')) { $hwnd = [IntPtr]([long]$opt['hwnd']) }
        elseif ($opt.ContainsKey('window')) { $hwnd = [GuiNative]::FindWindow([string]$opt['window']) }
        else { $hwnd = [GuiNative]::GetForegroundWindow() }
        if ($hwnd -eq [IntPtr]::Zero) { throw 'elements: 找不到目标窗口' }
        if ([GuiNative]::IsIconic($hwnd)) { throw 'elements: 目标窗口已最小化，先用 activate 还原' }

        $maxNodes = if ($opt.ContainsKey('maxnodes')) { [int]$opt['maxnodes'] } else { 220 }
        $maxDepth = if ($opt.ContainsKey('depth')) { [int]$opt['depth'] } else { 9 }
        $needle = if ($opt.ContainsKey('filter')) { [string]$opt['filter'] } else { '' }

        $sb = New-Object System.Text.StringBuilder 512
        [void][GuiNative]::GetWindowText($hwnd, $sb, 512)
        $l = 0; $t = 0; $w = 0; $h = 0
        [void][GuiNative]::GetRect($hwnd, [ref]$l, [ref]$t, [ref]$w, [ref]$h)

        $rows = [UiaNative]::Walk($hwnd, $maxNodes, $maxDepth)
        $showAll = $opt.ContainsKey('all')
        $kept = @()
        foreach ($row in $rows) {
            if ($needle) {
                if (($row.Name -notlike "*$needle*") -and ($row.Id -notlike "*$needle*")) { continue }
            }
            elseif (-not $showAll -and $row.Name -eq '' -and $row.Id -eq '') { continue }
            $kept += $row
        }

        "# window: {0} | hwnd=0x{1:X} | {2}x{3} at {4},{5} | nodes={6}" -f $sb.ToString(), $hwnd.ToInt64(), $w, $h, $l, $t, $kept.Count
        "# columns: centerX,centerY,width,height | ControlType | Name | AutomationId | flags"
        foreach ($row in $kept) {
            $flags = @()
            if ($row.Invokable) { $flags += 'invoke' }
            if (-not $row.Enabled) { $flags += 'disabled' }
            $cx = [int]($row.X + [Math]::Floor($row.W / 2))
            $cy = [int]($row.Y + [Math]::Floor($row.H / 2))
            $clean = (($row.Name -replace '[|\r\n\t]+', '/')).Trim()
            "{0},{1},{2},{3}|{4}|{5}|{6}|{7}" -f $cx, $cy, $row.W, $row.H, $row.Type, $clean, $row.Id, ($flags -join ',')
        }
    }

    'ocr' {
        $path = if ($rest.Count -ge 1) { [string]$rest[0] } else { throw 'ocr 需要图片路径' }
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path (Get-Location).Path $path }
        $path = [System.IO.Path]::GetFullPath($path)
        if (-not (Test-Path $path)) { throw "找不到图片: $path" }

        $needle = if ($opt.ContainsKey('filter')) { [string]$opt['filter'] } else { '' }
        $zoom = if ($opt.ContainsKey('zoom')) { [double]$opt['zoom'] } else { 2.0 }

        $ocr = Invoke-OcrFile -Path $path -Zoom $zoom -Filter $needle

        "# ocr: {0} | {1} lines | lang={2} | zoom={3} | coords are screen pixels" -f $path, $ocr.LineCount, $ocr.Lang, $ocr.Zoom
        "# columns: centerX,centerY,width,height | text"
        foreach ($row in $ocr.Rows) {
            "{0},{1},{2},{3}|{4}" -f $row.X, $row.Y, $row.W, $row.H, $row.Text
        }
    }

    'find' {
        # 本地 OCR 直接找文字并给出屏幕坐标：模型不必读整屏文字，token 从上千降到几十。
        $needle = if ($rest.Count -ge 1) { [string]$rest[0] } else { throw 'find 需要要查找的文字，例如: find 保存' }
        $zoom = if ($opt.ContainsKey('zoom')) { [double]$opt['zoom'] } else { 2.0 }
        $threshold = if ($opt.ContainsKey('threshold')) { [double]$opt['threshold'] } else { 0.55 }

        $hwnd = [IntPtr]::Zero
        if ($opt.ContainsKey('window')) { $hwnd = [GuiNative]::FindWindow([string]$opt['window']) }
        elseif ($opt.ContainsKey('hwnd')) { $hwnd = [IntPtr]([long]$opt['hwnd']) }
        if ($opt.ContainsKey('window') -and $hwnd -eq [IntPtr]::Zero) { throw "find: 找不到窗口 ""$($opt['window'])""" }
        if ($hwnd -ne [IntPtr]::Zero -and [GuiNative]::IsIconic($hwnd)) { throw 'find: 目标窗口已最小化，先用 activate 还原' }
        $region = $null
        if ($opt.ContainsKey('region')) { $region = Get-RectFromString ([string]$opt['region']) }

        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dsh-find-' + [Guid]::NewGuid().ToString('N') + '.png')
        $rect = $null
        $ocr = $null
        # 前台窗口直接截屏幕（真实像素，GPU 渲染的应用也能读到）；
        # 只有被遮挡的窗口才用 PrintWindow —— 它对部分应用会返回空白图。
        $fg = [GuiNative]::GetForegroundWindow()
        $usePrint = ($hwnd -ne [IntPtr]::Zero) -and ($hwnd -ne $fg) -and ($null -eq $region) -and (-not $opt.ContainsKey('screen'))
        try {
            $rect = Save-QuickShot -Hwnd $hwnd -Region $region -Out $tmp -Print:$usePrint
            $ocr = Invoke-OcrFile -Path $tmp -Zoom $zoom
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }

        $all = @()
        foreach ($row in $ocr.Rows) {
            $all += [pscustomobject]@{
                Score = (Get-MatchScore -Candidate $row.Text -Needle $needle)
                X     = $rect.X + $row.X
                Y     = $rect.Y + $row.Y
                W     = $row.W
                H     = $row.H
                Text  = $row.Text
            }
        }
        $all = @($all | Sort-Object Score -Descending)
        if ($opt.ContainsKey('exact')) {
            $want = Normalize-UiText $needle
            $scored = @($all | Where-Object { (Normalize-UiText $_.Text) -eq $want })
        } else {
            $scored = @($all | Where-Object { $_.Score -ge $threshold })
        }

        $scope = if ($hwnd -ne [IntPtr]::Zero) { 'window' } elseif ($null -ne $region) { 'region' } else { 'screen' }
        "# find `"$needle`" | $scope $($rect.W)x$($rect.H) at $($rect.X),$($rect.Y) | $($ocr.LineCount) lines | matches=$($scored.Count)"
        if ($scored.Count -eq 0) {
            'notfound'
            if ($ocr.LineCount -eq 0) {
                if ($usePrint) { "# hint: 后台截图是空白（该应用不支持 PrintWindow），先 activate 把它提到前台再找" }
                else { "# hint: 这一屏没有可识别文字（纯图形界面），改用 screenshot" }
            }
            # 未命中时给最接近的几行，模型据此换关键词，而不是再读一遍整屏
            $n = 0
            foreach ($m in $all) {
                if ($n -ge 3) { break }
                if ($m.Score -le 0.15) { break }
                $n++
                "closest|{0:N2}|{1},{2}|{3}" -f $m.Score, $m.X, $m.Y, $m.Text
            }
            return
        }
        $n = 0
        foreach ($m in $scored) {
            if ($n -ge 5) { break }
            $n++
            "{0},{1},{2},{3}|{4:N2}|{5}" -f $m.X, $m.Y, $m.W, $m.H, $m.Score, $m.Text
        }
        if ($opt.ContainsKey('click')) {
            $chosen = $null
            if ($opt.ContainsKey('index')) {
                $idx = [int]$opt['index']
                if ($idx -lt 1 -or $idx -gt $scored.Count) {
                    'notfound'
                    "# index $idx out of range (matches=$($scored.Count)); nothing clicked"
                    return
                }
                $chosen = $scored[$idx - 1]
            }
            elseif ($scored.Count -gt 1) {
                foreach ($m in ($scored | Select-Object -First 5)) {
                    "ambiguous|{0:N2}|{1},{2}|{3}" -f $m.Score, $m.X, $m.Y, $m.Text
                }
                "# click refused: $($scored.Count) matches; pass index:N (or exact:true) to choose one"
                return
            }
            else {
                $chosen = $scored[0]
            }

            if ($hwnd -ne [IntPtr]::Zero) {
                $root = [GuiNative]::HitTestRoot($chosen.X, $chosen.Y)
                $expectedRoot = [GuiNative]::RootOf($hwnd)
                $exactMatch = ($root -eq $expectedRoot)
                $sameProcess = $false
                if (-not $exactMatch -and $root -ne [IntPtr]::Zero) {
                    $sameProcess = ([GuiNative]::PidOf($root) -eq [GuiNative]::PidOf($expectedRoot))
                }
                if (-not $exactMatch -and -not $sameProcess) {
                    '# click refused: hit-test mismatch (the point belongs to another window)'
                    return
                }
            }
            $button = if ($opt.ContainsKey('button')) { [string]$opt['button'] } else { 'left' }
            [void][GuiNative]::MoveTo($chosen.X, $chosen.Y)
            Start-Sleep -Milliseconds 60
            [GuiNative]::MouseButton($button, $true)
            Start-Sleep -Milliseconds 40
            [GuiNative]::MouseButton($button, $false)
            "clicked $button @ $($chosen.X),$($chosen.Y)"
        }
    }

    'seq' {
        $file = if ($opt.ContainsKey('file')) { [string]$opt['file'] } else { throw 'seq 需要 -file ops.json' }
        if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path (Get-Location).Path $file }
        if (-not (Test-Path $file)) { throw "找不到 ops 文件: $file" }

        $ops = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ops -isnot [System.Array]) { $ops = @($ops) }
        $defaultDelay = if ($opt.ContainsKey('delay')) { [int]$opt['delay'] } else { 60 }

        $i = 0
        foreach ($op in $ops) {
            $i++
            $subCmd = [string]$op.cmd
            $subRest = @()
            if ($null -ne $op.rest) { $subRest = @($op.rest | ForEach-Object { [string]$_ }) }
            $subOpt = @{}
            if ($null -ne $op.opt) {
                foreach ($p in $op.opt.PSObject.Properties) { $subOpt[$p.Name.ToLowerInvariant()] = $p.Value }
            }
            try {
                $r = Invoke-GuiCmd $subCmd $subRest $subOpt
                $text = ($r | Out-String).Trim()
                "[$i] $subCmd ok"
                if ($text) { $text }
            }
            catch {
                "[$i] $subCmd FAILED: $($_.Exception.Message)"
                break
            }
            if ($i -lt $ops.Count) {
                $ms = if ($op.delayMs) { [int]$op.delayMs } else { $defaultDelay }
                if ($ms -gt 0) { Start-Sleep -Milliseconds $ms }
            }
        }
    }

    default {
        Write-Host "未知命令: $cmd"
        Write-Host "可用: windows | pos | fg | shot | elements | ocr | seq | activate | move | click | drag | scroll | type | key | wait"
        exit 1
    }
}
}

Invoke-GuiCmd $cmd $rest $opt
