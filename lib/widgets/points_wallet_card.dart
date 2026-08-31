import 'package:flutter/material.dart';

/// 兑换商店顶部的积分钱包卡。
/// 视觉按设计稿 luntan_exchange_store_mascot_version.html 还原：
/// 粉金配色、余额金币、樱花点缀与右下角吉祥物立绘。
class PointsWalletCard extends StatelessWidget {
  const PointsWalletCard({
    super.key,
    required this.balance,
    this.balanceLoading = false,
    this.onOpenDetails,
  });

  final int balance;
  final bool balanceLoading;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final rulesStyle = const TextStyle(
      fontSize: 11,
      height: 1.55,
      color: Color(0xFF7C6E76),
    );
    final gainStyle = const TextStyle(
      fontSize: 11,
      height: 1.55,
      color: Color(0xFFDD9A2E),
      fontWeight: FontWeight.w800,
    );
    final detailsLink = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '查看积分明细',
          style: TextStyle(fontSize: 11, color: Color(0xFF8A7080)),
        ),
        const SizedBox(width: 2),
        Text(
          '›',
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A7080)),
        ),
      ],
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFFF7FB), Color(0xFFFFEFD9)],
          stops: [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF4D9E4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E182A3D),
            offset: Offset(0, 8),
            blurRadius: 28,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 104, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.filter_vintage,
                      size: 12,
                      color: Color(0xFFF5AEC8),
                    ),
                    SizedBox(width: 5),
                    Text(
                      '论坛周边兑换',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFA55E77),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const _Coin(size: 25, fontSize: 13),
                    const SizedBox(width: 7),
                    Text(
                      balanceLoading ? '…' : '$balance',
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: Color(0xFFEF5E91),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Text(
                        '积分',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5D4651),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text.rich(
                  TextSpan(
                    style: rulesStyle,
                    children: [
                      const TextSpan(text: '发帖 '),
                      TextSpan(text: '+5', style: gainStyle),
                      const TextSpan(text: ' · 点赞 '),
                      TextSpan(text: '+1', style: gainStyle),
                      const TextSpan(text: ' · 评论 '),
                      TextSpan(text: '+1', style: gainStyle),
                      const TextSpan(text: ' · 每天最多获得 '),
                      TextSpan(text: '20', style: gainStyle),
                      const TextSpan(text: ' 积分'),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  '兑换需人工审核，水贴、水回复产生的积分不计入兑换资格。',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.45,
                    color: Color(0xFF8C6677),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  '提交后管理员会查看发帖与评论，审核未通过会告知原因。',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.45,
                    color: Color(0xFF9A858D),
                  ),
                ),
                const SizedBox(height: 2),
                if (onOpenDetails == null)
                  detailsLink
                else
                  GestureDetector(
                    onTap: onOpenDetails,
                    behavior: HitTestBehavior.translucent,
                    child: detailsLink,
                  ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFF9FC), Color(0xFFFFF0F6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x1FEF5E91)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/store_mascot.webp',
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: -6,
                    top: -6,
                    child: Icon(
                      Icons.filter_vintage,
                      size: 18,
                      color: Color(0xFFFFD9E7),
                    ),
                  ),
                  Positioned(
                    left: -9,
                    bottom: 13,
                    child: Transform.rotate(
                      angle: -0.244,
                      child: const _Coin(size: 22, fontSize: 11),
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
}

class _Coin extends StatelessWidget {
  const _Coin({required this.size, required this.fontSize});

  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD96F), Color(0xFFFFBE46)],
        ),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFEEA22B), width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x4DEEA22B),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Text(
        '\$',
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}
