/// Deterministic money arithmetic for invoices. Everything is an integer in
/// minor currency units (paise for INR); no floating point is used anywhere.
///
/// Rounding rule (documented in docs/phase-7/FINANCIAL_ARCHITECTURE.md): every
/// division rounds half up. Remainders created by splitting an amount across
/// lines or tax components go to the largest part (ties: first), so the parts
/// always add up to the whole.
library;

/// `numerator / denominator` rounded half up (non-negative inputs).
int divRoundHalfUp(int numerator, int denominator) {
  assert(numerator >= 0 && denominator > 0);
  return (numerator * 2 + denominator) ~/ (denominator * 2);
}

/// `amount × bps / 10000`, rounded half up.
int percentOf(int amount, int bps) => divRoundHalfUp(amount * bps, 10000);

/// Splits [total] in proportion to [weights] (largest-remainder method).
/// All-zero weights put the whole amount on the first part.
List<int> allocateProportionally(int total, List<int> weights) {
  if (weights.isEmpty) return const [];
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (sum == 0) {
    return [total, for (var i = 1; i < weights.length; i++) 0];
  }
  final parts = <int>[];
  final remainders = <int>[];
  var given = 0;
  for (final w in weights) {
    final exact = total * w;
    parts.add(exact ~/ sum);
    remainders.add(exact % sum);
    given += parts.last;
  }
  var left = total - given;
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final c = remainders[b].compareTo(remainders[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (final i in order) {
    if (left == 0) break;
    parts[i] += 1;
    left--;
  }
  return parts;
}

class TaxComponent {
  const TaxComponent(this.name, this.rateBps);
  final String name;
  final int rateBps;
}

/// A named tax configuration. [inclusive] means the entered price already
/// contains the tax.
class TaxRule {
  const TaxRule({
    required this.id,
    required this.name,
    required this.components,
    required this.inclusive,
  });

  final String id;
  final String name;
  final List<TaxComponent> components;
  final bool inclusive;

  int get totalBps => components.fold(0, (a, c) => a + c.rateBps);
}

/// A discount on a line or on the whole invoice.
class Discount {
  const Discount.fixed(this.amount) : bps = null;
  const Discount.percent(this.bps) : amount = null;
  final int? amount;
  final int? bps;

  int of(int base) {
    final v = amount ?? percentOf(base, bps!);
    return v > base ? base : v;
  }
}

class LineInput {
  const LineInput({
    required this.quantity,
    required this.unitMinor,
    this.discount,
    this.taxRule,
    this.taxExempt = false,
  });

  final int quantity;
  final int unitMinor;
  final Discount? discount;
  final TaxRule? taxRule;
  final bool taxExempt;
}

class TaxPart {
  const TaxPart(this.name, this.rateBps, this.amount);
  final String name;
  final int rateBps;
  final int amount;

  Map<String, Object?> toJson() => {
    'name': name,
    'rateBps': rateBps,
    'amount': amount,
  };
}

class LineResult {
  const LineResult({
    required this.gross,
    required this.lineDiscount,
    required this.invoiceDiscountShare,
    required this.taxableBase,
    required this.taxParts,
    required this.tax,
    required this.total,
  });

  final int gross;
  final int lineDiscount;
  final int invoiceDiscountShare;

  /// Amount the tax is calculated on (after discounts, without tax).
  final int taxableBase;
  final List<TaxPart> taxParts;
  final int tax;

  /// What the patient pays for this line.
  final int total;
}

class InvoiceResult {
  const InvoiceResult({
    required this.lines,
    required this.subtotal,
    required this.lineDiscountTotal,
    required this.invoiceDiscount,
    required this.taxTotal,
    required this.grandTotal,
  });

  final List<LineResult> lines;

  /// Sum of quantity × unit price, before any discount.
  final int subtotal;
  final int lineDiscountTotal;
  final int invoiceDiscount;
  final int taxTotal;
  final int grandTotal;

  int get discountTotal => lineDiscountTotal + invoiceDiscount;
}

/// Calculates an invoice. Pure and deterministic.
InvoiceResult calculateInvoice(
  List<LineInput> inputs, {
  Discount? invoiceDiscount,
}) {
  final gross = [for (final l in inputs) l.quantity * l.unitMinor];
  final lineDisc = [
    for (var i = 0; i < inputs.length; i++)
      inputs[i].discount?.of(gross[i]) ?? 0,
  ];
  final net = [for (var i = 0; i < inputs.length; i++) gross[i] - lineDisc[i]];
  final netSum = net.fold<int>(0, (a, b) => a + b);
  final invDisc = invoiceDiscount?.of(netSum) ?? 0;
  final share = allocateProportionally(invDisc, net);

  final lines = <LineResult>[];
  for (var i = 0; i < inputs.length; i++) {
    final after = net[i] - share[i];
    final rule = inputs[i].taxExempt ? null : inputs[i].taxRule;
    var base = after;
    var parts = <TaxPart>[];
    var tax = 0;
    var total = after;
    if (rule != null && rule.totalBps > 0) {
      if (rule.inclusive) {
        base = divRoundHalfUp(after * 10000, 10000 + rule.totalBps);
        tax = after - base;
        final split = allocateProportionally(tax, [
          for (final c in rule.components) c.rateBps,
        ]);
        parts = [
          for (var k = 0; k < rule.components.length; k++)
            TaxPart(
              rule.components[k].name,
              rule.components[k].rateBps,
              split[k],
            ),
        ];
        total = after;
      } else {
        parts = [
          for (final c in rule.components)
            TaxPart(c.name, c.rateBps, percentOf(after, c.rateBps)),
        ];
        tax = parts.fold(0, (a, p) => a + p.amount);
        total = after + tax;
      }
    }
    lines.add(
      LineResult(
        gross: gross[i],
        lineDiscount: lineDisc[i],
        invoiceDiscountShare: share[i],
        taxableBase: base,
        taxParts: parts,
        tax: tax,
        total: total,
      ),
    );
  }
  return InvoiceResult(
    lines: lines,
    subtotal: gross.fold(0, (a, b) => a + b),
    lineDiscountTotal: lineDisc.fold(0, (a, b) => a + b),
    invoiceDiscount: invDisc,
    taxTotal: lines.fold(0, (a, l) => a + l.tax),
    grandTotal: lines.fold(0, (a, l) => a + l.total),
  );
}

/// Money position of a finalized invoice.
class Balance {
  const Balance({
    required this.adjustedTotal,
    required this.outstanding,
    required this.status,
  });

  /// Grand total plus debit adjustments minus credit adjustments.
  final int adjustedTotal;

  /// What the patient still owes. Refunds return money that was paid; they do
  /// not re-open the debt (a debit adjustment does).
  final int outstanding;
  final String status;
}

/// Status and balance of a finalized or cancelled invoice. [paid] is the sum of
/// payment allocations, [refunded] the sum of completed refunds.
Balance balanceOf({
  required int grandTotal,
  required int debits,
  required int credits,
  required int paid,
  required int refunded,
  bool cancelled = false,
}) {
  final adjusted = grandTotal + debits - credits;
  final outstanding = adjusted - paid;
  final due = outstanding < 0 ? 0 : outstanding;
  if (cancelled) {
    return Balance(
      adjustedTotal: adjusted,
      outstanding: 0,
      status: 'cancelled',
    );
  }
  String status;
  if (paid == 0) {
    status = adjusted == 0 ? 'paid' : 'finalized';
  } else if (due > 0) {
    status = 'partially_paid';
  } else if (refunded == 0) {
    status = 'paid';
  } else if (refunded >= paid) {
    status = 'refunded';
  } else {
    status = 'partially_refunded';
  }
  return Balance(adjustedTotal: adjusted, outstanding: due, status: status);
}
