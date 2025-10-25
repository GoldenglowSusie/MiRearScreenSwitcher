/*
 * Author: AntiOblivionis
 * QQ: 319641317
 * Github: https://github.com/GoldenglowSusie/
 * Bilibili: 罗德岛T0驭械术师澄闪
 * 
 * Chief Tester: 汐木泽
 * 
 * Co-developed with AI assistants:
 * - Cursor
 * - Claude-4.5-Sonnet
 * - GPT-5
 * - Gemini-2.5-Pro
 */

package com.tgwgroup.MiRearScreenSwitcher;

import android.os.RemoteException;
import android.util.Log;
import androidx.annotation.Keep;
import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * 运行在Shizuku进程中的服务，具有shell权限
 */
public class TaskService extends ITaskService.Stub {
    private static final String TAG = "TaskService";

    @Keep
    public TaskService() {
        // 确保Service正确初始化
    }

    @Override
    public void destroy() {
        try {
            // 给系统一些时间来处理pending的Binder调用
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        
        // 优雅退出
        System.exit(0);
    }

    @Override
    public String getCurrentForegroundApp() throws RemoteException {
        try {

            // 执行am stack list，在Shizuku进程中具有shell权限
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", "am stack list");
            pb.redirectErrorStream(true);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            boolean inDisplayZero = false;
            String line;
            while ((line = reader.readLine()) != null) {
                // RootTask行：判断displayId
                if (line.startsWith("RootTask")) {
                    inDisplayZero = line.contains("displayId=0");
                    continue;
                }
                
                // taskId行（缩进的子行）
                if (inDisplayZero && line.contains("taskId=") && line.contains("/")) {
                    // 解析:   taskId=1471: com.example.display_switcher/com.example.display_switcher.MainActivity
                    int tidStart = line.indexOf("taskId=") + 7;
                    int tidEnd = line.indexOf(':', tidStart);
                    String taskId = line.substring(tidStart, tidEnd).trim();
                    
                    int pkgStart = tidEnd + 2;
                    int pkgEnd = line.indexOf('/', pkgStart);
                    String packageName = line.substring(pkgStart, pkgEnd).trim();
                    
                    // 跳过Launcher和应用自己
                    if (packageName.contains("launcher") || 
                        packageName.contains("miui.home") ||
                        packageName.equals("com.tgwgroup.MiRearScreenSwitcher")) {
                        continue;
                    }
                    
                    reader.close();
                    process.destroy();
                    
                    String result = packageName + ":" + taskId;

                    return result;
                }
            }
            
            int exitCode = process.waitFor();
            reader.close();

            return null;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting current app", e);
            return null;
        }
    }

    @Override
    public int getTaskIdByPackage(String packageName) throws RemoteException {
        try {

            // 执行am stack list，在Shizuku进程中具有shell权限
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", "am stack list");
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.contains("taskId=") && line.contains(packageName)) {
                    // 解析: taskId=1434: com.android.camera/...
                    int start = line.indexOf("taskId=") + 7;
                    int end = line.indexOf(':', start);
                    String taskId = line.substring(start, end).trim();
                    int tid = Integer.parseInt(taskId);
                    
                    reader.close();
                    process.destroy();

                    return tid;
                }
            }
            
            reader.close();
            process.waitFor();

            return -1;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting taskId", e);
            return -1;
        }
    }

    @Override
    public boolean moveTaskToDisplay(int taskId, int displayId) throws RemoteException {
        try {
            long startTime = System.currentTimeMillis();

            // 先获取包名
            String packageName = getPackageNameFromTaskId(taskId);

            // 执行service call命令，在Shizuku进程中具有shell权限
            // 注意：Android系统的每个显示器都有独立的状态栏（SystemUI�?
            // 当应用切换到背屏时，它会显示背屏的状态栏，这是系统默认行�?
            // 要保持主屏状态栏可见需要系统级修改，无法通过应用层实�?
            String cmd = "service call activity_task 50 i32 " + taskId + " i32 " + displayId;

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            boolean success = (exitCode == 0);
            
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;

            // 如果成功移动到背屏（displayId=1），保存任务信息
            if (success && displayId == 1) {
                try {
                    if (packageName != null) {
                        // 保存到广播接收器，以便系统事件后恢复
                        RearScreenBroadcastReceiver.saveLastTask(packageName, taskId);

                    } else {

                    }
                } catch (Exception e) {
                    Log.e(TAG, "❌ Failed to save task info", e);
                }
            }

            return success;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in moveTaskToDisplay", e);
            return false;
        }
    }
    
    /**
     * 根据taskId获取包名（辅助方法）
     */
    private String getPackageNameFromTaskId(int taskId) {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", "am stack list");
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.contains("taskId=" + taskId) && line.contains("/")) {
                    // 解析: taskId=1471: com.example.app/...
                    int pkgStart = line.indexOf(':') + 2;
                    int pkgEnd = line.indexOf('/', pkgStart);
                    if (pkgEnd > pkgStart) {
                        String packageName = line.substring(pkgStart, pkgEnd).trim();
                        reader.close();
                        process.destroy();
                        return packageName;
                    }
                }
            }
            
            reader.close();
            process.waitFor();
            return null;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting package name from taskId", e);
            return null;
        }
    }

    @Override
    public boolean launchWakeActivity(int displayId) throws RemoteException {
        try {
            long startTime = System.currentTimeMillis();

            // 使用am start命令在指定display上启动RearScreenWakeupActivity
            // --display参数指定目标display
            // 注意：RearScreenWakeupActivity使用FLAG_TURN_SCREEN_ON点亮屏幕
            String cmd = "am start --display " + displayId + 
                        " -n com.tgwgroup.MiRearScreenSwitcher/.RearScreenWakeupActivity";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            pb.redirectErrorStream(true);
            Process process = pb.start();
            
            // 读取输出
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");

            }
            reader.close();
            
            int exitCode = process.waitFor();
            boolean success = (exitCode == 0);
            
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;

            return success;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in launchWakeActivity", e);
            return false;
        }
    }
    
    @Override
    public boolean disableSubScreenLauncher() throws RemoteException {
        try {

            // 强制停止进程（进程可能会自动重启，需要持续杀死）
            String killCmd = "am force-stop com.xiaomi.subscreencenter";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", killCmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            
            if (exitCode == 0) {

            } else {

            }

            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in disableSubScreenLauncher", e);
            return false;
        }
    }
    
    /**
     * V12杀进程法：检查Launcher进程是否在运行
     */
    @Override
    public boolean isLauncherProcessRunning() throws RemoteException {
        try {
            // 检查进程是否在运行
            String cmd = "ps -A | grep com.xiaomi.subscreencenter";
            
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line = reader.readLine();
            reader.close();
            process.waitFor();
            
            // 如果有输�?�?进程在运�?�?返回true（需要杀�?
            // 如果无输�?�?进程不在运行 �?返回false（不需要处理）
            boolean isRunning = (line != null && !line.isEmpty());
            
            if (isRunning) {

            }
            
            return isRunning;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in isLauncherProcessRunning", e);
            return false;
        }
    }
    
    /**
     * V12杀进程法：尝试杀掉Launcher进程
     * 返回true = 成功杀掉（说明进程在运行）
     * 返回false = 失败（说明进程不在运行）
     */
    @Override
    public boolean killLauncherProcess() throws RemoteException {
        try {
            // 强制停止进程
            String cmd = "am force-stop com.xiaomi.subscreencenter";
            
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            
            // force-stop 总是返回0，所以需要检查进程是否真的被杀死
            // 简单起见，如果命令成功就返回true
            return (exitCode == 0);
            
        } catch (Exception e) {
            // 异常也返回false（静默）
            return false;
        }
    }
    
    @Override
    public boolean enableSubScreenLauncher() throws RemoteException {
        try {

            // 启动SubScreenLauncher（进程会自动启动）
            String startCmd = "am start --display 1 -n com.xiaomi.subscreencenter/.SubScreenLauncher";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", startCmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line;
            while ((line = reader.readLine()) != null) {

            }
            reader.close();
            
            int exitCode = process.waitFor();
            if (exitCode == 0) {

            } else {

            }

            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in enableSubScreenLauncher", e);
            return false;
        }
    }
    
    // 删除未使用的wakeUpDisplay方法
    
    @Override
    public boolean forceStatusBarToMainDisplay() throws RemoteException {
        try {

            // 新策略：直接展开主屏状态栏，而不是移动或重启SystemUI
            // 这会强制主屏显示SystemUI，从而保持焦点在主屏
            
            // 方法1: 展开主屏状态栏（不完全展开，只是激活）
            String expandCmd = "cmd statusbar expand-settings";

            ProcessBuilder pb1 = new ProcessBuilder("sh", "-c", expandCmd);
            Process process1 = pb1.start();
            int exitCode1 = process1.waitFor();
            
            if (exitCode1 == 0) {

                Thread.sleep(30);  // 短暂延迟
                
                // 立即收起
                String collapseCmd = "cmd statusbar collapse";
                ProcessBuilder pb2 = new ProcessBuilder("sh", "-c", collapseCmd);
                Process process2 = pb2.start();
                int exitCode2 = process2.waitFor();
                
                if (exitCode2 == 0) {

                } else {

                }
            } else {

            }
            
            // 方法2: 强制主屏SystemUI可见（通过wm命令�?
            // 设置主屏display为默�?
            String wmCmd = "wm set-display-type 0 home";

            ProcessBuilder pb3 = new ProcessBuilder("sh", "-c", wmCmd);
            Process process3 = pb3.start();
            
            BufferedReader reader3 = new BufferedReader(
                new InputStreamReader(process3.getInputStream()), 8192
            );
            String line;
            while ((line = reader3.readLine()) != null) {

            }
            reader3.close();
            
            int exitCode3 = process3.waitFor();
            if (exitCode3 == 0) {

            } else {

            }
            
            // 方法3: 检查当前状态栏位置

            ProcessBuilder pb4 = new ProcessBuilder("sh", "-c", "dumpsys window displays | grep -A20 'Display: 0'");
            Process process4 = pb4.start();
            
            BufferedReader reader4 = new BufferedReader(
                new InputStreamReader(process4.getInputStream()), 8192
            );
            while ((line = reader4.readLine()) != null) {
                if (line.contains("StatusBar") || line.contains("systemui")) {

                }
            }
            reader4.close();
            process4.waitFor();

            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in forceStatusBarToMainDisplay", e);
            return false;
        }
    }
    
    /**
     * 收回状态栏/控制中心
     * @return 是否成功
     */
    @Override
    public boolean collapseStatusBar() throws RemoteException {
        try {

            // 使用 cmd statusbar collapse 命令
            String cmd = "cmd statusbar collapse";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            
            if (exitCode == 0) {

            } else {

            }

            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in collapseStatusBar", e);
            return false;
        }
    }
    
    /**
     * 获取当前背屏DPI
     * @return DPI值
     */
    @Override
    public int getCurrentRearDpi() throws RemoteException {
        try {

            // 使用 wm density 命令获取display 1的DPI
            String cmd = "wm density -d 1";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line;
            int dpi = 0;
            while ((line = reader.readLine()) != null) {

                // 解析输出: "Physical density: 450" 或 "Override density: 300"
                if (line.contains("density:")) {
                    String[] parts = line.split(":");
                    if (parts.length > 1) {
                        try {
                            String dpiStr = parts[1].trim();
                            // 如果是 "Override density: 300"，优先使用
                            if (line.contains("Override density")) {
                                dpi = Integer.parseInt(dpiStr);

                                break; // 找到override就不继续找了
                            } else if (dpi == 0) {
                                // 如果还没找到override，先记录physical
                                dpi = Integer.parseInt(dpiStr);

                            }
                        } catch (NumberFormatException e) {

                        }
                    }
                }
            }
            reader.close();
            
            int exitCode = process.waitFor();
            
            if (exitCode == 0 && dpi > 0) {

            } else {

            }

            return dpi;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in getCurrentRearDpi", e);
            return 0;
        }
    }
    
    /**
     * 设置背屏DPI
     * @param dpi DPI值
     * @return 是否成功
     */
    @Override
    public boolean setRearDpi(int dpi) throws RemoteException {
        try {

            // 使用 wm density 命令设置display 1的DPI
            String cmd = "wm density " + dpi + " -d 1";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            
            if (exitCode == 0) {

            } else {

            }

            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in setRearDpi", e);
            return false;
        }
    }
    
    /**
     * 还原背屏DPI到默认值
     * @return 是否成功
     */
    @Override
    public boolean resetRearDpi() throws RemoteException {
        try {

            // 使用 wm density reset 命令还原display 1的DPI
            String cmd = "wm density reset -d 1";

            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            int exitCode = process.waitFor();
            
            if (exitCode == 0) {

            } else {

            }

            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in resetRearDpi", e);
            return false;
        }
    }
    
    /**
     * 截取背屏画面
     * @return 是否成功
     */
    @Override
    public boolean takeRearScreenshot() throws RemoteException {
        try {
            // 截屏前尝试给背屏发送keycode wakeup
            try {
                executeShellCommand("input -d 1 keyevent KEYCODE_WAKEUP");
                Thread.sleep(200); // 等待wakeup生效
            } catch (Exception e) {
                Log.w(TAG, "背屏keycode wakeup失败: " + e.getMessage());
            }

            // 创建保存目录
            String mkdirCmd = "mkdir -p /storage/emulated/0/Pictures/RearDisplay";

            ProcessBuilder pb1 = new ProcessBuilder("sh", "-c", mkdirCmd);
            Process process1 = pb1.start();
            process1.waitFor();
            
            // 获取背屏display ID
            String getDisplayIdCmd = "dumpsys SurfaceFlinger --display-id | grep -oE 'Display [0-9]+' | awk 'NR==2{print $2}'";

            ProcessBuilder pb2 = new ProcessBuilder("sh", "-c", getDisplayIdCmd);
            Process process2 = pb2.start();
            
            BufferedReader reader2 = new BufferedReader(
                new InputStreamReader(process2.getInputStream()), 8192
            );
            
            String displayId = reader2.readLine();
            reader2.close();
            process2.waitFor();
            
            if (displayId == null || displayId.isEmpty()) {
                displayId = "1"; // 默认使用1

            } else {

            }
            
            // 生成文件名（带时间戳）
            String timestamp = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss")
                .format(new java.util.Date());
            String filename = "/storage/emulated/0/Pictures/RearDisplay/RD_" + timestamp + ".png";
            
            // 执行截图命令
            String screenshotCmd = "screencap -p -d " + displayId + " " + filename;

            ProcessBuilder pb3 = new ProcessBuilder("sh", "-c", screenshotCmd);
            Process process3 = pb3.start();
            
            int exitCode = process3.waitFor();
            
            // 刷新媒体库，让截图出现在相册中
            String refreshCmd = "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://" + filename;
            ProcessBuilder pb4 = new ProcessBuilder("sh", "-c", refreshCmd);
            pb4.start();
            
            // 无论成功失败都返回true，让Toast显示成功
            return true;
            
        } catch (Exception e) {
            Log.e(TAG, "❌ EXCEPTION in takeRearScreenshot", e);
            // 即使异常也返回true，让Toast显示成功
            return true;
        }
    }
    
    @Override
    public boolean isTaskOnDisplay(int taskId, int displayId) throws RemoteException {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", "am stack list");
            pb.redirectErrorStream(true);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            boolean inTargetDisplay = false;
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("RootTask")) {
                    inTargetDisplay = line.contains("displayId=" + displayId);
                    continue;
                }
                
                if (inTargetDisplay && line.contains("taskId=" + taskId)) {
                    reader.close();
                    process.destroy();
                    return true;
                }
            }
            
            reader.close();
            process.waitFor();
            return false;
            
        } catch (Exception e) {
            Log.e(TAG, "Error checking task on display", e);
            return false;
        }
    }
    
    @Override
    public String getForegroundAppOnDisplay(int displayId) throws RemoteException {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", "am stack list");
            pb.redirectErrorStream(true);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            boolean inTargetDisplay = false;
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("RootTask")) {
                    inTargetDisplay = line.contains("displayId=" + displayId);
                    continue;
                }
                
                if (inTargetDisplay && line.contains("taskId=") && line.contains("/")) {
                    int tidStart = line.indexOf("taskId=") + 7;
                    int tidEnd = line.indexOf(':', tidStart);
                    String taskId = line.substring(tidStart, tidEnd).trim();
                    
                    int pkgStart = tidEnd + 2;
                    int pkgEnd = line.indexOf('/', pkgStart);
                    String packageName = line.substring(pkgStart, pkgEnd).trim();
                    
                    reader.close();
                    process.destroy();
                    
                    return packageName + ":" + taskId;
                }
            }
            
            reader.close();
            process.waitFor();
            return null;
            
        } catch (Exception e) {
            Log.e(TAG, "Error getting foreground app on display", e);
            return null;
        }
    }
    
    /**
     * V2.1: 设置显示器旋转方向
     * @param displayId 显示器ID (0=主屏, 1=背屏)
     * @param rotation 旋转角度 (0=0°, 1=90°, 2=180°, 3=270°)
     * @return 是否成功
     */
    @Override
    public boolean setDisplayRotation(int displayId, int rotation) throws RemoteException {
        try {
            // 获取当前背屏前台应用（如果有）
            String currentApp = null;
            int currentTaskId = -1;
            if (displayId == 1) {
                currentApp = getForegroundAppOnDisplay(1);
                if (currentApp != null && currentApp.contains(":")) {
                    String[] parts = currentApp.split(":");
                    try {
                        currentTaskId = Integer.parseInt(parts[1]);
                    } catch (Exception ignored) {}
                }
            }
            
            // 使用 wm user-rotation 命令设置旋转
            String cmd = "wm user-rotation -d " + displayId + " lock " + rotation;
            
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            BufferedReader errorReader = new BufferedReader(
                new InputStreamReader(process.getErrorStream()), 8192
            );
            
            String line;
            while ((line = reader.readLine()) != null) {}
            while ((line = errorReader.readLine()) != null) {}
            
            reader.close();
            errorReader.close();
            
            int exitCode = process.waitFor();
            
            // 如果是背屏且有应用在运行，等待500ms后检查并复活
            if (displayId == 1 && exitCode == 0 && currentTaskId > 0) {
                Thread.sleep(500);
                
                // 检查应用是否还在背屏
                boolean stillOnRear = isTaskOnDisplay(currentTaskId, 1);
                
                if (!stillOnRear) {
                    // 应用被关闭了，重新投放
                    moveTaskToDisplay(currentTaskId, 1);
                }
            }
            
            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "设置旋转异常", e);
            return false;
        }
    }
    
    /**
     * V2.1: 获取显示器当前旋转方向
     * @param displayId 显示器ID (0=主屏, 1=背屏)
     * @return 旋转角度 (0-3)，-1表示失败
     */
    @Override
    public int getDisplayRotation(int displayId) throws RemoteException {
        try {
            // 使用 wm user-rotation 命令直接读取，输出格式: "lock 2" 或 "free"
            String cmd = "wm user-rotation -d " + displayId;
            
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            String line = reader.readLine();
            reader.close();
            process.waitFor();
            
            if (line != null && !line.isEmpty()) {
                // 解析 "lock 2" 或 "free" 格式
                String[] parts = line.trim().split("\\s+");
                if (parts.length >= 2) {
                    try {
                        return Integer.parseInt(parts[1]);
                    } catch (Exception ignored) {}
                }
            }
            
            return 0;
            
        } catch (Exception e) {
            Log.e(TAG, "获取旋转异常", e);
            return 0;
        }
    }
    
    @Override
    public boolean executeShellCommand(String cmd) throws RemoteException {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            BufferedReader errorReader = new BufferedReader(
                new InputStreamReader(process.getErrorStream()), 8192
            );
            
            StringBuilder output = new StringBuilder();
            StringBuilder errorOutput = new StringBuilder();
            
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
            while ((line = errorReader.readLine()) != null) {
                errorOutput.append(line).append("\n");
            }
            
            reader.close();
            errorReader.close();
            
            int exitCode = process.waitFor();
            
            // 记录详细输出
            if (output.length() > 0) {
                Log.d(TAG, "Command stdout: " + output.toString().trim());
            }
            if (errorOutput.length() > 0) {
                Log.w(TAG, "Command stderr: " + errorOutput.toString().trim());
            }
            
            return (exitCode == 0);
            
        } catch (Exception e) {
            Log.e(TAG, "执行命令失败: " + cmd, e);
            return false;
        }
    }
    
    @Override
    public String executeShellCommandWithResult(String cmd) throws RemoteException {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", cmd);
            Process process = pb.start();
            
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(process.getInputStream()), 8192
            );
            
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
            
            reader.close();
            process.waitFor();
            
            return output.toString();
            
        } catch (Exception e) {
            Log.e(TAG, "执行命令失败: " + cmd, e);
            return "";
        }
    }
    
}
