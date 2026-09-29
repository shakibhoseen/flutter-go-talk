import 'package:whatsapp_flutter_go/core/state/simple_bloc_parent.dart';

import '../../../home/model/chat_message.dart';

class ViewModel {
  final messageListBloc = SimpleBlocParent<List<ChatMessage>>();

}