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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
              tabs: const [
                Tab(icon: Icon(Icons.tune), text: 'Joints'),
                Tab(icon: Icon(Icons.school), text: 'Teaching'),
                Tab(icon: Icon(Icons.sensors), text: 'Motion'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: const [
              JointControlScreen(),
              TeachingModeScreen(),
              MotionControlScreen(),
            ],
          ),
        );
      },
    );
  }
}
