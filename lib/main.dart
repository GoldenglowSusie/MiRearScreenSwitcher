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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
// 删除未使用的dart:io导入
import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 设置错误处理，防止Dart编译器异常退出
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter错误: ${details.exception}');
    print('堆栈跟踪: ${details.stack}');
  };
  
  // 设置沉浸式状态栏（透明状态栏）
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // 添加异常捕获
  PlatformDispatcher.instance.onError = (error, stack) {
    print('平台错误: $error');
    print('堆栈跟踪: $stack');
    return true;
  };
  
  runApp(const DisplaySwitcherApp());
}

class DisplaySwitcherApp extends StatelessWidget {
  const DisplaySwitcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MRSS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF9D88)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.display.switcher/task');
  
  bool _shizukuRunning = false;
  String _statusMessage = '正在检查Shizuku...';
  bool _isLoading = false;
  bool _hasError = false;  // 是否有错误
  String _errorDetail = '';  // 错误详情
  
  // V15: 背屏DPI相关
  int _currentRearDpi = 0;
  bool _dpiLoading = true;  // DPI加载状态
  final TextEditingController _dpiController = TextEditingController();
  final FocusNode _dpiFocusNode = FocusNode();
  
  // V2.1: 显示控制相关
  int _currentRotation = 0;  // 当前旋转方向 (0=0°, 1=90°, 2=180°, 3=270°)
  
  // V2.2: 接近传感器开关
  bool _proximitySensorEnabled = true;  // 默认打开
  
  // V2.3: 充电动画开关
  bool _chargingAnimationEnabled = true;  // 默认打开
  
  // V2.5: 背屏常亮开关
  bool _keepScreenOnEnabled = true;  // 默认打开
  
  // V2.4: 通知功能
  bool _notificationEnabled = false;  // 默认关闭（需要授权）
  bool _notificationDarkMode = false;  // 通知暗夜模式（默认关闭）
  
  @override
  void initState() {
    super.initState();
    _checkShizuku();
    _loadSettings();  // 加载所有设置
    _setupMethodCallHandler();
    _loadProximitySensorSetting();  // 加载接近传感器设置
    
    // 通知权限会在Shizuku授权完成后自动请求（见_checkShizuku）
    
    // 延迟获取DPI和旋转，等待TaskService连接
    Future.delayed(const Duration(seconds: 2), () {
      _getCurrentRearDpi();
      _getCurrentRotation();
    });
  }
  
  @override
  void dispose() {
    _dpiController.dispose();
    _dpiFocusNode.dispose();
    super.dispose();
  }
  
  void _setupMethodCallHandler() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onShizukuPermissionChanged') {
        final granted = call.arguments as bool;
        print('Shizuku permission changed: $granted');
        // 刷新状态
        await _checkShizuku();
        
        // Shizuku授权完成后，立即请求通知权限
        if (granted) {
          print('✓ Shizuku已授权，立即请求通知权限');
          _requestNotificationPermission();
        }
      }
    });
  }
  
  Future<void> _requestNotificationPermission() async {
    // Android 13+ 需要请求通知权限
    try {
      await platform.invokeMethod('requestNotificationPermission');
      print('通知权限请求已发送');
    } catch (e) {
      print('请求通知权限失败: $e');
    }
  }
  
  // V15: 获取当前背屏DPI
  Future<void> _getCurrentRearDpi() async {
    setState(() {
      _dpiLoading = true;
    });
    
    // 最多重试5次，每次间隔1秒
    for (int i = 0; i < 5; i++) {
      try {
        final int dpi = await platform.invokeMethod('getCurrentRearDpi');
        setState(() {
          _currentRearDpi = dpi;
          _dpiController.text = dpi.toString();
          _dpiLoading = false;
        });
        print('当前背屏DPI: $dpi');
        return; // 成功就退出
      } catch (e) {
        print('获取背屏DPI失败 (尝试 ${i + 1}/5): $e');
        if (i < 4) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    
    // 所有重试都失败
    setState(() {
      _dpiLoading = false;
      _currentRearDpi = 0;
    });
    print('获取背屏DPI最终失败');
  }
  
  // V15: 设置背屏DPI
  Future<void> _setRearDpi(int dpi) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 先尝试重新连接TaskService，确保连接正常
      await platform.invokeMethod('ensureTaskServiceConnected');
      
      // 等待连接建立
      await Future.delayed(const Duration(milliseconds: 500));
      
      await platform.invokeMethod('setRearDpi', {'dpi': dpi});
      
      // 刷新当前DPI
      await _getCurrentRearDpi();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('背屏DPI已设置为 $dpi')),
        );
      }
    } catch (e) {
      print('设置背屏DPI失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e\n请确保Shizuku正在运行')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // V15: 还原背屏DPI
  Future<void> _resetRearDpi() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 先尝试重新连接TaskService，确保连接正常
      await platform.invokeMethod('ensureTaskServiceConnected');
      
      // 等待连接建立
      await Future.delayed(const Duration(milliseconds: 500));
      
      await platform.invokeMethod('resetRearDpi');
      
      // 刷新当前DPI
      await _getCurrentRearDpi();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('背屏DPI已还原')),
        );
      }
    } catch (e) {
      print('还原背屏DPI失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('还原失败: $e\n请确保Shizuku正在运行')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _checkShizuku() async {
    setState(() {
      _statusMessage = '正在检查系统权限...';
      _hasError = false;
      _errorDetail = '';
    });
    
    try {
      // 简化检查：直接调用Java层
      final result = await platform.invokeMethod('checkShizuku');
      
      setState(() {
        _shizukuRunning = result == true;
        _hasError = false;
        _errorDetail = '';
        
        if (_shizukuRunning) {
          _statusMessage = '一切就绪';
          
          // Shizuku已授权，立即请求通知权限
          print('✓ Shizuku已授权，立即请求通知权限');
          _requestNotificationPermission();
        } else {
          _hasError = true;
          _statusMessage = '权限不足';
          _errorDetail = 'Shizuku未运行或未授权';
          // 获取详细信息帮助诊断
          _getDetailedStatus();
        }
      });
    } catch (e) {
      // 解析异常类型
      String errorType = '未知错误';
      String errorMsg = e.toString();
      
      if (errorMsg.contains('binder') || errorMsg.contains('Binder')) {
        errorType = 'Shizuku通信异常';
        _errorDetail = 'Shizuku服务可能已崩溃\n请重启Shizuku应用';
      } else if (errorMsg.contains('permission') || errorMsg.contains('Permission')) {
        errorType = '权限不足';
        _errorDetail = '请在Shizuku中授权MRSS';
      } else if (errorMsg.contains('RemoteException')) {
        errorType = '服务调用失败';
        _errorDetail = 'TaskService无响应\n请重启应用';
      } else {
        errorType = '未知错误';
        _errorDetail = errorMsg.length > 50 ? errorMsg.substring(0, 50) + '...' : errorMsg;
      }
      
      setState(() {
        _shizukuRunning = false;
        _hasError = true;
        _statusMessage = errorType;
      });
    }
  }
  
  Future<void> _getDetailedStatus() async {
    try {
      final info = await platform.invokeMethod('getShizukuInfo');
      setState(() {
        _errorDetail = info.toString();
      });
    } catch (e) {
      // 获取详细信息失败，保持当前错误信息
    }
  }
  
  
  
  // V2.1: 重启应用（实际是返回背屏应用到主屏）
  Future<void> _restartApp() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // 检查Shizuku是否可用
      if (!_shizukuRunning) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shizuku未运行，无法操作')),
          );
        }
        return;
      }
      
      // 确保TaskService连接
      await platform.invokeMethod('ensureTaskServiceConnected');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 检查是否有应用在背屏
      final result = await platform.invokeMethod('returnRearAppAndRestart');
      
      if (result == true) {
        // 成功返回主屏
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('应用已返回主屏')),
          );
        }
      } else {
        // 没有应用在背屏
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('背屏没有应用需要返回')),
          );
        }
      }
    } catch (e) {
      print('返回背屏应用时出错: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      // 重置加载状态
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  // V2.2: 加载所有设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _proximitySensorEnabled = prefs.getBool('proximity_sensor_enabled') ?? true;
        _chargingAnimationEnabled = prefs.getBool('charging_animation_enabled') ?? true;
        _keepScreenOnEnabled = prefs.getBool('keep_screen_on_enabled') ?? true;
        _notificationDarkMode = prefs.getBool('notification_dark_mode') ?? false;
      });
      
      // 启动充电服务（如果开关打开）
      if (_chargingAnimationEnabled) {
        _startChargingService();
      }
      
      // 检查通知监听权限
      _checkNotificationPermission();
    } catch (e) {
      print('加载设置失败: $e');
    }
  }
  
  // V2.2: 加载接近传感器设置
  Future<void> _loadProximitySensorSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _proximitySensorEnabled = prefs.getBool('proximity_sensor_enabled') ?? true;
      });
    } catch (e) {
      print('加载接近传感器设置失败: $e');
    }
  }
  
  
  // V2.4: 检查通知监听权限
  Future<void> _checkNotificationPermission() async {
    try {
      final bool hasPermission = await platform.invokeMethod('checkNotificationListenerPermission');
      setState(() {
        _notificationEnabled = hasPermission;
      });
    } catch (e) {
      print('检查通知权限失败: $e');
    }
  }
  
  // V2.4: 切换通知服务
  Future<void> _toggleNotificationService(bool enabled) async {
    if (enabled) {
      // 先检查权限
      final bool hasPermission = await platform.invokeMethod('checkNotificationListenerPermission');
      if (!hasPermission) {
        // 打开设置页面授权
        await platform.invokeMethod('openNotificationListenerSettings');
        return;
      }
    }
    
    await platform.invokeMethod('toggleNotificationService', {'enabled': enabled});
    setState(() {
      _notificationEnabled = enabled;
    });
  }
  
  
  // V2.4: 打开应用选择页面
  Future<void> _openAppSelectionPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AppSelectionPage()),
    );
  }
  
  // V2.2: 切换接近传感器开关
  Future<void> _toggleProximitySensor(bool enabled) async {
    try {
      // 先保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('proximity_sensor_enabled', enabled);
      
      // 通知Service更新状态
      await platform.invokeMethod('setProximitySensorEnabled', {'enabled': enabled});
      
      setState(() {
        _proximitySensorEnabled = enabled;
      });
      print('接近传感器已${enabled ? "启用" : "禁用"}');
    } catch (e) {
      print('切换接近传感器失败: $e');
      // 切换失败，恢复原状态
      setState(() {
        _proximitySensorEnabled = !enabled;
      });
    }
  }
  
  // V2.3: 切换充电动画开关
  Future<void> _toggleChargingAnimation(bool enabled) async {
    try {
      // 先保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('charging_animation_enabled', enabled);
      
      // 启动或停止充电服务
      await platform.invokeMethod('toggleChargingService', {'enabled': enabled});
      
      setState(() {
        _chargingAnimationEnabled = enabled;
      });
      print('充电动画已${enabled ? "启用" : "禁用"}');
    } catch (e) {
      print('切换充电动画失败: $e');
      // 切换失败，恢复原状态
      setState(() {
        _chargingAnimationEnabled = !enabled;
      });
    }
  }
  
  // V2.3: 启动充电服务
  Future<void> _startChargingService() async {
    try {
      await platform.invokeMethod('toggleChargingService', {'enabled': true});
    } catch (e) {
      print('启动充电服务失败: $e');
    }
  }
  
  // V2.5: 切换背屏常亮开关
  Future<void> _toggleKeepScreenOn(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('keep_screen_on_enabled', enabled);
      
      // 通过Intent通知RearScreenKeeperService
      await platform.invokeMethod('setKeepScreenOnEnabled', {'enabled': enabled});
      
      setState(() {
        _keepScreenOnEnabled = enabled;
      });
      print('背屏常亮已${enabled ? "启用" : "禁用"}');
    } catch (e) {
      print('切换背屏常亮失败: $e');
      // 切换失败，恢复原状态
      setState(() {
        _keepScreenOnEnabled = !enabled;
      });
    }
  }
  
  // V3.1: 通知暗夜模式开关
  Future<void> _toggleNotificationDarkMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_dark_mode', enabled);
      
      // 通过Intent通知NotificationService
      await platform.invokeMethod('setNotificationDarkMode', {'enabled': enabled});
      
      setState(() {
        _notificationDarkMode = enabled;
      });
      print('通知暗夜模式已${enabled ? "启用" : "禁用"}');
    } catch (e) {
      print('切换通知暗夜模式失败: $e');
      // 切换失败，恢复原状态
      setState(() {
        _notificationDarkMode = !enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        title: const Text('MRSS', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: _isLoading ? null : _restartApp,
            tooltip: '返回背屏应用到主屏',
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF9D88),  // 珊瑚橙
              Color(0xFFFFB5C5),  // 粉红
              Color(0xFFE0B5DC),  // 紫色
              Color(0xFFA8C5E5),  // 蓝色
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            physics: const BouncingScrollPhysics(), // 始终允许滑动
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // 整合后的状态和权限卡片（毛玻璃效果）
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(
                  decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                        ),
                        padding: const EdgeInsets.all(16),
                  child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                                _shizukuRunning ? Icons.check_circle : (_hasError ? Icons.error_outline : Icons.warning_rounded),
                                size: 28,
                                color: _shizukuRunning ? Colors.green : (_hasError ? Colors.red : Colors.orange),
                              ),
                              const SizedBox(width: 10),
                      Text(
                                _shizukuRunning ? 'Shizuku 运行中' : _statusMessage,
                                style: const TextStyle(
                                  fontSize: 16,
                          color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                        ),
                      ),
                            ],
                          ),
                          if (_hasError && _errorDetail.isNotEmpty) ...[
                            const SizedBox(height: 8),
                      Text(
                              _errorDetail,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.3,
                              ),
                        textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                      ),
                  ),
                ),
              ),
            ),
                  
                const SizedBox(height: 20),
                  
                  // V15: 背屏DPI调整卡片
                Stack(
                  children: [
                    CustomPaint(
                      painter: _SquircleBorderPainter(
                        radius: _SquircleRadii.large,
                        color: Colors.white.withOpacity(0.5),
                        strokeWidth: 1.5,
                      ),
                      child: ClipPath(
                        clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Container(
                        decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '背屏DPI调整',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_dpiLoading) ...[
                                  const SizedBox(width: 12),
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _dpiLoading ? '正在获取当前DPI...' : '当前DPI: $_currentRearDpi  推荐范围: 260-350',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _dpiController,
                                    focusNode: _dpiFocusNode,
                                    enabled: !_dpiLoading && !_isLoading,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.black87),
                                    decoration: const InputDecoration(
                                      labelText: '新DPI值',
                                      labelStyle: TextStyle(color: Colors.black54),
                                      hintText: '输入数字',
                                      hintStyle: TextStyle(color: Colors.black38),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black26),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black26),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black54, width: 2),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ClipPath(
                                  clipper: _SquircleClipper(cornerRadius: _SquircleRadii.small),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFFF9D88),  // 珊瑚橙
                                          Color(0xFFFFB5C5),  // 粉红
                                          Color(0xFFE0B5DC),  // 紫色
                                          Color(0xFFA8C5E5),  // 蓝色
                                        ],
                                      ),
                                    ),
                                    child: ElevatedButton(
                                  onPressed: (_isLoading || _dpiLoading) ? null : () {
                                    final dpi = int.tryParse(_dpiController.text);
                                    if (dpi != null && dpi > 0) {
                                      _setRearDpi(dpi);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('请输入有效的DPI值')),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                        shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(_SquircleRadii.small),
                                        ),
                                  ),
                                  child: const Text('设置'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _SquircleBorderPainter(
                                  radius: _SquircleRadii.small,
                                  color: Colors.black26,
                                  strokeWidth: 1,
                                ),
                                child: ClipPath(
                                  clipper: _SquircleClipper(cornerRadius: _SquircleRadii.small),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: (_isLoading || _dpiLoading) ? null : _resetRearDpi,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.restore, color: Colors.black87, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              '还原默认DPI',
                                              style: TextStyle(color: Colors.black87, fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            const Divider(color: Colors.black26, height: 1),
                            const SizedBox(height: 16),
                            
                            // V2.1: 旋转控制
                            Row(
                              children: [
                                const Text(
                                  '🔄 旋转',
                                  style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                ),
                                const Spacer(),
                                _buildRotationButton('0°', 0),
                                const SizedBox(width: 6),
                                _buildRotationButton('90°', 1),
                                const SizedBox(width: 6),
                                _buildRotationButton('180°', 2),
                                const SizedBox(width: 6),
                                _buildRotationButton('270°', 3),
                              ],
                            ),
                            
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
                  
                const SizedBox(height: 20),
                
                // V2.2: 背屏遮盖检测卡片（独立）
                Stack(
                  children: [
                    CustomPaint(
                      painter: _SquircleBorderPainter(
                        radius: _SquircleRadii.large,
                        color: Colors.white.withOpacity(0.5),
                        strokeWidth: 1.5,
                      ),
                      child: ClipPath(
                        clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            child: Row(
                          children: [
                            const Text(
                              '🤚 背屏遮盖检测',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const Spacer(),
                            _GradientToggle(
                              value: _proximitySensorEnabled,
                              onChanged: _toggleProximitySensor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  ],
                ),
                  
                const SizedBox(height: 20),
                
                // V2.5: 背屏常亮卡片
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '🔆 背屏常亮',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const Spacer(),
                            _GradientToggle(
                              value: _keepScreenOnEnabled,
                              onChanged: _toggleKeepScreenOn,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  
                const SizedBox(height: 20),
                
                // V2.3: 充电动画卡片（独立）
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '⚡ 充电动画',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const Spacer(),
                            _GradientToggle(
                              value: _chargingAnimationEnabled,
                              onChanged: _toggleChargingAnimation,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  
                const SizedBox(height: 20),
                
                // V2.4: 通知功能卡片
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题行
                            Row(
                              children: [
                                const Text(
                                  '📢 背屏通知',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                                const Spacer(),
                                // 三条杠按钮（选择应用）
                                IconButton(
                                  icon: const Icon(Icons.menu, size: 24),
                                  color: Colors.black87,
                                  onPressed: _openAppSelectionPage,
                                  tooltip: '选择应用',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                _GradientToggle(
                                  value: _notificationEnabled,
                                  onChanged: _toggleNotificationService,
                                ),
                              ],
                            ),
                            
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                  
                const SizedBox(height: 20),
                
                // 使用教程 - 可点击跳转到酷安帖子
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            // 跳转到腾讯文档使用教程
                            try {
                              await platform.invokeMethod('openTutorial');
                            } catch (e) {
                              print('打开教程失败: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('打开失败')),
                                );
                              }
                            }
                          },
                          splashColor: Colors.white.withOpacity(0.3),
                          highlightColor: Colors.white.withOpacity(0.2),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                '📖',
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '使用教程',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                  
                const SizedBox(height: 16),
                
                // 底部作者信息 - 可点击跳转到酷安
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            // 跳转到酷安个人主页
                            try {
                              await platform.invokeMethod('openCoolApkProfile');
                            } catch (e) {
                              print('打开酷安主页失败: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('请先安装酷安应用')),
                                );
                              }
                            }
                          },
                          splashColor: Colors.white.withOpacity(0.3),
                          highlightColor: Colors.white.withOpacity(0.2),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                '👨‍💻',
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 6),
                              Image.asset(
                                'assets/kuan.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.person, size: 24, color: Colors.black87);
                                },
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '酷安@AntiOblivionis',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                  
                const SizedBox(height: 16),
                
                // 测试人员信息 - 可点击跳转到酷安
                CustomPaint(
                  painter: _SquircleBorderPainter(
                    radius: _SquircleRadii.large,
                    color: Colors.white.withOpacity(0.5),
                    strokeWidth: 1.5,
                  ),
                  child: ClipPath(
                    clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                        onTap: () async {
                          // 跳转到汐木泽酷安主页
                          try {
                            await platform.invokeMethod('openCoolApkProfileXmz');
                          } catch (e) {
                            print('打开酷安主页失败: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先安装酷安应用')),
                              );
                            }
                          }
                        },
                        splashColor: Colors.white.withOpacity(0.3),
                        highlightColor: Colors.white.withOpacity(0.2),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                '🧪',
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 6),
                              Image.asset(
                                'assets/kuan.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.person, size: 24, color: Colors.black87);
                                },
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '酷安@汐木泽',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                  
                const SizedBox(height: 16),
                
                // 打赏和交流群 - 两列布局
                Row(
                  children: [
                    // 请作者喝咖啡
                    Expanded(
                      child: CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: _SquircleRadii.large,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  // 打开打赏页面
                                  try {
                                    await platform.invokeMethod('openDonationPage');
                                  } catch (e) {
                                    print('打开打赏页面失败: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('打开失败')),
                                      );
                                    }
                                  }
                                },
                                splashColor: Colors.white.withOpacity(0.3),
                                highlightColor: Colors.white.withOpacity(0.2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '☕',
                                        style: TextStyle(fontSize: 24),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '请作者喝咖啡',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // MRSS交流群
                    Expanded(
                      child: CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: _SquircleRadii.large,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  // 打开交流群页面
                                  try {
                                    await platform.invokeMethod('openQQGroup');
                                  } catch (e) {
                                    print('打开交流群页面失败: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('打开失败')),
                                      );
                                    }
                                  }
                                },
                                splashColor: Colors.white.withOpacity(0.3),
                                highlightColor: Colors.white.withOpacity(0.2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '💬',
                                        style: TextStyle(fontSize: 24),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'MRSS交流群',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                  
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  
  // V2.1: 构建旋转按钮（精确超椭圆，统一12px圆角）
  Widget _buildRotationButton(String label, int rotation) {
    bool isSelected = _currentRotation == rotation;
    
    return SizedBox(
      width: 50,
      height: 32,
       child: ClipPath(
         clipper: _SquircleClipper(cornerRadius: _SquircleRadii.small),
        child: Container(
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF9D88),  // 珊瑚橙
                Color(0xFFFFB5C5),  // 粉红
                Color(0xFFE0B5DC),  // 紫色
                Color(0xFFA8C5E5),  // 蓝色
              ],
            ) : null,
            color: isSelected ? null : Colors.white70,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_isLoading || _dpiLoading) ? null : () => _setRotation(rotation),
              child: Center(
                child: Text(
                  label, 
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.black54,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // V2.1: 获取当前旋转方向
  Future<void> _getCurrentRotation() async {
    try {
      final rotation = await platform.invokeMethod('getDisplayRotation', {'displayId': 1});
      if (rotation != null && rotation >= 0) {
        setState(() {
          _currentRotation = rotation;
        });
      }
    } catch (e) {
      print('获取旋转方向失败: $e');
    }
  }
  
  // V2.1: 设置旋转方向
  Future<void> _setRotation(int rotation) async {
    print('[Flutter] 🔄 开始设置旋转: $rotation (${rotation * 90}°)');
    
    if (!_shizukuRunning) {
      print('[Flutter] ❌ Shizuku未运行');
      return;
    }
    if (_isLoading) {
      print('[Flutter] ⚠️ 正在加载中，跳过');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // 确保TaskService连接
      print('[Flutter] 🔗 确保TaskService连接...');
      final connected = await platform.invokeMethod('ensureTaskServiceConnected');
      print('[Flutter] 🔗 TaskService连接状态: $connected');
      await Future.delayed(const Duration(milliseconds: 500));
      
      print('[Flutter] 📡 调用setDisplayRotation: displayId=1, rotation=$rotation');
      final result = await platform.invokeMethod('setDisplayRotation', {
        'displayId': 1,
        'rotation': rotation,
      });
      print('[Flutter] 📡 setDisplayRotation返回: $result');
      
      if (result == true) {
        setState(() => _currentRotation = rotation);
        print('[Flutter] ✅ 旋转成功: ${rotation * 90}°');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已旋转至 ${rotation * 90}°'), duration: const Duration(seconds: 1)),
          );
        }
      } else {
        print('[Flutter] ❌ 旋转失败: result=$result');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('旋转失败')),
          );
        }
      }
    } catch (e) {
      print('[Flutter] ❌ 旋转异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
      print('[Flutter] 🏁 旋转操作结束');
    }
  }
  
}

// 渐变开关，统一四段渐变样式，替代系统绿色Switch
class _GradientToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _GradientToggle({required this.value, required this.onChanged});

  @override
  State<_GradientToggle> createState() => _GradientToggleState();
}

class _GradientToggleState extends State<_GradientToggle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onChanged(!widget.value),
        onHighlightChanged: (h) => setState(() => _pressed = h),
        customBorder: _SquircleShapeBorder(cornerRadius: _SquircleRadii.tiny),
        splashColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.white.withOpacity(0.1),
        child: ClipPath(
          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.tiny),
          child: SizedBox(
            width: 52,
            height: 30,
            child: Stack(
              children: [
                // Base background
                Container(color: Colors.white.withOpacity(0.25)),
                // Gradient overlay with fade
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  opacity: widget.value ? 1.0 : 0.0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF9D88),
                          Color(0xFFFFB5C5),
                          Color(0xFFE0B5DC),
                          Color(0xFFA8C5E5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Knob
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 120),
                      scale: _pressed ? 0.95 : 1.0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 应用列表项优化组件（减少重建）
class _AppListItem extends StatelessWidget {
  final String appName;
  final String packageName;
  final Uint8List? iconBytes;
  final bool isSelected;
  final VoidCallback onToggle;

  const _AppListItem({
    required this.appName,
    required this.packageName,
    required this.iconBytes,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        splashColor: const Color(0x20FFB5C5), // 浅浅的粉红色（四色渐变中间色）
        highlightColor: const Color(0x10E0B5DC), // 浅浅的紫色高光
        radius: 8, // 优化：减少波纹计算
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // 图标优化：使用RepaintBoundary减少重绘
              RepaintBoundary(
                child: iconBytes != null
                    ? Image.memory(
                        iconBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium, // 优化：降低滤镜质量提升性能
                        isAntiAlias: false, // 优化：禁用抗锯齿提升性能
                        cacheWidth: 96, // 优化：缓存缩放后的尺寸
                        cacheHeight: 96,
                      )
                    : const Icon(Icons.android, size: 48, color: Colors.white),
              ),
              const SizedBox(width: 12),
              // 文本优化：使用RepaintBoundary
              Expanded(
                child: RepaintBoundary(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 15,
                          height: 1.2, // 优化：固定行高
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        packageName,
                        style: const TextStyle(
                          fontSize: 11, 
                          color: Colors.white70,
                          height: 1.2, // 优化：固定行高
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 渐变复选框优化：使用RepaintBoundary
              RepaintBoundary(
                child: _GradientCheckbox(value: isSelected, onChanged: (_) => onToggle()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 渐变复选框（替代绿色Checkbox）- 带过渡动画
class _GradientCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GradientCheckbox({required this.value, required this.onChanged});

  @override
  State<_GradientCheckbox> createState() => _GradientCheckboxState();
}

class _GradientCheckboxState extends State<_GradientCheckbox> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _controller.reverse();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _controller.reverse();
      },
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.white.withOpacity(0.25),
            gradient: widget.value ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF9D88),
                Color(0xFFFFB5C5),
                Color(0xFFE0B5DC),
                Color(0xFFA8C5E5),
              ],
            ) : null,
            border: widget.value ? null : Border.all(
              color: Colors.white.withOpacity(0.4),
              width: 2,
            ),
          ),
          child: widget.value 
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// 超椭圆圆角半径
/// 基于屏幕物理圆角半径16.4mm，超椭圆指数n=2.84
/// 使用固定值确保视觉一致性（基于标准DPI 420计算）
class _SquircleRadii {
  // 16.4mm @ 420dpi ≈ 27dp，实际屏幕略大，取32dp
  static const double large = 32.0;  // 大卡片圆角
  static const double small = 12.0;  // 小组件圆角 (large * 0.375)
  static const double tiny = 16.0;   // 开关圆角
  static const double checkbox = 6.0; // 复选框圆角
}

/// 精确的超椭圆（Squircle）形状边框 - 用于InkWell水波纹
/// 使用2.84指数实现与屏幕圆角一致的平滑曲线
class _SquircleShapeBorder extends ShapeBorder {
  final double cornerRadius;
  static const double n = 2.84; // 超椭圆指数
  
  const _SquircleShapeBorder({required this.cornerRadius});
  
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _createSquirclePath(rect.size, cornerRadius);
  }
  
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _createSquirclePath(rect.size, cornerRadius);
  }
  
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  
  @override
  ShapeBorder scale(double t) => _SquircleShapeBorder(cornerRadius: cornerRadius * t);
  
  static Path _createSquirclePath(Size size, double radius) {
    final double width = size.width;
    final double height = size.height;
    final double effectiveRadius = radius.clamp(0.0, math.min(width, height) / 2);
    
    final path = Path();
    
    // 顶部左侧圆角
    path.moveTo(0, effectiveRadius);
    for (double t = 0; t <= 1.0; t += 0.02) {
      final angle = (1 - t) * math.pi / 2;
      final x = effectiveRadius * (1 - math.pow(math.cos(angle).abs(), 2 / n) * (math.cos(angle) >= 0 ? 1 : -1));
      final y = effectiveRadius * (1 - math.pow(math.sin(angle).abs(), 2 / n) * (math.sin(angle) >= 0 ? 1 : -1));
      path.lineTo(x, y);
    }
    
    // 顶边
    path.lineTo(width - effectiveRadius, 0);
    
    // 顶部右侧圆角
    for (double t = 0; t <= 1.0; t += 0.02) {
      final angle = t * math.pi / 2;
      final x = width - effectiveRadius * (1 - math.pow(math.cos(angle).abs(), 2 / n) * (math.cos(angle) >= 0 ? 1 : -1));
      final y = effectiveRadius * (1 - math.pow(math.sin(angle).abs(), 2 / n) * (math.sin(angle) >= 0 ? 1 : -1));
      path.lineTo(x, y);
    }
    
    // 右边
    path.lineTo(width, height - effectiveRadius);
    
    // 底部右侧圆角
    for (double t = 0; t <= 1.0; t += 0.02) {
      final angle = (1 - t) * math.pi / 2 + math.pi / 2;
      final x = width - effectiveRadius * (1 - math.pow(math.cos(angle).abs(), 2 / n) * (math.cos(angle) >= 0 ? 1 : -1));
      final y = height - effectiveRadius * (1 - math.pow(math.sin(angle).abs(), 2 / n) * (math.sin(angle) >= 0 ? 1 : -1));
      path.lineTo(x, y);
    }
    
    // 底边
    path.lineTo(effectiveRadius, height);
    
    // 底部左侧圆角
    for (double t = 0; t <= 1.0; t += 0.02) {
      final angle = t * math.pi / 2 + math.pi;
      final x = effectiveRadius * (1 - math.pow(math.cos(angle).abs(), 2 / n) * (math.cos(angle) >= 0 ? 1 : -1));
      final y = height - effectiveRadius * (1 - math.pow(math.sin(angle).abs(), 2 / n) * (math.sin(angle) >= 0 ? 1 : -1));
      path.lineTo(x, y);
    }
    
    path.close();
    return path;
  }
}

/// 精确的超椭圆（Squircle）裁剪器
/// 使用2.84指数实现与屏幕圆角一致的平滑曲线
class _SquircleClipper extends CustomClipper<Path> {
  final double cornerRadius;
  static const double n = 2.84; // 超椭圆指数
  
  _SquircleClipper({required this.cornerRadius});
  
  @override
  Path getClip(Size size) {
    return _createSquirclePath(size, cornerRadius);
  }
  
  Path _createSquirclePath(Size size, double radius) {
    final w = size.width;
    final h = size.height;
    final r = radius;
    
    final path = Path();
    
    // 从左上角开始，顺时针绘制
    path.moveTo(0, r);
    
    // 左上角超椭圆
    _drawSquircleArc(path, r, r, r, math.pi, math.pi * 1.5);
    
    // 上边
    path.lineTo(w - r, 0);
    
    // 右上角超椭圆
    _drawSquircleArc(path, w - r, r, r, math.pi * 1.5, math.pi * 2);
    
    // 右边
    path.lineTo(w, h - r);
    
    // 右下角超椭圆
    _drawSquircleArc(path, w - r, h - r, r, 0, math.pi * 0.5);
    
    // 下边
    path.lineTo(r, h);
    
    // 左下角超椭圆
    _drawSquircleArc(path, r, h - r, r, math.pi * 0.5, math.pi);
    
    path.close();
    return path;
  }
  
  void _drawSquircleArc(Path path, double cx, double cy, double radius, double startAngle, double endAngle) {
    const int segments = 30;
    
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final angle = startAngle + (endAngle - startAngle) * t;
      
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      
      // 超椭圆公式: r * sgn(t) * |t|^(2/n)
      final x = cx + radius * _sgn(cosA) * math.pow(cosA.abs(), 2.0 / n);
      final y = cy + radius * _sgn(sinA) * math.pow(sinA.abs(), 2.0 / n);
      
      path.lineTo(x, y);
    }
  }
  
  double _sgn(double x) => x < 0 ? -1.0 : 1.0;
  
  @override
  bool shouldReclip(_SquircleClipper oldClipper) => oldClipper.cornerRadius != cornerRadius;
}

/// 精确的超椭圆边框绘制器
/// 用于绘制带边框的超椭圆
class _SquircleBorderPainter extends CustomPainter {
  final double radius;
  final Color color;
  final double strokeWidth;
  static const double n = 2.84; // 超椭圆指数
  
  _SquircleBorderPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    final path = _createSquirclePath(size, radius);
    canvas.drawPath(path, paint);
  }
  
  Path _createSquirclePath(Size size, double r) {
    final w = size.width;
    final h = size.height;
    
    final path = Path();
    path.moveTo(0, r);
    
    // 左上角
    _drawSquircleArc(path, r, r, r, math.pi, math.pi * 1.5);
    path.lineTo(w - r, 0);
    
    // 右上角
    _drawSquircleArc(path, w - r, r, r, math.pi * 1.5, math.pi * 2);
    path.lineTo(w, h - r);
    
    // 右下角
    _drawSquircleArc(path, w - r, h - r, r, 0, math.pi * 0.5);
    path.lineTo(r, h);
    
    // 左下角
    _drawSquircleArc(path, r, h - r, r, math.pi * 0.5, math.pi);
    
    path.close();
    return path;
  }
  
  void _drawSquircleArc(Path path, double cx, double cy, double radius, double startAngle, double endAngle) {
    const int segments = 30;
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final angle = startAngle + (endAngle - startAngle) * t;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final x = cx + radius * _sgn(cosA) * math.pow(cosA.abs(), 2.0 / n);
      final y = cy + radius * _sgn(sinA) * math.pow(sinA.abs(), 2.0 / n);
      path.lineTo(x, y);
    }
  }
  
  double _sgn(double x) => x < 0 ? -1.0 : 1.0;
  
  @override
  bool shouldRepaint(_SquircleBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
           oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth;
  }
}

/// V2.4: 应用选择页面
class AppSelectionPage extends StatefulWidget {
  const AppSelectionPage({Key? key}) : super(key: key);
  
  @override
  State<AppSelectionPage> createState() => _AppSelectionPageState();
}

class _AppSelectionPageState extends State<AppSelectionPage> {
  static const platform = MethodChannel('com.display.switcher/task');  // ✅ 修正channel名称
  
  List<Map<String, dynamic>> _apps = [];
  List<Map<String, dynamic>> _visibleApps = [];
  Set<String> _selectedApps = {};
  bool _isLoading = true;
  bool _privacyMode = false; // 隐私模式
  bool _followDndMode = true; // 跟随系统勿扰模式（默认开启）
  bool _onlyWhenLocked = false; // 仅在锁屏时通知（默认关闭）
  bool _notificationDarkMode = false; // 通知暗夜模式（默认关闭）
  bool _includeSystemApps = false; // 是否显示系统应用
  bool _settingsExpanded = true; // 设置区域是否展开（默认展开）
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadApps();
    _loadPrivacyMode();
    _loadFollowDndMode();
    _loadOnlyWhenLockedMode();
    _loadNotificationDarkMode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 启动权限检查循环（后台异步）
  void _startPermissionCheckLoop() async {
    print('→ 启动权限检查循环');
    int checkAttempts = 0;
    
    while (checkAttempts < 30 && mounted) { // 最多检查30次（30秒）
      await Future.delayed(const Duration(seconds: 1));
      
      if (!mounted) break; // 页面已销毁，退出循环
      
      try {
        final bool granted = await platform.invokeMethod('checkQueryAllPackagesPermission');
        if (granted) {
          print('✓ 权限已授予，自动刷新应用列表');
          
          // 权限已授予，刷新列表
          if (mounted) {
            setState(() {
              _isLoading = true;
            });
            
            await _loadAppsInternal();
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('权限已授予，应用列表已刷新')),
            );
          }
          return; // 成功，退出循环
        }
      } catch (e) {
        print('权限检查失败: $e');
      }
      
      checkAttempts++;
    }
    
    print('⚠ 权限检查超时（30秒），用户可能未授予权限');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在设置中授予权限后手动刷新')),
      );
    }
  }
  
  // 内部加载方法（不检查权限，直接加载）
  Future<void> _loadAppsInternal() async {
    try {
      // 优化1: 先显示加载状态，避免界面卡顿
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      
      // 加载已选择的应用
      final List<dynamic> selectedApps = await platform.invokeMethod('getSelectedNotificationApps');
      _selectedApps = selectedApps.cast<String>().toSet();
      
      // 直接加载应用列表，移除有问题的compute调用
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps', {
        'includeSystemApps': _includeSystemApps
      });
      
      if (mounted) {
        setState(() {
          _apps = apps.map((app) => Map<String, dynamic>.from(app)).toList();
          _isLoading = false;
        });
        
        _applyFilters();
        
        print('已加载 ${_apps.length} 个应用');
      }
    } catch (e) {
      print('加载应用列表失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // 根据系统应用开关重新加载应用列表（局部刷新）
  Future<void> _loadAppsWithSystemFilter() async {
    try {
      // 显示加载指示器，但不重建整个页面
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      
      // 根据开关状态重新获取应用列表
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps', {
        'includeSystemApps': _includeSystemApps
      });
      
      if (mounted) {
        // 只更新应用数据，避免不必要的页面重建
        setState(() {
          _apps = apps.map((app) => Map<String, dynamic>.from(app)).toList();
          _isLoading = false;
        });
        
        // 重新应用过滤器以确保列表正确更新
        _applyFilters();
        
        print('已重新加载 ${_apps.length} 个应用（系统应用开关：$_includeSystemApps）');
      }
    } catch (e) {
      print('重新加载应用列表失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // 静默更新过滤器，避免额外重建
  void _applyFiltersSilently() {
    final String q = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> filtered = _apps.where((app) {
      final String name = (app['appName'] ?? '').toString().toLowerCase();
      final String pkg = (app['packageName'] ?? '').toString().toLowerCase();
      final bool matchesQuery = q.isEmpty || name.contains(q) || pkg.contains(q);
      // 当不显示系统应用时，过滤掉系统应用
      if (!_includeSystemApps && _isSystemApp(app)) {
        return false;
      }
      return matchesQuery;
    }).toList();
    
    // 只更新可见列表，避免全页面重建
    if (mounted) {
      setState(() {
        _visibleApps = filtered;
      });
    }
  }

  void _applyFilters() {
    final String q = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> filtered = _apps.where((app) {
      final String name = (app['appName'] ?? '').toString().toLowerCase();
      final String pkg = (app['packageName'] ?? '').toString().toLowerCase();
      final bool matchesQuery = q.isEmpty || name.contains(q) || pkg.contains(q);
      if (!_includeSystemApps && _isSystemApp(app)) {
        return false;
      }
      return matchesQuery;
    }).toList();
    setState(() {
      _visibleApps = filtered;
    });
  }

  bool _isSystemApp(Map<String, dynamic> app) {
    final pkg = (app['packageName'] ?? '').toString();
    final dynamic isSystemApp = app['isSystemApp'];
    final dynamic isImportantSystemApp = app['isImportantSystemApp'];
    
    // 优先使用Android端传递的系统应用标识
    if (isSystemApp == true && isImportantSystemApp != true) return true;
    
    // 备用检测逻辑
    return pkg.startsWith('com.android.') || pkg.startsWith('com.google.android.') || pkg.startsWith('android');
  }

  Future<void> _selectAllVisible() async {
    setState(() {
      for (final app in _visibleApps) {
        final String pkg = app['packageName'];
        _selectedApps.add(pkg);
      }
    });
    try {
      await platform.invokeMethod('setSelectedNotificationApps', _selectedApps.toList());
    } catch (e) {
      print('批量全选保存失败: $e');
    }
  }

  Future<void> _deselectAllVisible() async {
    setState(() {
      for (final app in _visibleApps) {
        final String pkg = app['packageName'];
        _selectedApps.remove(pkg);
      }
    });
    try {
      await platform.invokeMethod('setSelectedNotificationApps', _selectedApps.toList());
    } catch (e) {
      print('批量全不选保存失败: $e');
    }
  }
  
  Future<void> _loadPrivacyMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _privacyMode = prefs.getBool('notification_privacy_mode') ?? false;
      });
    } catch (e) {
      print('加载隐私模式设置失败: $e');
    }
  }
  
  Future<void> _togglePrivacyMode(bool enabled) async {
    try {
      await platform.invokeMethod('setNotificationPrivacyMode', {'enabled': enabled});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_privacy_mode', enabled);
      setState(() {
        _privacyMode = enabled;
      });
    } catch (e) {
      print('切换隐私模式失败: $e');
    }
  }
  
  Future<void> _loadFollowDndMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _followDndMode = prefs.getBool('notification_follow_dnd_mode') ?? true;
      });
    } catch (e) {
      print('加载勿扰模式设置失败: $e');
    }
  }
  
  Future<void> _toggleFollowDndMode(bool enabled) async {
    try {
      await platform.invokeMethod('setFollowDndMode', {'enabled': enabled});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_follow_dnd_mode', enabled);
      setState(() {
        _followDndMode = enabled;
      });
    } catch (e) {
      print('切换勿扰模式设置失败: $e');
    }
  }
  
  Future<void> _loadOnlyWhenLockedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _onlyWhenLocked = prefs.getBool('notification_only_when_locked') ?? false;
      });
    } catch (e) {
      print('加载锁屏通知设置失败: $e');
    }
  }
  
  Future<void> _loadNotificationDarkMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationDarkMode = prefs.getBool('notification_dark_mode') ?? false;
      });
    } catch (e) {
      print('加载通知暗夜模式设置失败: $e');
    }
  }
  
  Future<void> _toggleNotificationDarkMode(bool enabled) async {
    try {
      await platform.invokeMethod('setNotificationDarkMode', {'enabled': enabled});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_dark_mode', enabled);
      
      setState(() {
        _notificationDarkMode = enabled;
      });
      print('通知暗夜模式已${enabled ? "启用" : "禁用"}');
    } catch (e) {
      print('切换通知暗夜模式失败: $e');
      // 切换失败，恢复原状态
      setState(() {
        _notificationDarkMode = !enabled;
      });
    }
  }
  
  Future<void> _toggleOnlyWhenLocked(bool enabled) async {
    try {
      await platform.invokeMethod('setOnlyWhenLocked', {'enabled': enabled});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_only_when_locked', enabled);
      setState(() {
        _onlyWhenLocked = enabled;
      });
    } catch (e) {
      print('切换锁屏通知设置失败: $e');
    }
  }
  
  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    
    try {
      // ✅ 主动检查QUERY_ALL_PACKAGES权限
      print('🔍 开始检查QUERY_ALL_PACKAGES权限...');
      final bool hasPermission = await platform.invokeMethod('checkQueryAllPackagesPermission');
      print('🔍 权限检查结果: $hasPermission');
      
      if (!hasPermission) {
        print('❌ 没有QUERY_ALL_PACKAGES权限，显示弹窗');
        // 没有权限，弹窗提示并跳转到设置
        setState(() => _isLoading = false);
        
        if (mounted) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('需要权限'),
              content: const Text(
                '为了显示完整的应用列表，需要授予"获取所有应用列表"权限。\n\n'
                '点击"去设置"后，请在应用信息页面向下滚动，找到并授予此权限。'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('去设置'),
                ),
              ],
            ),
          );
          
          if (shouldOpenSettings == true) {
            await platform.invokeMethod('requestQueryAllPackagesPermission');
            
            // 启动后台检查任务（不阻塞UI）
            _startPermissionCheckLoop();
          }
        }
        return;
      }
      
      // ✅ 有权限，继续加载
      await _loadAppsInternal();
    } catch (e) {
      print('加载应用列表失败: $e');
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _toggleApp(String packageName, bool selected) async {
    setState(() {
      if (selected) {
        _selectedApps.add(packageName);
      } else {
        _selectedApps.remove(packageName);
      }
    });
    
    // 保存到后台
    try {
      await platform.invokeMethod('setSelectedNotificationApps', _selectedApps.toList());
    } catch (e) {
      print('保存选择失败: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('选择应用 (${_selectedApps.length})'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF9D88),  // 珊瑚橙
              Color(0xFFFFB5C5),  // 粉红
              Color(0xFFE0B5DC),  // 紫色
              Color(0xFFA8C5E5),  // 蓝色
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 设置区域标题栏（带展开/收起箭头）
                      CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: 32,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _settingsExpanded = !_settingsExpanded;
                                  });
                                },
                                splashColor: Colors.white.withOpacity(0.3),
                                highlightColor: Colors.white.withOpacity(0.2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.settings, size: 20, color: Colors.black54),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '通知设置',
                                        style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                      ),
                                      const Spacer(),
                                      AnimatedRotation(
                                        turns: _settingsExpanded ? 0.25 : 0,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                        child: const Icon(Icons.keyboard_arrow_right, size: 24, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // 可展开/收起的设置卡片区域
                      ClipRect(
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          alignment: _settingsExpanded ? Alignment.topCenter : Alignment.bottomCenter,
                          heightFactor: _settingsExpanded ? 1.0 : 0.0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _settingsExpanded ? 1.0 : 0.0,
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
                            
                            // 隐私模式卡片
                            CustomPaint(
                              painter: _SquircleBorderPainter(
                                radius: 32,
                                color: Colors.white.withOpacity(0.5),
                                strokeWidth: 1.5,
                              ),
                              child: ClipPath(
                                clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.lock_outline, size: 20, color: Colors.black54),
                                        const SizedBox(width: 8),
                                        const Text(
                                          '隐私模式',
                                          style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '(隐藏通知内容)',
                                          style: TextStyle(fontSize: 12, color: Colors.black45),
                                        ),
                                        const Spacer(),
                                        _GradientToggle(
                                          value: _privacyMode,
                                          onChanged: _togglePrivacyMode,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                      
                      // 跟随系统勿扰模式卡片
                      CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: 32,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.do_not_disturb_on_outlined, size: 20, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '跟随系统勿扰模式',
                                    style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                  ),
                                  const Spacer(),
                                  _GradientToggle(
                                    value: _followDndMode,
                                    onChanged: _toggleFollowDndMode,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // 仅在锁屏时通知卡片
                      CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: 32,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_clock, size: 20, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '仅在锁屏时通知',
                                    style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                  ),
                                  const Spacer(),
                                  _GradientToggle(
                                    value: _onlyWhenLocked,
                                    onChanged: _toggleOnlyWhenLocked,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // 通知暗夜模式卡片
                      CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: 32,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.dark_mode, size: 20, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '通知暗夜模式',
                                    style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                                  ),
                                  const Spacer(),
                                  _GradientToggle(
                                    value: _notificationDarkMode,
                                    onChanged: _toggleNotificationDarkMode,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // 筛选与批量操作卡片
                      CustomPaint(
                        painter: _SquircleBorderPainter(
                          radius: 32,
                          color: Colors.white.withOpacity(0.5),
                          strokeWidth: 1.5,
                        ),
                        child: ClipPath(
                          clipper: _SquircleClipper(cornerRadius: _SquircleRadii.large),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    onChanged: (_) => _applyFilters(),
                                    style: const TextStyle(color: Colors.black87),
                                    decoration: const InputDecoration(
                                      hintText: '搜索应用或包名',
                                      hintStyle: TextStyle(color: Colors.black45),
                                      prefixIcon: Icon(Icons.search, color: Colors.black54),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black26),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black26),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(_SquircleRadii.small)),
                                        borderSide: BorderSide(color: Colors.black54, width: 2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      // 全选/全不选
                                      ClipPath(
                                         clipper: _SquircleClipper(cornerRadius: _SquircleRadii.small),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFFF9D88),
                                                Color(0xFFFFB5C5),
                                                Color(0xFFE0B5DC),
                                                Color(0xFFA8C5E5),
                                              ],
                                            ),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: _selectAllVisible,
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                child: Text('全选', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ClipPath(
                                         clipper: _SquircleClipper(cornerRadius: _SquircleRadii.small),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFFF9D88),
                                                Color(0xFFFFB5C5),
                                                Color(0xFFE0B5DC),
                                                Color(0xFFA8C5E5),
                                              ],
                                            ),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: _deselectAllVisible,
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                child: Text('全不选', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      const Text('显示系统应用', style: TextStyle(color: Colors.black87, fontSize: 12)),
                                      const SizedBox(width: 6),
                                      _GradientToggle(
                                        value: _includeSystemApps,
                                        onChanged: (v) async {
                                          // 立即更新UI状态，提供即时反馈
                                          setState(() => _includeSystemApps = v);
                                          // 异步加载应用列表，不阻塞UI
                                          await _loadAppsWithSystemFilter();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 应用列表 - 使用RepaintBoundary隔离重绘
                      Expanded(
                        child: RepaintBoundary(
                          child: ListView.builder(
                            itemCount: _visibleApps.length,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemExtent: 72,
                            cacheExtent: 2000, // 增加缓存范围
                            addAutomaticKeepAlives: false,
                            addRepaintBoundaries: false, // 优化：减少重绘边界
                            addSemanticIndexes: false, // 优化：减少语义索引
                            physics: const BouncingScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            itemBuilder: (context, index) {
                              final app = _visibleApps[index];
                              final String appName = app['appName'];
                              final String packageName = app['packageName'];
                              final Uint8List? iconBytes = app['icon'];
                              final bool isSelected = _selectedApps.contains(packageName);
                              return _AppListItem(
                                appName: appName,
                                packageName: packageName,
                                iconBytes: iconBytes,
                                isSelected: isSelected,
                                onToggle: () => _toggleApp(packageName, !isSelected),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

