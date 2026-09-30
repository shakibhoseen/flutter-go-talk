import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

import '../../../core/config/app_flavor_config.dart';
import '../../../core/db/network/network_service_type.dart';
import '../../login/model/login_response.dart';
import 'view_model/view_model.dart';

/// Real data (the same `profileBloc` the app bar title uses, backed by the
/// Go server's `/user/me`) — `hk`'s `ProfilePage`, without the Firebase
/// bio-edit dialog, which nothing here supports yet.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.viewModel});

  final ViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return viewModel.profileBloc.build(
      builder: (context, state) {
        if (state is LoadingState || state is InitialState) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ErrorState) {
          return Center(child: Text(state.message));
        }
        final user = state is SuccessState<User> ? state.data : null;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.primaryColor.shade100,
                backgroundImage: user?.avatarUrl !=null? NetworkImage(_getFullUrl(user?.avatarUrl)): null,
                child: user?.avatarUrl !=null? null:Text(
                  (user?.name?.isNotEmpty ?? false)
                      ? user!.name![0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.name ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(user?.email ?? ''),
            ],
          ),
        );
      },
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
}
