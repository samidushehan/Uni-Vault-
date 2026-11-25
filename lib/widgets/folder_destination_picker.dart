import 'package:flutter/material.dart';

import '../controllers/univault_controller.dart';
import '../models/folder_model.dart';

class FolderDestination {
  const FolderDestination(this.folderId);

  final int? folderId;
}

Future<FolderDestination?> showFolderDestinationPicker(
  BuildContext context,
  UnivaultController controller, {
  String title = 'Choose destination folder',
  Set<int> excludedFolderIds = const {},
}) async {
  final folders = await controller.loadAllFolders();
  if (!context.mounted) {
    return null;
  }
  final children = <int?, List<FolderModel>>{};
  for (final folder in folders) {
    children.putIfAbsent(folder.parentId, () => []).add(folder);
  }
  final path = <FolderModel>[];

  return showDialog<FolderDestination>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final currentParentId = path.isEmpty ? null : path.last.id;
        final currentFolders =
            (children[currentParentId] ?? const <FolderModel>[])
                .where((folder) => !excludedFolderIds.contains(folder.id))
                .toList();

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: path.isEmpty
                          ? null
                          : () => setDialogState(path.clear),
                      child: const Text('Root'),
                    ),
                    for (var index = 0; index < path.length; index++)
                      TextButton(
                        onPressed: index == path.length - 1
                            ? null
                            : () => setDialogState(
                                () => path.removeRange(index + 1, path.length),
                              ),
                        child: Text(path[index].name),
                      ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: currentFolders.isEmpty
                      ? Center(
                          child: Text(
                            path.isEmpty
                                ? 'No folders yet.'
                                : 'No subfolders here.',
                          ),
                        )
                      : ListView(
                          children: currentFolders
                              .map(
                                (folder) => ListTile(
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(folder.name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () =>
                                      setDialogState(() => path.add(folder)),
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const FolderDestination(null)),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Move to Root / Unfiled'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    FolderDestination(currentParentId),
                  ),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(
                    path.isEmpty
                        ? 'Select Root / Unfiled'
                        : 'Select ${path.last.name}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}
