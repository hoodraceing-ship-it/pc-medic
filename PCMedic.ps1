#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoElevation)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Test-Administrator {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not $NoElevation -and -not (Test-Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    exit
}

$script:AppRoot = Join-Path $env:ProgramData 'PCMedic'
$script:ReportRoot = Join-Path $script:AppRoot 'Reports'
$script:LogRoot = Join-Path $script:AppRoot 'Logs'
New-Item -ItemType Directory -Path $script:ReportRoot,$script:LogRoot -Force | Out-Null
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:ScanStarted = $null

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="PC Medic" Width="1180" Height="790" MinWidth="960" MinHeight="650" WindowStartupLocation="CenterScreen" Background="#15191E" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button"><Setter Property="Background" Value="#1875D1"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="18,10"/><Setter Property="Margin" Value="4"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#EDF1F5"/></Style>
    <Style TargetType="ListView"><Setter Property="Background" Value="#1D232A"/><Setter Property="Foreground" Value="#E5E9ED"/><Setter Property="BorderBrush" Value="#343C45"/><Setter Property="BorderThickness" Value="1"/></Style>
    <Style TargetType="ListViewItem"><Setter Property="Padding" Value="6"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#29333D"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#164F7A"/><Setter Property="Foreground" Value="White"/></Trigger></Style.Triggers></Style>
    <Style TargetType="GridViewColumnHeader"><Setter Property="Background" Value="#252C34"/><Setter Property="Foreground" Value="#BFC8D2"/><Setter Property="Padding" Value="8"/><Setter Property="BorderBrush" Value="#343C45"/></Style>
    <Style TargetType="TabItem"><Setter Property="Foreground" Value="#B9C2CB"/><Setter Property="Background" Value="#20262D"/><Setter Property="Padding" Value="20,11"/><Setter Property="Margin" Value="0,0,4,0"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TabItem"><Border Name="TabBorder" Background="{TemplateBinding Background}" BorderBrush="#343C45" BorderThickness="1" CornerRadius="3,3,0,0" Padding="{TemplateBinding Padding}"><ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/></Border><ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter TargetName="TabBorder" Property="Background" Value="#1875D1"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabBorder" Property="Background" Value="#2B343E"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsSelected" Value="True"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions><Setter TargetName="TabBorder" Property="Background" Value="#1875D1"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>
  <Grid Margin="24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel><TextBlock Text="PC MEDIC" FontSize="27" FontWeight="Bold" Foreground="#FFFFFF"/><TextBlock Text="System health and repair" Foreground="#8F9AA6"/></StackPanel>
      <Border Grid.Column="1" Background="#203B2E" CornerRadius="4" Padding="14,8"><TextBlock Name="AdminBadge" Text="Administrator mode" Foreground="#77D49B"/></Border>
    </Grid>
    <Border Grid.Row="1" Margin="0,18,0,14" Padding="18" CornerRadius="6" Background="#20262D" BorderBrush="#343C45" BorderThickness="1">
      <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel><TextBlock Name="StatusTitle" Text="Ready to examine this PC" FontSize="19" FontWeight="SemiBold"/><TextBlock Name="StatusDetail" Text="The full scan is read-only and normally takes 3-10 minutes." Margin="0,5,0,0" Foreground="#94A3B8"/></StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal"><Button Name="ScanButton" Content="Run full scan"/><Button Name="FixAllButton" Content="Fix all safe issues" Background="#1D8A55" IsEnabled="False"/><Button Name="ExportButton" Content="Export report" Background="#0F766E" IsEnabled="False"/></StackPanel>
      </Grid>
    </Border>
    <TabControl Name="MainTabs" Grid.Row="2" Background="#15191E" BorderBrush="#343C45" Foreground="#E5E9ED">
      <TabItem Header="Health Check"><Grid Margin="12"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><ListView Name="ResultsList"><ListView.View><GridView><GridViewColumn Header="Status" Width="85" DisplayMemberBinding="{Binding Status}"/><GridViewColumn Header="Category" Width="145" DisplayMemberBinding="{Binding Area}"/><GridViewColumn Header="What PC Medic found" Width="365" DisplayMemberBinding="{Binding Finding}"/><GridViewColumn Header="Recommended action" Width="430" DisplayMemberBinding="{Binding Recommendation}"/></GridView></ListView.View></ListView><Border Grid.Row="1" Margin="0,12,0,0" Background="#20262D" BorderBrush="#343C45" BorderThickness="1" CornerRadius="5" Padding="16"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Name="IssueTitleText" Text="Select a result to see what it means" FontSize="17" FontWeight="SemiBold"/><TextBlock Name="IssueDetailText" Text="Warnings and failures will include a plain-language explanation and the safest next step." Foreground="#9DA8B3" TextWrapping="Wrap" Margin="0,6,16,0"/></StackPanel><Button Name="FixSelectedButton" Grid.Column="1" Content="Fix selected issue" IsEnabled="False" Background="#1D8A55" MinWidth="160"/></Grid></Border></Grid></TabItem>
      <TabItem Header="Hardware"><Grid Margin="12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="210"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="LIVE HARDWARE MONITOR" FontSize="18" FontWeight="Bold"/><TextBlock Text="Usage refreshes every 2 seconds while this window is open." Foreground="#94A3B8"/></StackPanel><Button Name="HardwareRefreshButton" Grid.Column="1" Content="Refresh inventory"/></Grid>
        <UniformGrid Grid.Row="1" Columns="4" Margin="0,14,0,14"><Border Background="#111827" CornerRadius="9" Margin="4" Padding="14"><StackPanel><TextBlock Text="CPU" Foreground="#94A3B8"/><TextBlock Name="CpuUsageText" Text="--" FontSize="28" FontWeight="Bold"/><TextBlock Name="CpuTempText" Text="Temperature: --" TextWrapping="Wrap"/></StackPanel></Border><Border Background="#111827" CornerRadius="9" Margin="4" Padding="14"><StackPanel><TextBlock Text="MEMORY" Foreground="#94A3B8"/><TextBlock Name="RamUsageText" Text="--" FontSize="28" FontWeight="Bold"/><TextBlock Name="RamDetailText" Text="--" TextWrapping="Wrap"/></StackPanel></Border><Border Background="#111827" CornerRadius="9" Margin="4" Padding="14"><StackPanel><TextBlock Text="GPU" Foreground="#94A3B8"/><TextBlock Name="GpuUsageText" Text="--" FontSize="28" FontWeight="Bold"/><TextBlock Name="GpuTempText" Text="Temperature: --" TextWrapping="Wrap"/></StackPanel></Border><Border Background="#111827" CornerRadius="9" Margin="4" Padding="14"><StackPanel><TextBlock Text="SYSTEM DRIVE" Foreground="#94A3B8"/><TextBlock Name="DiskUsageText" Text="--" FontSize="28" FontWeight="Bold"/><TextBlock Name="DiskDetailText" Text="--" TextWrapping="Wrap"/></StackPanel></Border></UniformGrid>
        <TextBlock Grid.Row="2" Text="DETECTED COMPONENTS" FontWeight="Bold" Margin="4,0,0,8"/><ListView Grid.Row="3" Name="HardwareList"><ListView.View><GridView><GridViewColumn Header="Component" Width="150" DisplayMemberBinding="{Binding Component}"/><GridViewColumn Header="Model" Width="390" DisplayMemberBinding="{Binding Model}"/><GridViewColumn Header="Details" Width="430" DisplayMemberBinding="{Binding Details}"/></GridView></ListView.View></ListView>
      </Grid></TabItem>
      <TabItem Name="RepairsTab" Header="Repairs"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="12">
        <TextBlock Text="REPAIR TOOLS" FontSize="18" FontWeight="Bold" Margin="0,0,0,8"/><TextBlock Text="The Health Check tab chooses the matching tool automatically. These controls remain available for manual troubleshooting." Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,15"/>
        <WrapPanel><Button Name="RestoreButton" Content="Create restore point"/><Button Name="SystemRepairButton" Content="Repair Windows files"/><Button Name="DiskRepairButton" Content="Repair disk online"/><Button Name="NetworkRepairButton" Content="Reset network stack"/><Button Name="MemoryButton" Content="Schedule memory test"/><Button Name="UpdateButton" Content="Open Windows Update"/><Button Name="DriversButton" Content="Open Device Manager"/><Button Name="DefenderButton" Content="Run Defender quick scan"/></WrapPanel>
        <Border Background="#20262D" BorderBrush="#343C45" BorderThickness="1" CornerRadius="6" Margin="4,18,4,8" Padding="16"><StackPanel><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Name="RepairStageText" Text="No repair is running" FontSize="17" FontWeight="SemiBold"/><TextBlock Name="RepairPercentText" Grid.Column="1" Text="" FontSize="17" FontWeight="SemiBold" Foreground="#55C986"/></Grid><ProgressBar Name="RepairProgress" Height="16" Minimum="0" Maximum="100" Value="0" Margin="0,12,0,8" Foreground="#22A861" Background="#11161B"/><TextBlock Name="RepairDetailText" Text="Choose a repair tool or fix a selected issue from Health Check." Foreground="#9DA8B3" TextWrapping="Wrap"/></StackPanel></Border>
        <Border Background="#111827" CornerRadius="6" Margin="4" Padding="15"><TextBlock Name="RepairOutput" Text="Detailed repair results will appear here." FontFamily="Consolas" TextWrapping="Wrap" Foreground="#CBD5E1"/></Border>
      </StackPanel></ScrollViewer></TabItem>
      <TabItem Header="About"><StackPanel Margin="18"><TextBlock Text="PC Medic" FontSize="20" FontWeight="Bold"/><TextBlock Name="VersionText" Margin="0,4,0,0" Foreground="#8F9AA6"/><Button Name="CheckUpdateButton" Content="Check for updates" HorizontalAlignment="Left" Margin="0,14,0,16"/><TextBlock Text="How PC Medic protects your PC" FontSize="17" FontWeight="SemiBold"/><TextBlock Margin="0,9,0,0" TextWrapping="Wrap" Foreground="#CBD5E1" Text="Diagnostics stay on this PC. Repairs use Microsoft tools built into Windows. Updates come only from the official hoodraceing-ship-it/PC-Medic GitHub Releases page and must pass SHA-256 verification. PC Medic does not install unknown drivers, clean the registry, delete personal files, change BIOS settings, or hide errors."/><TextBlock Margin="0,18,0,0" Text="Reports and logs are stored in:" Foreground="#94A3B8"/><TextBlock Name="PathText" FontFamily="Consolas"/></StackPanel></TabItem>
    </TabControl>
    <Grid Grid.Row="3" Margin="0,12,0,0"><ProgressBar Name="Progress" Height="8" Minimum="0" Maximum="100"/><TextBlock Name="ProgressText" Margin="0,12,0,0" Foreground="#94A3B8"/></Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in @('AdminBadge','StatusTitle','StatusDetail','ScanButton','FixAllButton','ExportButton','MainTabs','RepairsTab','ResultsList','IssueTitleText','IssueDetailText','FixSelectedButton','HardwareRefreshButton','HardwareList','CpuUsageText','CpuTempText','RamUsageText','RamDetailText','GpuUsageText','GpuTempText','DiskUsageText','DiskDetailText','RestoreButton','SystemRepairButton','DiskRepairButton','NetworkRepairButton','MemoryButton','UpdateButton','DriversButton','DefenderButton','RepairProgress','RepairStageText','RepairPercentText','RepairDetailText','RepairOutput','VersionText','CheckUpdateButton','PathText','Progress','ProgressText')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
