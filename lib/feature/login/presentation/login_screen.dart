import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/navigation/routes/auth_routes.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/core/widgets/custom_action_button.dart';

import '../../../core/helper/utils.dart';
import '../model/login_response.dart';
import 'view_model/view_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

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
    // TODO: implement dispose
    super.dispose();

    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _obsecurePassword.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                focusNode: _emailFocusNode,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                onFieldSubmitted: (valu) {
                  Utils.fieldFocusChanged(
                    context,
                    _emailFocusNode,
                    _passwordFocusNode,
                  );
                },
              ),
              UIHelper.verticalSpace16,
              ValueListenableBuilder(
                valueListenable: _obsecurePassword,
                builder: (context, value, child) {
                  return TextFormField(
                    controller: _passwordController,
                    obscureText: _obsecurePassword.value,
                    focusNode: _passwordFocusNode,

                    obscuringCharacter: "*",
                    decoration: InputDecoration(
                      hintText: 'Password',
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_open_rounded),
                      suffixIcon: InkWell(
                        onTap: () {
                          _obsecurePassword.value = !_obsecurePassword.value;
                        },
                        child: Icon(
                          _obsecurePassword.value
                              ? Icons.visibility_off_outlined
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: height * .085),
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
                },
                child: viewModel.simpleLogin.build(
                  builder: (context, state) {
                    return CustomActionButton(
                      title: 'Login',
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
                            email: _emailController.text.toString(),
                            password: _passwordController.text.toString(),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: height * .02),
              InkWell(
                onTap: () {
                  NavigationService.navigateTo(AuthRoutes.register);
                },
                child: const Text("Don't have an accont? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
