import 'package:backend/features/billing/billing_math.dart';
import 'package:test/test.dart';

const gst18 = TaxRule(
  id: 'gst18',
  name: 'GST 18%',
  components: [TaxComponent('CGST', 900), TaxComponent('SGST', 900)],
  inclusive: false,
);
const gst18Inc = TaxRule(
  id: 'gst18i',
  name: 'GST 18% inclusive',
  components: [TaxComponent('CGST', 900), TaxComponent('SGST', 900)],
  inclusive: true,
);

void main() {
  group('rounding helpers', () {
    test('divRoundHalfUp rounds .5 up', () {
      expect(divRoundHalfUp(5, 2), 3);
      expect(divRoundHalfUp(4, 3), 1);
      expect(divRoundHalfUp(7, 3), 2);
      expect(divRoundHalfUp(0, 7), 0);
    });
    test('percentOf uses basis points', () {
      expect(percentOf(10000, 1800), 1800);
      expect(percentOf(333, 1000), 33);
      expect(percentOf(335, 1000), 34); // 33.5 -> 34
    });
    test('allocateProportionally always sums to the total', () {
      for (final total in [0, 1, 7, 100, 9999]) {
        final parts = allocateProportionally(total, [1, 1, 1]);
        expect(parts.fold<int>(0, (a, b) => a + b), total);
      }
      expect(allocateProportionally(10, [0, 0]), [10, 0]);
      expect(allocateProportionally(100, [300, 100]), [75, 25]);
    });
  });

  group('invoice calculation', () {
    test('no tax, no discount', () {
      final r = calculateInvoice([
        const LineInput(quantity: 2, unitMinor: 50000),
      ]);
      expect(r.subtotal, 100000);
      expect(r.grandTotal, 100000);
      expect(r.taxTotal, 0);
    });

    test('exclusive tax with two components', () {
      final r = calculateInvoice([
        const LineInput(quantity: 1, unitMinor: 100000, taxRule: gst18),
      ]);
      expect(r.taxTotal, 18000);
      expect(r.lines.first.taxParts.map((p) => p.amount), [9000, 9000]);
      expect(r.grandTotal, 118000);
    });

    test('inclusive tax keeps the entered price as the total', () {
      final r = calculateInvoice([
        const LineInput(quantity: 1, unitMinor: 118000, taxRule: gst18Inc),
      ]);
      expect(r.grandTotal, 118000);
      expect(r.lines.first.taxableBase, 100000);
      expect(r.taxTotal, 18000);
    });

    test('inclusive tax split always adds up', () {
      final r = calculateInvoice([
        const LineInput(quantity: 1, unitMinor: 10001, taxRule: gst18Inc),
      ]);
      final l = r.lines.first;
      expect(l.taxableBase + l.tax, 10001);
      expect(l.taxParts.fold<int>(0, (a, p) => a + p.amount), l.tax);
    });

    test('line percentage discount happens before tax', () {
      final r = calculateInvoice([
        const LineInput(
          quantity: 1,
          unitMinor: 100000,
          discount: Discount.percent(1000),
          taxRule: gst18,
        ),
      ]);
      expect(r.lineDiscountTotal, 10000);
      expect(r.taxTotal, 16200);
      expect(r.grandTotal, 106200);
    });

    test('fixed discount is capped at the line amount', () {
      final r = calculateInvoice([
        const LineInput(
          quantity: 1,
          unitMinor: 5000,
          discount: Discount.fixed(999999),
        ),
      ]);
      expect(r.grandTotal, 0);
      expect(r.lineDiscountTotal, 5000);
    });

    test('invoice discount is shared across lines and taxed after', () {
      final r = calculateInvoice([
        const LineInput(quantity: 1, unitMinor: 60000, taxRule: gst18),
        const LineInput(quantity: 1, unitMinor: 40000),
      ], invoiceDiscount: const Discount.fixed(10000));
      expect(r.invoiceDiscount, 10000);
      expect(r.lines.map((l) => l.invoiceDiscountShare), [6000, 4000]);
      expect(r.taxTotal, 9720); // 18% of 54000
      expect(r.grandTotal, 54000 + 9720 + 36000);
    });

    test('invoice discount shares add up with awkward amounts', () {
      final r = calculateInvoice([
        const LineInput(quantity: 1, unitMinor: 3333),
        const LineInput(quantity: 1, unitMinor: 3333),
        const LineInput(quantity: 1, unitMinor: 3334),
      ], invoiceDiscount: const Discount.fixed(1001));
      expect(r.lines.fold<int>(0, (a, l) => a + l.invoiceDiscountShare), 1001);
      expect(r.grandTotal, 10000 - 1001);
    });

    test('tax exemption removes tax', () {
      final r = calculateInvoice([
        const LineInput(
          quantity: 1,
          unitMinor: 100000,
          taxRule: gst18,
          taxExempt: true,
        ),
      ]);
      expect(r.taxTotal, 0);
      expect(r.grandTotal, 100000);
    });
  });

  group('balance and status', () {
    Balance b({
      int debits = 0,
      int credits = 0,
      int paid = 0,
      int refunded = 0,
      bool cancelled = false,
    }) => balanceOf(
      grandTotal: 1000,
      debits: debits,
      credits: credits,
      paid: paid,
      refunded: refunded,
      cancelled: cancelled,
    );
    test('unpaid is finalized', () {
      expect(b().status, 'finalized');
      expect(b().outstanding, 1000);
    });
    test('partial and full payment', () {
      expect(b(paid: 400).status, 'partially_paid');
      expect(b(paid: 400).outstanding, 600);
      expect(b(paid: 1000).status, 'paid');
      expect(b(paid: 1000).outstanding, 0);
    });
    test('refunds do not re-open the debt', () {
      expect(b(paid: 1000, refunded: 300).status, 'partially_refunded');
      expect(b(paid: 1000, refunded: 300).outstanding, 0);
      expect(b(paid: 1000, refunded: 1000).status, 'refunded');
    });
    test('adjustments change the total', () {
      expect(b(debits: 200).outstanding, 1200);
      expect(b(credits: 1000).status, 'paid');
      expect(b(credits: 1000).outstanding, 0);
    });
    test('cancelled wins', () {
      expect(b(cancelled: true).status, 'cancelled');
    });
  });
}
