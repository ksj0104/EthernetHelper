using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace EthernetHelper
{
    public sealed class AdapterInfo
    {
        public string guid { get; set; }
        public string name { get; set; }
        public string description { get; set; }
        public string mac { get; set; }
        public string linkSpeed { get; set; }
        public string status { get; set; }
        public object ipv4 { get; set; }
        public object gateway { get; set; }
        public object dhcp { get; set; }
        public override string ToString()
        {
            return String.IsNullOrWhiteSpace(description) ? (name ?? "이더넷") : (name ?? "이더넷") + "  ·  " + description;
        }
    }

    public sealed class EngineResult
    {
        public bool ok { get; set; }
        public string status { get; set; }
        public string title { get; set; }
        public string message { get; set; }
        public string[] details { get; set; }
        public AdapterInfo[] adapters { get; set; }
        public AdapterInfo adapter { get; set; }
        public bool canRepair { get; set; }
        public bool canRestore { get; set; }
        public string logPath { get; set; }

        public static EngineResult Parse(string json)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = 8 * 1024 * 1024;
            EngineResult result = serializer.Deserialize<EngineResult>(json);
            if (result == null || String.IsNullOrWhiteSpace(result.title))
                throw new InvalidDataException("진단 결과에 필요한 내용이 없습니다.");
            return result;
        }
    }

    public static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        // CommandLineToArgvW-compatible quoting. Never build or execute shell commands.
        public static string QuoteArgument(string value)
        {
            if (value == null) value = String.Empty;
            StringBuilder quoted = new StringBuilder("\"");
            int slashes = 0;
            foreach (char ch in value)
            {
                if (ch == '\\') { slashes++; continue; }
                if (ch == '"')
                {
                    quoted.Append('\\', slashes * 2 + 1);
                    quoted.Append(ch);
                }
                else
                {
                    quoted.Append('\\', slashes);
                    quoted.Append(ch);
                }
                slashes = 0;
            }
            quoted.Append('\\', slashes * 2);
            quoted.Append('"');
            return quoted.ToString();
        }

        [STAThread]
        public static int Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--self-test")
            {
                int code = RunSelfTest();
                string result = code == 0 ? "PASS: JSON parsing, required fields, Korean text and Windows argument quoting." : "FAIL: self-test case " + code.ToString();
                Console.WriteLine(result);
                if (args.Length > 1) File.WriteAllText(args[1], result, new UTF8Encoding(true));
                return code;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { SetProcessDPIAware(); } catch (EntryPointNotFoundException) { }
            Application.ThreadException += delegate(object sender, System.Threading.ThreadExceptionEventArgs e)
            {
                MessageBox.Show("화면을 처리하는 중 문제가 발생했습니다. 프로그램을 다시 실행해 주세요.\r\n\r\n" + e.Exception.Message,
                    "이더넷 연결 도우미", MessageBoxButtons.OK, MessageBoxIcon.Error);
            };
            Application.Run(new MainForm());
            return 0;
        }

        private static int RunSelfTest()
        {
            try
            {
                if (QuoteArgument("") != "\"\"") return 11;
                if (QuoteArgument("a b") != "\"a b\"") return 12;
                if (QuoteArgument("C:\\folder\\") != "\"C:\\folder\\\\\"") return 13;
                if (QuoteArgument("a\"b") != "\"a\\\"b\"") return 14;
                if (QuoteArgument("a\\\"b") != "\"a\\\\\\\"b\"") return 15;
                EngineResult r = EngineResult.Parse("{\"ok\":true,\"title\":\"진단 완료\",\"adapters\":[{\"guid\":\"test\",\"name\":\"이더넷\"}],\"adapter\":{\"ipv4\":[\"192.0.2.1\"],\"dhcp\":true},\"canRepair\":false,\"details\":[\"연결됨\"]}");
                if (!r.ok || r.adapters.Length != 1 || r.adapters[0].name != "이더넷" || r.canRepair) return 16;
                bool invalidRejected = false;
                try { EngineResult.Parse("{}"); } catch (InvalidDataException) { invalidRejected = true; }
                if (!invalidRejected) return 17;
                return 0;
            }
            catch { return 19; }
        }
    }

    public sealed class CardPanel : Panel
    {
        public CardPanel()
        {
            BackColor = Color.White;
            DoubleBuffered = true;
            Padding = new Padding(20, 15, 20, 15);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen pen = new Pen(Color.FromArgb(224, 231, 238)))
                e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        }
    }

    public sealed class MainForm : Form
    {
        private static readonly Color Ink = Color.FromArgb(26, 42, 58);
        private static readonly Color Muted = Color.FromArgb(92, 109, 126);
        private static readonly Color Blue = Color.FromArgb(28, 91, 215);
        private static readonly Color Teal = Color.FromArgb(15, 120, 106);
        private readonly string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
        private readonly string dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "EthernetHelper");
        private readonly Timer pollTimer;
        private readonly Label statusTitle;
        private readonly Label statusMessage;
        private readonly Label statusBadge;
        private readonly Label footerText;
        private readonly Label adapterSummary;
        private readonly ComboBox adapterPicker;
        private readonly RichTextBox detailText;
        private readonly Button diagnoseButton;
        private readonly Button repairButton;
        private readonly Button restoreButton;
        private readonly Button logsButton;
        private readonly Button refreshButton;
        private readonly ProgressBar progress;
        private readonly StringBuilder capturedOutput = new StringBuilder();
        private Process activeProcess;
        private DateTime operationStarted;
        private string activeAction;
        private string activeOutputPath;
        private string lastLogPath;
        private EngineResult lastResult;
        private bool busy;
        private bool suppressSelection;
        private bool slowNoticeShown;

        public MainForm()
        {
            Text = "이더넷 연결 도우미";
            Name = "MainForm";
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(940, 760);
            MinimumSize = new Size(830, 700);
            Font = new Font("맑은 고딕", 9F, FontStyle.Regular, GraphicsUnit.Point);
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            BackColor = Color.FromArgb(244, 247, 251);
            ForeColor = Ink;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            TableLayoutPanel main = new TableLayoutPanel();
            main.Dock = DockStyle.Fill;
            main.Padding = new Padding(28, 23, 28, 18);
            main.ColumnCount = 1;
            main.RowCount = 7;
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 75));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 140));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 116));
            main.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 21));
            Controls.Add(main);

            Panel header = new Panel { Dock = DockStyle.Fill, Margin = new Padding(0) };
            Label brand = MakeLabel("이더넷 연결 도우미", 23, FontStyle.Bold, Ink);
            brand.SetBounds(0, 0, 670, 41);
            Label subtitle = MakeLabel("연결 상태를 확인하고, 문제가 생겼을 때 직접 복구하세요.", 10, FontStyle.Regular, Muted);
            subtitle.SetBounds(1, 44, 750, 24);
            header.Controls.Add(brand);
            header.Controls.Add(subtitle);
            main.Controls.Add(header, 0, 0);

            CardPanel statusCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 12) };
            TableLayoutPanel statusLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, Margin = new Padding(0) };
            statusLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            statusLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 106));
            statusLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
            statusLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            statusLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 6));
            statusTitle = MakeLabel("유선 연결을 확인하고 있습니다", 17, FontStyle.Bold, Ink);
            statusTitle.Name = "StatusTitle";
            statusTitle.Dock = DockStyle.Fill;
            statusTitle.AutoEllipsis = true;
            statusBadge = MakeLabel("확인 중", 9, FontStyle.Bold, Blue);
            statusBadge.TextAlign = ContentAlignment.MiddleCenter;
            statusBadge.BackColor = Color.FromArgb(234, 241, 255);
            statusBadge.Dock = DockStyle.Fill;
            statusBadge.Margin = new Padding(5, 2, 0, 4);
            statusMessage = MakeLabel("이 컴퓨터의 이더넷 어댑터를 찾는 중입니다.", 10, FontStyle.Regular, Muted);
            statusMessage.Name = "StatusMessage";
            statusMessage.Dock = DockStyle.Fill;
            statusMessage.AutoEllipsis = true;
            statusMessage.Padding = new Padding(0, 4, 0, 0);
            progress = new ProgressBar { Dock = DockStyle.Fill, Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 30, Margin = new Padding(0), Visible = false };
            statusLayout.Controls.Add(statusTitle, 0, 0);
            statusLayout.Controls.Add(statusBadge, 1, 0);
            statusLayout.Controls.Add(statusMessage, 0, 1);
            statusLayout.SetColumnSpan(statusMessage, 2);
            statusLayout.Controls.Add(progress, 0, 2);
            statusLayout.SetColumnSpan(progress, 2);
            statusCard.Controls.Add(statusLayout);
            main.Controls.Add(statusCard, 0, 1);

            CardPanel adapterCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 12), Padding = new Padding(18, 10, 18, 9) };
            TableLayoutPanel adapterLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3 };
            adapterLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            adapterLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 93));
            adapterLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
            adapterLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
            adapterLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            Label adapterLabel = MakeLabel("확인할 유선 연결", 9, FontStyle.Bold, Ink);
            adapterLabel.Dock = DockStyle.Fill;
            adapterPicker = new ComboBox { Name = "AdapterPicker", Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, IntegralHeight = false, DropDownHeight = 180, Margin = new Padding(0, 1, 12, 0) };
            adapterPicker.SelectedIndexChanged += AdapterChanged;
            refreshButton = MakeButton("새로 고침", false);
            refreshButton.Name = "RefreshButton";
            refreshButton.Dock = DockStyle.Fill;
            refreshButton.Margin = new Padding(0, 0, 0, 2);
            refreshButton.Click += delegate { StartOperation("Inventory", false); };
            adapterSummary = MakeLabel("어댑터를 찾는 중", 9, FontStyle.Regular, Muted);
            adapterSummary.Name = "AdapterSummary";
            adapterSummary.Dock = DockStyle.Fill;
            adapterSummary.AutoEllipsis = true;
            adapterSummary.Padding = new Padding(0, 3, 0, 0);
            adapterLayout.Controls.Add(adapterLabel, 0, 0);
            adapterLayout.SetColumnSpan(adapterLabel, 2);
            adapterLayout.Controls.Add(adapterPicker, 0, 1);
            adapterLayout.Controls.Add(refreshButton, 1, 1);
            adapterLayout.Controls.Add(adapterSummary, 0, 2);
            adapterLayout.SetColumnSpan(adapterSummary, 2);
            adapterCard.Controls.Add(adapterLayout);
            main.Controls.Add(adapterCard, 0, 2);

            CardPanel detailsCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 8), Padding = new Padding(18, 12, 18, 12) };
            Label detailsLabel = MakeLabel("연결 상태와 진단 결과", 10, FontStyle.Bold, Ink);
            detailsLabel.Dock = DockStyle.Top;
            detailsLabel.Height = 29;
            detailText = new RichTextBox { Name = "DetailText", Dock = DockStyle.Fill, BorderStyle = BorderStyle.None, ReadOnly = true, BackColor = Color.White, ForeColor = Ink, Font = new Font("맑은 고딕", 10F), DetectUrls = false, TabStop = true, ScrollBars = RichTextBoxScrollBars.Vertical, Text = "잠시만 기다려 주세요." };
            detailsCard.Controls.Add(detailText);
            detailsCard.Controls.Add(detailsLabel);
            main.Controls.Add(detailsCard, 0, 3);

            TableLayoutPanel buttons = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 1, Margin = new Padding(0), Padding = new Padding(0, 6, 0, 9) };
            buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 24));
            buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 28));
            buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 27));
            buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 21));
            diagnoseButton = MakeButton("진단하기", true);
            diagnoseButton.Name = "DiagnoseButton";
            diagnoseButton.Click += delegate { StartOperation("Diagnose", false); };
            repairButton = MakeButton("IP 충돌 복구", false);
            repairButton.Name = "RepairButton";
            repairButton.ForeColor = Teal;
            repairButton.FlatAppearance.BorderColor = Color.FromArgb(176, 215, 207);
            repairButton.Click += delegate { StartOperation("Repair", true); };
            restoreButton = MakeButton("변경 되돌리기", false);
            restoreButton.Name = "RestoreButton";
            restoreButton.Click += delegate { StartOperation("Restore", true); };
            logsButton = MakeButton("기록 폴더", false);
            logsButton.Name = "LogsButton";
            logsButton.Click += delegate { OpenLogFolder(); };
            Button[] actionButtons = { diagnoseButton, repairButton, restoreButton, logsButton };
            for (int i = 0; i < actionButtons.Length; i++)
            {
                actionButtons[i].Dock = DockStyle.Fill;
                actionButtons[i].Margin = new Padding(0, 0, i == actionButtons.Length - 1 ? 0 : 9, 0);
                buttons.Controls.Add(actionButtons[i], i, 0);
            }
            main.Controls.Add(buttons, 0, 4);

            Label actionNote = MakeLabel("복구는 선택한 어댑터의 설정을 보관하고 변경합니다. 실행 중 연결이 잠시 끊길 수 있습니다.\r\n되돌리면 이전 IP 충돌이 다시 생길 수 있습니다. 복구·되돌리기에만 관리자 승인이 필요합니다.", 9, FontStyle.Regular, Muted);
            actionNote.Dock = DockStyle.Fill;
            actionNote.Margin = new Padding(1, 0, 0, 0);
            main.Controls.Add(actionNote, 0, 5);
            footerText = MakeLabel("자동 복구 없이, 실행할 때만 확인합니다.", 8.5F, FontStyle.Regular, Muted);
            footerText.Name = "FooterText";
            footerText.Dock = DockStyle.Fill;
            footerText.Margin = new Padding(1, 0, 0, 0);
            main.Controls.Add(footerText, 0, 6);

            ToolTip hints = new ToolTip();
            hints.SetToolTip(repairButton, "현재 IP 충돌이면 장치 주소(MAC)를 바꾸고 DHCP 주소를 다시 받습니다.\nDHCP 응답 문제는 어댑터를 재시작합니다. 기존 설정은 보관합니다.\n공유기의 중복 할당 원인은 별도 확인이 필요합니다.");
            hints.SetToolTip(restoreButton, "이 프로그램이 보관한 어댑터 설정을 복원합니다.\n이전 IP 충돌이 다시 발생할 수 있습니다.");
            hints.SetToolTip(logsButton, "진단 결과와 설정 백업이 저장된 폴더를 엽니다.");
            pollTimer = new Timer { Interval = 350 };
            pollTimer.Tick += PollProcess;
            FormClosing += CheckBeforeClosing;
            Shown += delegate { BeginInvoke(new Action(delegate { StartOperation("Inventory", false); })); };
            UpdateButtons();
        }

        private static Label MakeLabel(string text, float size, FontStyle style, Color color)
        {
            return new Label { Text = text, Font = new Font("맑은 고딕", size, style), ForeColor = color, Margin = new Padding(0), TextAlign = ContentAlignment.MiddleLeft };
        }

        private static Button MakeButton(string text, bool primary)
        {
            Button button = new Button { Text = text, Font = new Font("맑은 고딕", 10F, FontStyle.Bold), Cursor = Cursors.Hand, FlatStyle = FlatStyle.Flat, BackColor = primary ? Blue : Color.White, ForeColor = primary ? Color.White : Ink, UseVisualStyleBackColor = false, AutoEllipsis = true };
            button.FlatAppearance.BorderSize = primary ? 0 : 1;
            button.FlatAppearance.BorderColor = Color.FromArgb(210, 221, 232);
            button.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(22, 76, 182) : Color.FromArgb(238, 243, 249);
            return button;
        }

        private AdapterInfo SelectedAdapter { get { return adapterPicker.SelectedItem as AdapterInfo; } }
        private bool IsMutating { get { return activeAction == "Repair" || activeAction == "Restore"; } }

        private void AdapterChanged(object sender, EventArgs e)
        {
            if (suppressSelection || busy) return;
            lastResult = null;
            UpdateAdapterSummary(SelectedAdapter);
            UpdateButtons();
            if (SelectedAdapter != null) StartOperation("Diagnose", false);
        }

        private void UpdateButtons()
        {
            bool selected = SelectedAdapter != null;
            adapterPicker.Enabled = !busy && adapterPicker.Items.Count > 0;
            refreshButton.Enabled = !busy;
            diagnoseButton.Enabled = !busy && selected;
            repairButton.Enabled = !busy && selected && lastResult != null && lastResult.canRepair;
            restoreButton.Enabled = !busy && selected && lastResult != null && lastResult.canRestore;
            logsButton.Enabled = true;
            progress.Visible = busy;
        }

        private void SetBusy(bool value)
        {
            busy = value;
            UpdateButtons();
        }

        public void StartOperation(string action, bool elevate)
        {
            if (busy) return;
            if (action != "Inventory" && action != "Diagnose" && action != "Repair" && action != "Restore")
                throw new ArgumentException("지원하지 않는 작업입니다.", "action");
            bool mutation = action == "Repair" || action == "Restore";
            if (mutation != elevate) throw new ArgumentException("작업에 필요한 권한이 일치하지 않습니다.");
            AdapterInfo selected = SelectedAdapter;
            if (action != "Inventory" && selected == null) return;
            if (action == "Repair" && (lastResult == null || !lastResult.canRepair)) return;
            if (action == "Restore" && (lastResult == null || !lastResult.canRestore)) return;
            activeAction = action;
            slowNoticeShown = false;
            try
            {
                string enginePath = Path.Combine(appDirectory, "Engine.ps1");
                if (!File.Exists(enginePath)) throw new FileNotFoundException("프로그램 폴더에 Engine.ps1 파일이 없습니다. 전체 프로그램 폴더를 함께 보관해 주세요.");
                string runDirectory = Path.Combine(dataDirectory, "runs");
                Directory.CreateDirectory(runDirectory);
                activeOutputPath = Path.Combine(runDirectory, DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N") + ".json");
                string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                string arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File " + Program.QuoteArgument(enginePath) + " -Action " + Program.QuoteArgument(action);
                if (selected != null && action != "Inventory") arguments += " -AdapterGuid " + Program.QuoteArgument(selected.guid);
                arguments += " -OutputPath " + Program.QuoteArgument(activeOutputPath);
                ProcessStartInfo info = new ProcessStartInfo(powershell, arguments);
                info.WorkingDirectory = appDirectory;
                info.UseShellExecute = elevate;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                if (elevate) info.Verb = "runas";
                else
                {
                    info.CreateNoWindow = true;
                    info.RedirectStandardError = true;
                    info.RedirectStandardOutput = true;
                    info.StandardErrorEncoding = Encoding.UTF8;
                    info.StandardOutputEncoding = Encoding.UTF8;
                }
                activeProcess = new Process { StartInfo = info };
                lock (capturedOutput) capturedOutput.Length = 0;
                if (!elevate)
                {
                    activeProcess.ErrorDataReceived += CaptureProcessOutput;
                    activeProcess.OutputDataReceived += CaptureProcessOutput;
                }
                SetBusy(true);
                statusTitle.Text = action == "Inventory" ? "유선 연결을 찾고 있습니다" : action == "Diagnose" ? "연결 상태를 진단하고 있습니다" : action == "Repair" ? "IP 충돌을 복구하고 있습니다" : "이전 설정으로 되돌리고 있습니다";
                statusMessage.Text = mutation ? "이 작업이 끝날 때까지 프로그램을 열어 두세요. 연결이 잠시 끊길 수 있습니다." : "연결 정보와 최근 오류를 확인합니다. 네트워크 설정은 바꾸지 않습니다.";
                SetBadge("진행 중", Blue, Color.FromArgb(234, 241, 255));
                footerText.Text = mutation ? "Windows 관리자 승인 요청을 확인해 주세요." : "진단 기록은 이 컴퓨터에 저장됩니다.";
                operationStarted = DateTime.UtcNow;
                if (!activeProcess.Start()) throw new InvalidOperationException("진단 작업을 시작하지 못했습니다.");
                if (!elevate)
                {
                    activeProcess.BeginErrorReadLine();
                    activeProcess.BeginOutputReadLine();
                }
                pollTimer.Start();
            }
            catch (Win32Exception ex)
            {
                CleanupProcess();
                SetBusy(false);
                if (ex.NativeErrorCode == 1223)
                {
                    statusTitle.Text = "관리자 승인이 취소되었습니다";
                    statusMessage.Text = "요청한 작업을 실행하지 않았습니다. 필요할 때 다시 실행할 수 있습니다.";
                    SetBadge("취소됨", Muted, Color.FromArgb(237, 241, 245));
                    footerText.Text = "현재 설정을 유지했습니다.";
                }
                else ShowFailure("작업을 시작하지 못했습니다", ex.Message);
            }
            catch (Exception ex)
            {
                CleanupProcess();
                SetBusy(false);
                ShowFailure("작업을 시작하지 못했습니다", ex.Message);
            }
        }

        private void CaptureProcessOutput(object sender, DataReceivedEventArgs e)
        {
            if (String.IsNullOrWhiteSpace(e.Data)) return;
            lock (capturedOutput)
            {
                if (capturedOutput.Length < 12000) capturedOutput.AppendLine(e.Data);
            }
        }

        private void PollProcess(object sender, EventArgs e)
        {
            if (activeProcess == null) return;
            try
            {
                TimeSpan elapsed = DateTime.UtcNow - operationStarted;
                if (!activeProcess.HasExited)
                {
                    footerText.Text = (IsMutating ? "설정 적용 중" : "진단 중") + "  ·  " + ((int)elapsed.TotalSeconds).ToString() + "초 경과";
                    if (elapsed.TotalSeconds > 180 && !slowNoticeShown)
                    {
                        slowNoticeShown = true;
                        if (IsMutating)
                        {
                            statusMessage.Text = "Windows의 응답이 늦어지고 있습니다. 설정 적용이 끝날 때까지 기다리고 있습니다.";
                        }
                        else
                        {
                            try { activeProcess.Kill(); } catch { }
                            CleanupProcess();
                            SetBusy(false);
                            ShowFailure("진단 시간이 오래 걸리고 있습니다", "Windows에서 연결 정보를 가져오지 못했습니다. 잠시 후 ‘진단하기’를 다시 눌러 주세요.");
                        }
                    }
                    return;
                }

                string completedAction = activeAction;
                string resultPath = activeOutputPath;
                int exitCode = activeProcess.ExitCode;
                CleanupProcess();
                SetBusy(false);
                if (!File.Exists(resultPath))
                {
                    string captured;
                    lock (capturedOutput) captured = capturedOutput.ToString().Trim();
                    if (!String.IsNullOrWhiteSpace(captured))
                    {
                        string failurePath = Path.ChangeExtension(resultPath, ".error.txt");
                        File.WriteAllText(failurePath, captured, new UTF8Encoding(true));
                        lastLogPath = failurePath;
                    }
                    ShowFailure("작업 결과를 받지 못했습니다", "작업이 종료되었지만 결과 파일이 만들어지지 않았습니다. 기록 폴더에서 오류 기록을 확인하고 다시 진단해 주세요. (종료 코드 " + exitCode.ToString() + ")");
                    return;
                }
                EngineResult result = EngineResult.Parse(File.ReadAllText(resultPath, Encoding.UTF8));
                ApplyResult(result, completedAction);
            }
            catch (Exception ex)
            {
                // An elevated process may temporarily deny status access. Retain the
                // operation guard rather than permitting a second repair or closing.
                if (activeProcess != null && IsMutating)
                {
                    statusTitle.Text = "설정 적용 완료를 기다리고 있습니다";
                    statusMessage.Text = "Windows에서 진행 상태를 확인하지 못했습니다. 작업 종료가 확인될 때까지 프로그램을 열어 두세요.";
                    footerText.Text = "작업 진행 정보: " + ex.Message;
                    return;
                }
                CleanupProcess();
                SetBusy(false);
                ShowFailure("작업 결과를 확인하지 못했습니다", ex.Message + "\r\n기록 폴더에서 결과를 확인한 뒤 다시 진단해 주세요.");
            }
        }

        public void ApplyResult(EngineResult result, string action)
        {
            if (result == null) throw new ArgumentNullException("result");
            lastResult = result;
            if (!String.IsNullOrWhiteSpace(result.logPath)) lastLogPath = result.logPath;
            statusTitle.Text = result.title;
            statusMessage.Text = result.message ?? String.Empty;
            string normalizedStatus = (result.status ?? String.Empty).ToLowerInvariant();
            if (result.ok && (normalizedStatus == "healthy" || normalizedStatus == "repaired"))
                SetBadge("연결 확인", Teal, Color.FromArgb(227, 245, 239));
            else if (result.ok && normalizedStatus == "restored")
                SetBadge("복원 완료", Blue, Color.FromArgb(234, 241, 255));
            else if (result.ok && action == "Inventory")
                SetBadge("목록 확인", Blue, Color.FromArgb(234, 241, 255));
            else
                SetBadge("확인 필요", Color.FromArgb(156, 91, 11), Color.FromArgb(255, 244, 221));

            string previousGuid = SelectedAdapter == null ? null : SelectedAdapter.guid;
            if (result.adapters != null)
            {
                suppressSelection = true;
                adapterPicker.BeginUpdate();
                try
                {
                    adapterPicker.Items.Clear();
                    foreach (AdapterInfo adapter in result.adapters)
                        if (adapter != null && !String.IsNullOrWhiteSpace(adapter.guid)) adapterPicker.Items.Add(adapter);
                    int selectedIndex = -1;
                    for (int i = 0; i < adapterPicker.Items.Count; i++)
                        if (String.Equals(((AdapterInfo)adapterPicker.Items[i]).guid, previousGuid, StringComparison.OrdinalIgnoreCase)) selectedIndex = i;
                    if (selectedIndex < 0)
                    {
                        for (int i = 0; i < adapterPicker.Items.Count; i++)
                            if (String.Equals(((AdapterInfo)adapterPicker.Items[i]).status, "Up", StringComparison.OrdinalIgnoreCase)) { selectedIndex = i; break; }
                    }
                    if (selectedIndex < 0 && adapterPicker.Items.Count > 0) selectedIndex = 0;
                    adapterPicker.SelectedIndex = selectedIndex;
                }
                finally { adapterPicker.EndUpdate(); suppressSelection = false; }
            }
            UpdateAdapterSummary(result.adapter ?? SelectedAdapter);
            StringBuilder details = new StringBuilder();
            if (result.details != null)
                foreach (string detail in result.details)
                    if (!String.IsNullOrWhiteSpace(detail)) details.AppendLine(detail.Trim());
            if (details.Length == 0) details.Append(result.message ?? "표시할 상세 정보가 없습니다.");
            detailText.Text = details.ToString().TrimEnd();
            detailText.SelectionStart = 0;
            detailText.SelectionLength = 0;
            detailText.ScrollToCaret();
            footerText.Text = "마지막 확인  " + DateTime.Now.ToString("HH:mm:ss") + "  ·  진단 기록은 이 컴퓨터에 저장됩니다.";
            UpdateButtons();
            if (action == "Inventory" && result.ok && SelectedAdapter != null)
            {
                lastResult = null;
                UpdateButtons();
                BeginInvoke(new Action(delegate { if (!IsDisposed && !busy) StartOperation("Diagnose", false); }));
            }
        }

        private void UpdateAdapterSummary(AdapterInfo adapter)
        {
            if (adapter == null) { adapterSummary.Text = "사용할 수 있는 유선 어댑터가 없습니다."; return; }
            string state = adapter.status ?? "상태 확인 중";
            if (String.Equals(state, "Up", StringComparison.OrdinalIgnoreCase)) state = "케이블 연결됨";
            else if (String.Equals(state, "Disconnected", StringComparison.OrdinalIgnoreCase)) state = "케이블 연결 끊김";
            else if (String.Equals(state, "Disabled", StringComparison.OrdinalIgnoreCase)) state = "어댑터 사용 안 함";
            adapterSummary.Text = state + (String.IsNullOrWhiteSpace(adapter.linkSpeed) ? "" : "  ·  " + adapter.linkSpeed) + (String.IsNullOrWhiteSpace(adapter.mac) ? "" : "  ·  MAC " + adapter.mac);
        }

        private void SetBadge(string text, Color foreground, Color background)
        {
            statusBadge.Text = text;
            statusBadge.ForeColor = foreground;
            statusBadge.BackColor = background;
        }

        private void ShowFailure(string title, string message)
        {
            lastResult = null;
            statusTitle.Text = title;
            statusMessage.Text = message;
            detailText.Text = message;
            SetBadge("확인 필요", Color.FromArgb(156, 91, 11), Color.FromArgb(255, 244, 221));
            footerText.Text = "다시 진단하거나 기록 폴더에서 자세한 내용을 확인해 주세요.";
            UpdateButtons();
        }

        private void OpenLogFolder()
        {
            try
            {
                Directory.CreateDirectory(dataDirectory);
                string folder = dataDirectory;
                if (!String.IsNullOrWhiteSpace(lastLogPath))
                {
                    string full = Path.GetFullPath(lastLogPath);
                    if (Directory.Exists(full)) folder = full;
                    else if (File.Exists(full)) folder = Path.GetDirectoryName(full);
                }
                Process.Start(new ProcessStartInfo("explorer.exe", Program.QuoteArgument(folder)) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show("기록 폴더를 열지 못했습니다.\r\n" + dataDirectory + "\r\n\r\n" + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void CleanupProcess()
        {
            pollTimer.Stop();
            if (activeProcess != null) { activeProcess.Dispose(); activeProcess = null; }
        }

        private void CheckBeforeClosing(object sender, FormClosingEventArgs e)
        {
            if (busy && IsMutating)
            {
                e.Cancel = true;
                MessageBox.Show("이더넷 설정을 적용하는 중입니다. 작업이 끝난 뒤 프로그램을 닫아 주세요.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (activeProcess != null)
            {
                try { if (!activeProcess.HasExited) activeProcess.Kill(); } catch { }
                CleanupProcess();
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (pollTimer != null) pollTimer.Dispose();
                if (activeProcess != null) activeProcess.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
