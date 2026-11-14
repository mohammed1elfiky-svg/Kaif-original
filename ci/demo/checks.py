# Checks of the payroll and of the VAT return against the figures computed by hand (Saudi rules).
import base64, json, sys, urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8080'


def post(action):
    req = urllib.request.Request(f'{BASE}/exec/{action}', method='POST')
    req.add_header('Authorization', 'Basic ' + base64.b64encode(b'admin:').decode())
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode('utf-8'))


problems = []
def near(name, got, expected, tol=0.011):
    ok = got is not None and expected is not None and abs(float(got) - float(expected)) <= tol
    print(('OK   ' if ok else 'FAIL ') + f'{name}: {got} (expected {expected})')
    if not ok:
        problems.append(f'{name}: {got} instead of {expected}')


# ---- payroll ----
p = post('KaifTest.payrollCheck')
print('payroll:', json.dumps(p, ensure_ascii=False))
near('payslips', p.get('payslips'), 2, 0)
near('Saudi nationality found', 1 if p.get('isSaudiFound') else 0, 1, 0)
near('Saudi basic', p.get('saudiBasic'), 6000)
near('Saudi housing', p.get('saudiHousing'), 1500)
near('Saudi transport', p.get('saudiTransport'), 500)
near('Saudi GOSI employee 9.75% of (basic + housing)', p.get('saudiGosi'), 7500 * 0.0975)
near('Saudi GOSI company 11.75%', p.get('saudiGosiCompany'), 7500 * 0.1175)
near('Saudi net wage', p.get('saudiNet'), 8000 - 731.25)
near('Saudi years of service', p.get('saudiServiceYears'), 3.0)
near('End of service on termination (half a month x 3 years)', p.get('saudiEosTermination'), 8000 * 0.5 * 3, 1)
near('End of service on resignation (a third, 2-5 years)', p.get('saudiEosResignation'), 8000 * 0.5 * 3 / 3, 1)
near('Accrued leave (21 days x 3 years)', p.get('saudiLeaveAccrued'), 63, 0.5)
days, month = p.get('foreignDaysWorked') or 0, p.get('monthDays') or 30
ratio = days / month
near('Non-Saudi basic, prorated', p.get('foreignBasic'), round(3000 * ratio, 2))
near('Non-Saudi housing, prorated', p.get('foreignHousing'), round(750 * ratio, 2))
near('Non-Saudi GOSI employee (none)', p.get('foreignGosi') or 0, 0)
near('Non-Saudi GOSI company 2% (occupational hazards)', p.get('foreignGosiCompany'), round(3750 * ratio * 0.02, 2))
near('Non-Saudi net wage', p.get('foreignNet'), round(3000 * ratio, 2) + round(750 * ratio, 2))

# ---- VAT return of the month ----
v = post('KaifTest.vatCheck')
print('vat:', json.dumps(v, ensure_ascii=False))
sales_vat, cn_vat = v.get('salesVatSum') or 0, v.get('creditNotesVatSum') or 0
near('Box 1 VAT = VAT of the sales - VAT of the credit notes', v.get('box1Vat'), sales_vat - cn_vat)
near('Box 13 = output VAT - input VAT', v.get('box13VatDue'), (v.get('box1Vat') or 0) - (v.get('box12Vat') or 0))
near('Box 1 VAT = 15% of (amount + adjustment)', v.get('box1Vat'), round(((v.get('box1Amount') or 0) + (v.get('box1Adjustment') or 0)) * 0.15, 2), 0.05)

print('\nPROBLEMS:' if problems else '\nALL CHECKS PASSED', *problems, sep='\n - ')
sys.exit(1 if problems else 0)
