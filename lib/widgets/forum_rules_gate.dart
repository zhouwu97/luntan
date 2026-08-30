import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// 圣杯酱立绘 + 版规弹窗的本地配色；弹窗整体走粉色系，与应用蓝色主题区分。
class _RulesPalette {
  static const strong = Color(0xFFFF5C8A);
  static const soft = Color(0xFFFF90B4);
  static const gradient = LinearGradient(
    colors: [strong, soft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const panelBase = Color(0xFFFFDCE8);
  static const separator = Color(0xFFF6E2EA);
}

/// 版规弹窗的展示与持久化控制器。
///
/// 生产入口通过 [ForumRulesGateController.withPreferences] 开启弹窗并用
/// SharedPreferences 记住"已同意"；测试注入 [ForumRulesGateController.disabled]
/// 跳过弹窗，避免遮挡页面交互。
class ForumRulesGateController {
  ForumRulesGateController.withPreferences() : enabled = true;

  ForumRulesGateController.disabled() : enabled = false;

  final bool enabled;
  bool _agreed = false;

  bool get shouldShow => enabled && !_agreed;

  static const storageKey = 'luntan.rules.agreed.v1';

  Future<void> restore() async {
    if (!enabled) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _agreed = preferences.getBool(storageKey) ?? false;
    } catch (_) {
      // 读取失败按未同意处理，保证版规一定会展示一次。
      _agreed = false;
    }
  }

  Future<void> agree() async {
    _agreed = true;
    if (!enabled) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(storageKey, true);
    } catch (_) {
      // 持久化失败只影响下次启动是否再次弹出，本次选择依然生效。
    }
  }
}

/// 进入论坛时的版规公告栏弹窗。
///
/// 覆盖全屏且不可点击穿透；超过两行的版规默认折叠，点"展开/收起"查看全文。
/// 底部提供未满 18 拒绝入口与同意按钮，同意后回调 [onAgree]。
class ForumRulesGate extends StatefulWidget {
  const ForumRulesGate({super.key, required this.onAgree});

  final VoidCallback onAgree;

  @override
  State<ForumRulesGate> createState() => _ForumRulesGateState();
}

class _ForumRulesGateState extends State<ForumRulesGate> {
  static const _intro =
      '欢迎各位杂鱼哥哥来到圣杯酱论坛，这是一个公告栏～请各位杂鱼哥哥认真阅读并遵守版规，'
      '为避免不必要的麻烦，保持论坛内良好风气，我们决定设立以下版规，请仔细阅读!';
  static const _rules = [
    '1.本论坛不得出现漏点涩图!并不欢迎对论坛稳定有影响的任何风险行为!大家虽然都不是什么正经人，但是还是要稍微矜持一点点♡~',
    '2.论坛内不得上传压缩包，apk, exe等文件~敬请谅解~',
    '3.我们欢迎各位分享自己使用的感受，以及对杯子的见解和推荐，但我们不欢迎各位引战，踩一捧一',
    '4.鼓励寻求帮助，但不得骚扰别人哦',
    '5.文明交流，不要吵架~吵起来一起塞口球，享受来自管理员的小黑屋',
    '6.不得出售二手商品！各位杂鱼哥哥……您如果有魏武遗风这种奇奇怪怪的癖好……请换个地方……？被骗概不负责',
    '7.这里是大人们讨论交流♂的地方哦♡~如果发现小孩子，我们免费提供封号♡~~~小孩子请好好学习，不要来玩大人才可以玩♂的玩具哦？',
    '8.圣杯酱论坛只做玩具交流玩法分享等，不允许发布任何裸露的生殖器官，以及色情暴力、漏点图片或色情资源在本站转载、不允许发布未成年人色情,尤其涉及到14以下的动漫图、真人图片或者文字描述暗示等！违者将封禁用户ip，不允许再阅览本站！ （注：zz类的，也违反版规！同样拒绝发布~发布者也会封禁ip）',
  ];
  static const _footer =
      '管理层人员拥有对版规的最终解释权，如果对于处罚不满，可以寻求其他管理和论坛主的帮助，'
      '我们欢迎大家为建设论坛提出更多良好的意见';

  bool _declined = false;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        // 空点击也由遮罩吸收，未做出选择前无法点到背后的论坛界面。
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        MediaQuery.sizeOf(context).height * 0.88,
                        720,
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusLarge,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x335A9EFF),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 手机定宽立绘栏；大屏按比例但封顶，栏一旦过宽
                        // cover 会转为纵向裁切、切掉头顶和靴底。
                        final compact = constraints.maxWidth < 520;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: compact
                                  ? 120
                                  : math.min(
                                      constraints.maxWidth * 0.32,
                                      250,
                                    ),
                              child: _CharacterArt(compact: compact),
                            ),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: AppMotion.normal,
                                child: _declined
                                    ? _DeclinePanel(
                                        key: const ValueKey('declined'),
                                        onBack: () =>
                                            setState(() => _declined = false),
                                        onExit: _exitApp,
                                      )
                                    : _buildRulesPanel(
                                        key: const ValueKey('rules'),
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRulesPanel({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '❀ 公告栏',
            style: TextStyle(
              color: _RulesPalette.strong,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _RulesPalette.separator),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    _intro,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final rule in _rules) _RuleTile(rule: rule),
                  const SizedBox(height: 4),
                  const Text(
                    _footer,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _GateButton(
            label: '不同意喵，未满18',
            color: const Color(0xFFF2F3F5),
            foreground: AppTheme.textSecondary,
            height: 44,
            onTap: () => setState(() => _declined = true),
          ),
          const SizedBox(height: 10),
          _GateButton(
            label: '同意版规，已满18',
            gradient: _RulesPalette.gradient,
            foreground: Colors.white,
            height: 48,
            onTap: widget.onAgree,
          ),
        ],
      ),
    );
  }

  Future<void> _exitApp() async {
    if (kIsWeb) return;
    await SystemNavigator.pop();
  }
}

