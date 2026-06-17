import 'package:flutter/material.dart';
import '../../services/transfer_controller.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TransferController();

  late TextEditingController _hostController;
  late TextEditingController _shareController;
  late TextEditingController _userController;
  late TextEditingController _passwordController;
  late TextEditingController _domainController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: _controller.host ?? '');
    _shareController = TextEditingController(text: _controller.share ?? '');
    _userController = TextEditingController(text: _controller.username ?? '');
    _passwordController = TextEditingController(text: _controller.password ?? '');
    _domainController = TextEditingController(text: _controller.domain ?? '');
  }

  @override
  void dispose() {
    _hostController.dispose();
    _shareController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  void _handleConnect() async {
    if (_formKey.currentState!.validate()) {
      final success = await _controller.connectSMB(
        host: _hostController.text.trim(),
        share: _shareController.text.trim(),
        user: _userController.text.isEmpty ? null : _userController.text.trim(),
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        domain: _domainController.text.isEmpty ? null : _domainController.text.trim(),
      );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully connected to SMB share!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _handleDisconnect() async {
    await _controller.disconnectSMB();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from SMB share.'),
          backgroundColor: Colors.amber,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildStatusCard(),
                const SizedBox(height: 24),
                _buildFormFields(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SMB Connection',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Configure connection details for your target network storage.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
              ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final bool connected = _controller.isConnected;
    final bool connecting = _controller.isConnecting;
    final String? error = _controller.connectionError;

    Color cardColor = Colors.grey[900]!;
    Color accentColor = Colors.grey;
    String statusTitle = 'Not Connected';
    String statusDesc = 'Enter connection parameters below and click Connect.';
    IconData icon = Icons.cloud_off_rounded;

    if (connecting) {
      cardColor = Colors.blueGrey[900]!;
      accentColor = Colors.blue;
      statusTitle = 'Connecting...';
      statusDesc = 'Establishing SMB session isolates...';
      icon = Icons.sync;
    } else if (connected) {
      cardColor = const Color(0xFF0F2E1E);
      accentColor = Colors.green;
      statusTitle = 'Connected';
      statusDesc = 'Active session established with ${_controller.host}/${_controller.share}';
      icon = Icons.cloud_done_rounded;
    } else if (error != null) {
      cardColor = const Color(0xFF2C1616);
      accentColor = Colors.redAccent;
      statusTitle = 'Connection Failed';
      statusDesc = error;
      icon = Icons.error_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: accentColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusDesc,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    final bool disabled = _controller.isConnecting || _controller.isConnected;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _hostController,
            enabled: !disabled,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Host IP or Name', Icons.dns_rounded),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Host address is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _shareController,
            enabled: !disabled,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Share Name', Icons.folder_shared_rounded),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Share name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _userController,
            enabled: !disabled,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Username (Optional)', Icons.person_rounded),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            enabled: !disabled,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Password (Optional)', Icons.lock_rounded),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _domainController,
            enabled: !disabled,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Domain (Optional)', Icons.domain_rounded),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[400]),
      prefixIcon: Icon(icon, color: Colors.grey[500]),
      filled: true,
      fillColor: Colors.black45,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[800]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[800]!),
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool connected = _controller.isConnected;
    final bool connecting = _controller.isConnecting;

    if (connected) {
      return ElevatedButton.icon(
        onPressed: _handleDisconnect,
        icon: const Icon(Icons.cloud_off_rounded),
        label: const Text('Disconnect Share'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[900],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: connecting ? null : _handleConnect,
      icon: connecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.cloud_done_rounded),
      label: Text(connecting ? 'Connecting...' : 'Connect to Share'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        disabledBackgroundColor: Colors.grey[800],
        disabledForegroundColor: Colors.grey[600],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
