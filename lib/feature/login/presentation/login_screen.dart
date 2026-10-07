import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/core/theme/app_colors.dart';
import 'package:whatsapp_flutter_go/core/widgets/custom_action_button.dart';

import '../../../core/helper/utils.dart';
import '../model/login_response.dart';
import 'view_model/view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _obsecurePassword = ValueNotifier<bool>(true);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  final viewModel = ViewModel();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _obsecurePassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cute Logo & Branding
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.cyanAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyanAccent.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome Back!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue chatting with your friends',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.neutralColor.shade500,
                  ),
                ),
                const SizedBox(height: 36),

                // Form Container
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.neutralColor.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Email Field
                      Text(
                        'Email',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.neutralColor.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        focusNode: _emailFocusNode,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Enter your email',
                          hintStyle: TextStyle(color: AppColors.neutralColor.shade400, fontSize: 14),
                          prefixIcon: Icon(Icons.alternate_email_rounded, color: AppColors.neutralColor.shade400, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.neutralColor.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.neutralColor.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.cyanAccent, width: 1.8),
                          ),
                        ),
                        onFieldSubmitted: (val) {
                          Utils.fieldFocusChanged(
                            context,
                            _emailFocusNode,
                            _passwordFocusNode,
                          );
                        },
                      ),
                      const SizedBox(height: 18),

                      // Password Field
                      Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.neutralColor.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: _obsecurePassword,
                        builder: (context, isObscure, child) {
                          return TextFormField(
                            controller: _passwordController,
                            obscureText: isObscure,
                            focusNode: _passwordFocusNode,
                            obscuringCharacter: "•",
                            style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: 'Enter your password',
                              hintStyle: TextStyle(color: AppColors.neutralColor.shade400, fontSize: 14),
                              prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.neutralColor.shade400, size: 20),
                              suffixIcon: IconButton(
                                splashRadius: 20,
                                icon: Icon(
                                  isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AppColors.neutralColor.shade400,
                                  size: 20,
                                ),
                                onPressed: () {
                                  _obsecurePassword.value = !_obsecurePassword.value;
                                },
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: AppColors.neutralColor.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: AppColors.neutralColor.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.cyanAccent, width: 1.8),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Action Button
                      BlocListener<SimpleBlocParent<LoginResponse>, CommonState>(
                        bloc: viewModel.simpleLogin,
                        listener: (context, state) {
                          if (state is ErrorState) {
                            Utils.showFlashBarMessage(
                              state.message,
                              FlasType.error,
                              context,
                            );
                          }
                          log('listener login: $state');
                        },
                        child: viewModel.simpleLogin.build(
                          builder: (context, state) {
                            return CustomActionButton(
                              title: 'Login',
                              borderRadius: 14,
                              backgroundColor: AppColors.cyanAccent,
                              fontSize: 16,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              loading: viewModel.simpleLogin.isLoading,
                              onTap: () {
                                if (_emailController.text.isEmpty) {
                                  Utils.showFlashBarMessage(
                                    'Please enter email',
                                    FlasType.error,
                                    context,
                                  );
                                } else if (_passwordController.text.isEmpty) {
                                  Utils.showFlashBarMessage(
                                    'Please enter password',
                                    FlasType.error,
                                    context,
                                  );
                                } else if (_passwordController.text.length < 6) {
                                  Utils.showFlashBarMessage(
                                    'Please enter 6 digit password',
                                    FlasType.error,
                                    context,
                                  );
                                } else {
                                  viewModel.login(
                                    email: _emailController.text.trim(),
                                    password: _passwordController.text.trim(),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Register Link
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      NavigationService.navigateTo(AuthRoutes.register);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.neutralColor.shade600,
                          ),
                          children: const [
                            TextSpan(text: "Don't have an account? "),
                            TextSpan(
                              text: 'Sign Up',
                              style: TextStyle(
                                color: AppColors.cyanAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