/// 左侧圣杯酱立绘栏。
///
/// 手机窄栏用预裁的 rail 版（只裁背景与外围发丝），cover 横向溢出极小；
/// 大屏栏变宽后若沿用窄图，cover 会转为纵向裁切、切掉头顶与靴底，
/// 因此换成接近原图比例的 full 版。底色仅在图片解码前兜底防闪白，
/// 右缘淡白渐变让粉色图区与白色正文自然过渡。
class _CharacterArt extends StatelessWidget {
  const _CharacterArt({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _RulesPalette.panelBase,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            compact
                ? 'assets/images/shengbei_rules_rail.webp'
                : 'assets/images/shengbei_rules_full.webp',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.20),
                  ],
                ),
              ),
            ),
          ),
          // 窄栏塞字会挤，品牌署名只在大屏展示。
          if (!compact)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Column(
                children: [
                  Text(
                    '圣杯酱',
                    style: TextStyle(
                      color: Color(0xFFD75D87),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'FORUM RULES',
                    style: TextStyle(
                      color: Color(0x99D75D87),
                      fontSize: 8,
                      letterSpacing: 1.7,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条版规：超过两行放不下时折叠成摘要，点"展开/收起"或整行切换；
/// 能完整展示的条文不显示展开选项。
///
/// 是否被截断用真实排版结果判定（[RenderParagraph.didExceedMaxLines]），
/// 与屏幕上实际渲染用的字体、系统字号缩放完全一致；预估值会因字体
/// 度量差异和真实换行对不上，导致截断了却不显示"展开"。
class _RuleTile extends StatefulWidget {
  const _RuleTile({required this.rule});

  final String rule;

  @override
  State<_RuleTile> createState() => _RuleTileState();
}

class _RuleTileState extends State<_RuleTile> {
  static const _style = TextStyle(
    color: AppTheme.textPrimary,
    fontSize: 13.5,
    height: 1.65,
  );

  final _textKey = GlobalKey();
  bool _expanded = false;
  bool _overflows = false;

  @override
  Widget build(BuildContext context) {
    // 帧结束后按真实排版结果修正"是否需要折叠"；展开状态下跳过，
    // 避免收起瞬间误判成放得下而闪没"展开/收起"标签。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _expanded) return;
      final renderObject = _textKey.currentContext?.findRenderObject();
      final overflowed =
          renderObject is RenderParagraph && renderObject.didExceedMaxLines;
      if (_overflows != overflowed) setState(() => _overflows = overflowed);
    });
    final collapsible = _overflows || _expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: collapsible
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              AnimatedSize(
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                alignment: Alignment.topCenter,
                child: Text(
                  widget.rule,
                  key: _textKey,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                  style: _style,
                ),
              ),
              if (collapsible)
                Text(
                  _expanded ? '收起' : '展开',
                  style: const TextStyle(
                    color: _RulesPalette.strong,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const Divider(height: 1, color: _RulesPalette.separator),
      ],
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({
    required this.label,
    this.color,
    this.gradient,
    required this.foreground,
    required this.height,
    required this.onTap,
  });

  final String label;
  final Color? color;
  final Gradient? gradient;
  final Color foreground;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: height,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(height / 2.6),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height / 2.6),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 未满 18 选择"不同意"后的拒绝页；保留返回入口避免误点后被困住。
class _DeclinePanel extends StatelessWidget {
  const _DeclinePanel({
    super.key,
    required this.onBack,
    required this.onExit,
  });

  final VoidCallback onBack;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.sentiment_very_dissatisfied_rounded,
            size: 46,
            color: _RulesPalette.strong,
          ),
          const SizedBox(height: 14),
          const Text(
            '呜喵……未满18不可以进入圣杯酱论坛哦',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kIsWeb ? '请关闭本页面，欢迎成年后再来~' : '也可以退出应用，欢迎成年后再来~',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _GateButton(
            label: '返回重新确认',
            color: const Color(0xFFF2F3F5),
            foreground: AppTheme.textSecondary,
            height: 44,
            onTap: onBack,
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 10),
            _GateButton(
              label: '退出应用',
              gradient: _RulesPalette.gradient,
              foreground: Colors.white,
              height: 44,
              onTap: onExit,
            ),
          ],
        ],
      ),
    );
  }
}
