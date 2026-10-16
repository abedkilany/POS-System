part of 'assistant_chat_page.dart';

/// Local chat history is restored when the user returns to this page.
class AssistantChatPage extends StatefulWidget {
  const AssistantChatPage({super.key, required this.store});

  final ApplicationSession store;

  @override
  State<AssistantChatPage> createState() => _AssistantChatPageState();
}
