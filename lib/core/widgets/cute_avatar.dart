import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:whatsapp_flutter_go/core/config/app_flavor_config.dart';
import 'package:whatsapp_flutter_go/core/db/network/network_service_type.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';

class CuteAvatar extends StatelessWidget {
  const CuteAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.isOnline = false,
    this.isGroup = false,
    this.size = 48.0,
    this.showOnlineDot = true,
  });

  final String name;
  final String? imageUrl;
  final bool isOnline;
  final bool isGroup;
  final double size;
  final bool showOnlineDot;

  String _getInitials(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final first = parts[0].isNotEmpty ? parts[0][0] : '';
      final second = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$first$second'.toUpperCase();
    }
    if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    }
    return trimmed.toUpperCase();
  }

  String _getFullUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
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
    final pastel = AppColors.getPastelFor(name);
    final initials = _getInitials(name);
    final fullUrl = _getFullUrl(imageUrl);
    final dotSize = size * 0.26;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pastel.bg,
            ),
            alignment: Alignment.center,
            child: fullUrl.isNotEmpty
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: fullUrl,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _buildInitialsOrGroup(pastel, initials),
                    ),
                  )
                : _buildInitialsOrGroup(pastel, initials),
          ),
          if (showOnlineDot && isOnline)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: AppColors.onlineGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.0,
                  ),
                ),
              ),
            ),
          if (isGroup && !isOnline && showOnlineDot)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.cyanAccent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.groups_rounded,
                  size: dotSize * 0.9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInitialsOrGroup(PastelPalette pastel, String initials) {
    if (isGroup && name.trim().isEmpty) {
      return Icon(
        Icons.groups_rounded,
        size: size * 0.5,
        color: pastel.text,
      );
    }
    return Text(
      initials,
      style: TextStyle(
        color: pastel.text,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.36,
        letterSpacing: -0.5,
      ),
    );
  }
}
