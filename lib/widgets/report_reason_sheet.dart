import 'package:flutter/material.dart';

Future<String?> showReportReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('选择举报原因')),
          for (final entry in const {
            'spam': '垃圾广告、恶意刷屏',
            'porn': '色情低俗、不雅内容',
            'abuse': '人身攻击、辱骂侵权',
            'illegal': '违法违规、诈骗欺凌',
            'other': '其他违反社区规范的行为',
          }.entries)
            ListTile(
              title: Text(entry.value),
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    ),
  );
}
