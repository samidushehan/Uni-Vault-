import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../widgets/folder_destination_picker.dart';
import 'folder_detail_screen.dart';
import 'pdf_reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final UnivaultController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  List<DocumentModel> _favorites = [];
  List<DocumentModel> _recent = [];
  List<FolderModel> _folders = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshData);
    _refreshData();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshData);
    super.dispose();
  }

  Future<void> _refreshData() async {
    final favorites = await widget.controller.loadFavoriteDocuments();
    final recent = await widget.controller.loadRecentlyOpenedDocuments();
    final folders = await widget.controller.loadFolders();

    if (!mounted) {
      return;
    }

    setState(() {
      _favorites = favorites;
      _recent = recent;
      _folders = folders;
      _loading = false;
    });
  }

  Future<void> _handleOpenDocument(DocumentModel document) async {
    await widget.controller.openDocument(document);
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfReaderScreen(controller: widget.controller, document: document),
      ),
    );
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Folder name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.controller.createFolder(controller.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder created successfully.')),
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    final selectedPaths = result
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (selectedPaths.isEmpty) {
      return;
    }

    final destination = await _chooseFolderDestination();
    if (destination == null) {
      return;
    }

    try {
      await widget.controller.importPdfFiles(
        selectedPaths,
        folderId: destination.folderId,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF files imported successfully.')),
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<FolderDestination?> _chooseFolderDestination({
    String title = 'Choose destination folder',
    Set<int> excludedFolderIds = const {},
  }) => showFolderDestinationPicker(
    context,
    widget.controller,
    title: title,
    excludedFolderIds: excludedFolderIds,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Home',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your personal PDF library is ready.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _importPdf,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Add PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add Folder'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Frequently Used'),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_favorites.isEmpty)
              const _EmptyState(
                icon: Icons.star_border_rounded,
                label: 'No favorites yet',
              )
            else ...[
              ..._favorites
                  .take(3)
                  .map(
                    (document) => _DocumentTile(
                      document: document,
                      onOpen: () => _handleOpenDocument(document),
                      onToggleFavorite: () async {
                        await widget.controller.toggleFavorite(document);
                      },
                      onRename: () async {
                        final name = await _showRenameDialog(document.name);
                        if (name == null || !mounted) return;
                        await widget.controller.renameDocument(
                          document.id,
                          name,
                        );
                      },
                      onMove: () async {
                        final folder = await _chooseFolderDestination();
                        if (folder == null || !mounted) return;
                        await widget.controller.moveDocument(
                          document.id,
                          folder.folderId,
                        );
                      },
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            _SectionTitle(title: 'Recently Opened'),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_recent.isEmpty)
              const _EmptyState(
                icon: Icons.history_rounded,
                label: 'No recent PDFs',
              )
            else ...[
              ..._recent
                  .take(4)
                  .map(
                    (document) => _DocumentTile(
                      document: document,
                      onOpen: () => _handleOpenDocument(document),
                      onToggleFavorite: () async {
                        await widget.controller.toggleFavorite(document);
                      },
                      onRename: () async {
                        final name = await _showRenameDialog(document.name);
                        if (name == null || !mounted) return;
                        await widget.controller.renameDocument(
                          document.id,
                          name,
                        );
                      },
                      onMove: () async {
                        final folder = await _chooseFolderDestination();
                        if (folder == null || !mounted) return;
                        await widget.controller.moveDocument(
                          document.id,
                          folder.folderId,
                        );
                      },
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            _SectionTitle(title: 'My Folders'),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_folders.isEmpty)
              const _EmptyState(
                icon: Icons.folder_off_rounded,
                label: 'No folders created yet',
              )
            else ...[
              ..._folders.map(
                (folder) => _FolderTile(
                  folder: folder,
                  onOpen: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FolderDetailScreen(
                          controller: widget.controller,
                          folder: folder,
                        ),
                        settings: RouteSettings(name: '/folder/${folder.id}'),
                      ),
                    );
                  },
                  onRename: () async {
                    final name = await _showRenameFolderDialog(folder.name);
                    if (name == null || !mounted) return;
                    try {
                      await widget.controller.renameFolder(folder.id, name);
                    } on FormatException catch (error) {
                      _showMessage(error.message);
                    }
                  },
                  onDelete: () async {
                    final confirmed = await _confirmDeleteFolder(folder.name);
                    if (confirmed != true) return;
                    await widget.controller.deleteFolder(folder.id);
                  },
                  onMove: () => _moveFolder(folder),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _showRenameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename document'),
          content: TextField(controller: controller, autofocus: true),
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
        );
      },
    );
    return result;
  }

  Future<String?> _showRenameFolderDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename folder'),
          content: TextField(controller: controller, autofocus: true),
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
        );
      },
    );
    return result;
  }

  Future<bool?> _confirmDeleteFolder(String folderName) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            'Deleting "$folderName" will delete this folder and all of its subfolders. '
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
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _moveFolder(FolderModel folder) async {
    final descendants = await widget.controller.loadDescendantFolderIds(
      folder.id,
    );
    if (!mounted) return;
    final destination = await _chooseFolderDestination(
      title: 'Move "${folder.name}"',
      excludedFolderIds: {...descendants, folder.id},
    );
    if (destination == null || !mounted) return;

    try {
      await widget.controller.moveFolder(folder.id, destination.folderId);
      await _refreshData();
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onRename,
    required this.onMove,
  });

  final DocumentModel document;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRename;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final date = document.createdAt.toLocal().toString().split(' ').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_rounded)),
        title: Text(document.name),
        subtitle: Text('Added $date'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: document.isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: onToggleFavorite,
              icon: Icon(
                document.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: document.isFavorite ? Colors.amber : null,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    onRename();
                    break;
                  case 'move':
                    onMove();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'move', child: Text('Move to folder')),
              ],
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
  });

  final FolderModel folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.folder_rounded),
        ),
        title: Text(folder.name),
        subtitle: Text(folder.createdAt.toLocal().toString().split(' ').first),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
                break;
              case 'delete':
                onDelete();
                break;
              case 'move':
                onMove();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'move', child: Text('Move folder')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}