$PathText.Text = $script:AppRoot
$VersionText.Text=(Get-Content (Join-Path $PSScriptRoot 'VERSION.txt') -First 1)
if (-not (Test-Administrator)) { $AdminBadge.Text = 'Limited mode'; $AdminBadge.Foreground = '#FBBF24' }

function Update-UI { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{},'Background') }
function Add-Result([string]$Status,[string]$Area,[string]$Finding,[string]$Recommendation,[object]$Evidence=$null) {
    $item = [pscustomobject]@{ Status=$Status; Area=$Area; Finding=$Finding; Recommendation=$Recommendation; Evidence=$Evidence }
    $script:Results.Add($item); $ResultsList.Items.Add($item) | Out-Null; Update-UI
}
function Set-Step([int]$Percent,[string]$Message) { $Progress.Value=$Percent; $ProgressText.Text=$Message; $StatusDetail.Text=$Message; Update-UI }
function Confirm-Action([string]$Title,[string]$Message) { [System.Windows.MessageBox]::Show($Message,$Title,'YesNo','Warning') -eq 'Yes' }
function Start-UpdateCheck([switch]$Force) {$updater=Join-Path $PSScriptRoot 'Update-PCMedic.ps1';$args='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$updater+'" -ParentPid '+$PID;if($Force){$args+=' -ForceCheck'};Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $args}
function Click-Control($Control) { $Control.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) }
function Show-SelectedIssue {
    $item=$ResultsList.SelectedItem
    if(-not $item){return}
    $IssueTitleText.Text="$($item.Status): $($item.Area)"
    $IssueDetailText.Text="$($item.Finding)  $($item.Recommendation)"
    $FixSelectedButton.IsEnabled=($item.Status -in @('WARN','FAIL'))
    $FixSelectedButton.Content=switch($item.Area){
        'System files' {'Repair Windows files'}
        'Storage' {'Open storage tools'}
        'Drivers' {'Open Device Manager'}
        'Security' {'Open Windows Security'}
        'Updates' {'Open Windows Update'}
        'Memory' {'Run memory test'}
        'Network' {'Reset network'}
        'Performance' {'Open Task Manager'}
        'Stability' {'Open Event Viewer'}
        'Hardware' {'Open Event Viewer'}
        default {'Review recommended action'}
    }
}
function Fix-SelectedIssue {
    $item=$ResultsList.SelectedItem;if(-not $item){return}
    switch($item.Area){
        'System files' {Click-Control $SystemRepairButton}
        'Storage' {Start-Process 'ms-settings:storagesense'}
        'Drivers' {Start-Process devmgmt.msc}
        'Security' {Start-Process 'windowsdefender:'}
        'Updates' {Start-Process 'ms-settings:windowsupdate'}
        'Memory' {Click-Control $MemoryButton}
        'Network' {Click-Control $NetworkRepairButton}
        'Performance' {Start-Process taskmgr.exe}
        'Stability' {Start-Process eventvwr.msc}
        'Hardware' {Start-Process eventvwr.msc}
        default {[System.Windows.MessageBox]::Show($item.Recommendation,'Recommended action','OK','Information')|Out-Null}
    }
}
function Invoke-Native([string]$File,[string]$Arguments,[scriptblock]$OnProgress=$null) {
    $outputFile=[IO.Path]::GetTempFileName()
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='cmd.exe';$psi.Arguments='/d /s /c ""'+$File+'" '+$Arguments+' > "'+$outputFile+'" 2>&1"';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    try {
        $p=[Diagnostics.Process]::Start($psi)
        $lastProgressRead=[datetime]::MinValue
        while(-not $p.WaitForExit(100)) {
            if($OnProgress -and ((Get-Date)-$lastProgressRead).TotalMilliseconds -ge 500 -and (Test-Path $outputFile)){
                $partial=Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
                $percentMatches=[regex]::Matches([string]$partial,'(\d+(?:\.\d+)?)%')
                if($percentMatches.Count){& $OnProgress ([double]$percentMatches[$percentMatches.Count-1].Groups[1].Value)}
                $lastProgressRead=Get-Date
            }
            Update-UI
        }
        $text=if(Test-Path $outputFile){Get-Content $outputFile -Raw -ErrorAction SilentlyContinue}else{''}
        [pscustomobject]@{ ExitCode=$p.ExitCode; Output=([string]$text).Trim() }
    } finally { Remove-Item $outputFile -Force -ErrorAction SilentlyContinue }
}

