import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/feature/profile/bloc/profile_bloc.dart';

import '../../chat_inbox/data/outbox/chat_sync_coordinator.dart';
import '../../group/presentation/create_group_screen.dart';
import '../../profile/presentation/profile_edit_screen.dart';
import '../model/conversation.dart';
import 'calls_page.dart';
import 'chat_page.dart';
import 'profile_page.dart';
import 'user_page.dart';
import 'view_model/chat_view_model.dart';
import 'view_model/view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ViewModel viewModel;
  final chatViewModel = ChatViewModel();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    viewModel = ViewModel(context.read<ProfileBloc>());
  }

  @override
  void dispose() {
    chatViewModel.dispose();
    super.dispose();
  }

  void _showNewChatMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.neutralColor.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Start Conversation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.cyanLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: AppColors.cyanDark,
                    ),
                  ),
                  title: const Text(
                    'New Chat',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Start chatting with a contact'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentIndex = 1);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.cyanLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.group_add_rounded,
                      color: AppColors.cyanDark,
                    ),
                  ),
                  title: const Text(
                    'New Group',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Create a new group discussion'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CreateGroupScreen(chatViewModel: chatViewModel),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle() {
    if (_currentIndex == 0) {
      return chatViewModel.conversationsBloc.build(
        builder: (context, state) {
          int totalUnread = 0;
          if (state is SuccessState<List<Conversation>>) {
            totalUnread = state.data.fold(0, (sum, c) => sum + c.unreadCount);
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Inbox',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              if (totalUnread > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '($totalUnread)',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cyanAccent,
                  ),
                ),
              ],
            ],
          );
        },
      );
    } else if (_currentIndex == 1) {
      return const Text(
        'Contacts',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      );
    } else if (_currentIndex == 2) {
      return const Text(
        'Calls',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      );
    } else {
      return const Text(
        'Profile',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      );
    }
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.cyanAccent : AppColors.neutralColor.shade400;

    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: _buildTitle(),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF0F172A),
              size: 24,
            ),
            onPressed: () {
              if (_currentIndex != 0 && _currentIndex != 1) {
                setState(() => _currentIndex = 0);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Color(0xFF0F172A),
              size: 24,
            ),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'group') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CreateGroupScreen(chatViewModel: chatViewModel),
                  ),
                );
              } else if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileEditScreen(),
                  ),
                );
              } else if (value == 'logout') {
                ChatSyncCoordinator.instance.stop();
                ChatSocketService.instance.disconnect();
                AuthSession.clear();
                locator<SessionCubit>().sync(isLoggedIn: false);
                NavigationService.removeALlAndReplace(AuthRoutes.login);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'group',
                child: Row(
                  children: [
                    Icon(Icons.group_add_rounded, size: 20, color: AppColors.cyanDark),
                    SizedBox(width: 10),
                    Text('New Group', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, size: 20, color: AppColors.cyanDark),
                    SizedBox(width: 10),
                    Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatPage(viewModel: chatViewModel),
          UserPage(viewModel: chatViewModel),
          CallsPage(viewModel: chatViewModel),
          ProfilePage(viewModel: viewModel),
        ],
      ),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 1)
          ? FloatingActionButton(
              elevation: 4,
              highlightElevation: 6,
              backgroundColor: AppColors.cyanAccent,
              shape: const CircleBorder(),
              onPressed: _showNewChatMenu,
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: AppColors.neutralColor.shade100,
              width: 1.2,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
                _buildNavItem(1, Icons.people_outline_rounded, Icons.people_rounded, 'Contacts'),
                _buildNavItem(2, Icons.headset_mic_outlined, Icons.headset_mic_rounded, 'Calls'),
                _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
