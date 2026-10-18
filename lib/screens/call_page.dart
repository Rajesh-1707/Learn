
import 'package:flutter/material.dart';


class CallPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String callId;
  final String? topicId;
  final String? topicTitle;

  const CallPage({
    super.key,
    required this.callId,
    this.topicId,
    this.topicTitle,
    this.profile,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}
