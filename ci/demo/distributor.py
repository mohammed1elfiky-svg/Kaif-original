# The distributor app scenario through the real API, with exactly the requests of the app
# (distributor-app/lib/data/api.dart and models.dart toUploadJson): download, then upload of a sale with a
# partial payment, a return with lines, a collection, a visit and the closing of the day; then the server
# side is checked as admin (KaifTest.distributorCheck).
import base64, json, sys, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8080'


def post(action, body=None, user='d01', password='test123'):
    req = urllib.request.Request(f'{BASE}/exec/{action}', method='POST',
                                 data=None if body is None else json.dumps(body).encode('utf-8'))
    req.add_header('Authorization', 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode())
    req.add_header('Content-Type', 'application/json; charset=utf-8')
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read().decode('utf-8')
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        print(f'{action}: HTTP {e.code}: {e.read().decode("utf-8", "replace")[:2000]}')
        raise


problems = []
def check(cond, msg):
    print(('OK   ' if cond else 'FAIL ') + msg)
    if not cond:
        problems.append(msg)


# ---- download (what the app does on "update data") ----
data = post('Distribution.getData')
d = data.get('distributor', [{}])
d = d[0] if isinstance(d, list) else d
customers = data.get('customers') or []
items = data.get('items') or []
prices = data.get('prices') or []
print('distributor:', json.dumps(d, ensure_ascii=False))
print('company:', json.dumps(data.get('company'), ensure_ascii=False))
print(f'customers {len(customers)}, items {len(items)}, prices {len(prices)}, open invoices {len(data.get("openInvoices") or [])}')
check(len(customers) == 3, 'the distributor gets his 3 customers')
check(any((i.get('onHand') or 0) > 0 for i in items), 'items with van stock')
check(len(prices) > 0, 'prices for the app (price type of the distributor invoice type)')
check(all(i.get('packRatio') for i in items if (i.get('onHand') or 0) > 0), 'carton size (pack ratio) of the van items')

stock = [i for i in items if (i.get('onHand') or 0) > 0]
price_of = {p['item']: float(p['price']) for p in prices}
tax_included = bool(prices[0].get('taxIncluded')) if prices else True
a, b = stock[0], stock[1]
pa, pb = price_of.get(a['id'], 10.0), price_of.get(b['id'], 10.0)
c1, c2 = customers[0], customers[1]
prefix = d.get('prefix') or 'D01'

now = datetime.now(timezone.utc) + timedelta(hours=3)   # Saudi local time, as the app sends
ts = lambda m: (now + timedelta(minutes=m)).strftime('%Y-%m-%dT%H:%M:%S')
money = lambda v: f'{v:.2f}'

