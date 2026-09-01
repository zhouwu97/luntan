import 'package:flutter/material.dart';

import '../data/api/store_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'exchange_store_screen.dart';

class PointsCenterScreen extends StatefulWidget {
  const PointsCenterScreen({super.key, this.apiRepository, this.store});

  final StoreRepository? apiRepository;
  final ForumStore? store;

  @override
  State<PointsCenterScreen> createState() => _PointsCenterScreenState();
}

class _PointsCenterScreenState extends State<PointsCenterScreen> {
  late Future<PointsOverview>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.apiRepository?.overview();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.apiRepository;
    if (repository == null) {
      final store = widget.store!;
      return AnimatedBuilder(
        animation: store,
        builder: (context, _) => _content(
          balance: store.points,
          transactions: const <PointTransaction>[],
          onStore: _openStore,
        ),
      );
    }
    return FutureBuilder<PointsOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            appBar: null,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('积分中心')),
            body: Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _future = repository.overview()),
                child: const Text('积分明细加载失败，点击重试'),
              ),
            ),
          );
        }
        final overview = snapshot.data!;
        return _content(
          balance: overview.balance,
          transactions: overview.transactions,
          onStore: _openStore,
        );
      },
    );
  }

  Future<void> _openStore() async {
    if (widget.apiRepository != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ExchangeStoreScreen(apiRepository: widget.apiRepository!),
        ),
      );
      if (mounted) {
        setState(() => _future = widget.apiRepository!.overview());
      }
      return;
    }
    final store = widget.store;
    if (store != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExchangeStoreScreen(store: store),
        ),
      );
    }
  }

  Widget _content({
    required int balance,
    required List<PointTransaction> transactions,
    required VoidCallback onStore,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('积分中心')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Colors.white,
                  size: 38,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '社区积分余额',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$balance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: onStore,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('去兑换'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '积分明细',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: Text(
                  '暂时没有积分流水',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ...transactions.map(_transactionTile),
        ],
      ),
    );
  }

  Widget _transactionTile(PointTransaction transaction) {
    final positive = transaction.delta >= 0;
    final sign = positive ? '+' : '';
    final source = switch (transaction.source) {
      'store' => '兑换商店',
      'post' => '发布帖子',
      'comment' => '参与回复',
      'login' => '每日登录',
      'recommend' => '帖子推荐',
      _ => transaction.source.isEmpty ? '社区行为' : transaction.source,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: (positive ? AppTheme.mint : AppTheme.pink).withValues(
          alpha: .12,
        ),
        child: Icon(
          positive ? Icons.add_rounded : Icons.remove_rounded,
          color: positive ? AppTheme.mint : AppTheme.pink,
        ),
      ),
      title: Text(transaction.reason.isEmpty ? source : transaction.reason),
      subtitle: Text(
        '$source · ${_formatDate(transaction.createdAt)} · 余额 ${transaction.balanceAfter}',
      ),
      trailing: Text(
        '$sign${transaction.delta}',
        style: TextStyle(
          color: positive ? AppTheme.mint : AppTheme.pink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
