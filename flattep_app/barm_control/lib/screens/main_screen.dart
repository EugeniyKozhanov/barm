import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/arm_ble_service.dart';
import 'joint_control_screen.dart';
import 'teaching_mode_screen.dart';
import 'motion_control_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late bool _hasMotionSupport;
  late List<Widget> _tabs;
  late List<Widget> _tabViews;

  @override
  void initState() {
    super.initState();
    
    // Check if platform supports motion sensors (Android, iOS, but not Linux, Windows, macOS, Web)
    _hasMotionSupport = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    
    // Build tabs list based on platform
    _tabs = [
      const Tab(icon: Icon(Icons.tune), text: 'Joints'),
      const Tab(icon: Icon(Icons.school), text: 'Teaching'),
      if (_hasMotionSupport) const Tab(icon: Icon(Icons.sensors), text: 'Motion'),
    ];
    
    _tabViews = [
      const JointControlScreen(),
      const TeachingModeScreen(),
      if (_hasMotionSupport) const MotionControlScreen(),
    ];
    
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArmBleService>(
      builder: (context, bleService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('ARM100 Control'),
            actions: [
              // Connection status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    bleService.isConnected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      color: bleService.isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: _tabs,
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: _tabViews,
          ),
        );
      },
    );
  }
}