qa, qb = 24, 12            # one carton of A (24) and one of B (12)
inv_total = qa * pa + qb * pb
paid = 100.0
upload = {
    'invoices': [{
        'id': 'test-inv-1', 'number': f'{prefix}-000001', 'date': ts(0), 'customer': c1['id'],
        'taxIncluded': tax_included, 'paid': money(paid), 'method': 'cash', 'note': '',
        'lines': [{'item': a['id'], 'quantity': str(qa), 'price': money(pa)},
                  {'item': b['id'], 'quantity': str(qb), 'price': money(pb)}],
    }],
    'payments': [{
        'id': 'test-pay-1', 'number': f'{prefix}-R-000001', 'date': ts(5), 'customer': c2['id'],
        'amount': money(50), 'method': 'cash', 'invoice': '', 'note': '',
    }],
    'returns': [{
        'id': 'test-ret-1', 'number': f'{prefix}-C-000001', 'date': ts(10), 'customer': c1['id'],
        'taxIncluded': tax_included, 'refund': money(0), 'invoice': f'{prefix}-000001', 'reason': 'تالف',
        'lines': [{'item': a['id'], 'quantity': '2', 'price': money(pa)}],
    }],
    'visits': [{
        'id': 'test-vis-1', 'date': ts(15), 'customer': customers[2]['id'],
        'latitude': 24.7136, 'longitude': 46.6753, 'result': 'closed', 'note': 'المحل مغلق',
    }],
    'closings': [{
        'id': 'test-clo-1', 'number': f'{prefix}-Z-000001', 'date': ts(30),
        'sales': money(inv_total), 'credit': money(inv_total - paid), 'returns': money(2 * pa), 'bank': money(0),
        'cashExpected': money(paid + 50), 'cashHanded': money(paid + 50), 'note': '',
        # expected after the day: A = start - 24 + 2 (return), counted one less (a missing piece)
        'lines': [{'item': a['id'], 'expected': str(int(a['onHand']) - qa + 2), 'counted': str(int(a['onHand']) - qa + 1)},
                  {'item': b['id'], 'expected': str(int(b['onHand']) - qb), 'counted': str(int(b['onHand']) - qb)}],
    }],
}
result = post('Distribution.upload', upload)
print('upload result:', json.dumps(result, ensure_ascii=False))
res = {r['id']: r['result'] for r in (result or [])}
for doc in ['test-inv-1', 'test-pay-1', 'test-ret-1', 'test-vis-1', 'test-clo-1']:
    check(res.get(doc) == 'ok', f'upload {doc}: {res.get(doc)}')

# a second upload of the same documents (the app resends when the answer was lost) must not duplicate them
again = post('Distribution.upload', upload)
check(all(r['result'] == 'ok' for r in again or []), 'resending the same documents is accepted')

# ---- server side, as admin ----
srv = post('KaifTest.distributorCheck', user='admin', password='')
print('server:', json.dumps(srv, ensure_ascii=False))
check(srv.get('invoiceNumber') == f'{prefix}-000001', 'invoice number from the device')
check(abs((srv.get('invoiceAmount') or 0) - inv_total) < 0.01, f'invoice amount {srv.get("invoiceAmount")} = {inv_total:.2f}')
check((srv.get('invoiceVat') or 0) > 0, f'invoice VAT {srv.get("invoiceVat")}')
check(srv.get('invoiceLines') == 2, 'invoice lines: 2')
check(abs((srv.get('returnAmount') or 0) - 2 * pa) < 0.01, f'return amount {srv.get("returnAmount")} = {2 * pa:.2f}')
check(srv.get('returnLines') == 1, f'return lines: {srv.get("returnLines")} (1 expected)')
check(abs((srv.get('invoicePaid') or 0) - (paid + 2 * pa)) < 0.01, f'paid on the invoice {srv.get("invoicePaid")} = cash {paid:.2f} + return {2 * pa:.2f}')
check(abs((srv.get('paymentAmount') or 0) - 50) < 0.01, 'collection 50.00')
check(srv.get('visits') == 1, 'visit saved')
check(srv.get('closingLines') == 2, f'closing lines: {srv.get("closingLines")}')
check(srv.get('closingDifferences') == 1, f'closing differences: {srv.get("closingDifferences")}')
check(abs((srv.get('firstItemVanStock') or 0) - (a['onHand'] - qa + 2)) < 0.001 if a['name'].startswith('شاي الكيف الأصلي فاخر') else True,
      f'van stock of {a["name"]}: {srv.get("firstItemVanStock")} = {a["onHand"]} - {qa} + 2')

# ---- download again: the numbers continue after the uploaded ones ----
data2 = post('Distribution.getData')
d2 = data2.get('distributor', [{}]); d2 = d2[0] if isinstance(d2, list) else d2
print('after upload:', json.dumps(d2, ensure_ascii=False))
check(d2.get('lastInvoice') == f'{prefix}-000001', 'last invoice number for the app')

print('\nPROBLEMS:' if problems else '\nALL CHECKS PASSED', *problems, sep='\n - ')
sys.exit(1 if problems else 0)
