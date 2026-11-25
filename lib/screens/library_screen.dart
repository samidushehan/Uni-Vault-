import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';
import '../models/document_model.dart';
import '../models/folder_model.dart';
import '../widgets/folder_destination_picker.dart';
import 'folder_detail_screen.dart';
import 'pdf_reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.controller, super.key});

  final UnivaultController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _loading = true;
  List<FolderModel> _folders = [];
  List<DocumentModel> _rootDocuments = [];
  final Map<int, (int documentCount, int subfolderCount)> _folderCounts = {};

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
    final folders = await widget.controller.loadFolders();
    final documents = await widget.controller.loadRootDocuments();
    final counts = <int, (int, int)>{};
    for (final folder in folders) {
      counts[folder.id] = await widget.controller.loadFolderCounts(folder.id);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _folders = folders;
      _rootDocuments = documents;
      _folderCounts
        ..clear()
        ..addAll(counts);
      _loading = false;
    });
  }

  Future<void> _createFolder() async {
    if (!mounted) {
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<bool>(
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

    if (result != true) {
      return;
    }

    try {
      await widget.controller.createFolder(controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Folder created.')));
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    final paths = result.map((file) => file.path).whereType<String>().toList();
    if (paths.isEmpty) {
      return;
    }

    final destination = await _chooseFolder();
    if (destination == null) return;

    try {
      await widget.controller.importPdfFiles(
        paths,
        folderId: destination.folderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDFs imported successfully.')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<FolderDestination?> _chooseFolder({
    String title = 'Choose destination folder',
    Set<int> excludedFolderIds = const {},
  }) => showFolderDestinationPicker(
    context,
    widget.controller,
    title: title,
    excludedFolderIds: excludedFolderIds,
  );

  Future<void> _renameFolder(FolderModel folder) async {
    final controller = TextEditingController(text: folder.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename folder'),
          content: TextField(controller: controller),
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

    if (value == null) {
      return;
    }

    try {
      await widget.controller.renameFolder(folder.id, value);
      await _refreshData();
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _deleteFolder(FolderModel folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            'Deleting "${folder.name}" will delete this folder and all of its subfolders. '
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

    if (confirmed != true) {
      return;
    }

    await widget.controller.deleteFolder(folder.id);
  }

  Future<void> _moveFolder(FolderModel folder) async {
    final descendants = await widget.controller.loadDescendantFolderIds(
      folder.id,
    );
    if (!mounted) return;
    final destination = await _chooseFolder(
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Library',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Create Folder'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importPdf,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Folders',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_folders.isEmpty)
              const EmptyTile(
                icon: Icons.folder_off_rounded,
                label: 'No folders yet',
              )
            else
              ..._folders.map(
                (folder) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: const Icon(Icons.folder_rounded),
                    ),
                    title: Text(folder.name),
                    subtitle: Text(
                      '${_folderCounts[folder.id]?.$1 ?? 0} PDFs · '
                      '${_folderCounts[folder.id]?.$2 ?? 0} subfolders',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameFolder(folder);
                        } else if (value == 'delete') {
                          _deleteFolder(folder);
                        } else if (value == 'move') {
                          _moveFolder(folder);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'move',
                          child: Text('Move folder'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () {
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
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Root / Unfiled',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rootDocuments.isEmpty)
              const EmptyTile(
                icon: Icons.description_outlined,
                label: 'No PDFs in the root folder yet',
              )
            else
              ..._rootDocuments.map(
                (document) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.picture_as_pdf_rounded),
                    ),
                    title: Text(document.name),
                    subtitle: Text(
                      'Added ${document.createdAt.toLocal().toString().split(' ').first}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'rename') {
                          final name = await _renameDocument(document);
                          if (name != null) {
                            await widget.controller.renameDocument(
                              document.id,
                              name,
                            );
                          }
                        } else if (value == 'favorite') {
                          await widget.controller.toggleFavorite(document);
                        } else if (value == 'move') {
                          final destination = await _chooseFolder();
                          if (destination != null) {
                            await widget.controller.moveDocument(
                              document.id,
                              destination.folderId,
                            );
                          }
                        } else if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete PDF?'),
                              content: Text(
                                'Delete "${document.name}" from your library?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
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
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text('Favorite'),
                        ),
                        PopupMenuItem(
                          value: 'move',
                          child: Text('Move to folder'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () async {
                      await widget.controller.openDocument(document);
                      if (!mounted || !context.mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfReaderScreen(
                            controller: widget.controller,
                            document: document,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _renameDocument(DocumentModel document) async {
    final controller = TextEditingController(text: document.name);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename PDF'),
          content: TextField(controller: controller),
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
  }
}

class EmptyTile extends StatelessWidget {
  const EmptyTile({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [Icon(icon), const SizedBox(width: 10), Text(label)],
      ),
    );
  }
}
