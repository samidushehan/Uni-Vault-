import 'package:flutter/material.dart';

import 'controllers/univault_controller.dart';
import 'screens/home_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UniVaultApp());
}

class UniVaultApp extends StatefulWidget {
  const UniVaultApp({super.key});

  @override
  State<UniVaultApp> createState() => _UniVaultAppState();
}

class _UniVaultAppState extends State<UniVaultApp> {
  late final UnivaultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = UnivaultController();
    _controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF163B5E)),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: UniVaultHomeShell(controller: _controller),
    );
  }
}

class UniVaultHomeShell extends StatefulWidget {
  const UniVaultHomeShell({required this.controller, super.key});

  final UnivaultController controller;

  @override
  State<UniVaultHomeShell> createState() => _UniVaultHomeShellState();
}

class _UniVaultHomeShellState extends State<UniVaultHomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(controller: widget.controller),
      LibraryScreen(controller: widget.controller),
      AiAssistantScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.library_books_outlined),
        selectedIcon: Icon(Icons.library_books),
        label: 'Library',
      ),
      const NavigationDestination(
        icon: Icon(Icons.auto_awesome_outlined),
        selectedIcon: Icon(Icons.auto_awesome),
        label: 'AI Assistant',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('UniVault')),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: destinations,
      ),
    );
  }
}
