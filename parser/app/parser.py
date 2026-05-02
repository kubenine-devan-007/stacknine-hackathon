import re

def parse_invoice_fields(raw_text: str) -> dict:
    result = {
        "invoice_number": None,
        "vendor": None,
        "invoice_date": None,
        "total": None,
        "line_items": []
    }

    inv = re.search(r'Invoice\s*#?\s*(INV[-\w]+|\d+)', raw_text, re.IGNORECASE)
    if inv:
        result["invoice_number"] = inv.group(1)

    vendor = re.search(r'From:\s*(.+)', raw_text, re.IGNORECASE)
    if vendor:
        result["vendor"] = vendor.group(1).strip()

    date = re.search(
        r'(?:Date|Invoice\s*Date):\s*(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})',
        raw_text, re.IGNORECASE
    )
    if date:
        result["invoice_date"] = date.group(1).strip()

    total = re.search(
        r'(?:TOTAL|Total Due|Amount Due)[\s:$]*(\d[\d,]*\.\d{2})',
        raw_text, re.IGNORECASE
    )
    if total:
        result["total"] = float(total.group(1).replace(',', ''))

    skip = {'total', 'subtotal', 'tax', 'invoice', 'date', 'from', 'bill', 'acme'}
    for desc, amount in re.findall(r'(.+?)\s{2,}\$?\s*(\d[\d,]*\.\d{2})', raw_text):
        desc = desc.strip()
        if not any(k in desc.lower() for k in skip) and len(desc) > 2:
            result["line_items"].append({
                "description": desc,
                "amount": float(amount.replace(',', ''))
            })

    return result