function Add-Hardware([string]$Component,[string]$Model,[string]$Details) { $HardwareList.Items.Add([pscustomobject]@{Component=$Component;Model=$Model;Details=$Details})|Out-Null }
function Load-HardwareInventory {
    $HardwareList.Items.Clear()
    try {
        foreach($cpu in Get-CimInstance Win32_Processor){Add-Hardware 'CPU' $cpu.Name.Trim() ("{0} cores / {1} threads; max {2:N2} GHz; socket {3}" -f $cpu.NumberOfCores,$cpu.NumberOfLogicalProcessors,($cpu.MaxClockSpeed/1000),$cpu.SocketDesignation)}
        $board=Get-CimInstance Win32_BaseBoard|Select-Object -First 1; Add-Hardware 'Motherboard' (($board.Manufacturer+' '+$board.Product).Trim()) ("Serial: {0}" -f $board.SerialNumber)
        $bios=Get-CimInstance Win32_BIOS|Select-Object -First 1; Add-Hardware 'BIOS/UEFI' (($bios.Manufacturer+' '+$bios.SMBIOSBIOSVersion).Trim()) ("Released: {0:yyyy-MM-dd}" -f $bios.ReleaseDate)
        foreach($gpu in Get-CimInstance Win32_VideoController){Add-Hardware 'GPU' $gpu.Name ("Driver {0}; VRAM {1:N1} GB; {2}" -f $gpu.DriverVersion,($gpu.AdapterRAM/1GB),$gpu.VideoModeDescription)}
        foreach($ram in Get-CimInstance Win32_PhysicalMemory){$speed=if($ram.ConfiguredClockSpeed){$ram.ConfiguredClockSpeed}else{$ram.Speed};Add-Hardware 'RAM module' (($ram.Manufacturer+' '+$ram.PartNumber).Trim()) ("{0:N1} GB; {1} MT/s; slot {2}; serial {3}" -f ($ram.Capacity/1GB),$speed,$ram.DeviceLocator,$ram.SerialNumber)}
        foreach($drive in Get-CimInstance Win32_DiskDrive){Add-Hardware 'Storage' $drive.Model ("{0:N1} GB; {1}; serial {2}" -f ($drive.Size/1GB),$drive.InterfaceType,$drive.SerialNumber)}
        foreach($netAdapter in Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True'|Where-Object {$_.Name -notmatch 'Bluetooth'}){Add-Hardware 'Network' $netAdapter.Name ("MAC {0}; {1}" -f $netAdapter.MACAddress,$netAdapter.NetConnectionStatus)}
        foreach($sound in Get-CimInstance Win32_SoundDevice|Where-Object Status -eq 'OK'){Add-Hardware 'Audio' $sound.Name $sound.Manufacturer}
        $battery=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue|Select-Object -First 1;if($battery){Add-Hardware 'Battery' $battery.Name ("Charge {0}%; status {1}" -f $battery.EstimatedChargeRemaining,$battery.Status)}
        $monitor=Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue;foreach($m in $monitor){$maker=([Text.Encoding]::ASCII.GetString([byte[]]($m.ManufacturerName|Where-Object {$_}))).Trim([char]0);$model=([Text.Encoding]::ASCII.GetString([byte[]]($m.UserFriendlyName|Where-Object {$_}))).Trim([char]0);Add-Hardware 'Monitor' (($maker+' '+$model).Trim()) $m.InstanceName}
    } catch { Add-Hardware 'Inventory error' $_.Exception.Message 'Run PC Medic as administrator and refresh.' }
}
function Get-NvidiaTelemetry {
    $nvidia=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if(-not $nvidia){$candidate=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe';if(Test-Path $candidate){$nvidia=$candidate}}
    if($nvidia){try{$line=& $nvidia '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total' '--format=csv,noheader,nounits' 2>$null|Select-Object -First 1;if($line){$v=$line-split ',\s*';return [pscustomobject]@{Usage=[int]$v[0];Temp=[int]$v[1];Used=[int]$v[2];Total=[int]$v[3]}}}catch{}}
    $null
}
function Get-NativeTemperature {
    try{$temps=@(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop|ForEach-Object {($_.CurrentTemperature/10)-273.15}|Where-Object {$_ -gt 0 -and $_ -lt 120});if($temps.Count){[math]::Round(($temps|Measure-Object -Maximum).Maximum,0)}}catch{$null}
}
function Update-LiveHardware {
    try{
        $os=Get-CimInstance Win32_OperatingSystem; $cpu=(Get-CimInstance Win32_Processor|Measure-Object LoadPercentage -Average).Average
        $usedKB=$os.TotalVisibleMemorySize-$os.FreePhysicalMemory;$ramPct=[math]::Round(100*$usedKB/$os.TotalVisibleMemorySize,0)
        $CpuUsageText.Text=("{0:N0}%" -f $cpu);$RamUsageText.Text=("{0}%" -f $ramPct);$RamDetailText.Text=("{0:N1} / {1:N1} GB used" -f ($usedKB/1MB),($os.TotalVisibleMemorySize/1MB))
        $temp=Get-NativeTemperature;$CpuTempText.Text=if($null-ne$temp){"ACPI sensor: $temp C"}else{'Temperature: not exposed by Windows'}
        $sys=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive);$diskPct=[math]::Round(100*($sys.Size-$sys.FreeSpace)/$sys.Size,0);$DiskUsageText.Text="$diskPct%";$DiskDetailText.Text=("{0:N1} GB free of {1:N1} GB" -f ($sys.FreeSpace/1GB),($sys.Size/1GB))
        $nv=Get-NvidiaTelemetry;if($nv){$GpuUsageText.Text="$($nv.Usage)%";$GpuTempText.Text=("{0} C; VRAM {1} / {2} MB" -f $nv.Temp,$nv.Used,$nv.Total)}else{$GpuUsageText.Text='--';$GpuTempText.Text='Telemetry not exposed by GPU driver'}
    }catch{}
}

function Add-EventGroups([object[]]$Events,[string]$Area,[string]$Status,[string]$Recommendation,[int]$Maximum=6) {
    $groups=@($Events | Group-Object ProviderName,Id | Sort-Object Count -Descending | Select-Object -First $Maximum)
    foreach($group in $groups){
        $sample=$group.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $message=([string]$sample.Message -replace '\s+',' ').Trim()
        if($message.Length -gt 190){$message=$message.Substring(0,190)+'...'}
        $finding=("{0} event {1} occurred {2} time(s); most recent {3:g}. {4}" -f $sample.ProviderName,$sample.Id,$group.Count,$sample.TimeCreated,$message)
        $evidence=$group.Group | Sort-Object TimeCreated -Descending | Select-Object -First 12 TimeCreated,Id,LevelDisplayName,ProviderName,Message
        Add-Result $Status $Area $finding $Recommendation $evidence
    }
}

function Invoke-FullScan {
    $script:Results.Clear(); $ResultsList.Items.Clear(); $script:ScanStarted=Get-Date
    $IssueTitleText.Text='Scanning for problems'; $IssueDetailText.Text='Results will appear here as each check completes.'; $FixSelectedButton.IsEnabled=$false
    $ScanButton.IsEnabled=$false; $FixAllButton.IsEnabled=$false; $ExportButton.IsEnabled=$false; $StatusTitle.Text='Scanning this PC...'
    try {
        Set-Step 5 'Collecting Windows and uptime information...'
        $os=Get-CimInstance Win32_OperatingSystem; $boot=$os.LastBootUpTime; $uptime=((Get-Date)-$boot)
        Add-Result 'INFO' 'Windows' ("{0} build {1}; uptime {2:N1} days" -f $os.Caption,$os.BuildNumber,$uptime.TotalDays) 'Keep Windows supported and current.'
        $pending=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        if($pending){Add-Result 'WARN' 'Windows' 'A restart is pending.' 'Restart before running repairs or installing drivers.'}else{Add-Result 'PASS' 'Windows' 'No pending restart detected.' 'No action needed.'}

        Set-Step 14 'Checking Windows component store...'
        $dism=Invoke-Native 'dism.exe' '/Online /Cleanup-Image /CheckHealth /English'
        if($dism.ExitCode -eq 0 -and $dism.Output -match 'No component store corruption detected'){Add-Result 'PASS' 'System files' 'Component store reports healthy.' 'No action needed.' $dism.Output}elseif($dism.Output -match 'component store is repairable|component store corruption detected'){Add-Result 'FAIL' 'System files' 'DISM found a repairable component-store issue.' 'Use Repair Windows files.' $dism.Output}else{Add-Result 'WARN' 'System files' 'DISM CheckHealth was inconclusive or could not complete.' 'Review the exported evidence, then rerun as administrator.' $dism.Output}
        Set-Step 23 'Verifying protected Windows files...'
        $sfc=Invoke-Native 'sfc.exe' '/verifyonly'
        if($sfc.Output -match 'did not find any integrity violations'){Add-Result 'PASS' 'System files' 'Protected Windows files are intact.' 'No action needed.' $sfc.Output}elseif($sfc.Output -match 'integrity violations|corrupt'){Add-Result 'FAIL' 'System files' 'Protected Windows files may be corrupted.' 'Create a restore point, then use Repair Windows files.' $sfc.Output}else{Add-Result 'WARN' 'System files' 'SFC verification was inconclusive.' 'Review the exported evidence or rerun as administrator.' $sfc.Output}

        Set-Step 35 'Checking disks and free space...'
        foreach($vol in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'){
            $freePct=if($vol.Size){[math]::Round(100*$vol.FreeSpace/$vol.Size,1)}else{0}
            if($freePct -lt 10){Add-Result 'FAIL' 'Storage' ("{0} has only {1}% free ({2:N1} GB)." -f $vol.DeviceID,$freePct,($vol.FreeSpace/1GB)) 'Free at least 15-20% for updates and stable performance.'}
            elseif($freePct -lt 20){Add-Result 'WARN' 'Storage' ("{0} is getting full: {1}% free." -f $vol.DeviceID,$freePct) 'Consider Storage Sense or moving large personal files.'}
            else{Add-Result 'PASS' 'Storage' ("{0} has {1}% free." -f $vol.DeviceID,$freePct) 'No action needed.'}
        }
        try { foreach($pd in Get-PhysicalDisk -ErrorAction Stop){ if($pd.HealthStatus -ne 'Healthy'){Add-Result 'FAIL' 'Storage' ("{0}: {1}, {2}" -f $pd.FriendlyName,$pd.HealthStatus,$pd.OperationalStatus) 'Back up important files now and run the manufacturer diagnostic.'}else{Add-Result 'PASS' 'Storage' ("{0}: healthy" -f $pd.FriendlyName) 'No action needed.'} } } catch { Add-Result 'INFO' 'Storage' 'Physical-disk health was unavailable.' 'Use the drive manufacturer diagnostic if storage symptoms exist.' }

        Set-Step 47 'Inspecting devices and drivers...'
        $badDevices=@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -ne 'OK')
        if($badDevices.Count){foreach($d in $badDevices | Select-Object -First 15){Add-Result 'FAIL' 'Drivers' ("{0}: {1}" -f $d.FriendlyName,$d.Status) 'Open Device Manager; identify the exact hardware vendor before updating or reinstalling.' $d.InstanceId}}else{Add-Result 'PASS' 'Drivers' 'No currently present device reports an error.' 'No action needed.'}
        $oldDrivers=@(Get-CimInstance Win32_PnPSignedDriver | Where-Object {$_.DriverDate -and $_.DeviceName -and $_.Manufacturer -notmatch 'Microsoft' -and $_.DriverDate -lt (Get-Date).AddYears(-5)} | Sort-Object DriverDate | Select-Object -First 10)
        if($oldDrivers.Count){Add-Result 'WARN' 'Drivers' ("{0} third-party drivers are over five years old (showing up to 10)." -f $oldDrivers.Count) 'Update only from the PC/component manufacturer when symptoms or known security issues justify it.' ($oldDrivers|Select DeviceName,Manufacturer,DriverVersion,DriverDate)}

        Set-Step 55 'Reading Windows error logs...'
        $start=(Get-Date).AddDays(-7)
        $systemEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2,3;StartTime=$start} -MaxEvents 700 -ErrorAction SilentlyContinue)
        $applicationEvents=@(Get-WinEvent -FilterHashtable @{LogName='Application';Level=1,2,3;StartTime=$start} -MaxEvents 500 -ErrorAction SilentlyContinue)
        $critical=@($systemEvents | Where-Object Level -eq 1)
        $whea=@($systemEvents | Where-Object ProviderName -eq 'Microsoft-Windows-WHEA-Logger')
        if($critical.Count){Add-Result 'WARN' 'Stability' ("{0} critical System events in the last 7 days." -f $critical.Count) 'Inspect exported evidence; recurring Kernel-Power events can be power, heat, driver, or hard-reset related.' ($critical|Select -First 20 TimeCreated,Id,ProviderName,Message)}else{Add-Result 'PASS' 'Stability' 'No critical System events in the last 7 days.' 'No action needed.'}
        if($whea.Count){Add-Result 'FAIL' 'Hardware' ("{0} WHEA hardware-error events in the last 7 days." -f $whea.Count) 'Check temperatures, BIOS defaults, RAM, CPU/GPU stability, power, and vendor diagnostics.' ($whea|Select -First 20 TimeCreated,Id,Message)}else{Add-Result 'PASS' 'Hardware' 'No recent WHEA hardware errors found.' 'No action needed.'}

        $appCrashes=@($applicationEvents | Where-Object {$_.ProviderName -in @('Application Error','Application Hang','.NET Runtime','Windows Error Reporting')})
        if($appCrashes.Count){Add-EventGroups $appCrashes 'Stability' 'WARN' 'Update or repair the named application. If crashes repeat, check its add-ons, drivers, and Reliability Monitor.' 6}else{Add-Result 'PASS' 'Stability' 'No application crash or hang events were found in the last 7 days.' 'No action needed.'}

        $storageEvents=@($systemEvents | Where-Object {$_.ProviderName -match '^(disk|Ntfs|stornvme|storahci|volmgr|partmgr|iaStor)'})
        if($storageEvents.Count){Add-EventGroups $storageEvents 'Storage' 'FAIL' 'Back up important files. Check drive health, cables, firmware, and run the manufacturer diagnostic before attempting repairs.' 6}else{Add-Result 'PASS' 'Storage' 'No recent disk, controller, or NTFS error events were found.' 'No action needed.'}

        $driverEvents=@($systemEvents | Where-Object {$_.ProviderName -match 'Kernel-PnP|DriverFrameworks-UserMode'})
        if($driverEvents.Count){Add-EventGroups $driverEvents 'Drivers' 'WARN' 'Open Device Manager and update or reinstall only the device named in the event, using the PC or component manufacturer.' 6}else{Add-Result 'PASS' 'Drivers' 'No recent driver-loading error events were found.' 'No action needed.'}

        $serviceEvents=@($systemEvents | Where-Object {$_.ProviderName -eq 'Service Control Manager' -and $_.Id -in @(7000,7001,7009,7011,7023,7024,7031,7034)})
        if($serviceEvents.Count){Add-EventGroups $serviceEvents 'Stability' 'WARN' 'Identify the service named in the event. Repair or reinstall its owning application if the failure repeats.' 5}else{Add-Result 'PASS' 'Stability' 'No repeated service-start or service-crash errors were found.' 'No action needed.'}

        $updateEvents=@($systemEvents | Where-Object {$_.ProviderName -match 'WindowsUpdateClient|Servicing' -and $_.Level -in @(1,2,3)})
        try{$updateEvents+=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational';Level=2,3;StartTime=$start} -MaxEvents 150 -ErrorAction SilentlyContinue)}catch{}
        if($updateEvents.Count){Add-EventGroups $updateEvents 'Updates' 'WARN' 'Open Windows Update and retry. If the same update repeatedly fails, note its KB number and error code from the exported report.' 6}else{Add-Result 'PASS' 'Updates' 'No Windows Update failure events were found in the last 7 days.' 'No action needed.'}

        $defenderEvents=@()
        try{$defenderEvents=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';Id=1116,1117,1118,1119,5001,5004,5010;StartTime=$start} -MaxEvents 150 -ErrorAction SilentlyContinue)}catch{}
        if($defenderEvents.Count){Add-EventGroups $defenderEvents 'Security' 'FAIL' 'Open Windows Security, review Protection History, remove or quarantine confirmed threats, and verify real-time protection is enabled.' 6}else{Add-Result 'PASS' 'Security' 'No recent Defender threat or protection-disabled events were found.' 'No action needed.'}

        $memoryEvents=@()
        try{$memoryEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-MemoryDiagnostics-Results';StartTime=$start} -MaxEvents 20 -ErrorAction SilentlyContinue)}catch{}
        if($memoryEvents.Count){$badMemory=@($memoryEvents | Where-Object {$_.Id -eq 1102 -or $_.Message -match 'hardware problems were detected|memory errors'});if($badMemory.Count){Add-Result 'FAIL' 'Memory' 'Windows Memory Diagnostic reported a hardware problem.' 'Test one RAM module at a time, disable memory overclocking/XMP temporarily, and retest.' ($badMemory|Select -First 10 TimeCreated,Id,Message)}else{Add-Result 'PASS' 'Memory' 'The latest Windows Memory Diagnostic result did not report an error.' 'No action needed.'}}

        Set-Step 72 'Checking security and update services...'
        try{$mp=Get-MpComputerStatus -ErrorAction Stop;if($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled){Add-Result 'PASS' 'Security' 'Microsoft Defender real-time protection is enabled.' 'No action needed.'}else{Add-Result 'FAIL' 'Security' 'Defender antivirus or real-time protection is disabled.' 'Confirm whether another trusted antivirus is active; otherwise enable Defender.'}}catch{Add-Result 'WARN' 'Security' 'Defender status was unavailable.' 'Confirm that a trusted antivirus product is active.'}
        $fw=@(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object Enabled -eq $false)
        if($fw.Count){Add-Result 'WARN' 'Security' ('Firewall disabled for: '+(($fw.Name)-join ', ')) 'Enable it unless a managed security product intentionally replaces it.'}else{Add-Result 'PASS' 'Security' 'Windows Firewall is enabled for all profiles.' 'No action needed.'}
        $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
        if($wu.StartType -eq 'Disabled'){Add-Result 'FAIL' 'Updates' 'Windows Update service is disabled.' 'Set it to Manual and check Windows Update.'}else{Add-Result 'PASS' 'Updates' 'Windows Update service is available.' 'Open Windows Update to check current patch status.'}

        Set-Step 82 'Checking memory and page file...'
        $cs=Get-CimInstance Win32_ComputerSystem; $ramGB=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
        Add-Result 'INFO' 'Memory' ("{0} GB physical memory installed." -f $ramGB) 'If crashes continue, schedule the Windows memory test.'
        $pf=@(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
        if(-not $pf.Count){Add-Result 'WARN' 'Memory' 'No active page file was detected.' 'Use system-managed virtual memory unless a specific workload requires otherwise.'}else{Add-Result 'PASS' 'Memory' 'A Windows page file is active.' 'No action needed.'}

        Set-Step 90 'Testing network and DNS...'
        $dnsOk=$false; try{Resolve-DnsName 'www.microsoft.com' -Type A -ErrorAction Stop | Out-Null;$dnsOk=$true}catch{}
        $net=Test-NetConnection 'www.microsoft.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        if($dnsOk -and $net){Add-Result 'PASS' 'Network' 'DNS and HTTPS connectivity are working.' 'No action needed.'}elseif(-not $dnsOk){Add-Result 'FAIL' 'Network' 'DNS lookup failed.' 'Check gateway/DNS settings, then use Reset network stack if the failure persists.'}else{Add-Result 'WARN' 'Network' 'DNS works, but HTTPS connectivity test failed.' 'Check firewall, proxy, VPN, router, and ISP status.'}

        Set-Step 96 'Reviewing startup and heavy processes...'
        $startup=@(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
        if($startup.Count -gt 20){Add-Result 'WARN' 'Performance' ("{0} startup entries detected." -f $startup.Count) 'Disable unneeded entries in Task Manager > Startup apps.' ($startup|Select Name,Command,Location)}else{Add-Result 'PASS' 'Performance' ("{0} startup entries detected." -f $startup.Count) 'Review periodically in Task Manager.'}
        $cpu=Get-CimInstance Win32_Processor|Measure-Object LoadPercentage -Average
        Add-Result 'INFO' 'Performance' ("Current average CPU load: {0:N0}%." -f $cpu.Average) 'Use Task Manager for a longer observation if the PC feels slow.'

        Set-Step 100 'Scan complete.'
        $fails=@($script:Results|Where Status -eq 'FAIL').Count; $warns=@($script:Results|Where Status -eq 'WARN').Count
        if($fails){$StatusTitle.Text="$fails issue(s) need attention"}elseif($warns){$StatusTitle.Text="No critical failures; $warns warning(s) found"}else{$StatusTitle.Text='No obvious issues found'}
        $StatusDetail.Text='Review each recommendation. A clean scan cannot rule out every intermittent hardware or software problem.'
        $firstProblem=$ResultsList.Items|Where-Object {$_.Status -in @('FAIL','WARN')}|Select-Object -First 1
        if($firstProblem){$ResultsList.SelectedItem=$firstProblem;$ResultsList.ScrollIntoView($firstProblem)}
    } catch { Add-Result 'FAIL' 'Scanner' $_.Exception.Message 'Export the report and rerun as administrator.'; $StatusTitle.Text='Scan stopped by an error' }
    finally { $ScanButton.IsEnabled=$true; $FixAllButton.IsEnabled=(@($script:Results|Where-Object {$_.Status -in @('WARN','FAIL')}).Count -gt 0); $ExportButton.IsEnabled=($script:Results.Count -gt 0) }
}

function Export-Report {
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $jsonPath=Join-Path $script:ReportRoot "PCMedic-$stamp.json"; $htmlPath=Join-Path $script:ReportRoot "PCMedic-$stamp.html"
    $payload=[ordered]@{App='PC Medic';Version='1.5.0';Computer=$env:COMPUTERNAME;Started=$script:ScanStarted;Exported=Get-Date;Results=$script:Results}
    $payload|ConvertTo-Json -Depth 8|Set-Content $jsonPath -Encoding UTF8
    $rows=foreach($r in $script:Results){'<tr class="'+$r.Status.ToLower()+'"><td>'+[Web.HttpUtility]::HtmlEncode($r.Status)+'</td><td>'+[Web.HttpUtility]::HtmlEncode($r.Area)+'</td><td>'+[Web.HttpUtility]::HtmlEncode($r.Finding)+'</td><td>'+[Web.HttpUtility]::HtmlEncode($r.Recommendation)+'</td></tr>'}
    $html='<!doctype html><meta charset="utf-8"><title>PC Medic Report</title><style>body{font:15px Segoe UI;background:#0b1220;color:#e5e7eb;margin:35px}table{border-collapse:collapse;width:100%;background:#111827}th,td{padding:11px;border:1px solid #334155;text-align:left;vertical-align:top}.pass td:first-child{color:#4ade80}.warn td:first-child{color:#fbbf24}.fail td:first-child{color:#fb7185}.info td:first-child{color:#60a5fa}</style><h1>PC Medic Report</h1><p>'+[Web.HttpUtility]::HtmlEncode($env:COMPUTERNAME)+' - '+(Get-Date)+'</p><table><tr><th>Status</th><th>Area</th><th>Finding</th><th>Recommendation</th></tr>'+($rows-join '')+'</table>'
    Set-Content $htmlPath $html -Encoding UTF8; Start-Process $htmlPath
    [System.Windows.MessageBox]::Show("Report saved:`n$htmlPath`n$jsonPath",'PC Medic','OK','Information')|Out-Null
}
function Set-RepairProgress([string]$Stage,[int]$Percent=-1,[string]$Detail=''){
    $RepairStageText.Text=$Stage;$RepairDetailText.Text=$Detail
    if($Percent -lt 0){$RepairProgress.IsIndeterminate=$true;$RepairPercentText.Text='Working'}else{$RepairProgress.IsIndeterminate=$false;$RepairProgress.Value=[math]::Max(0,[math]::Min(100,$Percent));$RepairPercentText.Text="$Percent%"}
    Update-UI
}
function Run-Repair([string]$Name,[string]$Warning,[scriptblock]$Action){
    if(-not(Confirm-Action $Name $Warning)){return}
    $MainTabs.SelectedItem=$RepairsTab
    $RepairOutput.Text="$Name started at $(Get-Date)."
    $repairButtons=@($FixAllButton,$RestoreButton,$SystemRepairButton,$DiskRepairButton,$NetworkRepairButton,$MemoryButton,$DefenderButton)
    foreach($button in $repairButtons){$button.IsEnabled=$false}
    Set-RepairProgress "Starting $Name" -1 'Preparing the Windows repair tools. Do not close PC Medic.'
    try{$out=&$Action;Set-RepairProgress "$Name complete" 100 'The requested repair finished successfully.';$RepairOutput.Text="$Name completed at $(Get-Date).`n`n$out"}
    catch{Set-RepairProgress "$Name failed" 0 $_.Exception.Message;$RepairOutput.Text="$Name failed at $(Get-Date).`n`n$($_.Exception.ToString())"}
    finally{foreach($button in $repairButtons){$button.IsEnabled=$true}}
}

function Invoke-FixAllSafeIssues {
    $problems=@($script:Results | Where-Object {$_.Status -in @('WARN','FAIL')})
    if(-not $problems.Count){[System.Windows.MessageBox]::Show('Run a full scan first, or there are no warnings or failures to repair.','PC Medic','OK','Information')|Out-Null;return}
    $systemFix=@($problems|Where-Object Area -eq 'System files').Count -gt 0
    $diskFix=@($problems|Where-Object {$_.Area -eq 'Storage' -and $_.Finding -match 'disk|controller|NTFS|health|file-system'}).Count -gt 0
    $driverFix=@($problems|Where-Object {$_.Area -eq 'Drivers' -and $_.Finding -notmatch 'over five years old'}).Count -gt 0
    $updateFix=@($problems|Where-Object Area -eq 'Updates').Count -gt 0
    $securityFix=@($problems|Where-Object Area -eq 'Security').Count -gt 0
    $networkFix=@($problems|Where-Object Area -eq 'Network').Count -gt 0
    $automaticCount=@(@($systemFix,$diskFix,$driverFix,$updateFix,$securityFix,$networkFix) | Where-Object {$_}).Count
    if(-not $automaticCount){[System.Windows.MessageBox]::Show('The detected warnings require manual review. PC Medic will not guess at hardware replacement, delete files, or install unknown drivers.','PC Medic','OK','Information')|Out-Null;return}
    $warning="PC Medic found $automaticCount safe repair group(s). It will create a restore point when possible, then run only the matching Windows repair tools.`n`nNetwork repair may require a restart. PC Medic will not delete personal files, uninstall applications, replace hardware, or install third-party drivers.`n`nContinue?"
    Run-Repair 'Fix all safe issues' $warning {
        $log=[System.Collections.Generic.List[string]]::new();$step=0
        try{Set-RepairProgress 'Creating a safety restore point' 2 'Saving Windows system settings before repairs.';Enable-ComputerRestore -Drive ($env:SystemDrive+'\') -ErrorAction SilentlyContinue;Checkpoint-Computer -Description 'PC Medic - Fix All' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop;$log.Add('Restore point created.')}catch{$log.Add('Restore point was unavailable: '+$_.Exception.Message)}
        if($systemFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Windows files" 5 'DISM is repairing the Windows component store.';$a=Invoke-Native 'dism.exe' '/Online /Cleanup-Image /RestoreHealth /English' {param($p) Set-RepairProgress "Repair $step of $automaticCount`: Windows files" (5+[math]::Round($p*0.35)) ("DISM progress: {0:N1}%" -f $p)};Set-RepairProgress "Repair $step of $automaticCount`: Windows files" 42 'SFC is checking and replacing protected Windows files.';$b=Invoke-Native 'sfc.exe' '/scannow' {param($p) Set-RepairProgress "Repair $step of $automaticCount`: Windows files" (42+[math]::Round($p*0.18)) ("SFC progress: {0:N1}%" -f $p)};$log.Add("DISM exit $($a.ExitCode); SFC exit $($b.ExitCode).")}
        if($diskFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Disk scan" 62 'CHKDSK is checking the Windows drive online.';$r=Invoke-Native 'chkdsk.exe' ($env:SystemDrive+' /scan') {param($p) Set-RepairProgress "Repair $step of $automaticCount`: Disk scan" (62+[math]::Round($p*0.12)) ("CHKDSK progress: {0:N1}%" -f $p)};$log.Add("CHKDSK exit $($r.ExitCode).")}
        if($driverFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Devices" 77 'Windows is rescanning connected hardware and installed drivers.';$r=Invoke-Native 'pnputil.exe' '/scan-devices';$log.Add("Device rescan exit $($r.ExitCode).")}
        if($updateFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Windows Update" 82 'Restoring the Windows Update and transfer services.';foreach($serviceName in @('bits','wuauserv')){try{Set-Service $serviceName -StartupType Manual -ErrorAction Stop;Start-Service $serviceName -ErrorAction SilentlyContinue;$log.Add("$serviceName service restored.")}catch{$log.Add("$serviceName service: "+$_.Exception.Message)}}}
        if($securityFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Windows Security" 88 'Enabling Defender real-time monitoring and starting a quick scan.';try{Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop;Start-MpScan -ScanType QuickScan -ErrorAction Stop;$log.Add('Defender real-time protection enabled and quick scan completed.')}catch{$log.Add('Defender repair: '+$_.Exception.Message)}}
        if($networkFix){$step++;Set-RepairProgress "Repair $step of $automaticCount`: Network" 94 'Flushing DNS and resetting Winsock and TCP/IP.';$one=ipconfig /flushdns|Out-String;$two=netsh winsock reset|Out-String;$three=netsh int ip reset|Out-String;$log.Add("Network stack reset. Restart Windows to finish.`n$one`n$two`n$three")}
        $manual=@($problems|Where-Object {($_.Area -in @('Hardware','Stability','Performance')) -or ($_.Area -eq 'Storage' -and $_.Finding -match 'free|full') -or ($_.Area -eq 'Drivers' -and $_.Finding -match 'over five years old')})
        if($manual.Count){$log.Add("$($manual.Count) item(s) still require manual review because automatic repair could be unsafe.")}
        $log -join "`n`n"
    }
}

$ScanButton.Add_Click({Invoke-FullScan})
$FixAllButton.Add_Click({Invoke-FixAllSafeIssues})
$ExportButton.Add_Click({Export-Report})
$ResultsList.Add_SelectionChanged({Show-SelectedIssue})
$FixSelectedButton.Add_Click({Fix-SelectedIssue})
$CheckUpdateButton.Add_Click({Start-UpdateCheck -Force})
$RestoreButton.Add_Click({Run-Repair 'Create restore point' 'This creates a Windows restore point named PC Medic. Continue?' {Set-RepairProgress 'Creating restore point' -1 'Windows is taking a snapshot of system settings.';Enable-ComputerRestore -Drive ($env:SystemDrive+'\') -ErrorAction SilentlyContinue;Checkpoint-Computer -Description 'PC Medic - Before Repair' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop;'Restore point created.'}})
$SystemRepairButton.Add_Click({Run-Repair 'Repair Windows files' 'This runs DISM RestoreHealth followed by SFC /scannow. It can take 10-45 minutes and should not be interrupted. Create a restore point first. Continue?' {
    Set-RepairProgress 'Stage 1 of 2: Repairing the Windows component store' 0 'DISM is checking Windows repair sources and replacing damaged components.'
    $a=Invoke-Native 'dism.exe' '/Online /Cleanup-Image /RestoreHealth /English' {param($p) Set-RepairProgress 'Stage 1 of 2: Repairing the Windows component store' ([math]::Round($p*0.65)) ("DISM progress: {0:N1}%" -f $p)}
    if($a.ExitCode -ne 0){throw "DISM failed with exit code $($a.ExitCode). $($a.Output)"}
    Set-RepairProgress 'Stage 2 of 2: Checking protected Windows files' 65 'SFC is verifying protected files and replacing incorrect copies.'
    $b=Invoke-Native 'sfc.exe' '/scannow' {param($p) Set-RepairProgress 'Stage 2 of 2: Checking protected Windows files' (65+[math]::Round($p*0.35)) ("SFC verification: {0:N1}%" -f $p)}
    if($b.ExitCode -ne 0){throw "SFC failed with exit code $($b.ExitCode). $($b.Output)"}
    "DISM exit: $($a.ExitCode)`n$($a.Output)`n`nSFC exit: $($b.ExitCode)`n$($b.Output)"
}})
$DiskRepairButton.Add_Click({Run-Repair 'Online disk repair' 'This runs CHKDSK /scan on the Windows drive. If offline repair is required, PC Medic will report it rather than forcing a restart. Continue?' {Set-RepairProgress 'Scanning the Windows drive' 0 'CHKDSK is checking file-system records without taking the drive offline.';$r=Invoke-Native 'chkdsk.exe' ($env:SystemDrive+' /scan') {param($p) Set-RepairProgress 'Scanning the Windows drive' ([math]::Round($p)) ("CHKDSK progress: {0:N1}%" -f $p)};if($r.ExitCode -gt 1){throw "CHKDSK failed with exit code $($r.ExitCode)."};$r.Output}})
$NetworkRepairButton.Add_Click({Run-Repair 'Reset network stack' 'This flushes DNS and resets Winsock/IP. VPN or custom network settings may need to be reapplied, and Windows should be restarted afterward. Continue?' {Set-RepairProgress 'Flushing the DNS cache' 20 'Removing cached domain-name records.';$one=ipconfig /flushdns|Out-String;Set-RepairProgress 'Resetting Winsock' 55 'Restoring Windows socket catalog defaults.';$two=netsh winsock reset|Out-String;Set-RepairProgress 'Resetting TCP/IP' 85 'Restoring Windows TCP/IP stack defaults.';$three=netsh int ip reset|Out-String;"$one`n$two`n$three`nNetwork stack reset. Restart Windows."}})
$MemoryButton.Add_Click({if(Confirm-Action 'Windows Memory Diagnostic' 'This opens Windows Memory Diagnostic. Choose when to restart; save your work first. Continue?'){Start-Process mdsched.exe}})
$UpdateButton.Add_Click({Start-Process 'ms-settings:windowsupdate'})
$DriversButton.Add_Click({Start-Process devmgmt.msc})
$DefenderButton.Add_Click({Run-Repair 'Defender quick scan' 'This runs a Microsoft Defender quick scan. Continue?' {Set-RepairProgress 'Scanning common malware locations' -1 'Microsoft Defender is running a quick scan. Duration depends on the number of files.';Start-MpScan -ScanType QuickScan -ErrorAction Stop;'Microsoft Defender quick scan completed.'}})
$HardwareRefreshButton.Add_Click({Load-HardwareInventory;Update-LiveHardware})
$script:HardwareTimer=New-Object Windows.Threading.DispatcherTimer
$script:HardwareTimer.Interval=[TimeSpan]::FromSeconds(2)
$script:HardwareTimer.Add_Tick({Update-LiveHardware})
$window.Add_ContentRendered({Load-HardwareInventory;Update-LiveHardware;$script:HardwareTimer.Start();Start-UpdateCheck})
$window.Add_Closed({$script:HardwareTimer.Stop()})
$window.ShowDialog()|Out-Null
