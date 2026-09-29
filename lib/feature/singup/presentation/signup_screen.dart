import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:whatsapp_flutter_go/core/helper/my_ui_import.dart';
import 'package:whatsapp_flutter_go/core/navigation/navigation_service.dart';
import 'package:whatsapp_flutter_go/core/state/common_base_bloc.dart';
import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';
import 'package:whatsapp_flutter_go/core/widgets/custom_action_button.dart';

import '../../../core/helper/utils.dart';
import '../../login/model/login_response.dart';
import 'view_model/view_model.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _obsecurePassword = ValueNotifier<bool>(true);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  final _userFocusNode = FocusNode();

  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  final viewModel = ViewModel();

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();

    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _userFocusNode.dispose();

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
                controller: _usernameController,
                keyboardType: TextInputType.name,
                focusNode: _userFocusNode,
                decoration: const InputDecoration(
                  hintText: 'User Name',
                  labelText: 'User Name',
                  prefixIcon: FaIcon(FontAwesomeIcons.user),
                ),
                onFieldSubmitted: (value) {
                  Utils.fieldFocusChanged(
                    context,
                    _userFocusNode,
                    _emailFocusNode,
                  );
                },
              ),

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
              BlocListener<SimpleBlocParent<User>, CommonState>(
                bloc: viewModel.simpleLogin,
                listener: (context, state) {
                  if (state is ErrorState) {
                    Utils.showFlashBarMessage(
                      state.message,
                      FlasType.error,
                      context,
                    );
                  } else if (state is SuccessState<User>) {
                    Utils.showFlashBarMessage(
                      'Account created — please log in',
                      FlasType.success,
                      context,
                    );
                    NavigationService.goBack();
                  }
                },
                child: viewModel.simpleLogin.build(
                  builder: (context, state) {
                    return CustomActionButton(
                      title: 'Login',
                      loading: viewModel.simpleLogin.isLoading,
                      onTap: () {
                        if (_usernameController.text.isEmpty) {
                          Utils.showFlashBarMessage(
                            'Please enter email',
                            FlasType.error,
                            context,
                          );
                        } else if (_emailController.text.isEmpty) {
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
                          viewModel.signUp(
                            name: _usernameController.text.toString(),
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
                  NavigationService.goBack();
                },
                child: const Text("Already  have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
