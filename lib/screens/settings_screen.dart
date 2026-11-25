import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});

  final UnivaultController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _folderCount = 0;
  int _documentCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshStats);
    _refreshStats();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshStats);
    super.dispose();
  }

  Future<void> _refreshStats() async {
    final folders = await widget.controller.countFolders();
    final documents = await widget.controller.countDocuments();

    if (!mounted) {
      return;
    }

    setState(() {
      _folderCount = folders;
      _documentCount = documents;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Library summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _StatRow(label: 'Folders', value: '$_folderCount'),
                  _StatRow(label: 'PDFs', value: '$_documentCount'),
                  _StatRow(label: 'Storage', value: 'Local device storage'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Local storage'),
              subtitle: const Text('Files remain on your Android device.'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.security_rounded),
              title: const Text('Privacy model'),
              subtitle: const Text(
                'No cloud sync or Firebase. Gemini API keys stay on your configured backend.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
