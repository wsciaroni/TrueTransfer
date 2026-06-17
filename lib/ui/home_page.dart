import 'package:flutter/material.dart';
import '../services/transfer_controller.dart';
import 'screens/connection_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/transfer_screen.dart';
import 'screens/summary_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final _controller = TransferController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  void _navigateToQueue() {
    setState(() {
      _currentIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const ConnectionScreen(),
      const QueueScreen(),
      const TransferScreen(),
      SummaryScreen(onNewTransfer: _navigateToQueue),
    ];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.grey[950],
            elevation: 0,
            title: Row(
              children: [
                const Icon(
                  Icons.swap_horizontal_circle_rounded,
                  color: Colors.blueAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'TrueTransfer',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _controller.isConnected
                      ? Colors.green[950]?.withValues(alpha: 0.4)
                      : Colors.red[950]?.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _controller.isConnected
                        ? Colors.green[800]!
                        : Colors.red[800]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _controller.isConnected
                            ? Colors.green
                            : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _controller.isConnected ? 'SMB Connected' : 'SMB Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _controller.isConnected
                            ? Colors.green[100]
                            : Colors.red[100],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(index: _currentIndex, children: screens),
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              indicatorColor: Colors.blueAccent.withValues(alpha: 0.15),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  );
                }
                return TextStyle(color: Colors.grey[500], fontSize: 12);
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(
                    color: Colors.blueAccent,
                    size: 26,
                  );
                }
                return IconThemeData(color: Colors.grey[500], size: 24);
              }),
            ),
            child: NavigationBar(
              backgroundColor: Colors.grey[950],
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                // Prevent navigation mid-transfer unless to check active progress screen
                if (_controller.isTransferring && index != 2) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Transfer in progress. Please check the backup status tab.',
                      ),
                      backgroundColor: Colors.blueAccent,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  setState(() {
                    _currentIndex = 2; // Route them to transfer screen
                  });
                  return;
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.cloud_queue_rounded),
                  selectedIcon: Icon(Icons.cloud_done_rounded),
                  label: 'Connection',
                ),
                NavigationDestination(
                  icon: Icon(Icons.format_list_bulleted_rounded),
                  selectedIcon: Icon(Icons.playlist_add_check_rounded),
                  label: 'Queue',
                ),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline_rounded),
                  selectedIcon: Icon(Icons.play_circle_filled_rounded),
                  label: 'Backup',
                ),
                NavigationDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics_rounded),
                  label: 'Summary',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
