import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String userName;

  const ChatScreen({super.key, required this.userName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // 1. We add a Controller to get the text from the field
  final TextEditingController _messageController = TextEditingController();
  
  // 2. We turn the static bubbles into a Dynamic List
  final List<Map<String, dynamic>> _messages = [
    {"text": "Hi! I've accepted your request. I'll be there in 10 mins.", "isMe": false},
    {"text": "Great, thank you so much! I'll be waiting at the main entrance.", "isMe": true},
    {"text": "Perfect, see you soon!", "isMe": false},
  ];

  // 3. The logic to actually send the message
  void _handleSend() {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _messages.add({
        "text": _messageController.text,
        "isMe": true,
      });
      _messageController.clear(); // Clears the input field after sending
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              radius: 15, 
              backgroundColor: Color(0xFF2167FF), 
              child: Icon(Icons.person, size: 18, color: Colors.white)
            ),
            const SizedBox(width: 10),
            Text(widget.userName, style: const TextStyle(color: Colors.black, fontSize: 18)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // 1. DYNAMIC CHAT MESSAGES AREA
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildChatBubble(
                  _messages[index]["text"], 
                  _messages[index]["isMe"]
                );
              },
            ),
          ),

          // 2. MESSAGE INPUT FIELD
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white, 
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(5), 
                  blurRadius: 10, 
                  offset: const Offset(0, -5)
                )
              ]
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController, // Connected controller
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25), 
                          borderSide: BorderSide.none
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onSubmitted: (_) => _handleSend(), // Send when "Enter" is pressed
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _handleSend, // Click to send
                    child: const CircleAvatar(
                      backgroundColor: Color(0xFF2167FF),
                      child: Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2167FF) : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isMe ? 15 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 15),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 15),
        ),
      ),
    );
  }
}