import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/cute_avatar.dart';
import 'package:whatsapp_flutter_go/feature/chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'package:whatsapp_flutter_go/feature/profile/presentation/profile_edit_screen.dart';

import '../../login/model/login_response.dart';
import 'view_model/view_model.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.viewModel});

  final ViewModel viewModel;

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(dialogContext);
              ChatSyncCoordinator.instance.stop();
              ChatSocketService.instance.disconnect();
              AuthSession.clear();
              locator<SessionCubit>().sync(isLoggedIn: false);
              NavigationService.removeALlAndReplace(AuthRoutes.login);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return viewModel.profileBloc.build(
      builder: (context, state) {
        if (state is LoadingState || state is InitialState) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.cyanAccent),
          );
        }
        if (state is ErrorState) {
          return Center(child: Text(state.message));
        }
        final user = state is SuccessState<User> ? state.data : null;
        final name = user?.name ?? 'User';
        final email = user?.email ?? '';

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Top Profile Hero Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.neutralColor.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CuteAvatar(
                    name: name,
                    imageUrl: user?.avatarUrl,
                    size: 80,
                    isOnline: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.neutralColor.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileEditScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyanLight,
                      foregroundColor: AppColors.cyanDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text(
                      'Edit Profile',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            // Settings List
            _buildSettingsTile(
              icon: Icons.notifications_none_rounded,
              iconColor: Colors.amber.shade700,
              iconBg: Colors.amber.shade50,
              title: 'Notifications',
              subtitle: 'Message, group & call alerts',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.lock_outline_rounded,
              iconColor: AppColors.cyanDark,
              iconBg: AppColors.cyanLight,
              title: 'Privacy',
              subtitle: 'Block contacts, disappearing messages',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: Colors.purple.shade600,
              iconBg: Colors.purple.shade50,
              title: 'Chats',
              subtitle: 'Theme, wallpapers, chat history',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.help_outline_rounded,
              iconColor: Colors.blue.shade600,
              iconBg: Colors.blue.shade50,
              title: 'Help',
              subtitle: 'Help center, contact us, privacy policy',
              onTap: () {},
            ),

            const SizedBox(height: 12),
            Material(
              color: Colors.red.shade50.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                ),
                title: Text(
                  'Log out',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => _confirmLogout(context),
              ),
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neutralColor.shade100, width: 1),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.neutralColor.shade500,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.neutralColor.shade400,
            size: 20,
          ),
        ),
      ),
    );
  }
}
