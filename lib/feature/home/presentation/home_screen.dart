import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whatsapp_flutter_go/feature/profile/bloc/profile_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:whatsapp_flutter_go/core/db/network/socket/chat_socket_service.dart';
import 'package:whatsapp_flutter_go/core/di/di.dart';
import 'package:whatsapp_flutter_go/core/extension/context_extension.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/session/auth_session.dart';
import 'package:whatsapp_flutter_go/core/session/session_cubit.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';

import '../../login/model/login_response.dart';
import '../../chat_inbox/data/outbox/chat_sync_coordinator.dart';
import 'chat_page.dart';
import 'profile_page.dart';
import '../../profile/presentation/profile_edit_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 1,
      child: Scaffold(

        appBar: AppBar(
           backgroundColor: Colors.lime.shade50,
          automaticallyImplyLeading: false,
          /* leading: Consumer<HomeViewModel>(
            builder:
                (BuildContext context, HomeViewModel viewModel, Widget? child) {
              return Center(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child:
                  Utils.profileImage(viewModel.currentUserModel?.imageUrl),
                ),
              );
            },
          ),*/
          title: viewModel.profileBloc.build(
            builder: (BuildContext context, state) {
              String name = "b";
              if (state is SuccessState<User>) {
                name = state.data.name ?? "";
              }
              return Row(
                children: [
                  Text(
                    name,
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  UIHelper.horizontalSpace(6),
                  const FaIcon(FontAwesomeIcons.whatsapp),
                ],
              );
            },
          ),
          actions: [
            PopupMenuButton(
              color: Colors.amber,
              itemBuilder: (context) {
                return [
                  PopupMenuItem(
                    onTap: () {
                      ChatSyncCoordinator.instance.stop();
                      ChatSocketService.instance.disconnect();
                      AuthSession.clear();
                      locator<SessionCubit>().sync(isLoggedIn: false);
                      NavigationService.removeALlAndReplace(AuthRoutes.login);
                    },
                    child: const Text('Logout'),
                  ),
                  PopupMenuItem(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileEditScreen(),
                        ),
                      );
                    },
                    child: const Text('Profile'),
                  ),
                  const PopupMenuItem(child: Text('Setting')),
                  const PopupMenuItem(child: Text('Privacy')),
                ];
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            indicatorWeight: 4,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.tealAccent,
            labelStyle: context.textTheme.titleLarge?.copyWith(
              color: Colors.white,
            ),
            tabs: [
              const SizedBox(
                width: 25,
                child: Tab(icon: Icon(Icons.camera_alt_outlined)),
              ),
              SizedBox(
                width: 80,
                child: Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Chat', style: GoogleFonts.firaSans(fontSize: 16)),
                    /*  Consumer<ChatUserViewModel>(
                        builder:
                            (
                              BuildContext context,
                              ChatUserViewModel value,
                              Widget? child,
                            ) {
                              final int count = value.actualNotificationCount();
                              if (count == 0) return Container();
                              return Row(
                                children: [
                                  addHoriztalSpace(7),
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.green,
                                    ),
                                    child: Text(
                                      '$count',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                  ),
                                ],
                              );
                            },
                      ),*/
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 85, child: Tab(text: 'Users')),
              const SizedBox(width: 85, child: Tab(text: 'Profile')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            page(),
            ChatPage(viewModel: chatViewModel),
            UserPage(viewModel: chatViewModel),
            ProfilePage(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}

Widget page() {
  return const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Center(
        child: SizedBox(
          height: 100,
          width: 100,
          child: Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 100),
        ),
      ),
    ],
  );
}
