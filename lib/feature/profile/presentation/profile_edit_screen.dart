import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_flutter_go/feature/login/model/login_response.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/feature/profile/bloc/profile_bloc.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final ProfileBloc _profileBloc;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    _profileBloc = context.read<ProfileBloc>();
  }

  Future<void> _updateName(String newName) async {
    try {
      await _profileBloc.updateName(newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update name: $e')));
      }
    }
  }

  Future<void> _updateBio(String newBio) async {
    try {
      await _profileBloc.updateBio(newBio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update about: $e')));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _pickedImage = File(pickedFile.path);
      });
      // TODO: Call your API to upload the image here. Example:
      if(_pickedImage?.path !=null){
        await _profileBloc.uploadProfileImage(_pickedImage!.path);
      }

    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPickerOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                _buildPickerOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                if (_pickedImage != null)
                  _buildPickerOption(
                    icon: Icons.delete,
                    label: 'Remove',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _pickedImage = null;
                      });
                      // TODO: Call API to remove image from backend
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Icon(icon, color: Colors.teal, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return 'https://cdn.pixabay.com/photo/2015/10/05/22/37/blank-profile-picture-973460_1280.png';
    if (path.startsWith("http")) return path;
    final baseUrl = AppFlavorConfig.baseUrlFor(NetworkServiceType.chat);
    
    if (baseUrl.endsWith('/') && path.startsWith('/')) {
      return baseUrl + path.substring(1);
    } else if (!baseUrl.endsWith('/') && !path.startsWith('/')) {
      return '$baseUrl/$path';
    }
    return baseUrl + path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _profileBloc.build(
        builder: (context, state) {
          if (state is LoadingState || state is InitialState) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = state is SuccessState<User> ? state.data : null;

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 30),
                Center(
                  child: GestureDetector(
                    onTap: _showImagePickerOptions,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: _pickedImage != null
                              ? FileImage(_pickedImage!) as ImageProvider
                              : user?.avatarUrl !=null? NetworkImage(_getFullUrl(user?.avatarUrl)): null,
                          child: (_pickedImage == null && user?.name?.isNotEmpty == true && (user?.avatarUrl == null || user!.avatarUrl!.isEmpty))
                              ? Text(
                                  user!.name![0].toUpperCase(),
                                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black54),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                _buildProfileItem(
                  icon: Icons.person,
                  title: 'Name',
                  value: user?.name ?? 'Unknown',
                  isEditable: true,
                  onEdit: () {
                    _showEditDialog('Enter your name', user?.name ?? '', (newValue) {
                      _updateName(newValue);
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 72, right: 20),
                  child: Text(
                    'This is not your username or pin. This name will be visible to your WhatsApp contacts.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(indent: 72),
                _buildProfileItem(
                  icon: Icons.info_outline,
                  title: 'About',
                  value: user?.bio ?? 'Hey there! I am using WhatsApp.',
                  isEditable: true,
                  onEdit: () {
                    _showEditDialog('Add about', user?.bio ?? '', (newValue) {
                      _updateBio(newValue);
                    });
                  },
                ),
                const Divider(indent: 72),
                _buildProfileItem(
                  icon: Icons.phone,
                  title: 'Email',
                  value: user?.email ?? 'Not provided',
                  isEditable: false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required String title,
    required String value,
    bool isEditable = false,
    VoidCallback? onEdit,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade600, size: 28),
      title: Text(
        title,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w500),
      ),
      trailing: isEditable
          ? IconButton(
              icon: Icon(Icons.edit, color: Colors.teal.shade700),
              onPressed: onEdit,
            )
          : null,
    );
  }

  void _showEditDialog(String title, String initialValue, Function(String) onSave) {
    TextEditingController controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
            ),
            TextButton(
              onPressed: () {
                onSave(controller.text);
                Navigator.pop(context);
              },
              child: const Text('Save', style: TextStyle(color: Colors.teal)),
            ),
          ],
        );
      },
    );
  }
}
