/**
 * @file boot_page.dart
 * @brief 启动/初始化页面：显示解包与内嵌 Python 服务的就绪进度
 * @author CorvusCinereus
 */

import 'package:flutter/material.dart';

import '../internal/design.dart';

class BootPage extends StatelessWidget {
  final double progress;
  final String message;
  final String? detail;
  final String? error;
  final VoidCallback onRetry;

  const BootPage({
    super.key,
    required this.progress,
    required this.message,
    required this.onRetry,
    this.detail,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final hasError = error != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 品牌标识
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: AppColors.brandSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasError
                            ? Icons.error_outline_rounded
                            : Icons.balance_rounded,
                        size: 44,
                        color: hasError ? AppColors.danger : AppColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'ChatLaw',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    hasError ? '初始化未完成' : '正在准备运行环境',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (hasError) ...[
                    // 错误态：不使用不确定进度条（避免无限动画与误导），直接给出原因与重试
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEC),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (detail != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              detail!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            error!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                  ] else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: AppColors.border,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$message  $percent%',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        detail!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '首次启动需解包内嵌 Python 资源，请耐心等待。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
