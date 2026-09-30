import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
import 'package:whatsapp_flutter_go/feature/home/model/conversation.dart';

class GroupInfoScreen extends StatefulWidget {
  final Conversation conversation;

  const GroupInfoScreen({super.key, required this.conversation});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  File? _selectedImage;

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    return '$baseUrl/$path';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
      // TODO: API Connect -> PUT /conversations/{id}/avatar
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Group Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: _selectedImage != null
                        ? FileImage(_selectedImage!)
                        : (widget.conversation.avatarUrl != null
                            ? NetworkImage(_getFullUrl(widget.conversation.avatarUrl))
                            : null) as ImageProvider?,
                    child: _selectedImage == null && widget.conversation.avatarUrl == null
                        ? const Icon(Icons.groups, size: 60, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showImageSourceActionSheet,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Group Title
            Text(
              widget.conversation.displayTitle,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            // Members Section Header
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Members',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      // TODO: API Connect / UI -> Open bottom sheet to pick users and POST /conversations/{id}/members
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add Member'),
                  ),
                ],
              ),
            ),
            // Placeholder for Members List
            // TODO: API Connect -> GET /conversations/{id}/members to fetch and show list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3, // Dummy count
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade300,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text('Member \${index + 1}'),
                  subtitle: Text(index == 0 ? 'Admin' : 'Member'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
