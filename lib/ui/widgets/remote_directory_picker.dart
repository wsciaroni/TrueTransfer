import 'package:flutter/material.dart';
import '../../services/transfer_controller.dart';

class RemoteDirectoryPicker extends StatefulWidget {
  final String initialPath;
  final ValueChanged<String> onSelected;

  const RemoteDirectoryPicker({
    super.key,
    required this.initialPath,
    required this.onSelected,
  });

  @override
  State<RemoteDirectoryPicker> createState() => _RemoteDirectoryPickerState();
}

class _RemoteDirectoryPickerState extends State<RemoteDirectoryPicker> {
  final _controller = TransferController();
  late String _currentPath;
  List<String> _subdirectories = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath.trim();
    // Normalize path separators to forward slash
    _currentPath = _currentPath.replaceAll('\\', '/');
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dirs = await _controller.listRemoteSubdirectories(_currentPath);
      // Sort alphabetically
      dirs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (mounted) {
        setState(() {
          _subdirectories = dirs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _subdirectories = [];
          _isLoading = false;
          _error = 'Failed to load directory: ${e.toString()}';
        });
      }
    }
  }

  void _navigateInto(String folderName) {
    setState(() {
      if (_currentPath.isEmpty) {
        _currentPath = folderName;
      } else {
        _currentPath = '$_currentPath/$folderName';
      }
    });
    _loadDirectory();
  }

  void _navigateUp() {
    if (_currentPath.isEmpty) return;

    setState(() {
      final parts = _currentPath.split('/');
      parts.removeLast();
      _currentPath = parts.join('/');
    });
    _loadDirectory();
  }

  Future<void> _createNewFolder() async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[950],
          title: const Text('Create New Folder', style: TextStyle(color: Colors.white)),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: textController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Folder Name',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Folder name cannot be empty';
                }
                if (value.contains('/') || value.contains('\\')) {
                  return 'Invalid folder name';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, textController.text.trim());
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final newFolderPath = _currentPath.isEmpty ? name : '$_currentPath/$name';
        await _controller.createRemoteDirectory(newFolderPath);
        _loadDirectory();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create folder: $e'),
              backgroundColor: Colors.red[900],
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[950],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(color: Colors.grey, height: 24, thickness: 0.5),
            _buildPathBar(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.blueAccent),
                    )
                  : _error != null
                      ? _buildErrorState()
                      : _buildDirectoryList(),
            ),
            const Divider(color: Colors.grey, height: 24, thickness: 0.5),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_open_rounded, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 12),
            Text(
              'Select Destination',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined, color: Colors.blueAccent),
          tooltip: 'Create New Folder',
          onPressed: _isLoading ? null : _createNewFolder,
        ),
      ],
    );
  }

  Widget _buildPathBar() {
    final displayPath = _currentPath.isEmpty ? '/' : '/$_currentPath';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[900]!),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            color: _currentPath.isEmpty ? Colors.grey[750] : Colors.blueAccent,
            onPressed: _currentPath.isEmpty || _isLoading ? null : _navigateUp,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Go Up',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayPath,
              style: TextStyle(
                color: Colors.grey[300],
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.blueAccent),
            onPressed: _isLoading ? null : _loadDirectory,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDirectory,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryList() {
    if (_subdirectories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, color: Colors.grey[800], size: 48),
            const SizedBox(height: 12),
            Text(
              'This folder is empty',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _subdirectories.length,
      itemBuilder: (context, index) {
        final folder = _subdirectories[index];
        return InkWell(
          onTap: () => _navigateInto(folder),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    folder,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _isLoading
              ? null
              : () {
                  widget.onSelected(_currentPath);
                  Navigator.pop(context);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'Select This Folder',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
