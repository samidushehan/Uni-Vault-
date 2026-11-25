import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../widgets/folder_destination_picker.dart';
import 'pdf_reader_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  const FolderDetailScreen({
    required this.controller,
    required this.folder,
    super.key,
  });

  final UnivaultController controller;
  final FolderModel folder;

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  bool _loading = true;
  List<DocumentModel> _documents = [];
  List<FolderModel> _subfolders = [];
  List<FolderModel> _path = [];
  final Map<int, (int documentCount, int subfolderCount)> _folderCounts = {};

  String get _currentFolderName =>
      _path.isEmpty ? widget.folder.name : _path.last.name;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshContent);
    _refreshContent();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshContent);
    super.dispose();
  }

  Future<void> _refreshContent() async {
    try {
      final results = await Future.wait([
        widget.controller.loadDocumentsForFolder(widget.folder.id),
        widget.controller.loadFolders(parentId: widget.folder.id),
        widget.controller.loadFolderPath(widget.folder.id),
      ]);
      final documents = results[0] as List<DocumentModel>;
      final subfolders = results[1] as List<FolderModel>;
      final path = results[2] as List<FolderModel>;
      final counts = <int, (int, int)>{};
      for (final folder in subfolders) {
        counts[folder.id] = await widget.controller.loadFolderCounts(folder.id);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _documents = documents;
        _subfolders = subfolders;
        _path = path;
        _folderCounts
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load this folder: $error')),
      );
    }
  }

  Future<void> _createSubfolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create subfolder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;

    try {
      await widget.controller.createFolder(name, parentId: widget.folder.id);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _importIntoFolder() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final paths = result.map((file) => file.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    try {
      await widget.controller.importPdfFiles(paths, folderId: widget.folder.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDFs imported into folder.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openDocument(DocumentModel document) async {
    await widget.controller.openDocument(document);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfReaderScreen(controller: widget.controller, document: document),
      ),
    );
  }

  Future<void> _renameFolder(FolderModel folder) async {
    final name = await _requestName(
      title: 'Rename folder',
      initialValue: folder.name,
    );
    if (name == null) return;
    try {
      await widget.controller.renameFolder(folder.id, name);
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _moveFolder(FolderModel folder) async {
    final descendants = await widget.controller.loadDescendantFolderIds(
      folder.id,
    );
    if (!mounted) return;
    final destination = await showFolderDestinationPicker(
      context,
      widget.controller,
      title: 'Move "${folder.name}"',
      excludedFolderIds: {...descendants, folder.id},
    );
    if (destination == null || !mounted) return;
    try {
      await widget.controller.moveFolder(folder.id, destination.folderId);
      await _refreshContent();
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _deleteFolder(FolderModel folder) async {
    final confirmed = await _confirmDeleteFolder(folder.name);
    if (confirmed != true) return;
    await widget.controller.deleteFolder(folder.id);
  }

  Future<void> _moveCurrentFolder() async {
    final descendants = await widget.controller.loadDescendantFolderIds(
      widget.folder.id,
    );
    if (!mounted) return;
    final destination = await showFolderDestinationPicker(
      context,
      widget.controller,
      title: 'Move "$_currentFolderName"',
      excludedFolderIds: {...descendants, widget.folder.id},
    );
    if (destination == null || !mounted) return;
    try {
      await widget.controller.moveFolder(
        widget.folder.id,
        destination.folderId,
      );
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _deleteCurrentFolder() async {
    final confirmed = await _confirmDeleteFolder(_currentFolderName);
    if (confirmed != true) return;
    await widget.controller.deleteFolder(widget.folder.id);
    if (mounted) Navigator.pop(context);
  }

  Future<bool?> _confirmDeleteFolder(String name) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'Deleting "$name" will delete this folder and all of its subfolders. '
          'All PDFs in this folder tree will be moved to Root / Unfiled. '
          'The original PDF files will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete folders'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDocument(DocumentModel document) async {
    final name = await _requestName(
      title: 'Rename PDF',
      initialValue: document.name,
    );
    if (name == null) return;
    try {
      await widget.controller.renameDocument(document.id, name);
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _moveDocument(DocumentModel document) async {
    final destination = await showFolderDestinationPicker(
      context,
      widget.controller,
    );
    if (destination == null) return;
    await widget.controller.moveDocument(document.id, destination.folderId);
  }

  Future<String?> _requestName({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDocumentAction(
    String action,
    DocumentModel document,
  ) async {
    switch (action) {
      case 'rename':
        await _renameDocument(document);
      case 'move':
        await _moveDocument(document);
      case 'favorite':
        await widget.controller.toggleFavorite(document);
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete PDF?'),
            content: Text('Delete "${document.name}" from your library?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await widget.controller.deleteDocument(document);
        }
    }
  }

  void _openFolder(FolderModel folder) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/folder/${folder.id}'),
        builder: (_) =>
            FolderDetailScreen(controller: widget.controller, folder: folder),
      ),
    );
  }

  void _navigateToBreadcrumb(FolderModel? folder) {
    if (folder == null) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    final routeName = '/folder/${folder.id}';
    if (Navigator.of(context).canPop()) {
      Navigator.popUntil(
        context,
        (route) => route.settings.name == routeName || route.isFirst,
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFolderName),
        actions: [
          IconButton(
            onPressed: _createSubfolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Create subfolder',
          ),
          IconButton(
            onPressed: _importIntoFolder,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import PDF',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _renameFolder(widget.folder);
                case 'move':
                  _moveCurrentFolder();
                case 'delete':
                  _deleteCurrentFolder();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename folder')),
              PopupMenuItem(value: 'move', child: Text('Move folder')),
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshContent,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBreadcrumb(),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _createSubfolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Create Subfolder'),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Subfolders',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_subfolders.isEmpty)
                    const _FolderEmptyTile(label: 'No subfolders yet.')
                  else
                    ..._subfolders.map(_buildFolderTile),
                  const SizedBox(height: 20),
                  Text(
                    'PDFs',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_documents.isEmpty)
                    const _FolderEmptyTile(label: 'No PDFs in this folder.')
                  else
                    ..._documents.map(_buildDocumentTile),
                ],
              ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _navigateToBreadcrumb(null),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('Root'),
          ),
          for (var index = 0; index < _path.length; index++) ...[
            const Icon(Icons.chevron_right, size: 18),
            TextButton(
              onPressed: index == _path.length - 1
                  ? null
                  : () => _navigateToBreadcrumb(_path[index]),
              child: Text(_path[index].name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderTile(FolderModel folder) {
    final counts = _folderCounts[folder.id] ?? (0, 0);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.folder_rounded),
        ),
        title: Text(folder.name),
        subtitle: Text('${counts.$1} PDFs · ${counts.$2} subfolders'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                _renameFolder(folder);
              case 'move':
                _moveFolder(folder);
              case 'delete':
                _deleteFolder(folder);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'move', child: Text('Move folder')),
            PopupMenuItem(value: 'delete', child: Text('Delete folder')),
          ],
        ),
        onTap: () => _openFolder(folder),
      ),
    );
  }

  Widget _buildDocumentTile(DocumentModel document) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_rounded)),
        title: Text(document.name),
        subtitle: Text(
          'Added ${document.createdAt.toLocal().toString().split(' ').first}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: document.isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: () => widget.controller.toggleFavorite(document),
              icon: Icon(
                document.isFavorite ? Icons.star_rounded : Icons.star_border,
                color: document.isFavorite ? Colors.amber : null,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (action) => _handleDocumentAction(action, document),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'move', child: Text('Move to folder')),
                PopupMenuItem(
                  value: 'favorite',
                  child: Text('Toggle favorite'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        onTap: () => _openDocument(document),
      ),
    );
  }
}

class _FolderEmptyTile extends StatelessWidget {
  const _FolderEmptyTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
