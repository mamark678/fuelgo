import 'package:flutter/material.dart';

class PriceReductionWidget extends StatelessWidget {
  final double reductionAmount;
  final String fuelType;
  final double originalPrice;
  final VoidCallback? onTap;

  const PriceReductionWidget({
    Key? key,
    required this.reductionAmount,
    required this.fuelType,
    required this.originalPrice,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (reductionAmount <= 0) {
      return const SizedBox.shrink();
    }

    final reducedPrice = originalPrice - reductionAmount;
    final reductionPercentage = (reductionAmount / originalPrice) * 100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer,
              size: 16,
              color: Colors.green[700],
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₱${reductionAmount.toStringAsFixed(2)} OFF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                Text(
                  '₱${reducedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green[600],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PriceWithReductionWidget extends StatelessWidget {
  final double originalPrice;
  final double reductionAmount;
  final String fuelType;
  final VoidCallback? onTap;

  const PriceWithReductionWidget({
    Key? key,
    required this.originalPrice,
    required this.reductionAmount,
    required this.fuelType,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final reducedPrice = originalPrice - reductionAmount;
    final hasReduction = reductionAmount > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_gas_station,
              size: 18,
              color: Colors.blueGrey,
            ),
            const SizedBox(width: 8),
            Text(
              fuelType,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        Row(
          children: [
            if (hasReduction) ...[
              PriceReductionWidget(
                reductionAmount: reductionAmount,
                fuelType: fuelType,
                originalPrice: originalPrice,
                onTap: onTap,
              ),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${reducedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hasReduction ? Colors.green : Colors.green,
                  ),
                ),
                if (hasReduction)
                  Text(
                    '₱${originalPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class VoucherReductionTooltip extends StatelessWidget {
  final double reductionAmount;
  final String fuelType;
  final String voucherTitle;

  const VoucherReductionTooltip({
    Key? key,
    required this.reductionAmount,
    required this.fuelType,
    required this.voucherTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Price reduced by ₱${reductionAmount.toStringAsFixed(2)} due to voucher: $voucherTitle',
      child: Icon(
        Icons.info_outline,
        size: 14,
        color: Colors.blue[600],
      ),
    );
  }
}
